// ⭐ 修复警告：移除未使用的 common，替换过时的 promptAction 为 UIContext
import { UIContext } from '@kit.ArkUI';

import { TransportManager } from '../common/transport/TransportManager';
import { ITransport } from '../common/transport/ITransport';
import { ProtocolFrame, ProtocolParser, DeviceType } from '../common/ProtocolParser';

export interface FilterSettingPageParams {
  deviceName?: string;
  deviceType?: number;
  connectionMode?: string;
  deviceAddress?: number;
}

@Observed
export class FilterSettingViewModel {
  filterSwitch: boolean = false;
  startHour: string = '00';
  startMinute: string = '00';
  endHour: string = '00';
  endMinute: string = '00';
  warnDuration: string = '0';

  inWindowStatus: boolean = false;
  warnLedStatus: boolean = false;
  
  isReading: boolean = false; // 用于控制读取按钮状态

  public deviceType: DeviceType = DeviceType.Microwave;
  public currentAddress: number = 0x01;
  
  // ⭐ 新增：添加 UIContext 引用以支持安全弹窗
  public uiContext: UIContext | null = null; 

  private transport: ITransport;
  private protocolParser: ProtocolParser = new ProtocolParser();
  private readonly LISTENER_KEY = 'FilterSettingVM';
  
  private pollTimer: number = 0;
  
  // 用于实现高级重试与超时控制的 Promise 凭证
  private pendingCommand: number | null = null;
  private commandResolve: ((payload: number[]) => void) | null = null;

  constructor() {
    this.transport = TransportManager.getInstance().getTransport();
  }

  // ⭐ 核心修复：封装安全的 UIContext 弹窗，根除所有弃用和异常警告
  private showToastMsg(msg: string): void {
    if (this.uiContext) {
      try {
        this.uiContext.getPromptAction().showToast({ message: msg });
      } catch (e) {}
    }
  }

