import { common } from '@kit.AbilityKit';

import { TransportManager } from '../common/transport/TransportManager';
import { ITransport } from '../common/transport/ITransport';
import { ProtocolFrame, ProtocolParser, DeviceType } from '../common/ProtocolParser';
import { ProtocolDecoder } from '../common/ProtocolDecoder';
import {
  DeviceNamePayload,
  DeviceTimePayload,
  ChannelPayload,
  ConfigValuePayload,
  VersionPayload
} from '../common/protocol/ProtocolTypes';
import { DeviceNameManager } from '../common/DeviceNameManager';
import { LogManager } from '../common/database/LogManager';
import { LogCategory } from '../common/database/LogEntity';

// ⭐ 已删除死代码 SettingPageParams

@Observed
export class SettingViewModel {
  // ========= 左侧字段 =========
  deviceName: string = '[读取中...]';
  currentDeviceIdHex: string = '';

  sensorTime: string = '[空]';
  alarmDuration: number = 0;
  alarmDurationText: string = '[空]';
  channel: number = 0;
  channelText: string = '[空]';
  alarmFactor: number = 0;
  alarmFactorText: string = '[空]';
  lockId: number = 0;
  lockIdText: string = '[空]';

  fiberAdaptiveTime: number = 20;
  fiberAdaptiveTimeText: string = '[空]';
  fiberDigitalGain: number = 20;
  fiberDigitalGainText: string = '[空]';
  fiber1Gain: number = 0;
  fiber1GainText: string = '[空]';
  fiber2Gain: number = 0;
  fiber2GainText: string = '[空]';
  fiber3Gain: number = 0;
  fiber3GainText: string = '[空]';
  fiber4Gain: number = 0;
  fiber4GainText: string = '[空]';

  // ========= 右侧字段 =========
  deviceVersion: string = '[空]';
  algorithmEnabled: boolean = false;
  filterEnabled: boolean = false;
  thresholdValue: number = 0;
  thresholdText: string = '[空]';
  factorValue: number = 0;
  factorValueText: string = '[空]';
  algorithmTime: number = 0;
  algorithmTimeText: string = '[空]';
  filterTime: number = 0;
  filterTimeText: string = '[空]';

  // Dropdowns
  algoSelectionIndex: number = 0;
  algoOptions: SelectOption[] = [
    { value: '选择算法方式' },
    { value: '躁扰算法' },
    { value: '阈值算法' },
    { value: '因子算法' }
  ];

  commModeIndex: number = 0;
  commOptions: SelectOption[] = [
    { value: '通信方式选择' },
    { value: '422通信' },
    { value: '485通信' }
  ];

  heartbeatInterval: number = 60;
  heartbeatIntervalText: string = '[空]';

  connectionTypeDisplay: string = 'BLE';
  tipText: string = '请先从设备读取参数';

  private transport: ITransport;

  public deviceType: DeviceType = DeviceType.Microwave;
  public connectionMode: string = 'BLE';
  public currentAddress: number = 0x01;
  public originalDeviceName: string = '未知设备';

  private protocolParser: ProtocolParser = new ProtocolParser();

  private hasReceivedAnyConfig: boolean = false;
  private timeRefreshTimer: number = 0;
  private nameManager: DeviceNameManager | null = null;

  private lastLoggedConfig: string = '';

  private readonly LISTENER_KEY = 'SettingVM';

  constructor() {
    this.transport = TransportManager.getInstance().getTransport();
  }

  // ================= 生命周期 =================
  async init(params: Record<string, Object> | undefined, ctx?: common.UIAbilityContext): Promise<void> {
    if (ctx !== undefined) {
      this.nameManager = await DeviceNameManager.getInstance(ctx);
      await LogManager.getInstance().init(ctx);
    }

    const globalType = AppStorage.get<DeviceType>('GlobalDeviceType');
    if (globalType !== undefined) {
      this.deviceType = globalType;
    }

    if (params) {
      if (params['deviceType'] !== undefined) this.deviceType = params['deviceType'] as number;
      if (params['connectionMode'] !== undefined) this.connectionMode = params['connectionMode'] as string;
      if (params['deviceAddress'] !== undefined) this.currentAddress = params['deviceAddress'] as number;
      if (params['deviceName'] !== undefined) {
        this.deviceName = params['deviceName'] as string;
        this.originalDeviceName = params['deviceName'] as string;
      }
    }

    console.info(`[SettingViewModel] 页面初始化参数: deviceType=${this.deviceType}, address=${this.currentAddress}, name=${this.deviceName}`);

    this.transport = TransportManager.getInstance().getTransport();
    this.connectionTypeDisplay = TransportManager.getInstance().getMode();

    this.registerCallbacks();

    if (this.transport.isConnected()) {
      setTimeout((): void => {
        this.readAllFromDevice();
      }, 500);
    }
  }

