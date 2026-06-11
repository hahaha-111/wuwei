import { ProtocolDecoder } from '../common/ProtocolDecoder';
import { StatusPayload, CalibrateSignalPayload, CommandPayload } from '../common/protocol/ProtocolTypes';
import { ProtocolFrame, DeviceType, ProtocolParser } from '../common/ProtocolParser';
import { UIContext } from '@kit.ArkUI'; 
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
  private protocolParser: ProtocolParser = new ProtocolParser();
  private transport: ITransport;

  private signalBuffer: number[] = [];
  private lastUiUpdate: number = 0;
  private readonly UI_UPDATE_INTERVAL = 100;

  private deviceType: DeviceType = DeviceType.Microwave;
  private connectionMode: 'BLE' | 'TCP' = 'BLE';
  private screenType: ScreenType = 'PHONE';

  private currentAddress: number = 0x01;
  private lastCalibrationDataTime: number = 0;

  private isManuallyStopped: boolean = false;

  private readonly LISTENER_KEY = 'SignalCalibrateVM';

  private lastLoggedSignal: number = -999;
  private deviceName: string = '未知设备';

  public uiContext: UIContext | null = null;

  constructor() {
    this.transport = TransportManager.getInstance().getTransport();
  }

  private safeShowToast(msg: string) {
    if (this.uiContext) {
      try {
        this.uiContext.getPromptAction().showToast({ message: msg });
      } catch (e) {
        console.error('ShowToast error:', e);
      }
    }
  }

  // ⭐ 修复：统一修改为只接收 1 个参数，与页面层完美匹配，且彻底删除了不需要的 context 上下文
  init(params: Record<string, Object> | undefined) {
    if (params) {
      if (params['deviceType'] !== undefined) {
        this.deviceType = params['deviceType'] as number;
      }
      if (params['connectionMode'] !== undefined) {
        this.connectionMode = params['connectionMode'] as ('BLE' | 'TCP');
      }
      if (params['screenType'] !== undefined) {
        this.screenType = params['screenType'] as ScreenType;
      }
      if (params['deviceName'] !== undefined) {
        this.deviceName = params['deviceName'] as string;
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

  getNavParams(): Record<string, Object> {
    const p: Record<string, Object> = {};
    p['deviceType'] = this.deviceType;
    p['connectionMode'] = this.connectionMode;
    p['screenType'] = this.screenType;
    p['deviceName'] = this.deviceName;
    return p;
  }

  // ⭐ 修复：彻底清理废弃的参数接收
  onAppear() {
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
    this.transport.offDataReceived(this.LISTENER_KEY);
  }

  public registerCallbacks() {
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

    if (this.isCalibrating) {
      const diff = Math.abs(signal - this.lastLoggedSignal);
      if (this.lastLoggedSignal === -999 || diff >= 5) {
        LogManager.getInstance().addLog(
          LogCategory.MAINTENANCE,
          '校准信号',
          `数值: ${signal}`,
          { name: this.deviceName, id: this.transport.getId() || '-' }
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
      this.safeShowToast('设备未连接');
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

    this.isManuallyStopped = false;
    this.isCalibrating = true;
    this.lastLoggedSignal = -999;

    this.tipText = '发送校准指令...';

    const hex = this.buildCommand(0x01, 0x01, []);
    this.sendHex(hex);

    this.safeShowToast('开始校准');
  }

  stopCalibration() {
    if (!this.isCalibrating) return;

    const hex = this.buildCommand(0x02, 0x01, [0x87]);
    this.sendHex(hex);

    this.isManuallyStopped = true;
    this.isCalibrating = false;
    this.tipText = `校准已停止。最大信号：${this.maxSignal}`;
    
    this.safeShowToast('停止校准');
  }

  private toHex(n: number): string {
    return n.toString(16).padStart(2, '0').toUpperCase();
  }

  private sendHex(hex: string) {
    this.transport.sendHexString(hex);
  }
}