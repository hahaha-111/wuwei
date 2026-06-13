import { UIContext, router } from '@kit.ArkUI'; 
import { detectScreenInfo, ScreenType } from '../common/ScreenTypeHelper';
import { SignalBoardViewModel } from './SignalBoardViewModel';
import { ProtocolFrame, DeviceType, ProtocolParser } from '../common/ProtocolParser';
import { TransportManager } from '../common/transport/TransportManager';
import { ITransport } from '../common/transport/ITransport';
import { ProtocolDecoder } from '../common/ProtocolDecoder';
import {
  CommandPayload,
  StatusPayload,
  DeviceTimePayload,
  ChannelPayload,
  DeviceNamePayload,
  AlarmThresholdPayload,
  SensitivityPayload,
  FiberDataPayload,
  TempHumidityPayload,
  VoltagePayload
} from '../common/protocol/ProtocolTypes'; 
import { common } from '@kit.AbilityKit';
import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import { DeviceNameManager } from '../common/DeviceNameManager';
import { LogManager } from '../common/database/LogManager';
import { LogCategory } from '../common/database/LogEntity';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileUtil } from '../common/utils/FileUtil';
import { ImageGenerator, SnapshotInfo } from '../common/utils/ImageGenerator';

export type DeviceMode = 'RX' | 'TX' | 'FIBER' | 'UNKNOWN';
export type FiberChannelMode = 'ALL' | 'CH1' | 'CH2' | 'CH3' | 'CH4';

// ⭐ 修复编译报错：恢复路由对象，且改为 class 防止被严格模式识别为结构化隐式转换
export class MonitorPageParams {
  screenType?: ScreenType;
  deviceType?: DeviceType;
  deviceKind?: DeviceMode;
  connectionMode?: 'BLE' | 'TCP';
  deviceName?: string;
  deviceAddress?: number;
  playbackMode?: boolean;
  playbackFilePath?: string;
  port?: string;
  fromPage?: string;
}

export class NavParamsRecord {
  deviceName?: string;
  deviceType?: number;
  screenType?: string;
  connectionMode?: string;
  deviceAddress?: number;
  baseDir?: string;
  deviceKind?: DeviceMode; 
}

export interface ParamItem {
  label: string;
  value: string;
}

export interface PendingLogItem {
  category: LogCategory;
  action: string;
  desc: string;
  id: string;
}

export interface DeviceLogState {
  channel?: number;
  threshold?: number;
  sensitivity?: number;
  calibrate?: number;
  name?: string;
  lastSignal?: number; 
}

export interface RecordFrame {
  t: number;
  s: number;
  th: number;
  a?: number;
  tm?: number;
}

export interface LogDeviceInfo {
  name: string;
  id: string;
}

@Observed
export class MonitorViewModel {
  deviceMode: DeviceMode = 'UNKNOWN';
  fiberChannelMode: FiberChannelMode = 'ALL';
  txTemp: number = 0;
  txHum: number = 0;
  txMcuVol: number = 0;
  txHighFreqVol: number = 0;
  txInputVol: number = 0;

  fiberAlarm1: boolean = false;
  fiberAlarm2: boolean = false;
  fiberAlarm3: boolean = false;
  fiberAlarm4: boolean = false;
  fiberDisconnect: boolean = false;
  fiberTamper: boolean = false;

  fiber1Signal: number = 0;
  fiber2Signal: number = 0;
  fiber3Signal: number = 0;
  fiber4Signal: number = 0;
  fiber1Up: number = 0;
  fiber1Down: number = 0;
  fiber2Up: number = 0;
  fiber2Down: number = 0;
  fiber3Up: number = 0;
  fiber3Down: number = 0;
  fiber4Up: number = 0;
  fiber4Down: number = 0;

  fiber1Sens: number = 0;
  fiber2Sens: number = 0;
  fiber3Sens: number = 0;
  fiber4Sens: number = 0;

  deviceNameStr: string = '[空]';
  deviceThresholdStr: string = '[空]';
  deviceChannelStr: string = '[空]';
  deviceTimeStr: string = '[空]';

  currentTab: number = 0;
  screenType: ScreenType = 'PHONE';
  isLargeScreen: boolean = false;
  isFoldDevice: boolean = false;
  alarmOn: boolean = false;
  tamperOn: boolean = false;
  txOn: boolean = true;
  rxOn: boolean = true;
  autoDownload: boolean = false;
  isRecording: boolean = false;
  isPlaybackMode: boolean = false;
  isPlaybackPaused: boolean = false;
  playbackProgress: number = 0;
  playbackTotalDuration: string = "00:00";
  playbackRate: number = 1.0;
  alarmBitStr: string = '-';
  tamperBitStr: string = '-';
  isMute: boolean = false;
  isMaster: boolean = true;
  sliderValue: number = 162;
  avgValue: number = 0;
  variance: number = 0;

  paramList: ParamItem[] = [];

  showListenDialog: boolean = false;
  listenTime: number = 1;
  listenVariance: number = 5;
  listenEnable: boolean = false;
  listenStatusText: string = '';

  public uiContext: UIContext | null = null; 

  private listenStartTime: number = 0;
  private listenCycleStartTime: number = 0;
  private listenTotalCycles: number = 0;
  private listenSuccessCycles: number = 0;
  private listenFailCycles: number = 0;
  private currentCycleFailed: boolean = false;

  currentTimeStr: string = '';
  signalVm: SignalBoardViewModel = new SignalBoardViewModel();
  waveVersion: number = 0;
  deviceType: DeviceType = DeviceType.Microwave;
  isMicrowaveDevice: boolean = false;
  connectionMode: 'BLE' | 'TCP' = 'BLE';
  isConnected: boolean = false;
  private transport: ITransport;
  // ⭐ P1: 统一使用全局 ProtocolParser，自定义校验在全业务层处理
  private protocolParser: ProtocolParser = new ProtocolParser();

  public currentDeviceAddress: number = 0x01;
  private lastProbeTime: number = 0;
  private hasSyncedTime: boolean = false;

  waveIntervalMs: number = 40;
  displayPointCount: number = 60;
  private waveTimer: number = -1;
  private timeSyncTimer: number = -1;
  private timeTimer: number = -1;
  private waveUiTimer: number = -1;
  private context?: common.UIAbilityContext;
  private nameManager: DeviceNameManager | null = null;
  private soundPool?: media.SoundPool;
  private soundId: number = -1;
  private streamId: number = -1;
  private isAudioPlaying: boolean = false;
  private lastAlarmTriggerTime: number = 0;
  private stopAlarmTimer: number = -1;
  private onStatusChangeCallback: ((alarm: boolean, tamper: boolean) => void) | undefined = undefined;