  onDisappear(): void {
    this.stopTimeRefresh();
    this.transport.offDataReceived(this.LISTENER_KEY);
  }

  private logSetting(action: string, content: string) {
    try {
      LogManager.getInstance().addLog(
        LogCategory.SETTING,
        action,
        content,
        { name: this.deviceName, id: this.currentDeviceIdHex || this.transport.getId() || '-' }
      );
    } catch (e) {
      console.error(`[SettingLog] Failed: ${e}`);
    }
  }

  private logFullConfiguration(action: string): void {
    let configStr = '';
    if (this.deviceType === DeviceType.Fiber) {
      configStr = `设备名称:${this.deviceName}, 通道:${this.channel}, 自适应时间:${this.fiberAdaptiveTime}, 数字增益:${this.fiberDigitalGain}, 光纤增益(1-4):[${this.fiber1Gain},${this.fiber2Gain},${this.fiber3Gain},${this.fiber4Gain}], 报警时长:${this.alarmDuration}s`;
    } else {
      configStr = `设备名称:${this.deviceName}, 通道:${this.channel}, 报警因子:${this.alarmFactor}, 锁定ID:${this.lockId}, 阈值:${this.thresholdValue}, 因子参数:${this.factorValue}, 算法时间:${this.algorithmTime}m, 过滤时间:${this.filterTime}s, 算法:${this.algorithmEnabled?'开':'关'}, 过滤:${this.filterEnabled?'开':'关'}, 心跳:${this.heartbeatInterval}s`;
    }

    if (this.lastLoggedConfig !== configStr) {
      this.lastLoggedConfig = configStr;
      this.logSetting(action, configStr);
    }
  }

  // ================= 读取逻辑 =================

  private resetDisplay(): void {
    this.stopTimeRefresh();

    if (this.originalDeviceName && this.originalDeviceName !== '未知设备' && this.originalDeviceName !== '[读取中...]') {
      this.deviceName = this.originalDeviceName;
    } else {
      this.deviceName = '[读取中...]';
    }

    this.currentDeviceIdHex = '';
    this.sensorTime = '[空]';
    this.alarmDurationText = '[空]';

    if (this.deviceType === DeviceType.Fiber) {
      this.channel = this.currentAddress;
      this.channelText = this.currentAddress.toString();
    } else {
      this.channelText = '[空]';
    }

    this.alarmFactorText = '[空]';
    this.lockIdText = '[空]';
    this.deviceVersion = '[空]';
    this.thresholdText = '[空]';
    this.factorValueText = '[空]';
    this.algorithmTimeText = '[空]';
    this.filterTimeText = '[空]';
    this.heartbeatIntervalText = '[空]';
    this.algoSelectionIndex = 0;
    this.commModeIndex = 0;
    this.fiberAdaptiveTimeText = '[空]';
    this.fiberDigitalGainText = '[空]';
    this.fiber1GainText = '[空]';
    this.fiber2GainText = '[空]';
    this.fiber3GainText = '[空]';
    this.fiber4GainText = '[空]';
  }

