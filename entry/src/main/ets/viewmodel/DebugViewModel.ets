import { common } from '@kit.AbilityKit';
import { constant, ble } from '@kit.ConnectivityKit';
import { util } from '@kit.ArkTS';
import dataPreferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import AdapterManager from '../bluetooth/AdapterManager';
import bleScanManager, { BleDevice } from '../bluetooth/BleSearch';
import gattClientManager from '../bluetooth/GattClientManager';
import { PermissionUtil } from '../utils/PermissionUtil';
import { BLE_PERMISSIONS } from '../utils/PermissionsConfig';
import { ProtocolFrame, ProtocolParser, DeviceType } from '../common/ProtocolParser';
import { ProtocolDecoder } from '../common/ProtocolDecoder';
import { AppConfig } from '../common/AppConfig';
import {
  DecodedCommand,
  CommandPayload,
  StatusPayload
} from '../common/protocol/ProtocolTypes';

// ⭐ 修复：全面接入主页同款 TCP 管理器与传输层，放弃不稳定的独立 TcpClient
import { TcpDeviceManager } from '../Network/TcpDeviceManager';
import { TcpTransport } from '../common/transport/TcpTransport';

import { getSystemInfo } from '../common/DeviceInfoUtil';
import { StcOtaController } from '../common/ota/StcOtaController';

export type DebugChannel = 'BLE' | 'TCP';

export interface ParsedFrameViewModel {
  time: string;
  rawHex: string;
  address: number;
  deviceTypeText: string;
  dataHex: string;
  checksumOk: boolean;
  decodedSummary: string;
}

export interface MultiSendItem {
  id: number;
  enabled: boolean;
  text: string;
  hex: boolean;
  remark?: string;
}

export interface ServiceViewItem {
  uuid: string;
  isPrimary: boolean;
  characteristics: CharViewItem[];
}

export interface CharViewItem {
  uuid: string;
  properties: string;
  canWrite: boolean;
  canNotify: boolean;
}

@Observed
export class DebugViewModel {
  message: string = '请选择 BLE 或 TCP 调试';
  activeChannel: DebugChannel = 'BLE';
  scanning: boolean = false;
  devices: Array<BleDevice> = [];
  connectedDeviceId: string = '';
  connectStateText: string = '未连接';
  showServiceSelector: boolean = false;
  serviceList: Array<ServiceViewItem> = [];
  selectedWriteUuid: string = '';
  selectedNotifyUuid: string = '';
  currentServiceUuid: string = '';
  tcpHost: string = AppConfig.SERVER_HOST; 

  tcpPortText: string = AppConfig.ALARM_SERVER_PORT.toString();
  tcpConnectStateText: string = '未连接';
  tcpConnected: boolean = false;
  bleReceiveHex: string = '';
  bleReceiveText: string = '';
  tcpReceiveHex: string = '';
  tcpReceiveText: string = '';
  recvDisplayMode: 'TEXT' | 'HEX' = 'HEX';
  sendText: string = '';
  sendAsHex: boolean = false;
  parsedFrames: Array<ParsedFrameViewModel> = [];
  autoSendEnabled: boolean = false;
  autoSendIntervalText: string = '100';

  public uiContext: UIContext | null = null; 

  isOtaLoading: boolean = false;
  otaProgress: number = 0;
  otaCostTime: string = '0.0';
  otaPacketSize: number = 64;
  otaDelayMs: number = 20;

  currentDeviceType: number = 0xC9;
  currentDeviceAddress: number = 0x01;
  multiSendList: Array<MultiSendItem> = [
    { id: 1, enabled: true, text: '', hex: true, remark: '' },
    { id: 2, enabled: true, text: '', hex: true, remark: '' },
    { id: 3, enabled: true, text: '', hex: true, remark: '' },
    { id: 4, enabled: true, text: '', hex: true, remark: '' },
    { id: 5, enabled: true, text: '', hex: true, remark: '' },
    { id: 6, enabled: true, text: '', hex: true, remark: '' },
    { id: 7, enabled: true, text: '', hex: true, remark: '' },
    { id: 8, enabled: true, text: '', hex: true, remark: '' },
  ];
  multiAutoEnabled: boolean = false;
  multiAutoIntervalText: string = '0';
  multiAutoLoopCountText: string = '0';
  alarmActive: boolean = false;
  tamperActive: boolean = false;
  
