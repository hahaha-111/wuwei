// pages/AlarmAnalysisPage.ets
import { router } from '@kit.ArkUI'; // ⭐ 修改：统一使用现代 ArkUI router
import { AlarmAnalysisViewModel, AlarmRowData, ConnectedDeviceKind } from '../viewmodel/AlarmAnalysisViewModel';
import { DeviceType } from '../common/ProtocolParser';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct AlarmAnalysisPage {
  @State vm: AlarmAnalysisViewModel = new AlarmAnalysisViewModel();
  @State isSearching: boolean = false;       
  @State searchingPort: string = '';         
  private uiContext: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    // ⭐ 修复：使用 API 13 专用的 getHostContext 代替已过时的全局 getContext(this)
    this.uiContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    
    // ⭐ 核心注入：给 vm 赋值当前的 UI 上下文，彻底激活高级弹窗与安全路由跳转
    this.vm.uiContext = this.getUIContext();

    // ⭐ 修复：使用安全不弃用的 UIContext 获取路由参数并注入 ViewModel
    const routerParams = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.vm.initData(routerParams);
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  async startSearchAndNavigate(port: string): Promise<void> {
    if (this.isSearching) return;
    
    this.isSearching = true;
    this.searchingPort = port;

    try {
      const kind: ConnectedDeviceKind = await this.vm.connectDevice(port);
      
      if (kind === 'UNKNOWN') {
        if (this.uiContext) {
          this.getUIContext().getPromptAction().showToast({ message: '连接成功，但未识别到支持的设备类型' });
        }
        this.isSearching = false;
        return;
      }

      if (this.uiContext) {
        this.getUIContext().getPromptAction().showToast({ message: `设备识别成功: ${kind}` });
      }

      let deviceTypeStr: DeviceType = DeviceType.Microwave;
      let deviceKindStr = 'UNKNOWN';
      
      if (kind === 'MICROWAVE_TX') { 
        deviceTypeStr = DeviceType.Microwave; 
        deviceKindStr = 'TX'; 
      } else if (kind === 'MICROWAVE_RX') { 
        deviceTypeStr = DeviceType.Microwave; 
        deviceKindStr = 'RX'; 
      } else if (kind === 'FIBER') { 
        deviceTypeStr = DeviceType.Fiber; 
        deviceKindStr = 'FIBER'; 
      }

      AppStorage.setOrCreate('GlobalConnectionMode', 'TCP');
      AppStorage.setOrCreate('GlobalDeviceType', deviceTypeStr);
      AppStorage.setOrCreate('GlobalDeviceKind', deviceKindStr);

      this.isSearching = false;
      
      // ⭐ 修复：在 pushUrl 时显式传入 RouterMode 并捕获 Promise 异常
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/MonitorPage',
        params: {
          deviceType: deviceTypeStr,
          deviceKind: deviceKindStr,
          connectionMode: 'TCP',
          port: port,
          fromPage: 'AlarmAnalysisPage'
        }
      }, router.RouterMode.Standard).catch((err: Error) => {
        console.error("跳转到 MonitorPage 失败: ", err.message);
      });

    } catch (e) {
      const err = e as BusinessError;
      this.isSearching = false;
      if (this.uiContext) {
        this.getUIContext().getPromptAction().showToast({ message: `连接异常: ${err.message}` });
      }
      console.error('AlarmAnalysis', `连接或识别失败: ${err.message}`);
    }
  }

  // 严重程度颜色分类标注图例（Legend）
  @Builder ColorLegendItem(color: string, text: string) {
    Row({ space: 4 }) {
      Rect({ width: 14, height: 14 })
        .fill(color)
        .borderRadius(3)
        .shadow({ radius: 1, color: '#30000000', offsetY: 0.5 })
      Text(text)
        .fontSize(12)
        .fontColor('#555555')
        .fontWeight(FontWeight.Medium)
    }
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      // 1. 顶部标题栏
      Row() {
        Button('返回', { type: ButtonType.Normal })
          .borderRadius(6)
          .backgroundColor('#1976D2')
          // ⭐ 修复：改用不被弃用的 getRouter().back() API 完成安全页面返回
          .onClick((): void => { this.getUIContext().getRouter().back(); })
          .margin({ right: 16 })
          .height(36)
        Text('报警分析数据研判')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 4, color: '#10000000', offsetY: 2 }) 
      .zIndex(1)

      // 严重程度说明区
      Row() {
        Text('图例说明:')
          .fontSize(12)
          .fontColor('#333333')
          .fontWeight(FontWeight.Bold)
          .margin({ right: 8 })

        this.ColorLegendItem('#FF66FFCC', '0天(安全)')
        this.ColorLegendItem('#FF00E0FF', '1天新增')
        this.ColorLegendItem('#FFFFFFCC', '2天新增')
        this.ColorLegendItem('#FFFF9933', '3天新增')
        this.ColorLegendItem('#FFFC1E1E', '严重(>3天)')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor('#ECEFF1')
      .justifyContent(FlexAlign.SpaceEvenly)

      // 正在刷新/识别时的状态提示条
      if (this.isSearching || this.vm.isUpdating) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color('#1976D2')
          Text(this.vm.isUpdating ? '正在重新申请最新报警并同步矩阵...' : `正在连接并识别端口 ${this.searchingPort} 绑定的设备...`)
            .fontSize(13)
            .fontColor('#1976D2')
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .backgroundColor('#E3F2FD')
        .justifyContent(FlexAlign.Center)
      }

      // 2. 中间核心矩阵数据区
      Column() {
        if (this.vm.headerList.length === 0 || this.vm.rowList.length === 0) {
          Column() {
            Text('📄').fontSize(48).opacity(0.3).margin({ bottom: 16 })
            Text(this.vm.loadStatusText).fontSize(16).fontColor('#888888')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Row() {
                ForEach(this.vm.headerList, (header: string) => {
                  Text(header)
                    .layoutWeight(1)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#006064')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 12, bottom: 12, left: 4, right: 4 })
                })
              }
              .backgroundColor('#B2EBF2')
              .width('100%')
              .border({ width: { bottom: 1 }, color: '#80DEEA' })

              List() {
                ForEach(this.vm.rowList, (rowData: AlarmRowData) => {
                  ListItem() {
                    Row() {
                      ForEach(rowData.items, (item: string) => {
                        Text(item)
                          .layoutWeight(1)
                          .fontSize(12)
                          .fontColor('#333333')
                          .textAlign(TextAlign.Center)
                          .padding({ top: 10, bottom: 10, left: 4, right: 4 })
                      })
                    }
                    .width('100%')
                    .backgroundColor(rowData.bgColor)
                    .onClick(() => this.startSearchAndNavigate(rowData.port))
                  }
                  .border({ width: { bottom: 1 }, color: '#EEEEEE' }) 
                })
              }
              .width('100%')
              .layoutWeight(1) 
            }
            .constraintSize({ minWidth: '100%' })
            .justifyContent(FlexAlign.Start) 
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart) 
        }
      }
      .width('100%')
      .layoutWeight(1) 
      .backgroundColor('#F5F7FA') 
      .padding(8)

      // 3. 底部固定操作与订阅订阅区
      Row() {
        Checkbox({ name: 'subscribe' })
          .select(this.vm.isSubscribed)
          .onChange((value: boolean): void => {
            this.vm.isSubscribed = value;
            this.vm.sendSubscriptionCommand(value);
          })
        Text('订阅报警周报').fontSize(14).fontColor('#333333')
        
        TextInput({ text: this.vm.emailText, placeholder: '请输入接收邮箱' })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#F0F0F0')
          .margin({ left: 16, right: 16 })
          .onChange((v: string): void => { this.vm.emailText = v; })
        
        Button('导出报表', { type: ButtonType.Normal })
          .height(40)
          .borderRadius(6)
          .backgroundColor('#4CAF50') 
          .margin({ right: 10 })
          .onClick((): void => { this.vm.exportAnalysisReport(this.uiContext); })

        Button('申请更新', { type: ButtonType.Normal })
          .height(40)
          .borderRadius(6)
          .backgroundColor('#1976D2')
          .onClick((): void => { this.vm.requestUpdate(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 8, color: '#10000000', offsetY: -2 }) 
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}