  readAllFromDevice(): void {
    if (!this.transport.isConnected()) {
      this.tipText = '设备未连接';
      return;
    }

    this.resetDisplay();
    this.hasReceivedAnyConfig = false;
    this.tipText = '正在读取参数...';

    let delay = 0;
    const step = 400;

    const send = (cmd: number) => {
      setTimeout((): void => this.sendFrame(cmd), delay);
      delay += step;
    };

    if (this.deviceType === DeviceType.Fiber) {
      send(0x03);
      send(0x15);
      send(0x14);
      send(0x33);
    } else {
      send(0x03);
      send(0x15);
      send(0x11);
      send(0x0D);
      send(0x0F);
      send(0x4E);
      send(0x42);
      send(0x58);
      send(0x46);
      send(0x48);
      send(0x4A);
      send(0x4C);
      send(0x50);
      send(0x44);
      send(0x79);
    }

    setTimeout(() => {
      if (this.hasReceivedAnyConfig) {
        this.logFullConfiguration('读取全部参数');
      }
    }, delay + 1500);
  }

  refreshLocal(): void {
    if (this.hasReceivedAnyConfig) {
      this.syncNumberTexts();
      this.tipText = '界面数据已刷新';
    } else {
      this.tipText = '暂无数据可刷新';
    }
  }

  applyAllToDevice(): void {
    if (!this.transport.isConnected()) return;
    let delay = 0;
    const step = 400;

    setTimeout((): void => { this.applyDeviceName(); }, delay += 0);
    setTimeout((): void => this.applySensorTime(), delay += step);
    setTimeout((): void => this.applyAlarmDuration(), delay += step);

    if (this.deviceType === DeviceType.Fiber) {
      setTimeout((): void => this.applyFiberAdaptiveTime(), delay += step);
      setTimeout((): void => this.applyFiberDigitalGain(), delay += step);
      setTimeout((): void => this.applyFiberGain(1), delay += step);
      setTimeout((): void => this.applyFiberGain(2), delay += step);
      setTimeout((): void => this.applyFiberGain(3), delay += step);
      setTimeout((): void => this.applyFiberGain(4), delay += step);
    } else {
      setTimeout((): void => this.applyAlarmFactor(), delay += step);
      setTimeout((): void => this.applyLockId(), delay += step);
      setTimeout((): void => this.applyHeartbeat(), delay += step);
      setTimeout((): void => this.applyThreshold(), delay += step);
      setTimeout((): void => this.applyFactorValue(), delay += step);
      setTimeout((): void => this.applyAlgorithmTime(), delay += step);
      setTimeout((): void => this.applyFilterTime(), delay += step);
      setTimeout((): void => this.applyAlgorithmEnabled(), delay += step);
      setTimeout((): void => this.applyFilterEnabled(), delay += step);
      setTimeout((): void => this.applyAlgorithmSelection(), delay += step);
      setTimeout((): void => this.applyCommMode(), delay += step);
    }

    setTimeout((): void => {
      this.sendSaveCommand();
      this.logFullConfiguration('批量保存参数');
      this.tipText = '批量保存参数完成';
    }, delay + 1000);
  }

  // ================= 左侧字段逻辑 =================

  updateDeviceNameInput(v: string): void { this.deviceName = v; }

  // ⭐ 修复：清理了空 catch 以及毫无意义的 throw
  async applyDeviceName(): Promise<void> {
    if (!this.transport.isConnected()) {
      this.tipText = '请先连接设备';
      return;
    }
    
    if (!this.nameManager) return;

    let targetIdHex = this.currentDeviceIdHex;
    let needWriteToDevice = false;

    if (!targetIdHex || targetIdHex.startsWith('FFFFFFFF')) {
      targetIdHex = await this.nameManager.generateNewId();
      needWriteToDevice = true;
      this.tipText = `正在初始化新设备ID: ${targetIdHex}`;
    }

    await this.nameManager.saveName(targetIdHex, this.deviceName);
    this.originalDeviceName = this.deviceName;

    if (needWriteToDevice) {
      const dataArr = DeviceNameManager.hexToBytes(targetIdHex);
      this.sendFrame(0x2B, dataArr);
      setTimeout((): void => this.sendSaveCommand(), 300);
      this.currentDeviceIdHex = targetIdHex;
      this.tipText = '设备初始化成功，名称已保存';
      this.logSetting('修改名称', `初始化新ID: ${targetIdHex}, 名称: ${this.deviceName}`);
    } else {
      this.tipText = '本地名称已修改 (无需写入设备)';
      this.logSetting('修改名称', `本地修改名称为: ${this.deviceName}`);
    }

    this.tipText = '名称修改成功';
  }