  private autoSendTimer: number = -1;
  private multiAutoTimer: number = -1;
  private appContext?: common.UIAbilityContext;
  private otaController: StcOtaController;

  virtualMqttCode: string = '';
  fullSysInfo: string = '';
  
  private readonly LISTENER_KEY = 'DebugVM';

  private showToastMsg(msg: string, duration?: number): void {
    if (this.uiContext) {
      try {
        if (duration !== undefined) {
          this.uiContext.getPromptAction().showToast({ message: msg, duration: duration });
        } else {
          this.uiContext.getPromptAction().showToast({ message: msg });
        }
      } catch (e) {}
    }
  }

  constructor() {
    this.otaController = new StcOtaController({
      onSendData: async (data: Uint8Array): Promise<void> => {
        await this.sendRawData(data);
      },
      onMessage: (msg: string): void => {
        this.message = msg;
      },
      onProgress: (progress: number): void => {
        this.otaProgress = progress;
      },
      onSuccess: (costTime: string): void => {
        this.isOtaLoading = false;
        this.otaCostTime = costTime;
        this.message = `OTA 升级成功！耗时 ${costTime} 秒`;
        this.showToastMsg(this.message, 3000); 
      },
      onError: (reason: string): void => {
        this.isOtaLoading = false;
        this.message = 'OTA 失败: ' + reason;
        this.showToastMsg(this.message, 3000); 
      }
    });
  }

  private parseHexString(hex: string): Uint8Array {
    const clean: string = hex.replace(/\s+/g, '').toUpperCase();
    if (clean.length === 0 || clean.length % 2 !== 0) return new Uint8Array();
    const result: Array<number> = [];
    for (let i = 0; i + 1 < clean.length; i += 2) {
      result.push(Number.parseInt(clean.substring(i, i + 2), 16) & 0xFF);
    }
    return new Uint8Array(result);
  }

  private bytesToHexString(data: Uint8Array): string {
    return Array.from(data).map((b: number): string => b.toString(16).padStart(2, '0')).join(' ');
  }

  private getCurrentTimeString(): string {
    const d = new Date();
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;
  }

  private getDeviceTypeText(type: number): string {
    switch (type) {
      case DeviceType.Microwave: return '微波 (C9)';
      case DeviceType.Fiber: return '光纤 (66)';
      case DeviceType.Laser: return '激光 (19)';
      default: return `未知 (0x${type.toString(16).toUpperCase()})`;
    }
  }

  private buildDecodedSummary(decoded: DecodedCommand | null): string {
    if (!decoded) return '无解析结果';
    if (decoded.payload === null) return `命令 0x${decoded.cmd.toString(16).toUpperCase()}：无数据`;
    if (decoded.payload instanceof Uint8Array) {
      return `原始数据: ${ProtocolParser.bytesToHexString(decoded.payload)}`;
    }
    const payload = decoded.payload as CommandPayload;
    return `Type: ${payload.type}`;
  }

  private async sendTcpTextGbk(text: string): Promise<void> {
    if (!this.tcpConnected) return;
    let encoder: util.TextEncoder;
    try {
      encoder = new util.TextEncoder('gb2312');
    } catch (_e) {
      encoder = new util.TextEncoder('utf-8');
    }
    const hexStr = this.bytesToHexString(encoder.encodeInto(text)).replace(/\s+/g, '').toUpperCase();
    TcpTransport.getInstance().sendHexString(hexStr);
  }

