import { ProtocolDecoder } from '../common/ProtocolDecoder';
import { StatusPayload, CalibrateSignalPayload, CommandPayload } from '../common/protocol/ProtocolTypes';
import { ProtocolFrame, DeviceType, ProtocolParser } from '../common/ProtocolParser';
import { common } from '@kit.AbilityKit';
import { constant } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { MonitorPageParams } from '../viewmodel/MonitorViewModel';
import { ScreenType } from '../common/ScreenTypeHelper';
import { TransportManager } from '../common/transport/TransportManager';
import { ITransport } from '../common/transport/ITransport';
import { LogManager } from '../common/database/LogManager';
import { LogCategory } from '../common/database/LogEntity';

interface ExtendedProtocolFrame {
  deviceType?: number;
  payloadBytes?: Uint8Array;
  payload?: Uint8Array;
  data?: Uint8Array;
  raw?: Uint8Array;
}

@Observed
export class SignalCalibrateViewModel {
  signalHistory: number[] = [];
  peakWindowHistory: number[] = [];
  peakTime: string = '--:--:--';
  currentSignal: number = 0;
  maxSignal: number = 0;
  tipText: string = '正在检测设备状态...';
  lastUpdateTime: string = '--:--:--';

  isCalibrating: boolean = false;
  // ⭐ 统一使用内部 Parser
  private protocolParser: ProtocolParser = new ProtocolParser();
  private transport: ITransport;

  private signalBuffer: number[] = [];
  private lastUiUpdate: number = 0;
  private readonly UI_UPDATE_INTERVAL = 100;

  private context?: common.UIAbilityContext;

  private deviceType: DeviceType = DeviceType.Microwave;
  private connectionMode: 'BLE' | 'TCP' = 'BLE';
  private screenType: ScreenType = 'PHONE';

  private currentAddress: number = 0x01;
  private lastCalibrationDataTime: number = 0;

  // ⭐ 新增：手动停止标志位，防止残余数据自动触发开启
  private isManuallyStopped: boolean = false;

  // ⭐ 定义唯一监听 Key
  private readonly LISTENER_KEY = 'SignalCalibrateVM';

  // ⭐ 新增：上一次记录的信号值，用于日志去重 (波动 >= 5 才记录)
  private lastLoggedSignal: number = -999;

  // ⭐ 新增：保存设备名称用于日志
  private deviceName: string = '未知设备';

  constructor() {
    this.transport = TransportManager.getInstance().getTransport();
  }

  init(params: MonitorPageParams, ctx: common.UIAbilityContext) {
    this.context = ctx;
    if (params) {
      this.deviceType = params.deviceType ?? DeviceType.Microwave;
      this.connectionMode = params.connectionMode ?? 'BLE';
      if (params.screenType) {
        this.screenType = params.screenType;
      }
      // ⭐ 获取设备名称
      if (params.deviceName) {
        this.deviceName = params.deviceName;
      }
    }

    this.transport = TransportManager.getInstance().getTransport();
    this.registerCallbacks();

    if (this.deviceType === DeviceType.Microwave) {
      this.lastCalibrationDataTime = 0;
      this.isManuallyStopped = false; // 初始化时重置
      this.scheduleAutoStartChecks();
    } else {
      this.tipText = '当前设备非微波设备，无需校准';
    }
  }

  private scheduleAutoStartChecks() {
    setTimeout(() => {
      this.checkAndAutoStart('快速检测');
    }, 800);

    setTimeout(() => {
      this.checkAndAutoStart('二次验证');
    }, 3000);
  }

  private checkAndAutoStart(reason: string) {
    // ⭐ 修复：使用标志位判断，替代不稳定的 tipText 字符串匹配
    if (this.isCalibrating === false && this.isManuallyStopped) {
      return;
    }

    const now = Date.now();
    const hasRecentData = (this.lastCalibrationDataTime > 0) && (now - this.lastCalibrationDataTime < 1500);

    if (hasRecentData) {
      if (!this.isCalibrating) {
        this.isCalibrating = true;
        this.tipText = '检测到设备正在传输校准数据...';
      }
    } else {
      if (this.transport.isConnected()) {
        console.info(`[Calibrate] ${reason}: 未收到数据，自动发送开始指令`);
        this.startCalibration();
      }
    }
  }

  getNavParams(): MonitorPageParams {
    return {
      deviceType: this.deviceType,
      connectionMode: this.connectionMode,
      screenType: this.screenType,
      deviceName: this.deviceName // 传递回去
    };
  }

  onAppear(ctx?: common.UIAbilityContext) {
    if (ctx) this.context = ctx;
    this.registerCallbacks();
  }

  onPageHide() {
    if (this.isCalibrating) {
      this.stopCalibration();
    }
  }

  onDisappear() {
    if (this.isCalibrating) {
      this.stopCalibration();
    }
    // ⭐ 注销监听
    this.transport.offDataReceived(this.LISTENER_KEY);
  }