  init(params?: FilterSettingPageParams): void {
    if (params) {
       if (params.deviceType !== undefined) this.deviceType = params.deviceType;
       if (params.deviceAddress !== undefined) this.currentAddress = params.deviceAddress;
    }

    this.transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array): void => {
      const frames = this.protocolParser.feed(data);
      frames.forEach((f: ProtocolFrame): void => { this.handleFrame(f); });
    });

    this.readAll();

    // 开启 1 秒轮询，实时读取滤波状态 (0x92)
    this.pollTimer = setInterval((): void => {
      // 如果在高级读取或设置中，暂停状态轮询以防指令交叉干扰
      if (!this.pendingCommand && !this.isReading) {
        this.sendFrame(0x92);
      }
    }, 1000);
  }

  onDisappear(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = 0;
    }
    this.transport.offDataReceived(this.LISTENER_KEY);
  }

  /**
   * 带有重试和超时判断的高级查询器
   */
  private async queryCommand(cmdToSend: number, expectedResp: number, data: number[] = [], timeout: number = 600, retries: number = 2): Promise<number[] | null> {
    for (let i = 0; i <= retries; i++) {
      const result = await new Promise<number[] | null>((resolve: (value: number[] | null) => void): void => {
        this.pendingCommand = expectedResp;
        this.commandResolve = resolve;

        this.sendFrame(cmdToSend, data);

        setTimeout((): void => {
          if (this.pendingCommand === expectedResp) {
            this.pendingCommand = null;
            this.commandResolve = null;
            resolve(null); // 超时返回 null
          }
        }, timeout);
      });

      if (result !== null) {
        return result; // 成功收到结果
      }
      
      // 失败后等待短暂时间再发起下一次重试
      if (i < retries) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, 200);
        });
      }
    }
    return null; // 重试用尽，返回失败
  }

  async readAll(): Promise<void> {
    if (this.isReading) return;
    this.isReading = true;
    
    try {
      this.showToastMsg('正在读取滤波参数...');

      // 1. 读开关 0x8C
      let r = await this.queryCommand(0x8C, 0x8C);
      if (!r) throw new Error('读取滤波开关超时，请重试');

      // 2. 读起始时间 0x8E
      r = await this.queryCommand(0x8E, 0x8E);
      if (!r) throw new Error('读取起始时间超时，请重试');

      // 3. 读结束时间 0x90
      r = await this.queryCommand(0x90, 0x90);
      if (!r) throw new Error('读取结束时间超时，请重试');

      // 4. 读预警时长 0x93
      r = await this.queryCommand(0x93, 0x93);
      if (!r) throw new Error('读取预警时长超时，请重试');

      this.showToastMsg('读取参数完毕!');
    } catch (e) {
      this.showToastMsg((e as Error).message);
    } finally {
      this.isReading = false;
    }
  }

  private handleFrame(frame: ProtocolFrame): void {
    if (frame.data.length === 0) return;
    const cmd = frame.data[0];
    const payload = Array.from(frame.data.slice(1));

    if (cmd === 0x8C) {
      this.filterSwitch = payload[0] === 1;
    } else if (cmd === 0x8E) {
      this.startHour = payload[0].toString(16).padStart(2, '0');
      this.startMinute = payload[1].toString(16).padStart(2, '0');
    } else if (cmd === 0x90) {
      this.endHour = payload[0].toString(16).padStart(2, '0');
      this.endMinute = payload[1].toString(16).padStart(2, '0');
    } else if (cmd === 0x92) {
      const status = payload[0];
      this.inWindowStatus = (status & 0x01) !== 0;
      this.warnLedStatus = (status & 0x02) !== 0;
    } else if (cmd === 0x93) {
      this.warnDuration = payload[0].toString(10);
    }

    // 解除高级查询器的锁定
    if (this.pendingCommand === cmd && this.commandResolve) {
      this.commandResolve(payload);
      this.commandResolve = null;
      this.pendingCommand = null;
    }
  }

  async setFilterSwitch(val: boolean): Promise<void> {
    this.filterSwitch = val;
    const r = await this.queryCommand(0x8D, 0x8D, [val ? 1 : 0]);
    if (r) {
      this.showToastMsg(val ? '设置滤波启用参数成功!' : '设置滤波关闭参数成功!');
      this.sendSaveCommand();
    } else {
      this.showToastMsg('设置滤波开关失败，未收到响应');
    }
  }

  async setStartTime(): Promise<void> {
    let h = parseInt(this.startHour, 10);
    let m = parseInt(this.startMinute, 10);
    
    if (isNaN(h) || h < 0 || h > 23 || isNaN(m) || m < 0 || m > 59) {
      this.showToastMsg('输入范围不合法!');
      return;
    }
    
    const r = await this.queryCommand(0x8F, 0x8F, [h, m]);
    if (r) {
      this.showToastMsg('设置滤波开始时间成功!');
      this.sendSaveCommand();
    } else {
      this.showToastMsg('设置滤波开始时间失败');
    }
  }

  async setEndTime(): Promise<void> {
    let h = parseInt(this.endHour, 10);
    let m = parseInt(this.endMinute, 10);
    
    if (isNaN(h) || h < 0 || h > 23 || isNaN(m) || m < 0 || m > 59) {
      this.showToastMsg('输入范围不合法!');
      return;
    }
    
    const r = await this.queryCommand(0x91, 0x91, [h, m]);
    if (r) {
      this.showToastMsg('设置滤波结束时间成功!');
      this.sendSaveCommand();
    } else {
      this.showToastMsg('设置滤波结束时间失败');
    }
  }

  async setWarnDuration(): Promise<void> {
    let d = parseInt(this.warnDuration, 10);
    if (isNaN(d) || d < 0 || d > 255) {
      this.showToastMsg('输入范围不合法!');
      return;
    }
    
    const r = await this.queryCommand(0x94, 0x94, [d]);
    if (r) {
      this.showToastMsg('设置预警时长成功!');
      this.sendSaveCommand();
    } else {
      this.showToastMsg('设置预警时长失败');
    }
  }

  private sendFrame(cmd: number, data: number[] = []): void {
    if (!this.transport.isConnected()) return;

    let addr = 0x01;
    let type = 0xC9;

    if (this.deviceType === DeviceType.Fiber) {
      addr = this.currentAddress;
      type = 0x66;
    }

    const len = 1 + data.length;
    let sum = type + len + cmd;
    for (const b of data) { sum += b; }
    const cs = sum & 0xFF;

    let hex = `FF${this.toHex(addr)}${this.toHex(type)}${this.toHex(len)}${this.toHex(cmd)}`;
    for (const b of data) { hex += this.toHex(b); }
    hex += this.toHex(cs);

    this.transport.sendHexString(hex);
  }

  private sendSaveCommand(): void {
    this.sendFrame(0x23);
  }

  private toHex(n: number): string {
    return n.toString(16).padStart(2, '0').toUpperCase();
  }
}