  public async sendMqttAuth(): Promise<void> {
    if (!this.tcpConnected) return;
    if (this.fullSysInfo) {
      await this.sendTcpTextGbk(this.fullSysInfo);
      this.message = '已手动发送本机 MQT 信息进行验证';
      this.showToastMsg('验证包已发送');
    }
  }

  // ⭐ 核心修复：直接复用底层 TcpDeviceManager，它内部已包含了完整的 TCP MQT 验证与心跳机制
  public async onTcpConnectClick(): Promise<void> {
    if (this.tcpConnected) {
      try { TcpTransport.getInstance().disconnect(); } catch (e) {}
      this.tcpConnected = false;
      this.tcpConnectStateText = '未连接';
      return;
    }
    
    const portNum = Number.parseInt(this.tcpPortText);
    if (Number.isNaN(portNum)) return;

    this.tcpConnectStateText = `正在连接...`;
    
    try {
      await TcpDeviceManager.instance.connectDevice(this.tcpHost, portNum);
      
      this.tcpConnected = true;
      this.tcpConnectStateText = `已连接: ${this.tcpHost}:${portNum}`;
      this.activeChannel = 'TCP';
      this.message = 'TCP 成功接入 (已自动完成底层验证)';
      
      const transport = TcpTransport.getInstance();
      transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array) => {
        this.onTcpDataReceived(data);
      });
      