  private onFiberAlarmChangeCallback: ((a1: boolean, a2: boolean, a3: boolean, a4: boolean) => void) | undefined = undefined;

  private isPollingPaused: boolean = false;
  private static logCache: Map<string, DeviceLogState> = new Map<string, DeviceLogState>();
  private pendingLogs: Array<PendingLogItem> = [];
  private readonly LISTENER_KEY = 'MonitorVM';
  private isAlarmingLocked: boolean = false;
  private alarmDebounceTimer: number = -1;
  private recordBuffer: RecordFrame[] = [];
  private recordStartTime: number = 0;
  private playbackTimer: number = -1;
  private playbackData: RecordFrame[] = [];
  private playbackIndex: number = 0;
  private playbackFrameAccumulator: number = 0;
  private paramRetryCount: number = 0;
  private paramRetryTimer: number = -1;
  private readonly MAX_PARAM_RETRIES = 3;
  private txPollCounter: number = 0;
  private lastSetThresholdTime: number = 0;

  constructor() {
    this.transport = TransportManager.getInstance().getTransport();
  }

  private showToastMsg(msg: string, duration?: number): void {
    if (this.uiContext) {
      try {
        if (duration !== undefined) {
          this.uiContext.getPromptAction().showToast({ message: msg, duration: duration });
        } else {
          this.uiContext.getPromptAction().showToast({ message: msg });
        }
      } catch (e) {
        console.error('showToastMsg error:', e);
      }
    }
  }

  private getLogState(): DeviceLogState {
    const id = this.transport.getId() || 'temp_session';
    if (!MonitorViewModel.logCache.has(id)) {
      const emptyState: DeviceLogState = {};
      MonitorViewModel.logCache.set(id, emptyState);
    }
    return MonitorViewModel.logCache.get(id)!;
  }

  public clearLogState() {
    const id = this.transport.getId();
    if (id && MonitorViewModel.logCache.has(id)) {
      MonitorViewModel.logCache.delete(id);
    }
  }

  private checkAndLog(type: 'name' | 'channel' | 'threshold', value: string | number) {
    const state = this.getLogState();
    const deviceId = this.transport.getId() || '-';

    if (type === 'name') {
      const valStr = String(value);
      if (state.name !== valStr) {
        state.name = valStr;
        if (valStr !== '[空]' && valStr !== '未配置' && valStr !== '[未命名]' && valStr !== '未命名设备') {
          this.addLog(LogCategory.QUERY, '设备信息', `设备名称: ${valStr}`, deviceId);
        }
      }
    } else if (type === 'channel') {
      const valNum = Number(value);
      if (state.channel !== valNum) {
        state.channel = valNum;
        this.addLog(LogCategory.QUERY, '参数读取', `通道变动: ${valNum}`, deviceId);
      }
    } else if (type === 'threshold') {
      const valNum = Number(value);
      if (state.threshold !== valNum) {
        state.threshold = valNum;
        this.addLog(LogCategory.QUERY, '参数读取', `阈值/灵敏度变动: ${valNum}`, deviceId);
      }
    }
  }

  private checkAndLogSignal(signal: number) {
    const state = this.getLogState();
    if (state.lastSignal === undefined || Math.abs(state.lastSignal - signal) > 4) {
      state.lastSignal = signal;
      this.addLog(LogCategory.QUERY, '信号波动', `当前信号值大幅波动: ${signal}`, this.transport.getId() || '-');
    }
  }

  private addLog(category: LogCategory, action: string, desc: string, id: string = '-'): void {
    const currentName = this.deviceNameStr;
    const isNameValid = currentName !== '[空]' && currentName !== '[未配置]' && currentName !== '[未命名]' && currentName !== '未知设备';
    const logInfo: LogDeviceInfo = { name: currentName, id: id };

    if (isNameValid) {
      LogManager.getInstance().addLog(category, action, desc, logInfo);
    } else {
      this.pendingLogs.push({ category: category, action: action, desc: desc, id: id });
    }
  }

  private flushPendingLogs(): void {
    const currentName = this.deviceNameStr;
    if (currentName !== '[空]' && currentName !== '[未配置]' && currentName !== '[未命名]' && currentName !== '未知设备') {
      if (this.pendingLogs.length > 0) {
        this.pendingLogs.forEach(log => {
          const logInfo: LogDeviceInfo = { name: currentName, id: log.id };
          LogManager.getInstance().addLog(log.category, log.action, log.desc, logInfo);
        });
        this.pendingLogs = [];
      }
    }
  }

  async init(params?: Record<string, Object>, context?: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (context) {
      try {
        this.initAudioPlayer(context);
        this.nameManager = await DeviceNameManager.getInstance(context);
        await LogManager.getInstance().init(context);
      } catch (e) {
        console.error('MonitorVM init modules error:', e);
      }
    }

    if (params) {
      if (params['deviceType'] !== undefined) {
        this.deviceType = params['deviceType'] as number;
        this.isMicrowaveDevice = this.deviceType === DeviceType.Microwave;
      }
      
      if (params['deviceKind'] !== undefined && params['deviceKind'] !== 'UNKNOWN') {
        this.deviceMode = params['deviceKind'] as DeviceMode;
      } else if (params['deviceKind']) {
        this.deviceMode = params['deviceKind'] as DeviceMode;
      }
      
      if (params['screenType']) {
        this.screenType = params['screenType'] as ScreenType;
      }
      if (params['connectionMode']) {
        this.connectionMode = params['connectionMode'] as ('BLE' | 'TCP');
        TransportManager.getInstance().switchMode(this.connectionMode);
        this.transport = TransportManager.getInstance().getTransport();
      }
      if (params['deviceAddress'] !== undefined) {
        this.currentDeviceAddress = params['deviceAddress'] as number;
      }
      if (params['deviceName']) {
        const pName = params['deviceName'] as string;
        if (this.deviceNameStr !== pName) {
          this.deviceNameStr = pName;
        }
      }
      if (params['playbackMode'] === true && params['playbackFilePath']) {
        this.isPlaybackMode = true;
        this.isRecording = false;
        this.autoDownload = false;
        this.detectScreenSize();
        this.signalVm.setDisplayCount(this.displayPointCount);
        this.startWaveUiTimer();
        this.startPlayback(params['playbackFilePath'] as string);
        return;
      }
    }

    this.detectScreenSize();
    this.updateCurrentTime();
    this.startTimeTimer();
    this.signalVm.setDisplayCount(this.displayPointCount);
    this.startWaveUiTimer();
    this.registerDataCallbacks();

    const isConn = this.transport.isConnected();
    this.setConnected(isConn);
  }