  public registerCallbacks() {
    // ⭐ 统一使用多播监听
    this.transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array) => {
      const frames = this.protocolParser.feed(data);
      frames.forEach((frame): void => this.handleFrame(frame));
    });
  }

  private handleFrame(frame: ProtocolFrame) {
    if (frame.address > 0) {
      this.currentAddress = frame.address;
    }

    try {
      const ext: ExtendedProtocolFrame = frame as ExtendedProtocolFrame;
      const devType: number = ext.deviceType ?? 0;
      const payloadBytes: Uint8Array | undefined = ext.data;

      if (!payloadBytes || payloadBytes.length === 0) return;

      const decoded = ProtocolDecoder.decode(devType, payloadBytes);
      if (!decoded || !decoded.payload) return;

      const payload = decoded.payload;

      if (!(payload instanceof Uint8Array)) {
        const cmdPayload = payload as CommandPayload;

        if (decoded.cmd === 0x01 && cmdPayload.type === 'calibrateSignal') {
          this.lastCalibrationDataTime = Date.now();

          // ⭐ 核心修复：如果用户已手动停止，忽略残余的校准数据，不自动恢复状态
          if (this.isManuallyStopped) {
            return;
          }

          if (!this.isCalibrating) {
            this.isCalibrating = true;
          }
          const p = cmdPayload as CalibrateSignalPayload;
          this.processSignalValue(p.signal);
        }
        else if (cmdPayload.type === 'status') {
          const p = cmdPayload as StatusPayload;
          // 状态包的数据即使在停止时也可以更新显示，但不改变校准状态
          this.processSignalValue(p.signal);
        }
      }

    } catch (e) {
      console.error('SignalCalibrateViewModel decode error: ' + e);
    }
  }

  private processSignalValue(signal: number) {
    this.signalBuffer.push(signal);
    const now = Date.now();
    if (now - this.lastUiUpdate > this.UI_UPDATE_INTERVAL) {
      this.flushUiUpdate(now);
    }

    // ⭐⭐ 日志记录逻辑：波动过滤 (>=5) ⭐⭐
    if (this.isCalibrating) {
      // 如果是首次记录 (-999) 或者 波动超过 5，则记录
      const diff = Math.abs(signal - this.lastLoggedSignal);
      if (this.lastLoggedSignal === -999 || diff >= 5) {
        LogManager.getInstance().addLog(
          LogCategory.MAINTENANCE,
          '校准信号',
          `数值: ${signal}`,
          { name: this.deviceName, id: this.transport.getId() }
        );
        this.lastLoggedSignal = signal;
      }
    }
  }

  private flushUiUpdate(now: number) {
    if (this.signalBuffer.length === 0) return;

    let batchMax = 0;
    const latestSignal = this.signalBuffer[this.signalBuffer.length - 1];

    for (let val of this.signalBuffer) {
      if (val > batchMax) batchMax = val;
    }

    this.currentSignal = latestSignal;

    if (batchMax > this.maxSignal) {
      this.maxSignal = batchMax;
      const d = new Date();
      this.peakTime = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;

      const windowStart = Math.max(0, this.signalHistory.length - 30);
      this.peakWindowHistory = [...this.signalHistory.slice(windowStart), batchMax];
    }

    const history = [...this.signalHistory, latestSignal];
    const MAX_LEN = 100;
    if (history.length > MAX_LEN) {
      history.splice(0, history.length - MAX_LEN);
    }
    this.signalHistory = history;

    const d = new Date();
    this.lastUpdateTime = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;

    // 只有在非手动停止（即正常校准或监听状态）时才更新提示文字
    if (!this.isManuallyStopped) {
      this.tipText = `正在校准... 当前信号: ${this.currentSignal} / 最大值: ${this.maxSignal}`;
    }

    this.lastUiUpdate = now;
    this.signalBuffer = [];
  }

  clearMax() {
    this.maxSignal = this.currentSignal;
    this.peakWindowHistory = [];
    this.peakTime = '--:--:--';
  }

  simulateRandomSignal() {
    const val = Math.floor(Math.random() * 255);
    this.processSignalValue(val);
  }

  private buildCommand(len: number, cmd: number, data: number[] = []): string {
    const addr = this.currentAddress;
    const type = this.deviceType;
    let sum = type + len + cmd;
    for (let b of data) {
      sum += b;
    }
    const cs = sum & 0xFF;
    let hex = `FF${this.toHex(addr)}${this.toHex(type)}${this.toHex(len)}${this.toHex(cmd)}`;
    for (let b of data) {
      hex += this.toHex(b);
    }
    hex += this.toHex(cs);
    return hex;
  }

  startCalibration() {
    if (!this.transport.isConnected()) {
      try { promptAction.showToast({ message: '设备未连接' }); } catch(e){}
      return;
    }

    if (!this.isCalibrating) {
      this.signalHistory = [];
      this.peakWindowHistory = [];
      this.currentSignal = 0;
      this.maxSignal = 0;
      this.signalBuffer = [];
      this.lastUpdateTime = '--:--:--';
      this.peakTime = '--:--:--';
    }

    // ⭐ 重置手动停止标志
    this.isManuallyStopped = false;
    this.isCalibrating = true;
    // ⭐ 重置日志去重基准，确保重新开始时能记录当前值
    this.lastLoggedSignal = -999;

    this.tipText = '发送校准指令...';

    const hex = this.buildCommand(0x01, 0x01, []);
    this.sendHex(hex);

    try { promptAction.showToast({ message: '开始校准' }); } catch(e){}
  }

  stopCalibration() {
    if (!this.isCalibrating) return;

    const hex = this.buildCommand(0x02, 0x01, [0x87]);
    this.sendHex(hex);

    // ⭐ 设置手动停止标志，阻止自动恢复
    this.isManuallyStopped = true;
    this.isCalibrating = false;
    this.tipText = `校准已停止。最大信号：${this.maxSignal}`;
    try { promptAction.showToast({ message: '停止校准' }); } catch(e){}
  }

  private toHex(n: number): string {
    return n.toString(16).padStart(2, '0').toUpperCase();
  }

  private sendHex(hex: string) {
    this.transport.sendHexString(hex);
  }
}