      transport.setOnStateChange(this.LISTENER_KEY, (state: string) => {
         if (state === 'DISCONNECTED') {
           this.tcpConnected = false;
           this.tcpConnectStateText = '未连接';
           this.message = 'TCP 连接已关闭';
         }
      });
    } catch (error) {
      this.tcpConnected = false;
      this.tcpConnectStateText = '连接失败';
      this.message = 'TCP 连接失败: ' + (error as BusinessError).message;
    }
  }

  private onTcpDataReceived(data: Uint8Array): void {
    if (this.isOtaLoading) {
      this.otaController.processRxData(data);
      return;
    }

    const hexStr = this.bytesToHexString(data).toUpperCase();
    const now = this.getCurrentTimeString();
    this.tcpReceiveHex = this.tcpReceiveHex ? `${this.tcpReceiveHex}\n[${now}] ${hexStr}` : `[${now}] ${hexStr}`;

    let decoder: util.TextDecoder;
    try {
      decoder = util.TextDecoder.create('gb2312');
    } catch (_e) {
      decoder = util.TextDecoder.create('utf-8');
    }
    const textPart = decoder.decodeToString(data);
    this.tcpReceiveText = this.tcpReceiveText ? `${this.tcpReceiveText}\n[${now}] ${textPart}` : `[${now}] ${textPart}`;
    this.message = '收到 TCP 数据';
  }

  private stopAutoSend(): void {
    if (this.autoSendTimer !== -1) {
      clearInterval(this.autoSendTimer);
      this.autoSendTimer = -1;
      this.autoSendEnabled = false;
    }
  }

  public toggleAutoSend(): void {
    if (!this.autoSendEnabled) {
      this.autoSendEnabled = true;
      this.autoSendTimer = setInterval((): void => {
        this.onSendClick();
      }, Number(this.autoSendIntervalText) || 100);
    } else {
      this.stopAutoSend();
    }
  }

  private stopMultiAutoSend(): void {
    if (this.multiAutoTimer !== -1) {
      clearInterval(this.multiAutoTimer);
      this.multiAutoTimer = -1;
      this.multiAutoEnabled = false;
    }
  }

  public toggleMultiAutoSend(): void {
    if (!this.multiAutoEnabled) {
      this.multiAutoEnabled = true;
      this.multiAutoTimer = setInterval((): void => {
        this.sendSelectedMultiItems();
      }, Number(this.multiAutoIntervalText) || 1000);
    } else {
      this.stopMultiAutoSend();
    }
  }

  public sendOneMultiItem(item: MultiSendItem): void {
    this.onSendClickInner(item.text, item.hex);
  }

  private sendSelectedMultiItems(): void {
    this.multiSendList.forEach((item: MultiSendItem) => {
      if (item.enabled) this.sendOneMultiItem(item);
    });
  }

  public clearAllMultiSend(): void {
    this.multiSendList.forEach((i: MultiSendItem) => i.text = '');
    this.saveMultiSendConfig();
  }

  public updateMultiSendItem(id: number, updater: (old: MultiSendItem) => MultiSendItem): void {
    const idx = this.multiSendList.findIndex((i: MultiSendItem) => i.id === id);
    if (idx >= 0) {
      this.multiSendList[idx] = updater(this.multiSendList[idx]);
    }
    this.saveMultiSendConfig();
  }

  private async onSendClickInner(text: string, isHex: boolean): Promise<void> {
    if (!text) return;
    let data: Uint8Array;
    if (isHex) {
      data = this.parseHexString(text);
      if (data.length === 0) {
        this.message = 'HEX 格式错误';
        return;
      }
    } else {
      let encoder: util.TextEncoder;
      try {
        encoder = new util.TextEncoder('gb2312');
      } catch (_e) {
        encoder = new util.TextEncoder('utf-8');
      }
      data = encoder.encodeInto(text);
    }
    await this.sendRawData(data);
    this.message = `已发送 (${this.activeChannel})`;
  }

  public onSendClick(): void {
    this.onSendClickInner(this.sendText, this.sendAsHex);
  }

  public async sendNewLine(): Promise<void> {
    if (this.activeChannel === 'BLE' && this.connectedDeviceId) {
      gattClientManager.writeText('\r\n');
    } else if (this.activeChannel === 'TCP' && this.tcpConnected) {
      await this.sendTcpTextGbk('\r\n');
    }
  }

  private async sendRawData(data: Uint8Array): Promise<void> {
    if (this.activeChannel === 'BLE' && this.connectedDeviceId) {
      gattClientManager.writeBytes(data);
    } else if (this.activeChannel === 'TCP' && this.tcpConnected) {
      const hex = this.bytesToHexString(data).replace(/\s+/g, '');
      TcpTransport.getInstance().sendHexString(hex);
    } else {
      throw new Error('设备未连接');
    }
  }

  public async pickFileAndStartOTA(context: common.UIAbilityContext): Promise<void> {
    if ((this.activeChannel === 'BLE' && !this.connectedDeviceId) || (this.activeChannel === 'TCP' && !this.tcpConnected)) {
      this.message = '请先连接设备';
      return;
    }

    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const uriList = await documentPicker.select({ maxSelectNumber: 1 });
      if (uriList.length > 0) {
        const uri = uriList[0];
        if (uri.endsWith('.hex')) {
          this.message = '警告：.hex 文件可能无法直接使用，建议使用 .bin';
        }

        this.otaController.packetSize = this.otaPacketSize;
        this.otaController.delayMs = this.otaDelayMs;

        this.isOtaLoading = true;
        await this.otaController.start(uri);
      }
    } catch (err) {
      console.error('File pick failed', JSON.stringify(err));
    }
  }

  public getCurrentRecvTextRaw(): string {
    return this.activeChannel === 'BLE' ? this.bleReceiveText : this.tcpReceiveText;
  }

  public getCurrentRecvHexRaw(): string {
    return this.activeChannel === 'BLE' ? this.bleReceiveHex : this.tcpReceiveHex;
  }

  public copyRecvToArea(): void {
    let content = this.recvDisplayMode === 'TEXT' ? this.getCurrentRecvTextRaw() : this.getCurrentRecvHexRaw();
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteboardData).then((): void => {
        this.message = '已复制当前缓冲区内容到系统剪贴板';
        this.showToastMsg('复制成功');
      }).catch((err: BusinessError) => {
        this.message = '复制失败: ' + err.message;
      });
    } catch (e) {
      this.message = '剪贴板异常: ' + JSON.stringify(e);
    }
  }

  public async saveCurrentRecv(context: common.UIAbilityContext): Promise<void> {
    try {
      const preferences = await dataPreferences.getPreferences(context, 'recv_log');
      let content = this.recvDisplayMode === 'TEXT' ? this.getCurrentRecvTextRaw() : this.getCurrentRecvHexRaw();
      await preferences.put('last', content);
      await preferences.flush();
      this.message = '接收数据已保存到本地偏好';
      this.showToastMsg('保存成功');
    } catch (err) {
      console.error('saveCurrentRecv error: ' + JSON.stringify(err));
      this.message = '保存接收数据失败';
    }
  }

  public setMultiAutoIntervalText(t: string): void {
    this.multiAutoIntervalText = t;
    this.saveMultiSendConfig();
  }

  public setMultiAutoLoopCountText(t: string): void {
    this.multiAutoLoopCountText = t;
    this.saveMultiSendConfig();
  }

  public async startBleScan(context: common.UIAbilityContext): Promise<void> {
    if (await PermissionUtil.checkAndRequestPermissions(context, BLE_PERMISSIONS)) {
      if (!AdapterManager.isBluetoothOn()) AdapterManager.openBluetooth();
      this.scanning = true;
      this.devices = [];
      bleScanManager.setOnDeviceFoundCallback((d: BleDevice) => {
        const existingIdx = this.devices.findIndex((x: BleDevice) => x.id === d.id);
        let newDevices: Array<BleDevice> = [];
        this.devices.forEach((dev) => newDevices.push(dev));

        if (existingIdx === -1) {
          newDevices.push(d);
        } else {
          newDevices[existingIdx] = d;
        }
        this.devices = newDevices;
        this.message = `已发现 ${this.devices.length} 个 BLE 设备`;
      });
      bleScanManager.startScan();
    }
  }

  public stopBleScan(): void {
    bleScanManager.stopScan();
    this.scanning = false;
  }

  public onSelectDevice(device: BleDevice): void {
    this.stopBleScan();
    this.connectedDeviceId = '';
    this.connectStateText = '连接中...';
    gattClientManager.startConnect(device.id);
  }

  private parseServices(services: Array<ble.GattService>): void {
    this.serviceList = services.map((svc: ble.GattService): ServiceViewItem => ({
      uuid: svc.serviceUuid,
      isPrimary: svc.isPrimary,
      characteristics: svc.characteristics.map((ch): CharViewItem => ({
        uuid: ch.characteristicUuid,
        properties: (ch.properties ? ((ch.properties.read ? 'Read ' : '') + (ch.properties.write || ch.properties.writeNoResponse ? 'Write ' : '') + (ch.properties.notify || ch.properties.indicate ? 'Notify ' : '')) : '').trim(),
        canWrite: !!(ch.properties?.write || ch.properties?.writeNoResponse),
        canNotify: !!(ch.properties?.notify || ch.properties?.indicate)
      }))
    }));
  }

  public confirmServiceSelection(): void {
    if (this.currentServiceUuid && this.selectedWriteUuid && this.selectedNotifyUuid) {
      gattClientManager.updateTargetService(this.currentServiceUuid, this.selectedWriteUuid, this.selectedNotifyUuid);
      gattClientManager.discoverServices()
        .then((): Promise<void> => gattClientManager.Notify(true))
        .then((): void => {
          this.showServiceSelector = false;
          this.message = 'Notify开启成功';
        })
        .catch((e: BusinessError) => {
          this.message = 'Err:' + e.message;
        });
    }
  }

  public cancelServiceSelection(): void {
    this.showServiceSelector = false;
  }

  public onDisappear(): void {
    this.stopAutoSend();
    this.stopMultiAutoSend();
    try { TcpTransport.getInstance().disconnect(); } catch(e) {}
    this.otaController.stop();
  }

  public initBleCallbacks(): void {
    gattClientManager.setOnConnectionStateChange((state: ble.ProfileConnectionState, deviceId: string) => {
      if (state === constant.ProfileConnectionState.STATE_CONNECTED) {
        this.connectedDeviceId = deviceId;
        this.connectStateText = `已连接: ${deviceId}`;
        this.activeChannel = 'BLE';
        gattClientManager.discoverServices().then((s: Array<ble.GattService>) => {
          this.parseServices(s);
          this.showServiceSelector = true;
        });
      } else if (state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
        this.connectedDeviceId = '';
        this.connectStateText = '未连接';
        this.otaController.stop();
      }
    });

    gattClientManager.setOnDataReceived((data: Uint8Array) => {
      if (this.isOtaLoading) {
        this.otaController.processRxData(data);
        return;
      }

      const hexStr = this.bytesToHexString(data).toUpperCase();
      const now = this.getCurrentTimeString();
      this.bleReceiveHex = this.bleReceiveHex ? `${this.bleReceiveHex}\n[${now}] ${hexStr}` : `[${now}] ${hexStr}`;

      let decoder: util.TextDecoder;
      try {
        decoder = util.TextDecoder.create('gb2312');
      } catch (_e) {
        decoder = util.TextDecoder.create('utf-8');
      }
      const textPart = decoder.decodeToString(data);
      this.bleReceiveText = this.bleReceiveText ? `${this.bleReceiveText}\n[${now}] ${textPart}` : `[${now}] ${textPart}`;
      this.message = '收到 BLE 数据';
    });

    gattClientManager.setOnFrameReceived((frame: ProtocolFrame) => {
      const now = this.getCurrentTimeString();
      const rawHex = ProtocolParser.bytesToHexString(frame.raw);
      const dataHex = ProtocolParser.bytesToHexString(frame.data);
      const deviceTypeText = this.getDeviceTypeText(frame.deviceType);
      const decoded = ProtocolDecoder.decode(frame.deviceType, frame.data);
      const summary = this.buildDecodedSummary(decoded);
      if (decoded && decoded.payload && !(decoded.payload instanceof Uint8Array)) {
        const p = decoded.payload as CommandPayload;
        if (p.type === 'status') {
          const s = p as StatusPayload;
          this.alarmActive = s.alarm;
          this.tamperActive = s.tamper;
        }
      }
      const viewModel: ParsedFrameViewModel = {
        time: now,
        rawHex,
        address: frame.address,
        deviceTypeText,
        dataHex,
        checksumOk: frame.checksumOk,
        decodedSummary: summary
      };
      this.parsedFrames.unshift(viewModel);
      if (this.parsedFrames.length > 200) {
        this.parsedFrames.pop();
      }
    });
  }

  public async initWithContext(context: common.UIAbilityContext): Promise<void> {
    this.appContext = context;
    this.loadMultiSendConfig();
    
    // ⭐ 初始化时即提取 MQT，供界面展示，方便后续协议认证使用
    try {
      const sysInfo = await getSystemInfo();
      this.fullSysInfo = sysInfo.info;
      const match = sysInfo.info.match(/mqt=([^,]+)/);
      if (match && match[1]) {
        this.virtualMqttCode = match[1].trim();
      } else {
        this.virtualMqttCode = '未生成';
      }
    } catch(e) {
      console.error('getSystemInfo for mqt error', e);
    }
  }

  private async saveMultiSendConfig(): Promise<void> {
    if (this.appContext) {
      try {
        const p = await dataPreferences.getPreferences(this.appContext, 'cfg');
        await p.put('list', JSON.stringify(this.multiSendList));
        await p.flush();
      } catch (e) {
        console.error('saveMultiSendConfig error', e);
      }
    }
  }

  private async loadMultiSendConfig(): Promise<void> {
    if (this.appContext) {
      try {
        const p = await dataPreferences.getPreferences(this.appContext, 'cfg');
        const s = await p.get('list', '') as string;
        if (s) this.multiSendList = JSON.parse(s);
      } catch (e) {
        console.error('loadMultiSendConfig error', e);
      }
    }
  }
}