  updateSensorTimeInput(v: string): void { this.sensorTime = v; }
  applySensorTime(): void {
    if (!this.transport.isConnected()) return;
    const now = new Date();
    this.sendFrame(0x13, [now.getFullYear() % 100, now.getMonth() + 1, now.getDate(), now.getHours(), now.getMinutes(), now.getSeconds()]);
    this.tipText = '时间已强制同步';
    this.startTimeRefresh();
    this.logSetting('同步时间', '强制同步设备时间');
  }

  updateAlarmDurationInput(v: string): void {
    const n = this.parseIntInRange(v, 1, 100);
    if (n >= 0) { this.alarmDuration = n; this.alarmDurationText = n.toString(); } else { this.alarmDurationText = v; }
  }
  setAlarmDurationFromSlider(v: number): void { this.alarmDuration = Math.floor(v); this.alarmDurationText = this.alarmDuration.toString(); }

  applyAlarmDuration(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x07, [this.alarmDuration]);
    this.sendSaveCommand();
    this.tipText = '持续时间已设置';
    this.logSetting('修改报警时长', `时长修改为: ${this.alarmDuration}s`);
  }

  updateChannelInput(v: string): void {
    const n = this.parseIntInRange(v, 1, 16);
    if (n >= 0) { this.channel = n; this.channelText = n.toString(); } else { this.channelText = v; }
  }
  setChannelFromSlider(v: number): void {
    this.channel = Math.floor(v);
    this.channelText = this.channel.toString();
  }

  applyChannel(): void {
    if (!this.transport.isConnected()) return;
    if (this.deviceType === DeviceType.Fiber) {
      this.tipText = '光纤设备暂只支持手动硬件拨码调节通道!';
      return;
    }

    this.sendFrame(0x3D, [this.channel]);
    setTimeout((): void => {
      this.sendSaveCommand();
      setTimeout((): void => {
        this.sendFrame(0x1D);
        this.tipText = '设备重启中... 请稍候';
      }, 300);
    }, 300);
    this.logSetting('修改通道', `通道修改为: ${this.channel}`);
  }

  updateFiberAdaptiveTimeInput(v: string): void {
    const n = this.parseIntInRange(v, 0, 255);
    if (n >= 0) { this.fiberAdaptiveTime = n; this.fiberAdaptiveTimeText = n.toString(); } else { this.fiberAdaptiveTimeText = v; }
  }
  applyFiberAdaptiveTime(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x0F, [this.fiberAdaptiveTime]);
    this.sendSaveCommand();
    this.tipText = '自适应时间已设置';
    this.logSetting('修改自适应时间', `时间修改为: ${this.fiberAdaptiveTime}`);
  }

  updateFiberDigitalGainInput(v: string): void {
    const n = this.parseIntInRange(v, 0, 100);
    if (n >= 0) { this.fiberDigitalGain = n; this.fiberDigitalGainText = n.toString(); } else { this.fiberDigitalGainText = v; }
  }
  applyFiberDigitalGain(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x02, [this.fiberDigitalGain]);
    this.sendSaveCommand();
    this.tipText = '数字增益已设置';
    this.logSetting('修改数字增益', `增益修改为: ${this.fiberDigitalGain}`);
  }

  updateFiberGainInput(ch: number, v: string): void {
    const n = this.parseIntInRange(v, 0, 2);
    if (n >= 0) {
      if (ch === 1) { this.fiber1Gain = n; this.fiber1GainText = n.toString(); }
      else if (ch === 2) { this.fiber2Gain = n; this.fiber2GainText = n.toString(); }
      else if (ch === 3) { this.fiber3Gain = n; this.fiber3GainText = n.toString(); }
      else if (ch === 4) { this.fiber4Gain = n; this.fiber4GainText = n.toString(); }
    } else {
      if (ch === 1) this.fiber1GainText = v;
      else if (ch === 2) this.fiber2GainText = v;
      else if (ch === 3) this.fiber3GainText = v;
      else if (ch === 4) this.fiber4GainText = v;
    }
  }

  applyFiberGain(ch: number): void {
    if (!this.transport.isConnected()) return;
    let val = 0;
    if (ch === 1) val = this.fiber1Gain;
    else if (ch === 2) val = this.fiber2Gain;
    else if (ch === 3) val = this.fiber3Gain;
    else if (ch === 4) val = this.fiber4Gain;

    this.sendFrame(0x32, [ch, val]);
    this.sendSaveCommand();
    this.tipText = `光纤${ch}增益已设置`;
    this.logSetting(`修改光纤${ch}增益`, `倍率修改为: ${val}`);
  }

  updateAlarmFactorInput(v: string): void {
    const n = this.parseIntInRange(v, 100, 65535);
    if (n >= 0) { this.alarmFactor = n; this.alarmFactorText = n.toString(); } else { this.alarmFactorText = v; }
  }
  applyAlarmFactor(): void {
    if (!this.transport.isConnected()) return;
    const low = this.alarmFactor & 0xFF;
    const high = (this.alarmFactor >> 8) & 0xFF;
    this.sendFrame(0x2D, [low, high]);
    this.sendSaveCommand();
    this.tipText = '报警因子已设置';
    this.logSetting('修改报警因子', `因子修改为: ${this.alarmFactor}`);
  }

  updateLockIdInput(v: string): void {
    const n = this.parseIntInRange(v, 20, 255);
    if (n >= 0) { this.lockId = n; this.lockIdText = n.toString(); } else { this.lockIdText = v; }
  }
  applyLockId(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x37, [(this.lockId >> 8) & 0xFF, this.lockId & 0xFF]);
    this.sendSaveCommand();
    this.tipText = '锁定识别已设置';
    this.logSetting('修改锁定ID', `ID修改为: ${this.lockId}`);
  }

  setAlgorithmEnabled(v: boolean): void { this.algorithmEnabled = v; }
  setFilterEnabled(v: boolean): void { this.filterEnabled = v; }

  applyAlgorithmEnabled(): void {
    const val = this.algorithmEnabled ? 0x00 : 0x01;
    this.sendFrame(0x43, [val]);
    this.sendSaveCommand();
    this.tipText = '算法开关已设置';
    this.logSetting('修改算法开关', `状态: ${this.algorithmEnabled ? '开启' : '关闭'}`);
  }

  applyFilterEnabled(): void {
    const val = this.filterEnabled ? 0x01 : 0x00;
    this.sendFrame(0x4F, [val]);
    this.sendSaveCommand();
    this.tipText = '过滤开关已设置';
    this.logSetting('修改过滤开关', `状态: ${this.filterEnabled ? '开启' : '关闭'}`);
  }

  updateThresholdInput(v: string): void {
    const n = this.parseIntInRange(v, 1, 255);
    if (n >= 0) { this.thresholdValue = n; this.thresholdText = n.toString(); } else { this.thresholdText = v; }
  }
  applyThreshold(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x47, [this.thresholdValue & 0xFF]);
    this.sendSaveCommand();
    this.tipText = '阈值算法参数已设置';
    this.logSetting('修改阈值', `阈值修改为: ${this.thresholdValue}`);
  }

  updateFactorValueInput(v: string): void {
    const n = this.parseIntInRange(v, 1, 65535);
    if (n >= 0) { this.factorValue = n; this.factorValueText = n.toString(); } else { this.factorValueText = v; }
  }
  applyFactorValue(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x49, [(this.factorValue >> 8) & 0xFF, this.factorValue & 0xFF]);
    this.sendSaveCommand();
    this.tipText = '因子算法参数已设置';
    this.logSetting('修改因子参数', `因子修改为: ${this.factorValue}`);
  }

  updateAlgorithmTimeInput(v: string): void {
    const n = this.parseIntInRange(v, 1, 255);
    if (n >= 0) { this.algorithmTime = n; this.algorithmTimeText = n.toString(); } else { this.algorithmTimeText = v; }
  }
  applyAlgorithmTime(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x4B, [this.algorithmTime & 0xFF]);
    this.sendSaveCommand();
    this.tipText = '算法时间已设置';
    this.logSetting('修改算法时间', `时间修改为: ${this.algorithmTime}`);
  }

  updateFilterTimeInput(v: string): void {
    const n = this.parseIntInRange(v, 1, 255);
    if (n >= 0) { this.filterTime = n; this.filterTimeText = n.toString(); } else { this.filterTimeText = v; }
  }
  applyFilterTime(): void {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x4D, [this.filterTime & 0xFF]);
    this.sendSaveCommand();
    this.tipText = '过滤时间已设置';
    this.logSetting('修改过滤时间', `时间修改为: ${this.filterTime}`);
  }

  updateAlgoSelection(index: number) { this.algoSelectionIndex = index; }
  applyAlgorithmSelection() {
    if (!this.transport.isConnected()) return;
    if (this.algoSelectionIndex === 0) return;
    const val = this.algoSelectionIndex - 1;
    this.sendFrame(0x45, [val]);
    this.sendSaveCommand();
    this.tipText = '算法类型已设置';
    this.logSetting('修改算法类型', `类型索引: ${this.algoSelectionIndex}`);
  }

  updateCommMode(index: number) { this.commModeIndex = index; }
  applyCommMode() {
    if (!this.transport.isConnected()) return;
    if (this.commModeIndex === 0) return;
    const val = this.commModeIndex - 1;
    this.sendFrame(0x7A, [val]);
    this.sendSaveCommand();
    this.tipText = '通信方式已设置';
    this.logSetting('修改通信方式', `方式索引: ${this.commModeIndex}`);
  }

  updateHeartbeatInput(v: string) {
    const n = parseInt(v);
    if(!isNaN(n) && n > 0) this.heartbeatInterval = n;
    this.heartbeatIntervalText = v;
  }
  applyHeartbeat() {
    if (!this.transport.isConnected()) return;
    this.sendFrame(0x50, [this.heartbeatInterval & 0xFF]);
    this.sendSaveCommand();
    this.tipText = '心跳间隔已设置';
    this.logSetting('修改心跳间隔', `间隔修改为: ${this.heartbeatInterval}s`);
  }

  // ================= 通信核心 =================

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

  private registerCallbacks(): void {
    this.transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array) => {
      const frames = this.protocolParser.feed(data);
      frames.forEach(f => this.handleFrame(f));
    });
  }

  private async handleFrame(frame: ProtocolFrame): Promise<void> {
    const cmd = frame.data.length > 0 ? frame.data[0] : 0;

    if (this.deviceType === DeviceType.Fiber) {
      if (cmd === 0x14 && frame.raw.length >= 26) {
        this.fiberDigitalGain = frame.raw[14];
        this.fiber1Gain = frame.raw[15];
        this.fiber2Gain = frame.raw[17];
        this.fiber3Gain = frame.raw[19];
        this.fiber4Gain = frame.raw[21];
        this.alarmDuration = frame.raw[23] === 0 ? 1 : frame.raw[23];
        this.fiberAdaptiveTime = frame.raw[24];

        this.syncNumberTexts();
        this.hasReceivedAnyConfig = true;
        this.tipText = '光纤系统参数已同步';
        return;
      } else if (cmd === 0x33 && frame.raw.length >= 9) {
        this.fiber1Gain = frame.raw[5];
        this.fiber2Gain = frame.raw[6];
        this.fiber3Gain = frame.raw[7];
        this.fiber4Gain = frame.raw[8];

        this.syncNumberTexts();
        this.hasReceivedAnyConfig = true;
        this.tipText = '光纤增益倍率已同步';
        return;
      }
    }

    const decoded = ProtocolDecoder.decode(frame.deviceType, frame.data);
    if (!decoded || !decoded.payload) return;

    const payload = decoded.payload;
    if (payload instanceof Uint8Array) return;

    let updated = false;

    switch (payload.type) {
      case 'name':
        const pName = payload as DeviceNamePayload;
        this.currentDeviceIdHex = pName.deviceIdHex;

        if (this.nameManager) {
          if (!pName.isConfigured) {
            if (!this.originalDeviceName || this.originalDeviceName === '未知设备' || this.originalDeviceName === '[读取中...]') {
              this.deviceName = '[未配置]';
            } else {
              this.deviceName = this.originalDeviceName;
            }
          } else {
            const savedName = await this.nameManager.getName(pName.deviceIdHex);
            this.deviceName = savedName || `设备(${pName.deviceIdHex.substring(0,4)})`;
            this.originalDeviceName = this.deviceName;
          }
        }
        updated = true;
        break;
      case 'time':
        const t = payload as DeviceTimePayload;
        this.handleDeviceTime(t);
        updated = true;
        break;
      case 'channel':
        const ch = (payload as ChannelPayload).channel;
        this.channel = ch;
        this.channelText = ch.toString();
        updated = true;
        break;
      case 'version':
        this.deviceVersion = (payload as VersionPayload).version;
        updated = true;
        break;
      case 'configValue':
        const cfg = payload as ConfigValuePayload;
        this.handleConfigValue(cfg.subtype, cfg.value);
        updated = true;
        break;
    }

    if (updated) {
      this.hasReceivedAnyConfig = true;
      this.tipText = '设备参数已更新';
    }
  }

  private handleDeviceTime(t: DeviceTimePayload) {
    const devDate = new Date(t.year, t.month - 1, t.day, t.hour, t.minute, t.second);
    const now = new Date();
    const diff = Math.abs(now.getTime() - devDate.getTime());

    const pad = (n: number) => n.toString().padStart(2, '0');
    this.sensorTime = `${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}`;

    if (diff > 3000) {
      this.applySensorTime();
    } else {
      this.startTimeRefresh();
    }
  }

  private startTimeRefresh() {
    this.stopTimeRefresh();
    this.timeRefreshTimer = setInterval((): void => {
      const now = new Date();
      const pad = (n: number) => n.toString().padStart(2, '0');
      this.sensorTime = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
    }, 1000);
  }

  private stopTimeRefresh() {
    if (this.timeRefreshTimer) {
      clearInterval(this.timeRefreshTimer);
      this.timeRefreshTimer = 0;
    }
  }

  private handleConfigValue(subtype: string, val: number): void {
    switch (subtype) {
      case 'duration':
        this.alarmDuration = val;
        this.alarmDurationText = val.toString();
        break;
      case 'alarmFactor':
        this.alarmFactor = val;
        this.alarmFactorText = val.toString();
        break;
      case 'lockId':
        this.lockId = val;
        this.lockIdText = val.toString();
        break;
      case 'thresholdAlgo':
        this.thresholdValue = val;
        this.thresholdText = val.toString();
        break;
      case 'factorAlgo':
        this.factorValue = val;
        this.factorValueText = val.toString();
        break;
      case 'algoTime':
        this.algorithmTime = val;
        this.algorithmTimeText = val.toString();
        break;
      case 'filterTime':
        this.filterTime = val;
        this.filterTimeText = val.toString();
        break;
      case 'heartbeat':
        this.heartbeatInterval = val;
        this.heartbeatIntervalText = val.toString();
        break;
      case 'algoSwitch':
        this.algorithmEnabled = (val === 0x00);
        break;
      case 'filterSwitch':
        this.filterEnabled = (val === 0x01);
        break;
      case 'algoSelection':
        this.algoSelectionIndex = val + 1;
        break;
      case 'commMode':
        this.commModeIndex = val + 1;
        break;
    }
  }

  private syncNumberTexts(): void {
    this.alarmDurationText = this.alarmDuration.toString();
    this.channelText = this.channel.toString();
    this.alarmFactorText = this.alarmFactor.toString();
    this.lockIdText = this.lockId.toString();
    this.thresholdText = this.thresholdValue.toString();
    this.factorValueText = this.factorValue.toString();
    this.algorithmTimeText = this.algorithmTime.toString();
    this.filterTimeText = this.filterTime.toString();
    this.heartbeatIntervalText = this.heartbeatInterval.toString();
    this.fiberAdaptiveTimeText = this.fiberAdaptiveTime.toString();
    this.fiberDigitalGainText = this.fiberDigitalGain.toString();
    this.fiber1GainText = this.fiber1Gain.toString();
    this.fiber2GainText = this.fiber2Gain.toString();
    this.fiber3GainText = this.fiber3Gain.toString();
    this.fiber4GainText = this.fiber4Gain.toString();
  }

  private parseIntInRange(v: string, min: number, max: number): number {
    const n = parseInt(v);
    if (isNaN(n) || n < min || n > max) return -1;
    return n;
  }

  private toHex(n: number): string {
    return n.toString(16).padStart(2, '0').toUpperCase();
  }
}