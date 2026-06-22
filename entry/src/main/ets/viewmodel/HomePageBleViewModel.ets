import { SignalBoardViewModel } from './SignalBoardViewModel';
import bundleManager from '@ohos.bundle.bundleManager';
import { common } from '@kit.AbilityKit';
import { constant, ble } from '@kit.ConnectivityKit';
import { BusinessError } from '@ohos.base';
import { TcpClient, TcpMessageEvent } from '../Network/TcpClient';
import { TcpDeviceManager } from '../Network/TcpDeviceManager';
import { TcpTransport } from '../common/transport/TcpTransport';
import { util } from '@kit.ArkTS';

import pasteboard from '@ohos.pasteboard';
import { UIContext, router } from '@kit.ArkUI'; 
import window from '@ohos.window';
import dataPreferences from '@ohos.data.preferences';

import AdapterManager from '../bluetooth/AdapterManager';
import bleScanManager, { BleDevice } from '../bluetooth/BleSearch';
import sleScanManager, { SleDevice } from '../bluetooth/SleSearch';
import gattClientManager from '../bluetooth/GattClientManager';
import { PermissionUtil } from '../utils/PermissionUtil';
import { BLE_PERMISSIONS, SLE_PERMISSIONS } from '../utils/PermissionsConfig';

import { LicenseManager, LicenseCheckResult } from '../common/LicenseManager';

import { detectScreenInfo, ScreenType as ScreenTypeFromHelper } from '../common/ScreenTypeHelper';
import { DeviceType, ProtocolFrame, ProtocolParser } from '../common/ProtocolParser';
import { getSystemInfo } from '../common/DeviceInfoUtil';
import resourceManager from '@ohos.resourceManager';
import { i18n } from '@kit.LocalizationKit';

import { LogManager } from '../common/database/LogManager';
import { LogCategory } from '../common/database/LogEntity';
import { AppConfig } from '../common/AppConfig';

type Resource = resourceManager.Resource;

export interface DeviceInfoView {
  id: string;
  name: string;
  address: string;
  status: string;
  rssi: number;
}

export type ScreenType = ScreenTypeFromHelper;

type ConnectedDeviceKind = 'MICROWAVE_RX' | 'MICROWAVE_TX' | 'FIBER' | 'UNKNOWN';

@Observed
export class HomePageBleViewModel {
  // ============ UI 绑定状态 ============
  isSearching: boolean = false;
  searchProgress: number = 0;
  searchTip: string = '';

  isLargeScreen: boolean = false;
  screenType: ScreenType = 'PHONE';
  screenDiagonalInch: number = 0;

  deviceList: DeviceInfoView[] = [];
  private allFoundDevices: DeviceInfoView[] = [];

  isFilterBarVisible: boolean = false;
  filterText: string = '';

  connectedDeviceId: string = '';
  connectStateText: string = '';

  // ⭐ 新增：记录被选中的列表名称
  selectedDeviceName: string = '';
  // ⭐ 光纤：记录探测到的设备地址
  detectedFiberAddress: number = 0x01;

  versionName: string = '';

  staMode: boolean = false;
  tcpMode: boolean = false;
  sleMode: boolean = false;  // ⭐ 星闪模式

  // 授权相关
  isAuthorized: boolean = false;
  showAuthDialog: boolean = false;
  machineCode: string = '';
  registerCode: string = '';

  signalBoardVm: SignalBoardViewModel = new SignalBoardViewModel();
  deviceKind: ConnectedDeviceKind = 'UNKNOWN';

  currentLocale: 'zh-CN' | 'en-US' | 'ja-JP' = 'zh-CN';
  currentLanguageIndex: number = 0;

  languageOptions: Array<SelectOption> = [
    { value: '中文', icon: $r('app.media.icon_foreground') },
    { value: 'English', icon: $r('app.media.icon_foreground') },
    { value: '日本語', icon: $r('app.media.icon_foreground') }
  ];

 
  tcpIp: string = AppConfig.SERVER_HOST; 
    // 修复2：使用 .toString() 将 number 转换为 string
    tcpPort: string = AppConfig.ALARM_SERVER_PORT.toString();
  showTcpDialog: boolean = false;
  tcpListConnected: boolean = false;

  public uiContext: UIContext | null = null; 

  private receiveBuffer: string = '';
  private receiveTimer: number | undefined = undefined;

  private scanTimer: number | undefined = undefined;
  private context?: common.UIAbilityContext;
  private windowSizeListenerInited: boolean = false;

  private detectingDevice: boolean = false;
  private detectPhase: 'IDLE' | 'MICROWAVE_RX' | 'FIBER' | 'MICROWAVE_TX' = 'IDLE';
  private currentPhaseResolve?: (kind: ConnectedDeviceKind) => void;

  private tcpListClient: TcpClient | undefined = undefined;
  private readonly PREF_NAME = 'app_settings';
  private readonly KEY_LANG = 'language_code';
  private readonly KEY_LOCAL_DEVICES = 'local_tcp_devices_v1';
  private readonly LISTENER_KEY = 'HomePageVM';