  destroy(): void {
    this.stopTimeTimer();
    this.stopWaveCommandTimer();
    this.stopTimeSyncLoop();
    this.stopWaveUiTimer();
    this.releaseAudioPlayer();
    this.stopPlayback();
    if (this.isRecording) {
      this.stopRecording();
    }
    if (this.alarmDebounceTimer !== -1) {
      clearTimeout(this.alarmDebounceTimer);
    }
    if (this.stopAlarmTimer !== -1) {
      clearTimeout(this.stopAlarmTimer);
    }
    if (this.paramRetryTimer !== -1) {
      clearTimeout(this.paramRetryTimer);
    }
    this.transport.offStateChange(this.LISTENER_KEY);
    this.transport.offDataReceived(this.LISTENER_KEY);
  }

  openRunDirFolder() {
    const p: Record<string, Object> = {};
    p['deviceName'] = this.deviceNameStr;
    p['baseDir'] = '';
    p['deviceKind'] = this.deviceMode; 
    if (this.uiContext) {
      try {
        this.uiContext.getRouter().pushUrl({ url: 'pages/RecordListPage', params: p }, router.RouterMode.Standard).catch((err: Error) => {
          console.error('Router error:', err);
        });
      } catch (e) {
        console.error('Router pushUrl sync error:', e);
      }
    }
  }

  private sendFrame(cmd: number, data: number[] = [], forceType?: number, forceAddr?: number): void {
    if (this.isPlaybackMode || !this.isConnected) return;

    const addr = forceAddr !== undefined ? forceAddr : this.currentDeviceAddress;
    const type = forceType !== undefined ? forceType : (this.deviceType === DeviceType.Fiber ? 0x66 : 0xC9);

    const len = data.length + 1;
    let sum = type + len + cmd;
    for (let b of data) sum += b;
    const cs = sum & 0xFF;
    let hex = `FF${this.toHex(addr)}${this.toHex(type)}${this.toHex(len)}${this.toHex(cmd)}`;
    for (let b of data) hex += this.toHex(b);
    hex += this.toHex(cs);

    try {
      this.transport.sendHexString(hex);
    } catch (e) {
      console.error('sendHexString error:', e);
    }
  }

  private syncTimeToDevice(): void {
    const now = new Date();
    const toBcd = (val: number) => Math.floor(val / 10) * 16 + (val % 10);
    const year = toBcd(now.getFullYear() % 100);
    const month = toBcd(now.getMonth() + 1);
    const day = toBcd(now.getDate());
    const hour = toBcd(now.getHours());
    const minute = toBcd(now.getMinutes());
    const second = toBcd(now.getSeconds());

    this.sendFrame(0x13, [year, month, day, hour, minute, second]);
  }

  public onSetFiberSensitivity() {
    this.lastSetThresholdTime = Date.now();
    let ch = 0;
    if (this.fiberChannelMode === 'CH1') ch = 1;
    else if (this.fiberChannelMode === 'CH2') ch = 2;
    else if (this.fiberChannelMode === 'CH3') ch = 3;
    else if (this.fiberChannelMode === 'CH4') ch = 4;

    const targetSens = this.sliderValue;
    this.sendFrame(0x09, [ch, targetSens], 0x66);

    setTimeout(() => {
      this.sendFrame(0x23, [], 0x66);

      setTimeout(() => {
        let currentSens = 0;
        if (ch === 1 || ch === 0) currentSens = this.fiber1Sens;
        else if (ch === 2) currentSens = this.fiber2Sens;
        else if (ch === 3) currentSens = this.fiber3Sens;
        else if (ch === 4) currentSens = this.fiber4Sens;

        if (Math.abs(currentSens - targetSens) > 2) {
          this.showToastMsg('设定失败，请改为软件调灵方式', 3000);
        } else {
          this.showToastMsg('灵敏度调节成功并已保存！');
        }
      }, 800);
    }, 500);
  }

  public sendRebootCommand() {
    if (this.deviceMode === 'FIBER') {
      this.sendFrame(0x1D, [], 0x66);
    } else {
      this.sendFrame(0x07);
    }
    this.showToastMsg('已下发重启指令');
  }

  public onSetSensitivityClick() {
    this.lastSetThresholdTime = Date.now();
    if (this.deviceMode === 'TX') {
      this.sendFrame(0x02, [this.sliderValue], 0xC9, 0x01);
      this.showToastMsg('调节高频电压成功!');
    } else {
      this.sendFrame(0x05, [this.sliderValue]);
      this.showToastMsg('阈值已发送');
    }
  }

  public onTestWaveButtonClickDebug() {
    this.sendFrame(0x0B);
    this.showToastMsg('已下发巡检指令');
  }

  private readDeviceParams(): void {
    if (this.isPlaybackMode || !this.isConnected) return;
    this.paramRetryCount = 0;
    this.executeReadParams();
    if (this.paramRetryTimer !== -1) clearTimeout(this.paramRetryTimer);
    this.paramRetryTimer = setTimeout(() => {
      this.checkAndRetryParams();
    }, 5000);
  }

  private executeReadParams() {
    let delay = 0;
    const step = 800;
    setTimeout(() => { this.sendFrame(0x15); }, delay += step);
    setTimeout(() => { this.sendFrame(0x03); }, delay += step);

    if (this.deviceMode !== 'FIBER') {
      setTimeout(() => { this.sendFrame(0x0D); }, delay += step);
      setTimeout(() => { this.sendFrame(0x19); }, delay += step);
    }
  }

  private checkAndRetryParams(): void {
    if (this.isPlaybackMode || !this.isConnected) return;

    let needsRetry = false;
    if (this.deviceNameStr === '[空]') needsRetry = true;
    if (this.deviceTimeStr === '[空]') needsRetry = true;

    if (needsRetry && this.paramRetryCount < this.MAX_PARAM_RETRIES) {
      this.paramRetryCount++;
      let delay = 0;
      const step = 800;
      if (this.deviceNameStr === '[空]') {
        setTimeout(() => { this.sendFrame(0x03); }, delay += step);
      }
      if (this.deviceTimeStr === '[空]') {
        setTimeout(() => { this.sendFrame(0x15); }, delay += step);
      }
      this.paramRetryTimer = setTimeout(() => {
        this.checkAndRetryParams();
      }, 5000);
    }
  }

  private toHex(n: number): string {
    return n.toString(16).padStart(2, '0').toUpperCase();
  }