  private localParser: ProtocolParser = new ProtocolParser();

  private showToastMsg(msg: string, duration?: number): void {
    if (this.uiContext) {
      try {
        this.uiContext.getPromptAction().showToast({
          message: msg,
          duration: duration
        });
      } catch (e) {}
    }
  }

  private getString(res: Resource, fallback?: string): string {
    if (!this.context) return fallback ?? '';
    try { return this.context.resourceManager.getStringSync(res.id); }
    catch (err) { return fallback ?? ''; }
  }

  private getStringFmt(res: Resource, args: (string | number)[], fallback?: string): string {
    if (!this.context) return fallback ?? '';
    try {
      if (args && args.length > 0) return this.context.resourceManager.getStringSync(res.id, ...args);
      return this.context.resourceManager.getStringSync(res.id);
    } catch (err) { return fallback ?? ''; }
  }

  switchLanguageByIndex(index: number) {
    if (this.currentLanguageIndex === index) return;
    this.currentLanguageIndex = index;
    let target: 'zh-CN' | 'en-US' | 'ja-JP' = 'zh-CN';
    if (index === 1) target = 'en-US';
    if (index === 2) target = 'ja-JP';
    this.changeLanguage(target);
  }

  async changeLanguage(locale: 'zh-CN' | 'en-US' | 'ja-JP'): Promise<void> {
    this.currentLocale = locale;
    let langCode = locale;
    try {
      if (this.context) {
        const pref = await dataPreferences.getPreferences(this.context, this.PREF_NAME);
        await pref.put(this.KEY_LANG, langCode);
        await pref.flush();
      }
      let currentAppLang = i18n.System.getAppPreferredLanguage();
      if (currentAppLang === langCode) return;
      i18n.System.setAppPreferredLanguage(langCode);
      this.refreshLocalizedText();
      this.showToastMsg('Language switching...'); 
    } catch (error) {
      console.error('Change language failed: ' + error);
    }
  }

  async onAppear(context: common.UIAbilityContext) {
    this.context = context;
    await LogManager.getInstance().init(context);

    if (this.deviceList.length === 0) {
      this.deviceList = [];
      this.allFoundDevices = [];
    }
    await this.loadAppVersion();
    this.detectScreenSize();
    this.initWindowSizeListener().catch(() => {});
    await this.initLicense();
    await this.initLanguagePreference();
    this.refreshLocalizedText();
    this.initGattConnectionListener();
    this.initGattDataListener();
  }

  onPageShow() {
    gattClientManager.resetConfiguration();
    this.initGattConnectionListener();
    this.initGattDataListener();
  }

  private async initLanguagePreference() {
    if (!this.context) return;
    try {
      const pref = await dataPreferences.getPreferences(this.context, this.PREF_NAME);
      let savedLang = await pref.get(this.KEY_LANG, 'zh-CN') as string;
      if (savedLang === 'en-US') {
        this.currentLanguageIndex = 1;
        this.currentLocale = 'en-US';
      } else if (savedLang === 'ja-JP') {
        this.currentLanguageIndex = 2;
        this.currentLocale = 'ja-JP';
      } else {
        this.currentLanguageIndex = 0;
        this.currentLocale = 'zh-CN';
      }
      let currentAppLang = i18n.System.getAppPreferredLanguage();
      if (currentAppLang !== savedLang) {
        i18n.System.setAppPreferredLanguage(savedLang);
      }
    } catch (e) {
      this.currentLanguageIndex = 0;
      this.currentLocale = 'zh-CN';
    }
  }

  private refreshLocalizedText() {
    if (this.connectedDeviceId) {
      this.connectStateText = this.getStringFmt($r('app.string.connect_state_connected_fmt'), [this.connectedDeviceId]);
    } else {
      this.connectStateText = this.getString($r('app.string.connect_state_disconnected'), '未连接');
    }
    if (!this.isSearching && !this.connectedDeviceId && !this.detectingDevice) {
      this.searchTip = this.getString($r('app.string.home_search_tip_idle'), '点击“搜索设备”开始搜索');
    } else if (this.isSearching) {
      this.searchTip = this.getString($r('app.string.list_empty_searching'), '正在搜索...');
    }
  }

  private async initLicense() {
    if (!this.context) return;
    try {
      await LicenseManager.init(this.context);
      this.machineCode = LicenseManager.getMachineCode();
    } catch (e) {}
  }

  async ensureAuthorized(consume: boolean = false): Promise<boolean> {
    if (!this.context) return false;
    await LicenseManager.init(this.context);
    const res: LicenseCheckResult = await LicenseManager.checkLicenseAndConsumeOne(consume);
    if (!res.ok) {
      this.showAuthDialog = true;
      if (res.msg) {
        this.showToastMsg(res.msg, 3000); 
      }
      return false;
    }
    if (consume && res.isNearExpiry && res.expiryMsg) {
      this.showToastMsg(res.expiryMsg, 3500); 
    }
    return true;
  }

  private async loadAppVersion() {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName ?? '';
    } catch (err) {
      console.error('loadAppVersion failed: ' + err);
    }
  }

  private detectScreenSize() {
    const info = detectScreenInfo();
    this.screenType = info.screenType as ScreenType;
    this.isLargeScreen = info.isLargeScreen;
    this.screenDiagonalInch = info.diagonalInch;
  }

  private async initWindowSizeListener() {
    if (!this.context || this.windowSizeListenerInited) return;
    this.windowSizeListenerInited = true;
    try {
      const win = await window.getLastWindow(this.context);
      win.on('windowSizeChange', () => this.detectScreenSize());
    } catch (e) {}
  }

  private initGattConnectionListener() {
    gattClientManager.setOnConnectionStateChange((state: ble.ProfileConnectionState, deviceId: string) => {
      if (this.staMode || this.tcpMode || this.sleMode) return;
      if (state === constant.ProfileConnectionState.STATE_CONNECTED) {
        this.connectedDeviceId = deviceId;
        this.refreshLocalizedText();
        this.consumeLicenseOnConnected();
        gattClientManager.discoverServices().then(async () => {
          await gattClientManager.Notify(true);
          this.searchTip = this.getString($r('app.string.home_search_tip_detecting_device'), '正在识别设备类型...');
          const kind = await this.detectDeviceTypeByProtocol();
          this.handleIdentifySuccess(kind);
        }).catch(() => {
          this.searchTip = this.getString($r('app.string.home_search_tip_discover_failed'), '服务发现失败');
        });
        this.updateDeviceStatus(deviceId, this.getString($r('app.string.connect_state_connected_fmt'), '已连接'));
        LogManager.getInstance().addLog(LogCategory.CONNECTION, '连接成功 (BLE)', '蓝牙连接已建立', { name: '设备', id: deviceId });
      } else if (state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
        this.connectedDeviceId = '';
        this.refreshLocalizedText();
        this.updateDeviceStatus(deviceId, this.getString($r('app.string.connect_state_disconnected'), '未连接'));
        LogManager.getInstance().addLog(LogCategory.CONNECTION, '断开连接', '设备连接已断开', { name: '设备', id: deviceId });
      }
    });
  }

  private initGattDataListener() {
    gattClientManager.setOnFrameReceived((frame: ProtocolFrame) => {
      if (this.staMode || this.tcpMode || this.sleMode) return;
      this.handleDeviceDetectFrame(frame);
    });
  }

  private async consumeLicenseOnConnected() {
    await this.ensureAuthorized(true);
  }

  private handleIdentifySuccess(kind: ConnectedDeviceKind) {
    if (this.deviceKind !== 'UNKNOWN' && this.deviceKind === kind) return;
    this.deviceKind = kind;
    const kindText = this.getDeviceKindText(kind);
    this.searchTip = this.getStringFmt($r('app.string.home_search_tip_detect_success_fmt'), [kindText], `识别成功: ${kindText}`);
    const mode = (this.staMode || this.tcpMode) ? 'TCP' : (this.sleMode ? 'SLE' : 'BLE');
    let deviceType = DeviceType.Microwave;
    if (kind === 'FIBER') deviceType = DeviceType.Fiber;
    AppStorage.setOrCreate('GlobalConnectionMode', mode);
    AppStorage.setOrCreate('GlobalDeviceType', deviceType);
    AppStorage.setOrCreate('GlobalDeviceKind', kind);
    this.detectingDevice = false;
    this.detectPhase = 'IDLE';
    this.currentPhaseResolve = undefined;
    this.navigateToMonitorPage(kind);
  }

  private getDeviceKindText(kind: ConnectedDeviceKind): string {
    if (kind === 'MICROWAVE_RX') return this.getString($r('app.string.device_kind_microwave_rx'), '微波接收');
    if (kind === 'MICROWAVE_TX') return this.getString($r('app.string.device_kind_microwave_tx'), '微波发射');
    if (kind === 'FIBER') return this.getString($r('app.string.device_kind_fiber'), '光纤设备');
    return this.getString($r('app.string.device_kind_unknown'), '未知设备');
  }

  private resolveDetectedKind(kind: ConnectedDeviceKind) {
    if (!this.detectingDevice) return;
    if (this.currentPhaseResolve) {
      const cb = this.currentPhaseResolve;
      this.currentPhaseResolve = undefined;
      cb(kind);
    }
  }

  private handleDeviceDetectFrame(frame: ProtocolFrame) {
    if (!this.detectingDevice) return;
    if (frame.deviceType === 0x66) {
      this.detectedFiberAddress = frame.address;
      this.resolveDetectedKind('FIBER');
    }
    else if (frame.deviceType === 0xC9 && frame.data.length >= 1) {
      const echoedCmd = frame.data[0];
      if (echoedCmd === 0x96 || echoedCmd === 0x97) {
        this.resolveDetectedKind('MICROWAVE_TX');
      } else if (echoedCmd === 0x0B) {
        if (this.detectPhase === 'MICROWAVE_RX') {
          this.resolveDetectedKind('MICROWAVE_RX');
        }
      }
    }
  }

  private async sendProtocolCommand(hex: string): Promise<void> {
    if (this.staMode || this.tcpMode) {
      await TcpDeviceManager.instance.sendHexString(hex);
    } else {
      gattClientManager.writeHexString(hex);
    }
  }

  private runDetectPhase(
    phase: 'MICROWAVE_RX' | 'FIBER' | 'MICROWAVE_TX',
    sendFn: () => void,
    timeoutMs: number
  ): Promise<ConnectedDeviceKind | null> {
    return new Promise(resolve => {
      let done = false;
      let timer: number;
      const finish = (kind: ConnectedDeviceKind | null) => {
        if (done) return;
        done = true;
        this.detectingDevice = false;
        this.detectPhase = 'IDLE';
        this.currentPhaseResolve = undefined;
        clearTimeout(timer);
        resolve(kind);
      };
      this.detectPhase = phase;
      this.detectingDevice = true;
      this.currentPhaseResolve = finish;
      try { sendFn(); } catch (e) { finish(null); return; }
      timer = setTimeout(() => { finish(null); }, timeoutMs);
    });
  }

  private async detectDeviceTypeByProtocol(): Promise<ConnectedDeviceKind> {
    await this.delay(150);
    this.searchTip = this.getString($r('app.string.home_detect_step1'), '正在识别设备类型 (步骤1/3 - 探测发射端)...');
    let kind: ConnectedDeviceKind | null = await this.runDetectPhase('MICROWAVE_TX', (): void => {
      this.sendProtocolCommand('FF01C9019660');
    }, 600);
    if (kind) return kind;
    kind = await this.runDetectPhase('MICROWAVE_TX', (): void => {
      this.sendProtocolCommand('FF01C9019660');
    }, 600);
    if (kind) return kind;
    this.searchTip = this.getString($r('app.string.home_detect_step2'), '正在识别设备类型 (步骤2/3 - 探测接收端)...');
    kind = await this.runDetectPhase('MICROWAVE_RX', (): void => { this.sendProtocolCommand('FF01C9010BD5'); }, 600);
    if (kind) {
      this.searchTip = '收到0x0B应答，二次确认是否为发射端...';
      const recheck = await this.runDetectPhase('MICROWAVE_TX', (): void => {
        this.sendProtocolCommand('FF01C9019660');
      }, 400);
      if (recheck === 'MICROWAVE_TX') return 'MICROWAVE_TX';
      return 'MICROWAVE_RX';
    }
    kind = await this.runDetectPhase('MICROWAVE_RX', (): void => { this.sendProtocolCommand('FF01C9010BD5'); }, 600);
    if (kind) {
      this.searchTip = '收到0x0B应答，二次确认是否为发射端...';
      const recheck = await this.runDetectPhase('MICROWAVE_TX', (): void => {
        this.sendProtocolCommand('FF01C9019660');
      }, 400);
      if (recheck === 'MICROWAVE_TX') return 'MICROWAVE_TX';
      return 'MICROWAVE_RX';
    }
    this.searchTip = this.getString($r('app.string.home_detect_step3'), '正在识别设备类型 (步骤3/3 - 扫描光纤)...');
    for (let addr = 0x00; addr <= 0x0F; addr++) {
      if ((this.staMode || this.tcpMode) && !TcpDeviceManager.instance.isConnected) return 'UNKNOWN';
      const addrHex = addr.toString(16).padStart(2, '0').toUpperCase();
      const cmdHex = 'FF' + addrHex + '6601AA11';
      kind = await this.runDetectPhase('FIBER', (): void => { this.sendProtocolCommand(cmdHex); }, 150);
      if (kind) return kind;
    }
    return 'UNKNOWN';
  }

  private navigateToMonitorPage(kind?: ConnectedDeviceKind) {
    let deviceType: DeviceType | undefined = undefined;
    let deviceKind: string | undefined = undefined;
    if (kind === 'MICROWAVE_TX') { deviceType = DeviceType.Microwave; deviceKind = 'TX'; }
    else if (kind === 'MICROWAVE_RX') { deviceType = DeviceType.Microwave; deviceKind = 'RX'; }
    else if (kind === 'FIBER') { deviceType = DeviceType.Fiber; deviceKind = 'FIBER'; }
    
    if (this.uiContext) {
      // ⭐ 修复：使用 Record 字典传递参数，并补上缺失的逗号，完美避开所有编译报错！
      const navParams: Record<string, Object> = {};
      navParams['screenType'] = this.screenType;
      if (deviceType !== undefined) navParams['deviceType'] = deviceType;
      if (deviceKind !== undefined) navParams['deviceKind'] = deviceKind;
      navParams['connectionMode'] = (this.staMode || this.tcpMode) ? 'TCP' : (this.sleMode ? 'SLE' : 'BLE');
      navParams['deviceName'] = this.selectedDeviceName;
      navParams['deviceAddress'] = this.detectedFiberAddress;

      this.uiContext.getRouter().pushUrl({
        url: 'pages/MonitorPage',
        params: navParams
      }, router.RouterMode.Standard).catch(() => {});
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private updateDeviceStatus(id: string, status: string) {
    const idx = this.allFoundDevices.findIndex(d => d.id === id);
    if (idx >= 0) {
      const oldItem = this.allFoundDevices[idx];
      const newItem: DeviceInfoView = {
        id: oldItem.id, name: oldItem.name, address: oldItem.address,
        status: status, rssi: oldItem.rssi
      };
      this.allFoundDevices[idx] = newItem;
    }
    this.refreshDeviceList();
  }

  async onSelectDevice(item: DeviceInfoView) {
    this.stopBleScan();
    this.closeTcpListClient();
    if (!await this.ensureAuthorized(false)) return;

    this.selectedDeviceName = item.name;

    this.updateDeviceStatus(item.id, this.getString($r('app.string.device_status_connecting'), '正在连接'));
    this.searchTip = this.getStringFmt($r('app.string.home_search_tip_connecting'), [item.name], `正在连接: ${item.name}`);

    // ⭐ 星闪模式：暂时仅显示扫描结果，连接功能后续开发
    if (this.sleMode) {
      this.searchTip = `已选星闪设备: ${item.name}（连接功能开发中，本次仅验证扫描）`;
      this.updateDeviceStatus(item.id, '已选择');
      return;
    }

    if (this.staMode || this.tcpMode) {
      const parts = item.id.split(':');
      if (parts.length !== 2) {
        this.searchTip = '无效地址';
        return;
      }
      const ip = parts[0];
      const port = parseInt(parts[1]);
      try {
        await TcpDeviceManager.instance.connectDevice(ip, port);
        this.consumeLicenseOnConnected();
        LogManager.getInstance().addLog(LogCategory.CONNECTION, '连接设备 (TCP)', `IP: ${ip}, Port: ${port}`, { name: item.name, id: item.id });
        const transport = TcpTransport.getInstance();
        transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array) => {
          const frames = this.localParser.feed(data);
          frames.forEach((frame): void => this.handleDeviceDetectFrame(frame));
        });
        this.connectedDeviceId = item.id;
        this.connectStateText = this.getStringFmt($r('app.string.connect_state_connected_fmt'), [item.name]);
        this.updateDeviceStatus(item.id, '已连接');
        this.searchTip = this.getString($r('app.string.home_search_tip_detecting_device'), '正在识别设备类型...');
        const kind = await this.detectDeviceTypeByProtocol();
        this.handleIdentifySuccess(kind);
      } catch (e) {
        const err = e as BusinessError;
        this.searchTip = `TCP Error: ${err.message}`;
        this.updateDeviceStatus(item.id, '连接失败');
      }
    } else {
      this.connectedDeviceId = '';
      gattClientManager.startConnect(item.id);
      LogManager.getInstance().addLog(LogCategory.CONNECTION, '发起连接 (BLE)', `尝试连接蓝牙设备`, { name: item.name, id: item.id });
    }
  }

  onSearchButtonClick() {
    if (this.staMode) {
      this.autoFetchTcpList();
    } else if (this.sleMode) {
      // ⭐ 星闪模式：扫描 SLE 设备
      if (this.isSearching) {
        this.stopSleScan();
      } else {
        this.startSleScanWithProgress();
      }
    } else {
      this.startBleScanWithProgress();
    }
  }

  async onAlarmAnalysisClick() {
    if (!await this.ensureAuthorized(false)) return;

    this.isSearching = true; 
    this.searchTip = '正在连接服务器请求报警分析数据...';

    const ip = AppConfig.SERVER_HOST;
    const port = AppConfig.ALARM_SERVER_PORT

    this.closeTcpListClient(); 
   // this.tcpListClient = new TcpClient({ host: ip, port: port, timeout: 5000 });
   this.tcpListClient = new TcpClient({ host: ip, port: port, timeout: 5000 });
    this.receiveBuffer = '';
    if (this.receiveTimer) {
      clearTimeout(this.receiveTimer);
      this.receiveTimer = undefined;
    }

    this.tcpListClient.setOnConnect(async () => {
      this.tcpListConnected = true;
      this.searchTip = '服务器已连接，正在请求报警数据...';
      try {
        let imei = (this.machineCode || 'default_imei').trim(); 
        try {
          const sysInfo = await getSystemInfo();
          await this.tcpListClient?.sendTextGbk(sysInfo.info);
          
          const match = sysInfo.info.match(/mqt=([^,]+)/);
          if (match && match[1]) {
            imei = match[1].trim(); 
          }
        } catch (e) {
          console.warn('获取系统信息失败', e);
        }
        
        await this.delay(150);
        console.info('AlarmAnalysis', `👉 正在发送报警请求，当前使用的真正虚拟码是: [${imei}]`);

        const cmd = `${imei}|报警统计`;
        await this.tcpListClient?.sendTextGbk(cmd);
      } catch (e) {
        let err = e as BusinessError; 
        console.error('发送报警请求异常: ' + err.message);
        this.searchTip = '数据请求发送失败';
        this.isSearching = false;
      }
    });

    this.tcpListClient.setOnMessage((event: TcpMessageEvent) => {
      const data = new Uint8Array(event.message);
      try {
        const decoder = util.TextDecoder.create('gbk', { ignoreBOM: true });
        this.receiveBuffer += decoder.decodeToString(data);
      } catch (e) {}

      if (this.receiveTimer !== undefined) {
        clearTimeout(this.receiveTimer);
      }

      this.receiveTimer = setTimeout(() => {
        console.info('HomePageBleViewModel', '👉 完整接收到的缓冲数据:\n' + this.receiveBuffer);
        if (this.receiveBuffer.includes('设备名')) {
          this.searchTip = '获取报警数据成功，正在解析...';
          setTimeout(() => {
            this.closeTcpListClient();
            this.isSearching = false;
            this.searchTip = '';
          }, 500);

          if (this.uiContext) {
            this.uiContext.getRouter().pushUrl({
              url: 'pages/AlarmAnalysisPage', 
              params: { alarmData: this.receiveBuffer }
            }, router.RouterMode.Standard).catch((err: Error) => { 
               console.error('跳转报警页面失败', err.message);
            });
          }
        } else {
          this.searchTip = '未获取到有效的报警统计数据格式';
          this.isSearching = false;
        }
      }, 300); 
    });

    this.tcpListClient.setOnError((err: BusinessError) => { 
      this.searchTip = `连接失败: ${err.message}`;
      this.isSearching = false;
      this.tcpListConnected = false;
      this.showToastMsg('连接服务器失败，请检查网络');
    });

    this.tcpListClient.setOnClose(() => {
      this.tcpListConnected = false;
      if (this.isSearching) this.isSearching = false;
    });

    try {
      await this.tcpListClient.connect();
    } catch (e) {
      this.searchTip = 'TCP Server Connection Error';
      this.isSearching = false;
    }
  }

  private async autoFetchTcpList() {
    const ip = AppConfig.SERVER_HOST
    const port = AppConfig.ALARM_SERVER_PORT

    this.closeTcpListClient();
    this.isSearching = true;
    this.searchTip = `Connecting ${ip}:${port}...`;

    this.tcpListClient = new TcpClient({ host: ip, port: port, timeout: 5000 });

    this.tcpListClient.setOnConnect(async () => {
        this.tcpListConnected = true;
        this.searchTip = 'Authenticating...';
        try {
            const sysInfo = await getSystemInfo();
            await this.tcpListClient?.sendTextGbk(sysInfo.info);
            await this.delay(100);
            this.searchTip = 'Fetching list...';
            await this.tcpListClient?.sendTextGbk('确认更新数据');
        } catch (e) {
            console.error('Send info error: ' + e);
            this.searchTip = 'Send request failed';
            this.isSearching = false;
        }
    });

    this.tcpListClient.setOnMessage((event: TcpMessageEvent) => {
      const data = new Uint8Array(event.message);
      let text = '';
      try {
        const decoder = util.TextDecoder.create('gbk', { ignoreBOM: true });
        text = decoder.decodeToString(data);
      } catch (e) {}
      
      this.parseAndAddTcpDevices(text, ip);

      setTimeout(() => {
        this.closeTcpListClient();
        this.isSearching = false;
        this.searchTip = '';
      }, 500);
    });

    this.tcpListClient.setOnError((err: BusinessError) => {
      this.searchTip = `Connect failed: ${err.message}`;
      this.isSearching = false;
      this.tcpListConnected = false;
    });

    this.tcpListClient.setOnClose(() => {
      this.tcpListConnected = false;
      if (this.isSearching) this.isSearching = false;
    });

    try {
      await this.tcpListClient.connect();
    } catch (e) {
      this.searchTip = 'TCP Connection Error';
      this.isSearching = false;
    }
  }

  private parseAndAddTcpDevices(text: string, serverIp: string) {
    const lines = text.split(/\r?\n/);
    const newItems: DeviceInfoView[] = [];
    for (const line of lines) {
      const cleanLine = line.trim();
      if (!cleanLine) continue;
      const parts = cleanLine.split(/\s+/);
      if (parts.length >= 2) {
        const portStr = parts[0];
        const name = parts.slice(1).join(' ');
        const portNum = parseInt(portStr);
        if (isNaN(portNum)) continue;

        const id = `${serverIp}:${portStr}`;
        if (!this.allFoundDevices.find(d => d.id === id)) {
          newItems.push({
            id: id, name: name, address: 'Online', status: 'Online', rssi: -1
          });
        }
      }
    }
    if (newItems.length > 0) {
      this.allFoundDevices = [...this.allFoundDevices, ...newItems];
      this.refreshDeviceList();
    }
  }

  private closeTcpListClient() {
    if (this.tcpListClient) {
      try { this.tcpListClient.close(); } catch(e){}
      this.tcpListClient = undefined;
    }
    this.tcpListConnected = false;
  }

  private async startBleScanWithProgress() {
    if (!this.context) return;
    const ok = await PermissionUtil.checkAndRequestPermissions(this.context, BLE_PERMISSIONS);
    if (!ok) {
      this.searchTip = this.getString($r('app.string.home_tip_permission_denied_search'), '权限不足');
      return;
    }

    if (!AdapterManager.isBluetoothOn()) AdapterManager.openBluetooth();

    try { bleScanManager.stopScan(); } catch (e) {}
    await this.delay(100);

    this.isSearching = true;
    this.allFoundDevices = [];
    this.deviceList = [];
    this.refreshDeviceList();
    this.searchProgress = 0;
    this.searchTip = this.getString($r('app.string.list_empty_searching'), '正在搜索...');

    bleScanManager.setOnDeviceFoundCallback((device: BleDevice) => {
      if (!device.name || device.name.trim().length === 0) return;
      const idx = this.allFoundDevices.findIndex(d => d.id === device.id);
      if (idx === -1) {
        let newItem: DeviceInfoView = {
          id: device.id, name: device.name, address: device.id,
          status: this.getString($r('app.string.connect_state_disconnected'), '未连接'), rssi: device.rssi
        };
        this.allFoundDevices.push(newItem);
      } else {
        this.allFoundDevices[idx].rssi = device.rssi;
      }
      this.refreshDeviceList();
    });

    bleScanManager.startScan();
    this.scanTimer = setInterval(() => {
      this.searchProgress = Math.min(this.searchProgress + 5, 100);
      if (this.searchProgress >= 100) this.stopBleScan();
    }, 200);
  }

  stopBleScan() {
    if (AdapterManager.isBluetoothOn()) {
      try { bleScanManager.stopScan(); } catch (e) {}
    }
    if (this.isSearching) {
      this.isSearching = false;
      if (this.scanTimer) {
        clearInterval(this.scanTimer);
        this.scanTimer = undefined;
      }
      if (this.searchProgress > 100) this.searchProgress = 100;
      this.searchTip = this.getString($r('app.string.home_search_tip_stopped'), '搜索已停止');
    }
  }

  // ⭐ 星闪 SLE 扫描
  async startSleScanWithProgress() {
    if (!this.context) return;
    const ok = await PermissionUtil.checkAndRequestPermissions(this.context, SLE_PERMISSIONS);
    if (!ok) {
      this.searchTip = '星闪权限不足，请在设置中授予 NearLink 和位置权限';
      return;
    }

    try { sleScanManager.stopScan(); } catch (e: Error) {}
    await this.delay(100);

    this.isSearching = true;
    this.allFoundDevices = [];
    this.deviceList = [];
    this.refreshDeviceList();
    this.searchProgress = 0;
    this.searchTip = '正在扫描星闪设备...';

    sleScanManager.setOnDeviceFoundCallback((device: SleDevice) => {
      if (!device.name || device.name.trim().length === 0) return;

      const idx = this.allFoundDevices.findIndex(d => d.id === device.id);
      if (idx === -1) {
        let newItem: DeviceInfoView = {
          id: device.id,
          name: device.name,
          address: device.id,
          status: '未连接',
          rssi: device.rssi
        };
        this.allFoundDevices.push(newItem);
      } else {
        this.allFoundDevices[idx].rssi = device.rssi;
      }
      this.refreshDeviceList();
    });

    sleScanManager.startScan();

    this.scanTimer = setInterval(() => {
      this.searchProgress = Math.min(this.searchProgress + 5, 100);
      if (this.searchProgress >= 100) {
        this.stopSleScan();
      }
    }, 200);
  }

  stopSleScan() {
    try { sleScanManager.stopScan(); } catch (e: Error) {}

    if (this.isSearching) {
      this.isSearching = false;
      if (this.scanTimer) {
        clearInterval(this.scanTimer);
        this.scanTimer = undefined;
      }
      this.searchProgress = 100;
      this.searchTip = '星闪搜索已停止';
    }
  }

  async onTcpModeChange(value: boolean) {
    if (value) {
      if (!await this.ensureAuthorized(false)) {
        this.tcpMode = false;
        return;
      }
      this.tcpMode = true;
      this.staMode = false;
      this.sleMode = false;
      this.stopBleScan();
      this.closeTcpListClient();
      this.isFilterBarVisible = false;
      this.filterText = '';
      this.searchTip = '本地设备模式 (TCP)';
      await this.loadLocalDevices();
    } else {
      this.tcpMode = false;
      this.searchTip = this.getString($r('app.string.home_connect_mode_ble'), '默认模式');
      this.allFoundDevices = [];
      this.refreshDeviceList();
    }
  }

  async onStaModeChange(value: boolean) {
    if (value) {
      if (!await this.ensureAuthorized(false)) {
        this.staMode = false;
        return;
      }
      this.staMode = true;
      if (value) this.tcpMode = false;
      this.sleMode = false;
      this.isFilterBarVisible = false;
      this.filterText = '';
      this.allFoundDevices = [];
      this.deviceList = [];
      this.closeTcpListClient(); 
      this.searchTip = this.getString($r('app.string.home_connect_mode_sta'), 'STA 模式(网络)');
    } else {
      this.staMode = false;
    }
  }

  async onSleModeChange(value: boolean) {
    if (value) {
      if (!await this.ensureAuthorized(false)) {
        this.sleMode = false;
        return;
      }
      this.sleMode = true;
      this.staMode = false;
      this.tcpMode = false;
      this.stopBleScan();
      this.closeTcpListClient();
      this.isFilterBarVisible = false;
      this.filterText = '';
      this.allFoundDevices = [];
      this.deviceList = [];
      this.refreshDeviceList();
      this.searchTip = '星闪模式 (SLE) — 点击搜索扫描附近星闪设备';
    } else {
      this.sleMode = false;
      this.stopSleScan();
      this.searchTip = this.getString($r('app.string.home_connect_mode_ble'), '默认模式');
      this.allFoundDevices = [];
      this.refreshDeviceList();
    }
  }

  async loadLocalDevices() {
    if (!this.context) return;
    try {
      const pref = await dataPreferences.getPreferences(this.context, this.PREF_NAME);
      const jsonStr = await pref.get(this.KEY_LOCAL_DEVICES, '[]') as string;
      const list = JSON.parse(jsonStr) as DeviceInfoView[];
      list.forEach(d => { d.status = '离线'; d.rssi = -1; });
      this.allFoundDevices = list;
      this.refreshDeviceList();
    } catch (e) {
      this.allFoundDevices = [];
      this.refreshDeviceList();
    }
  }

  async addLocalDevice(name: string, ip: string, port: string, type: string) {
    const id = `${ip}:${port}`;
    const newItem: DeviceInfoView = {
      id: id, name: `${type}-${name}`, address: id, status: '离线', rssi: -1
    };
    const idx = this.allFoundDevices.findIndex(d => d.id === id);
    if (idx >= 0) {
      this.allFoundDevices[idx] = newItem;
    } else {
      this.allFoundDevices.push(newItem);
    }
    await this.saveLocalDevices();
    this.refreshDeviceList();
  }

  async deleteLocalDevice(id: string) {
    this.allFoundDevices = this.allFoundDevices.filter(d => d.id !== id);
    await this.saveLocalDevices();
    this.refreshDeviceList();
  }

  private async saveLocalDevices() {
    if (!this.context) return;
    try {
      const pref = await dataPreferences.getPreferences(this.context, this.PREF_NAME);
      await pref.put(this.KEY_LOCAL_DEVICES, JSON.stringify(this.allFoundDevices));
      await pref.flush();
    } catch (e) {}
  }

  async copyMachineCode(): Promise<void> {
    if (!this.machineCode) return;
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.machineCode);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToastMsg(this.getString($r('app.string.toast_copy_machine_code_success'), '已复制')); 
    } catch (e) {
      console.error('Copy machine code failed', e);
    }
  }

  async pasteRegisterCode(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      if (data) {
        const text = data.getPrimaryText();
        if (text) {
          this.registerCode = text;
          this.showToastMsg(this.getString($r('app.string.toast_paste_success'), '已粘贴')); 
        }
      }
    } catch (e) {
      console.error('Paste register code failed', e);
    }
  }

  cancelLicenseDialog() { this.showAuthDialog = false; }
  async confirmLicenseFromDialog() {
    await LicenseManager.verifyAndSaveLicense(this.registerCode);
    this.showAuthDialog = false;
  }

  onDisappear() {
    this.stopBleScan();
    this.stopSleScan();
    this.closeTcpListClient();
    TcpTransport.getInstance().offDataReceived(this.LISTENER_KEY);
  }

  toggleFilterBar() {
    this.isFilterBarVisible = !this.isFilterBarVisible;
    if (!this.isFilterBarVisible) {
      this.filterText = '';
      this.refreshDeviceList();
    }
  }

  setFilterText(text: string) {
    this.filterText = text;
    this.refreshDeviceList();
  }

  private refreshDeviceList() {
    if (!this.filterText || this.filterText.trim().length === 0) {
      this.deviceList = [...this.allFoundDevices];
    } else {
      const keyword = this.filterText.toLowerCase().trim();
      this.deviceList = this.allFoundDevices.filter(d => {
        return d.name.toLowerCase().includes(keyword) || 
               d.address.toLowerCase().includes(keyword) || 
               d.id.toLowerCase().includes(keyword);
      });
    }
  }

  openTcpDialog() {}
  cancelTcpDialog() {}
  confirmTcpConnect() {}
}