  private registerDataCallbacks(): void {
    this.transport.setOnStateChange(this.LISTENER_KEY, (state, deviceId): void => {
      if (this.isPlaybackMode) return;
      const isConn = (state === 'CONNECTED');
      this.setConnected(isConn);
      if (state === 'DISCONNECTED') {
        this.addLog(LogCategory.CONNECTION, '设备断开', '检测到连接中断', deviceId || '-');
        this.showToastMsg('设备已断开');
      } else if (isConn) {
        this.txPollCounter = 0;
        this.deviceMode = 'UNKNOWN';
        this.hasSyncedTime = false;
        this.startWaveCommandTimer();
      }
    });

    this.transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array): void => {
      if (this.isPlaybackMode) return;

      const frames = this.protocolParser.feed(data);
      frames.forEach((f: ProtocolFrame): void => {
        this.onFrameReceived(f);
      });
    });
  }

  private onFrameReceived(frame: ProtocolFrame): void {
    if (this.isPlaybackMode) return;

    const cmdByte = (frame.data && frame.data.length > 0) ? frame.data[0] : 0;
    if (cmdByte !== 0) {
      console.info('MonitorVM', `◀ 收到帧: cmd=0x${cmdByte.toString(16).toUpperCase()} dataLen=${frame.dataLength}`);
    }

    // ⭐ P1: 使用统一的全局 ProtocolParser，校验宽容规则放在业务层
    const isFiber = (frame.deviceType === 0x66);
    const isVoltage = (cmdByte === 0x97);
    if (!frame.checksumOk && !isFiber && !isVoltage) {
      console.warn('MonitorVM', `[校验和错误] 丢弃脏帧: DeviceType=${frame.deviceType}`);
      return;
    }

    const decoded = ProtocolDecoder.decode(frame.deviceType, frame.data);

    if (decoded && decoded.cmd === 0xFF) {
      console.info('MonitorVM', '↻ 拆解 0xFF 合并帧中...');
      const subDatas = ProtocolDecoder.parseMergeFrames(frame.data);
      for (const subData of subDatas) {
        const subFrame: ProtocolFrame = {
          raw: new Uint8Array(0),
          address: frame.address,
          deviceType: frame.deviceType,
          dataLength: subData.length,
          data: subData,
          checksum: 0,
          checksumOk: true
        };
        this.onFrameReceived(subFrame);
      }
      return;
    }

    if (!decoded || !decoded.payload) return;
    const payload = decoded.payload;

    if (!(payload instanceof Uint8Array)) {
      const cmdPayload = payload as CommandPayload;

      if (cmdPayload.type === 'fiber') {
        const channel = (cmdPayload as FiberDataPayload).channel;
        if (channel !== undefined && channel !== 0) {
          this.currentDeviceAddress = channel;
          const chStr = channel.toString().padStart(2, '0');
          if (this.deviceChannelStr !== chStr) {
            this.deviceChannelStr = chStr;
            this.checkAndLog('channel', channel);
          }
        }
      }

      if (cmdPayload.type === 'fiber') {
        if (this.deviceMode !== 'FIBER') {
          this.deviceMode = 'FIBER';
          this.deviceType = DeviceType.Fiber;
          this.readDeviceParams();
        }
      } else if (cmdPayload.type === 'tempHumidity' || cmdPayload.type === 'voltage') {
        if (this.deviceMode !== 'TX') {
          console.info('MonitorVM', '收到温湿度/电压，判定为发射端 TX');
          this.currentDeviceAddress = 0x01;
          this.deviceMode = 'TX';
          this.deviceType = DeviceType.Microwave;
          this.readDeviceParams();
        }
      } else if (cmdPayload.type === 'status' && this.deviceMode === 'UNKNOWN') {
        console.info('MonitorVM', '收到状态响应，暂判为接收端 RX');
        this.currentDeviceAddress = 0x01;
        this.deviceMode = 'RX';
        this.deviceType = DeviceType.Microwave;
        this.readDeviceParams();
      }

      if (cmdPayload.type === 'status') {
        const s = cmdPayload as StatusPayload;
        if (this.alarmOn !== s.alarm) this.alarmOn = s.alarm;
        if (this.tamperOn !== s.tamper) this.tamperOn = s.tamper;

        if (this.onStatusChangeCallback) {
          this.onStatusChangeCallback(this.alarmOn, this.tamperOn);
        }

        if (Date.now() - this.lastSetThresholdTime > 3000) {
          const strVal = s.alarmThreshold.toString();
          if (this.deviceThresholdStr !== strVal) {
            this.deviceThresholdStr = strVal;
          }
          if (this.sliderValue !== s.alarmThreshold) {
            this.sliderValue = s.alarmThreshold;
            this.checkAndLog('threshold', s.alarmThreshold);
          }
        }

        this.signalVm.pushStatus(s);
        this.checkAndLogSignal(s.signal);

        this.checkAndPlaySound();
        this.handleAutoDownload(s.alarm);
        this.handleRecording(s);

      } else if (cmdPayload.type === 'fiber') {
        const f = cmdPayload as FiberDataPayload;

        if (this.fiber1Signal !== f.fiber1Signal) this.fiber1Signal = f.fiber1Signal;
        if (this.fiber2Signal !== f.fiber2Signal) this.fiber2Signal = f.fiber2Signal;
        if (this.fiber3Signal !== (f.fiber3Signal ?? 0)) this.fiber3Signal = f.fiber3Signal ?? 0;
        if (this.fiber4Signal !== (f.fiber4Signal ?? 0)) this.fiber4Signal = f.fiber4Signal ?? 0;

        if (this.fiber1Up !== f.fiber1Up) this.fiber1Up = f.fiber1Up;
        if (this.fiber1Down !== f.fiber1Down) this.fiber1Down = f.fiber1Down;
        if (this.fiber2Up !== f.fiber2Up) this.fiber2Up = f.fiber2Up;
        if (this.fiber2Down !== f.fiber2Down) this.fiber2Down = f.fiber2Down;
        if (this.fiber3Up !== (f.fiber3Up ?? 0)) this.fiber3Up = f.fiber3Up ?? 0;
        if (this.fiber3Down !== (f.fiber3Down ?? 0)) this.fiber3Down = f.fiber3Down ?? 0;
        if (this.fiber4Up !== (f.fiber4Up ?? 0)) this.fiber4Up = f.fiber4Up ?? 0;
        if (this.fiber4Down !== (f.fiber4Down ?? 0)) this.fiber4Down = f.fiber4Down ?? 0;

        if (this.fiber1Sens !== f.fiber1Sens) this.fiber1Sens = f.fiber1Sens;
        if (this.fiber2Sens !== f.fiber2Sens) this.fiber2Sens = f.fiber2Sens;
        if (this.fiber3Sens !== (f.fiber3Sens ?? 0)) this.fiber3Sens = f.fiber3Sens ?? 0;
        if (this.fiber4Sens !== (f.fiber4Sens ?? 0)) this.fiber4Sens = f.fiber4Sens ?? 0;

        const a1 = f.alarm1 ?? false;
        const a2 = f.alarm2 ?? false;
        const a3 = f.alarm3 ?? false;
        const a4 = f.alarm4 ?? false;

        if (this.fiberAlarm1 !== a1) this.fiberAlarm1 = a1;
        if (this.fiberAlarm2 !== a2) this.fiberAlarm2 = a2;
        if (this.fiberAlarm3 !== a3) this.fiberAlarm3 = a3;
        if (this.fiberAlarm4 !== a4) this.fiberAlarm4 = a4;

        if (this.onFiberAlarmChangeCallback) {
          this.onFiberAlarmChangeCallback(a1, a2, a3, a4);
        }

        const anyFiberAlarm = a1 || a2 || a3 || a4;
        if (this.alarmOn !== anyFiberAlarm) {
          this.alarmOn = anyFiberAlarm;
          if (this.onStatusChangeCallback) {
            this.onStatusChangeCallback(this.alarmOn, this.tamperOn);
          }
        }

        this.checkAndPlaySound();

        if (this.fiberDisconnect !== f.disconnect) this.fiberDisconnect = f.disconnect;
        if (this.fiberTamper !== f.tamper) this.fiberTamper = f.tamper;

        if (Date.now() - this.lastSetThresholdTime > 3000) {
          let currentSens = 0;
          if (this.fiberChannelMode === 'CH2') currentSens = f.fiber2Sens;
          else if (this.fiberChannelMode === 'CH3') currentSens = f.fiber3Sens ?? 0;
          else if (this.fiberChannelMode === 'CH4') currentSens = f.fiber4Sens ?? 0;
          else currentSens = f.fiber1Sens;

          const strVal = currentSens.toString();
          if (this.deviceThresholdStr !== strVal) {
            this.deviceThresholdStr = strVal;
          }
          if (this.sliderValue !== currentSens) {
            this.sliderValue = currentSens;
            this.checkAndLog('threshold', currentSens);
          }
        }

        this.signalVm.pushFiber(f);
        this.checkAndLogSignal(f.fiber1Signal);

      } else if (cmdPayload.type === 'tempHumidity') {
        const t = cmdPayload as TempHumidityPayload;
        if (this.txTemp !== t.temperature) this.txTemp = t.temperature;
        if (this.txHum !== t.humidity) this.txHum = t.humidity;
        this.signalVm.pushTempHum(t.temperature, t.humidity);

      } else if (cmdPayload.type === 'voltage') {
        const v = cmdPayload as VoltagePayload;
        if (this.txMcuVol !== v.mcuVoltage) this.txMcuVol = v.mcuVoltage;
        if (this.txHighFreqVol !== v.highFreqVoltage) this.txHighFreqVol = v.highFreqVoltage;
        if (this.txInputVol !== v.inputVoltage) this.txInputVol = v.inputVoltage;
        this.signalVm.pushVoltages(v.mcuVoltage, v.highFreqVoltage, v.inputVoltage);

      } else if (cmdPayload.type === 'name') {
        const n = cmdPayload as DeviceNamePayload;

        if (this.connectionMode === 'TCP') {
          this.checkAndLog('name', this.deviceNameStr);
          this.flushPendingLogs();
        } else {
          try {
            if (this.nameManager && n.deviceIdHex) {
              this.nameManager.getName(n.deviceIdHex).then((localName: string) => {
                const finalName = localName ? localName : (n.isConfigured && n.name ? n.name : '[未命名]');
                if (this.deviceNameStr !== finalName) {
                  this.deviceNameStr = finalName;
                  this.checkAndLog('name', finalName);
                  this.flushPendingLogs();
                }
              }).catch(() => {
                const fallbackName = n.isConfigured && n.name ? n.name : '[未命名]';
                if (this.deviceNameStr !== fallbackName) {
                  this.deviceNameStr = fallbackName;
                  this.checkAndLog('name', fallbackName);
                  this.flushPendingLogs();
                }
              });
            } else {
              const fallbackName = n.isConfigured && n.name ? n.name : '[未命名]';
              if (this.deviceNameStr !== fallbackName) {
                this.deviceNameStr = fallbackName;
                this.checkAndLog('name', fallbackName);
                this.flushPendingLogs();
              }
            }
          } catch(e) {
            console.error('getName error:', e);
          }
        }

      } else if (cmdPayload.type === 'channel') {
        if (this.deviceMode !== 'FIBER') {
          const val = (cmdPayload as ChannelPayload).channel;
          const chStr = val.toString().padStart(2, '0');
          if (this.deviceChannelStr !== chStr) {
            this.deviceChannelStr = chStr;
            this.checkAndLog('channel', val);
          }
        }
      } else if (cmdPayload.type === 'alarmThreshold' || cmdPayload.type === 'sensitivity') {
        const val = (cmdPayload as SensitivityPayload).sensitivity || (cmdPayload as AlarmThresholdPayload).threshold;
        const strVal = val.toString();
        if (this.deviceThresholdStr !== strVal) {
          this.deviceThresholdStr = strVal;
        }
        if (this.sliderValue !== val) {
          this.sliderValue = val;
          this.checkAndLog('threshold', val);
        }

      } else if (cmdPayload.type === 'time') {
        const t = cmdPayload as DeviceTimePayload;
        const pad = (n: number) => n.toString().padStart(2, '0');
        const timeStr = `${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}`;

        if (this.deviceTimeStr !== timeStr) {
          this.deviceTimeStr = timeStr;
        }

        try {
          const deviceTime = new Date(t.year, t.month - 1, t.day, t.hour, t.minute, t.second).getTime();
          const localTime = Date.now();
          if (Math.abs(deviceTime - localTime) > 2000) {
            if (!this.hasSyncedTime) {
              this.hasSyncedTime = true;
              this.syncTimeToDevice();
            }
          } else {
            this.hasSyncedTime = false;
          }
        } catch (e) {
          console.error('Time sync error:', e);
        }
      }
    }
  }

  setItemList() {}

  setAutoDownload(v: boolean) {
    this.autoDownload = v;
  }

  private handleAutoDownload(isAlarm: boolean) {
    if (!this.autoDownload || !this.context) return;

    if (isAlarm && !this.isAlarmingLocked) {
      this.isAlarmingLocked = true;

      // ⭐ P0: 设置新定时器前，先清掉旧的防止堆积
      if (this.alarmDebounceTimer !== -1) {
        clearTimeout(this.alarmDebounceTimer);
      }

      this.alarmDebounceTimer = setTimeout(() => {
        this.saveAlarmSnapshot();
      }, 2500);

    } else if (!isAlarm) {
      this.isAlarmingLocked = false;

      // ⭐ P0: 报警恢复时，截断未执行的截图任务
      if (this.alarmDebounceTimer !== -1) {
        clearTimeout(this.alarmDebounceTimer);
        this.alarmDebounceTimer = -1;
      }
    }
  }

  public manualSnapshot() {
    this.saveAlarmSnapshot(false);
  }

  private async saveAlarmSnapshot(isAuto: boolean = true) {
    if (!this.context) return;
    try {
      const samples = this.signalVm.getBufferSnapshot(100);
      if (samples.length === 0) return;
      const name = this.deviceNameStr;
      const channelStr = this.deviceChannelStr;
      const now = new Date();
      const pad = (n: number) => n.toString().padStart(2, '0');
      const alarmTimeStr = `${now.getHours()}:${pad(now.getMinutes())}:${pad(now.getSeconds())}.${pad(Math.floor(now.getMilliseconds()/10))}`;
      const info: SnapshotInfo = {
        deviceName: name,
        threshold: this.sliderValue,
        channel: channelStr,
        alarmTime: alarmTimeStr
      };
      const pathDir = FileUtil.getStandardPath(this.context, name, '报警图');
      const fileName = FileUtil.generateFileName('.png');
      await ImageGenerator.saveWaveformImage(samples, info, `${pathDir}/${fileName}`);
      this.showToastMsg(isAuto ? `自动保存报警图成功` : `手动截图已保存`);
    } catch (e) {
      console.error('saveAlarmSnapshot error:', e);
    }
  }

  toggleRecording() {
    if (this.isPlaybackMode) return;
    if (this.isRecording) {
      this.stopRecording();
    } else {
      this.startRecording();
    }
  }

  private startRecording() {
    this.isRecording = true;
    this.recordBuffer = [];
    this.recordStartTime = Date.now();
    this.showToastMsg('开始录像...');
  }

  stopRecording() {
    if (!this.isRecording) return;
    this.isRecording = false;
    this.saveRecordFile();
  }

  private handleRecording(s: StatusPayload) {
    if (this.isRecording) {
      this.recordBuffer.push({
        t: Date.now() - this.recordStartTime,
        s: s.signal,
        th: s.alarmThreshold,
        a: s.alarm ? 1 : 0,
        tm: s.tamper ? 1 : 0
      });
    }
  }

  private async saveRecordFile() {
    if (!this.context || this.recordBuffer.length === 0) return;
    try {
      const pathDir = FileUtil.getStandardPath(this.context, this.deviceNameStr, '数据录像');
      const fileName = FileUtil.generateFileName('.json');
      const content = JSON.stringify(this.recordBuffer);
      await FileUtil.writeText(`${pathDir}/${fileName}`, content);
      this.showToastMsg(`录像已保存`);
    } catch (e) {
      console.error('saveRecordFile error:', e);
    }
  }

  private async readFileContent(path: string): Promise<string> {
    try {
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      const buf = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buf);
      await fs.close(file);

      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (e) {
      console.error('readFileContent error:', e);
      throw new Error(String(e));
    }
  }

  private async startPlayback(filePath: string) {
    try {
      const content = await this.readFileContent(filePath);
      const parsedObj = JSON.parse(content) as Object;
      const data = parsedObj as Array<RecordFrame>;
      if (!data || data.length === 0) {
        this.showToastMsg('录像文件为空');
        return;
      }
      this.playbackData = data;
      this.playbackIndex = 0;
      this.playbackProgress = 0;
      this.signalVm.clearBuffer();
      const totalMs = data[data.length - 1].t;
      const min = Math.floor(totalMs / 60000);
      const sec = Math.floor((totalMs % 60000) / 1000);
      this.playbackTotalDuration = `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
      this.startPlaybackTimer();
    } catch (e) {
      console.error('startPlayback error:', e);
      this.showToastMsg('无法加载录像');
    }
  }

  private startPlaybackTimer() {
    this.stopPlaybackTimer();
    this.playbackFrameAccumulator = 0;
    this.playbackTimer = setInterval(() => {
      this.processPlaybackTick();
    }, 20);
  }

  private stopPlaybackTimer() {
    if (this.playbackTimer !== -1) {
      clearInterval(this.playbackTimer);
      this.playbackTimer = -1;
    }
  }

  private processPlaybackTick() {
    if (this.isPlaybackPaused) return;
    if (this.playbackIndex >= this.playbackData.length) {
      this.stopPlayback();
      return;
    }
    const framesToProcess = this.playbackRate;
    this.playbackFrameAccumulator += framesToProcess;
    let count = Math.floor(this.playbackFrameAccumulator);
    this.playbackFrameAccumulator -= count;
    let lastFrame: RecordFrame | null = null;
    for (let i = 0; i < count; i++) {
      if (this.playbackIndex >= this.playbackData.length) break;
      const frame = this.playbackData[this.playbackIndex];
      lastFrame = frame;
      const isAlarm = (frame.a !== undefined) ? (frame.a === 1) : (frame.s >= frame.th);
      const isTamper = (frame.tm !== undefined) ? (frame.tm === 1) : false;
      const mockStatus: StatusPayload = {
        type: 'status',
        signal: frame.s,
        alarmThreshold: frame.th,
        alarm: isAlarm,
        tamper: isTamper,
        statusRaw: 0,
        binary: '',
      };
      this.signalVm.pushStatus(mockStatus);
      this.playbackIndex++;
    }
    if (lastFrame) {
      const isAlarm = (lastFrame.a !== undefined) ? (lastFrame.a === 1) : (lastFrame.s >= lastFrame.th);
      const isTamper = (lastFrame.tm !== undefined) ? (lastFrame.tm === 1) : false;
      this.alarmOn = isAlarm;
      this.tamperOn = isTamper;
      if (this.onStatusChangeCallback) {
        this.onStatusChangeCallback(this.alarmOn, this.tamperOn);
      }
      this.checkAndPlaySound();
      this.playbackProgress = (this.playbackIndex / this.playbackData.length) * 100;
    }
  }

  stopPlayback() {
    this.stopPlaybackTimer();
    this.playbackProgress = 100;
    this.alarmOn = false;
    this.stopAlarmSoundImmediate();
    this.showToastMsg('回放结束');
  }

  seekPlayback(percent: number) {
    if (this.playbackData.length === 0) return;
    let targetIndex = Math.floor((percent / 100) * this.playbackData.length);
    if (targetIndex >= this.playbackData.length) targetIndex = this.playbackData.length - 1;
    if (targetIndex < 0) targetIndex = 0;
    this.playbackIndex = targetIndex;
    this.playbackProgress = percent;
    this.signalVm.clearBuffer();
  }

  setPlaybackRate(rate: number) {
    this.playbackRate = rate;
  }

  togglePlaybackPause() {
    if (this.playbackTimer === -1 && this.playbackData.length > 0) {
      this.startPlaybackTimer();
      this.isPlaybackPaused = false;
      if (this.playbackIndex >= this.playbackData.length - 1) {
        this.playbackIndex = 0;
        this.signalVm.clearBuffer();
      }
      return;
    }
    this.isPlaybackPaused = !this.isPlaybackPaused;
    if (this.isPlaybackPaused) {
      this.stopAlarmSoundImmediate();
    }
  }

  setConnected(connected: boolean): void {
    if (this.isPlaybackMode) return;
    this.isConnected = connected;
    if (connected) {
      this.startTimeSyncLoop();
      this.startWaveCommandTimer();
      this.startWaveUiTimer();
    } else {
      // ⭐ P0: 断开时彻底停掉所有定时器，防止后台空跑
      this.stopWaveCommandTimer();
      this.stopTimeSyncLoop();
      this.stopWaveUiTimer();
      this.clearLogState();
      this.pendingLogs = [];

      // 重置波形数据，避免 UI 停留在最后一帧乱码
      this.signalVm.clearBuffer();
      this.avgValue = 0;
      this.variance = 0;
    }
  }

  private startWaveUiTimer(): void {
    if (this.waveUiTimer !== -1) return;
    this.waveUiTimer = setInterval(() => {
      const samples = this.signalVm.getVisibleSamples();
      if (samples.length > 0) {
        let sum = 0;
        for (let s of samples) {
          sum += (s.signal ?? 0);
        }
        const avg = sum / samples.length;
        this.avgValue = avg;
        let sumSqDiff = 0;
        for (let s of samples) {
          const diff = (s.signal ?? 0) - avg;
          sumSqDiff += diff * diff;
        }
        this.variance = sumSqDiff / samples.length;
      }
      this.waveVersion++;

      if (this.listenEnable) {
        this.processListenLogic();
      }
    }, 33);
  }

  private processListenLogic() {
    const now = Date.now();
    if (this.variance > this.listenVariance) {
      this.currentCycleFailed = true;
    }
    const cycleDuration = this.listenTime * 60 * 1000;
    const elapsedInCycle = now - this.listenCycleStartTime;

    if (elapsedInCycle >= cycleDuration) {
      this.listenTotalCycles++;
      if (this.currentCycleFailed) {
        this.listenFailCycles++;
      } else {
        this.listenSuccessCycles++;
      }
      this.listenCycleStartTime = now;
      this.currentCycleFailed = false;
    }

    const totalElapsed = now - this.listenStartTime;
    const min = Math.floor(totalElapsed / 60000);
    const sec = Math.floor((totalElapsed % 60000) / 1000);
    const timeStr = `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
    const statusStr = this.currentCycleFailed ? '⚠超标' : '✔正常';
    this.listenStatusText = `${timeStr} | ${statusStr} | 周期:${this.listenTotalCycles} | 过:${this.listenSuccessCycles} | 挂:${this.listenFailCycles}`;
  }

  detectScreenSize(): void {
    const info = detectScreenInfo();
    this.screenType = info.screenType;
    this.isLargeScreen = info.isLargeScreen;
    if (info.screenType === 'FOLD') {
      this.isFoldDevice = true;
    }
  }

  updateCurrentTime(): void {
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    this.currentTimeStr = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
  }

  startTimeTimer(): void {
    if (this.timeTimer === -1) {
      this.timeTimer = setInterval(() => {
        this.updateCurrentTime();
      }, 1000);
    }
  }

  stopTimeTimer(): void {
    if (this.timeTimer !== -1) {
      clearInterval(this.timeTimer);
      this.timeTimer = -1;
    }
  }

  stopWaveUiTimer(): void {
    if (this.waveUiTimer !== -1) {
      clearInterval(this.waveUiTimer);
      this.waveUiTimer = -1;
    }
  }

  startWaveCommandTimer(): void {
    if (this.isPlaybackMode) return;
    if (this.waveTimer === -1) {
      this.waveTimer = setInterval(() => {
        if (!this.isConnected) return;

        if (this.deviceMode === 'FIBER') {
          this.sendFrame(0xAA, [], 0x66, this.currentDeviceAddress);
        } else if (this.deviceMode === 'RX') {
          this.sendFrame(0x0B, [], 0xC9, this.currentDeviceAddress);
        } else if (this.deviceMode === 'TX') {
          const sendCmd = this.txPollCounter % 2 === 0 ? 0x96 : 0x97;
          console.info('MonitorVM', `▶ 发送TX查询: cmd=0x${sendCmd.toString(16)} addr=${this.currentDeviceAddress} cnt=${this.txPollCounter}`);
          this.sendFrame(sendCmd, [], 0xC9, this.currentDeviceAddress);
          this.txPollCounter++;
        } else {
          const now = Date.now();
          if (now - this.lastProbeTime < 150) return;
          this.lastProbeTime = now;

          let probeAddr = this.txPollCounter % 16;

          if (this.deviceType === DeviceType.Fiber) {
            this.sendFrame(0xAA, [], 0x66, probeAddr);
          } else if (this.deviceType === DeviceType.Microwave) {
            const phase = this.txPollCounter % 2;
            if (phase === 0) this.sendFrame(0x0B, [], 0xC9, 0x01);
            else this.sendFrame(0x96, [], 0xC9, 0x01);
          } else {
            const phase = this.txPollCounter % 3;
            if (phase === 0) this.sendFrame(0x0B, [], 0xC9, 0x01);
            else if (phase === 1) this.sendFrame(0xAA, [], 0x66, probeAddr);
            else this.sendFrame(0x96, [], 0xC9, 0x01);
          }
          this.txPollCounter++;
        }
      }, this.waveIntervalMs);
    }
  }

  stopWaveCommandTimer(): void {
    if (this.waveTimer !== -1) {
      clearInterval(this.waveTimer);
      this.waveTimer = -1;
    }
  }

  async initAudioPlayer(ctx: common.UIAbilityContext) {
    try {
      const info: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_ALARM,
        rendererFlags: 0
      };
      this.soundPool = await media.createSoundPool(5, info);
      const fd = await ctx.resourceManager.getRawFd('alarm.mp3');
      this.soundId = await this.soundPool.load(fd.fd, fd.offset, fd.length);
    } catch (e) {
      console.error('initAudioPlayer error:', e);
    }
  }

  checkAndPlaySound() {
    if (this.isMute) {
      this.stopAlarmSoundImmediate();
      return;
    }
    if (this.alarmOn) {
      this.lastAlarmTriggerTime = Date.now();
      if (this.stopAlarmTimer !== -1) clearTimeout(this.stopAlarmTimer);
      this.playAlarmSoundActual();
    } else {
      if (Date.now() - this.lastAlarmTriggerTime < 1000 && this.isAudioPlaying) {
        if (this.stopAlarmTimer === -1) {
          this.stopAlarmTimer = setTimeout(() => {
            this.stopAlarmSoundImmediate();
            this.stopAlarmTimer = -1;
          }, 1000 - (Date.now() - this.lastAlarmTriggerTime));
        }
      } else {
        this.stopAlarmSoundImmediate();
      }
    }
  }

  private async playAlarmSoundActual() {
    if (!this.soundPool || this.isAudioPlaying) return;
    try {
      this.streamId = await this.soundPool.play(this.soundId, {
        loop: -1, rate: 1, leftVolume: 1, rightVolume: 1, priority: 0
      });
      this.isAudioPlaying = true;
    } catch (e) {
      console.error('playAlarmSoundActual error:', e);
      this.isAudioPlaying = false;
    }
  }

  private async stopAlarmSoundImmediate() {
    if (!this.soundPool || this.streamId === -1) return;
    try {
      await this.soundPool.stop(this.streamId);
      this.streamId = -1;
      this.isAudioPlaying = false;
    } catch (e) {
      console.error('stopAlarmSoundImmediate error:', e);
    }
  }

  releaseAudioPlayer() {
    if (this.soundPool) {
      try { 
        this.soundPool.release(); 
      } catch (e) {
        console.error('releaseAudioPlayer error:', e);
      }
      this.soundPool = undefined;
    }
  }

  disconnectAndGoHome(): void {
    try {
      try {
        this.transport.disconnect();
      } catch (e) {
        console.error('[disconnect error]', String(e));
      }

      if (this.uiContext) {
        try {
          this.uiContext.getRouter().replaceUrl({
            url: 'pages/HomePage'
          }, router.RouterMode.Standard).catch((e: Error) => {
            console.error('[router error]', String(e));
          });
        } catch(e) {
          console.error('[router sync replace error]', String(e));
        }
      }
    } catch (e) {
      console.error('[disconnectAndGoHome]', String(e));
    }
  }

  openListenDialog() { this.showListenDialog = true; }
  closeListenDialog() { this.showListenDialog = false; }
  updateListenTime(v: string) { this.listenTime = parseInt(v) || 1; }
  updateListenVariance(v: string) { this.listenVariance = parseInt(v) || 5; }
  setListenEnable(v: boolean) { this.listenEnable = v; }

  saveListenSettings() {
    this.showListenDialog = false;
    if (this.listenEnable) {
      const now = Date.now();
      this.listenStartTime = now;
      this.listenCycleStartTime = now;
      this.listenTotalCycles = 0;
      this.listenSuccessCycles = 0;
      this.listenFailCycles = 0;
      this.currentCycleFailed = false;
      this.listenStatusText = '初始化...';
      this.showToastMsg('监听已启动');
    } else {
      this.listenStatusText = '';
    }
  }

  toggleMute() {
    this.isMute = !this.isMute;
    this.checkAndPlaySound();
    this.showToastMsg(this.isMute ? '已静音' : '声音已开启');
  }

  updateThresholdFromInput(v: string) {
    this.sliderValue = parseInt(v) || 0;
    this.lastSetThresholdTime = Date.now();
  }

  updateThresholdFromSlider(v: number) {
    this.sliderValue = v;
    this.lastSetThresholdTime = Date.now();
  }

  startTimeSyncLoop() {
    if (this.timeSyncTimer === -1) {
      this.timeSyncTimer = setInterval(() => {
        if (this.isConnected && !this.isPollingPaused) {
          this.sendFrame(0x15);
        }
      }, 3000);
    }
  }

  stopTimeSyncLoop() {
    if (this.timeSyncTimer !== -1) {
      clearInterval(this.timeSyncTimer);
      this.timeSyncTimer = -1;
    }
  }

  onPageShow() {
    if (this.isPlaybackMode) return;
    this.registerDataCallbacks();
    if (this.isConnected) {
      this.startWaveCommandTimer();
      
      if (this.deviceMode === 'TX') {
        console.info('MonitorVM', '发射端页面唤醒，执行高频电压和温湿度强刷');
        this.sendFrame(0x96, [], 0xC9, 0x01); 
        setTimeout(() => {
          this.sendFrame(0x97, [], 0xC9, 0x01); 
        }, 150);
      } else {
        this.readDeviceParams();
      }
    }
  }

  onPageHide() {
    this.stopWaveCommandTimer();
    this.stopAlarmSoundImmediate();
    if (this.isRecording) {
      this.stopRecording();
    }
  }

  setOnStatusChange(cb: (alarm: boolean, tamper: boolean) => void) {
    this.onStatusChangeCallback = cb;
  }

  setOnFiberAlarmChange(cb: (a1: boolean, a2: boolean, a3: boolean, a4: boolean) => void) {
    this.onFiberAlarmChangeCallback = cb;
  }

  setWaveIntervalMs(v: number): void {
    this.waveIntervalMs = v;
    if (this.isConnected) {
      this.stopWaveCommandTimer();
      this.startWaveCommandTimer();
    }
  }

  setDisplayPointCount(v: number): void {
    this.displayPointCount = v;
    this.signalVm.setDisplayCount(v);
  }

  setMaster(v: boolean) {
    this.isMaster = v;
  }

  onNavClick(idx: number): void {
    this.currentTab = idx;
    try {
      const navParams: Record<string, Object> = {};
      navParams['deviceName'] = this.deviceNameStr;
      navParams['deviceType'] = this.deviceType;
      navParams['connectionMode'] = this.connectionMode;
      navParams['deviceAddress'] = this.currentDeviceAddress;
      navParams['deviceKind'] = this.deviceMode; 

      if (this.uiContext) {
        const routerInstance = this.uiContext.getRouter();
        switch (idx) {
          case 1: {
            try { routerInstance.replaceUrl({ url: 'pages/CalibratePage', params: navParams }, router.RouterMode.Standard).catch((e: Error) => { console.error('Router error:', e); }); } catch(e) { console.error('Router error:', e); }
            break;
          }
          case 2: {
            try { routerInstance.replaceUrl({ url: 'pages/AlarmRecordPage', params: navParams }, router.RouterMode.Standard).catch((e: Error) => { console.error('Router error:', e); }); } catch(e) { console.error('Router error:', e); }
            break;
          }
          case 3: {
            try { routerInstance.replaceUrl({ url: 'pages/SettingPage', params: navParams }, router.RouterMode.Standard).catch((e: Error) => { console.error('Router error:', e); }); } catch(e) { console.error('Router error:', e); }
            break;
          }
          case 4: {
            try { routerInstance.replaceUrl({ url: 'pages/LogPage', params: navParams }, router.RouterMode.Standard).catch((e: Error) => { console.error('Router error:', e); }); } catch(e) { console.error('Router error:', e); }
            break;
          }
        }
      }
    } catch (err) {
      console.error('onNavClick error:', err);
    }
  }
}
