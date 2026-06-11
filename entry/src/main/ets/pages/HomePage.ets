import { common } from '@kit.AbilityKit';
import { HomePageBleViewModel, DeviceInfoView } from '../viewmodel/HomePageBleViewModel';
import { UpdateLogPopup } from '../common/UpdateLogComponent';

@Extend(Text)
function mainTitleText(size: number) {
  .fontWeight(FontWeight.Bold)
  .fontColor(Color.Red)
  .fontSize(size)
}

@Extend(Text)
function subTitleText() {
  .fontSize(15)
  .fontColor(Color.Red)
}

@Extend(Text)
function modeLabelText() {
  .fontSize(14)
}

@Extend(Text)
function tableHeaderText() {
  .fontSize(13)
  .fontWeight(FontWeight.Medium)
}

@Extend(Text)
function footerText() {
  .fontSize(11)
  .fontColor('#666666')
}

const DEVICE_TYPE_OPTIONS = [
  '微波接收',
  '微波发射',
  '移动微波',
  '张力围栏',
  '光纤栅栏',
  '激光探测'
];

@Entry
@Component
struct HomePage {
  @State vm: HomePageBleViewModel = new HomePageBleViewModel();
  @State showUpdateLog: boolean = false; 

  @State showAddDeviceDialog: boolean = false;
  @State newDeviceName: string = '';
  @State newDeviceIp: string = '';
  @State newDevicePort: string = '8080';
  @State selectedDeviceTypeIndex: number = 0;

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.uiContext = this.getUIContext(); 
    this.vm.onAppear(ctx);
  }

  onPageShow() {
    this.vm.onPageShow();
  }

  aboutToDisappear() {
    this.vm.onDisappear();
  }

  private isPhone(): boolean { return this.vm.screenType === 'PHONE'; }
  private isFold(): boolean { return this.vm.screenType === 'FOLD'; }
  private isLargeScreen(): boolean { return this.vm.isLargeScreen; }

  private getVersionDisplay(): string {
    return this.vm.versionName || '1.0.0';
  }

  private getPanelTopMargin(): number {
    if (this.isPhone() || (this.isFold() && !this.isLargeScreen())) {
      let offset = 0;
      if (this.vm.tcpMode || this.vm.staMode) {
        offset -= 40;
      }
      if ((this.vm.tcpMode || this.vm.staMode) && this.vm.isFilterBarVisible) {
        offset -= 40;
      }
      return offset;
    }
    return 0;
  }

  private safeShowToast(msg: string) {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {}
  }

  @Builder
  authDialog() {
    Column() {
      Text($r('app.string.auth_dialog_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })

      Row() {
        Text() {
          Span($r('app.string.auth_machine_code_label'));
          Span(this.vm.machineCode)
        }
        .fontSize(14)
        .layoutWeight(1)

        Button($r('app.string.auth_copy'))
          .height(30)
          .fontSize(12)
          .backgroundColor('#E53935')
          .onClick(() => this.vm.copyMachineCode())
      }
      .margin({ bottom: 8 })

      Row() {
        TextInput({
          text: this.vm.registerCode,
          placeholder: $r('app.string.auth_register_placeholder')
        })
          .layoutWeight(1)
          .height(40)
          .onChange((v) => this.vm.registerCode = v)

        Blank().width(8)

        PasteButton().onClick((_e, res) => {
          if (res === 0) this.vm.pasteRegisterCode();
        })
      }
      .margin({ bottom: 16 })

      Row() {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor('#CCCCCC')
          .onClick(() => this.vm.cancelLicenseDialog())

        Button($r('app.string.common_confirm'))
          .layoutWeight(1)
          .backgroundColor('#E53935')
          .margin({ left: 12 })
          .onClick(() => this.vm.confirmLicenseFromDialog())
      }
    }
    .width('90%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 20, color: '#40000000', offsetY: 10 })
    .onClick(() => {})
  }

  @Builder
  addDeviceDialog() {
    Column() {
      Text('添加本地设备')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })

      Row() {
        Text('设备类型').fontSize(14).width(70)
        Select(DEVICE_TYPE_OPTIONS.map(v => ({ value: v } as SelectOption)))
          .selected(this.selectedDeviceTypeIndex)
          .value(DEVICE_TYPE_OPTIONS[this.selectedDeviceTypeIndex])
          .onSelect((index: number) => {
            this.selectedDeviceTypeIndex = index;
          })
          .height(36)
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .borderRadius(4)
      }.margin({ bottom: 10 })

      Row() {
        Text('备注名称').fontSize(14).width(70)
        TextInput({ text: this.newDeviceName, placeholder: '选填' })
          .height(36)
          .layoutWeight(1)
          .onChange((v) => this.newDeviceName = v)
      }.margin({ bottom: 10 })

      Row() {
        Text('IP 地址').fontSize(14).width(70)
        TextInput({ text: this.newDeviceIp, placeholder: '例如 192.168.1.100' })
          .height(36)
          .layoutWeight(1)
          .onChange((v) => this.newDeviceIp = v)
      }.margin({ bottom: 10 })

      Row() {
        Text('端口号').fontSize(14).width(70)
        TextInput({ text: this.newDevicePort, placeholder: '例如 8080' })
          .height(36)
          .type(InputType.Number)
          .layoutWeight(1)
          .onChange((v) => this.newDevicePort = v)
      }.margin({ bottom: 16 })

      Row() {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#CCCCCC')
          .onClick(() => { this.showAddDeviceDialog = false; })

        Button('添加')
          .layoutWeight(1)
          .backgroundColor('#E53935')
          .margin({ left: 12 })
          .onClick(() => {
            if (!this.newDeviceIp || !this.newDevicePort) {
              this.safeShowToast('IP地址和端口号不能为空'); 
              return;
            }

            const ipRegex = /^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$/;
            if (!ipRegex.test(this.newDeviceIp)) {
              this.safeShowToast('请输入有效的 IP 地址 (如 192.168.1.100)');
              return;
            }

            const port = parseInt(this.newDevicePort);
            if (isNaN(port) || port < 1 || port > 65535) {
              this.safeShowToast('端口号必须在 1 - 65535 之间');
              return;
            }

            const type = DEVICE_TYPE_OPTIONS[this.selectedDeviceTypeIndex];
            this.vm.addLocalDevice(this.newDeviceName, this.newDeviceIp, this.newDevicePort, type);
            this.showAddDeviceDialog = false;
            this.newDeviceName = '';
            this.newDeviceIp = '';
          })
      }
    }
    .width('90%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 20, color: '#40000000', offsetY: 10 })
    .onClick(() => {})
  }

  private getRssiColor(rssi: number): string {
    if (rssi >= -60) return '#4CAF50'; 
    if (rssi >= -80) return '#FF9800'; 
    return '#F44336'; 
  }

  @Builder
  searchPanelContent() {
    Column() {
      Row() {
        if (this.vm.tcpMode) {
          Button('＋ 添加设备')
            .width(this.isPhone() ? '50%' : '40%')
            .height(36)
            .fontSize(14)
            .backgroundColor('#2196F3') 
            .fontColor(Color.White)
            .onClick(() => { this.showAddDeviceDialog = true; })
        } else {
          Button(this.vm.isSearching ? $r('app.string.btn_stop_search') : $r('app.string.btn_search_device'))
            .width(this.isPhone() ? '50%' : '40%')
            .height(36)
            .fontSize(14)
            .backgroundColor(this.vm.isSearching ? '#DD4444' : '#E53935')
            .fontColor(Color.White)
            .onClick(() => this.vm.onSearchButtonClick())
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: this.isPhone() ? 4 : 8 })

      Row() {
        Checkbox({ name: 'staMode' })
          .select(this.vm.staMode)
          .onChange((v) => this.vm.onStaModeChange(v))
        Text($r('app.string.label_sta_mode')).modeLabelText().fontSize(12).margin({ right: 8 })

        Checkbox({ name: 'tcpMode' }) 
          .select(this.vm.tcpMode)
          .onChange((v) => this.vm.onTcpModeChange(v))
        Text($r('app.string.label_tcp_mode')).modeLabelText().fontSize(12)
      }
      .margin({ top: this.isPhone() ? 4 : 8 })

      if (this.vm.tcpMode || this.vm.staMode) {
        Row() {
          Button("📋 列表筛选")
            .type(ButtonType.Normal)
            .backgroundColor('#F0F0F0')
            .fontColor('#333333')
            .fontSize(12)
            .borderRadius(4)
            .height(32)
            .layoutWeight(1)
            .margin({ right: 8 })
            .onClick(() => this.vm.toggleFilterBar())

          Button("📊 报警分析")
            .type(ButtonType.Normal)
            .backgroundColor('#F0F0F0')
            .fontColor('#333333')
            .fontSize(12)
            .borderRadius(4)
            .height(32)
            .layoutWeight(1)
            .onClick(() => this.vm.onAlarmAnalysisClick())
        }
        .width('100%')
        .margin({ top: 8 })
        .alignSelf(this.isPhone() ? ItemAlign.Center : ItemAlign.Start)
      }

      if ((this.vm.tcpMode || this.vm.staMode) && this.vm.isFilterBarVisible) {
        Row() {
          TextInput({ text: this.vm.filterText, placeholder: '请输入关键字过滤...' })
            .height(34)
            .fontSize(13)
            .placeholderFont({ size: 11 })
            .backgroundColor(Color.White)
            .border({ width: 1, color: '#E0E0E0', radius: 4 })
            .layoutWeight(1)
            .padding({ left: 8, right: 8 })
            .onChange((value: string) => this.vm.setFilterText(value))
        }
        .width('100%')
        .margin({ top: 6 })
        .alignSelf(this.isPhone() ? ItemAlign.Center : ItemAlign.Start)
      }

      Row() {
        Text($r('app.string.label_connect_state')).modeLabelText().fontSize(12).margin({ right: 4 })
        Text(this.vm.connectStateText).modeLabelText().fontSize(12)
      }
      .margin({ top: this.isPhone() ? 6 : 8 })

      if (this.vm.searchTip && this.vm.searchTip.length > 0) {
        Text(this.vm.searchTip)
          .fontSize(12)
          .fontColor('#1976D2') 
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (!this.vm.staMode && !this.vm.tcpMode) {
        Column() {
          Row() {
            Text($r('app.string.label_search_progress')).fontSize(12)
            Blank()
            Text(this.vm.searchProgress.toFixed(0) + '%').fontSize(12)
          }
          Slider({
            value: this.vm.searchProgress,
            min: 0,
            max: 100,
            style: SliderStyle.OutSet
          }).enabled(false)
        }
        .margin({ top: this.isPhone() ? 4 : 8 })
        .width('100%')
        .alignSelf(ItemAlign.Center)
      }

      Row() {
        Text($r('app.string.table_header_name')).layoutWeight(1).tableHeaderText().fontSize(12)
        Text($r('app.string.table_header_address')).layoutWeight(2).tableHeaderText().fontSize(12)
        Text($r('app.string.table_header_status')).layoutWeight(1).tableHeaderText().fontSize(12)
        Text($r('app.string.table_header_signal')).layoutWeight(1).tableHeaderText().fontSize(12)
        if (this.vm.tcpMode) {
          Text('操作').width(40).tableHeaderText().fontSize(12)
        }
      }
      .margin({ top: this.isPhone() ? 8 : 12, bottom: this.isPhone() ? 2 : 4 })
      .width('100%')
      .alignSelf(this.isPhone() ? ItemAlign.Center : ItemAlign.Start)

      List() {
        if (this.vm.deviceList.length === 0) {
          ListItem() {
            Text(this.vm.isSearching ? $r('app.string.list_empty_searching') : $r('app.string.list_empty_no_device'))
              .fontSize(12)
              .fontColor('#666666')
              .padding({ top: 10, bottom: 10 })
          }
        } else {
          ForEach(this.vm.deviceList, (item: DeviceInfoView) => {
            ListItem() {
              Row() {
                Row() {
                  Text(item.name).layoutWeight(1).fontSize(12)
                  Text(item.address).layoutWeight(2).fontSize(11).fontColor('#666666')
                  Text(item.status)
                    .layoutWeight(1)
                    .fontSize(12)
                    .fontColor(
                      item.status === '已连接'
                        ? '#4CAF50'
                        : (item.status === '在线' ? '#2196F3' : '#333333')
                    )
                  Text(item.rssi === -1 ? '-' : item.rssi.toString())
                    .layoutWeight(1)
                    .fontSize(12)
                    .fontColor(this.getRssiColor(item.rssi))
                    .fontWeight(FontWeight.Medium)
                }
                .layoutWeight(1)
                .onClick(() => this.vm.onSelectDevice(item))

                if (this.vm.tcpMode) {
                  Text('🗑️')
                    .width(40)
                    .fontSize(16)
                    .textAlign(TextAlign.Center)
                    .onClick(() => {
                      this.vm.deleteLocalDevice(item.id);
                    })
                }
              }
              .padding({ top: 8, bottom: 8 })
            }
          }, (item: DeviceInfoView) => item.id)
        }
      }
      .width('100%')
      .height('100%') // ⭐ 修复警告：补全了 List 缺失的宽高属性
      .alignSelf(this.isPhone() ? ItemAlign.Center : ItemAlign.Start)
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: '#DDDDDD' })
    }
    .width(this.isPhone() ? '70%' : '100%')
    .margin({ top: this.getPanelTopMargin() })
    .padding(12)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  infoPanel() {
    Column() {
      Image($r('app.media.main_qj'))
        .width('100%')
        .height(this.isPhone() ? '65%' : '55%')
        .objectFit(ImageFit.Contain)
        .borderRadius(12)

      Text($r('app.string.home_intro_line'))
        .fontSize(12)
        .fontColor('#444444')
        .margin({ top: 8 })

      if (this.isPhone()) {
        Blank().layoutWeight(1)
      }

      Column() {
        Text($r('app.string.home_company_address')).footerText().fontSize(11)
        Text($r('app.string.home_company_phone')).footerText().fontSize(11)
        Text($r('app.string.home_company_website')).footerText().fontSize(11)
      }
      .padding({ top: 12, bottom: this.isPhone() ? 10 : 0 })
      .layoutWeight(this.isPhone() ? undefined : 1)
    }
    .padding(8)
    .height('100%')
  }

  @Builder
  topButtonsRow() {
    Row() {
      Button($r('app.string.btn_serial_assistant'))
        .fontSize(12)
        .backgroundColor('#E53935')
        .fontColor(Color.White)
        .margin({ left: 10, right: 8 })
        .height(32)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/Index' }).catch(() => {});
        })

      Button($r('app.string.btn_monitor_test'))
        .fontSize(12)
        .backgroundColor('#CCCCCC')
        .fontColor('#333333')
        .height(32)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/MonitorPage' }).catch(() => {});
        })
    }
    .margin(this.isPhone() ? { top: -10, bottom: 8 } : { top: 0, bottom: 8 })
  }

  build() {
    Stack({ alignContent: this.isPhone() ? Alignment.Top : Alignment.Center }) {

      Column() {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.home_title_main'))
              .mainTitleText(this.isLargeScreen() ? 26 : 22)
            Text($r('app.string.home_title_sub'))
              .subTitleText()
          }

          Row() {
            Text($r('app.string.home_version_text', this.getVersionDisplay()))
              .fontSize(14)
              .fontColor('#666666')
              .margin({ right: 12 })

            Text($r('app.string.home_lang_label'))
              .fontSize(14)
              .fontColor('#333333')
              .margin({ right: 8 })

            Select(this.vm.languageOptions)
              .selected(this.vm.currentLanguageIndex)
              .value(this.vm.languageOptions[this.vm.currentLanguageIndex].value as string)
              .font({ size: 14 })
              .selectedOptionFont({ size: 14 })
              .optionFont({ size: 14 })
              .onSelect((index: number) => {
                this.vm.switchLanguageByIndex(index);
              })
              .height(32)
              .width(120)
              .backgroundColor(Color.White)
              .borderRadius(8)
          }
          .margin({ left: 16, right: 16 })

          Row() {
            Column() {
              Text('📄').fontSize(22)
              Text('更新日志').fontSize(10).fontColor('#666666').margin({ top: 2 })
            }
            .onClick(() => { this.showUpdateLog = true; })
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 16 })

            Image($r('app.media.icon_foreground'))
              .width(40)
              .height(40)
              .objectFit(ImageFit.Contain)
          }
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 20, right: 20, top: 10, bottom: 4 })
        .width('100%')

        this.topButtonsRow()

        Row() {
          Column() { this.infoPanel() }
          .layoutWeight(this.isPhone() ? 1.2 : 1.5)
          .padding(4)

          Column() { this.searchPanelContent() }
          .layoutWeight(1.8)
          .padding({ left: 4 })
          .alignItems(this.isPhone() ? HorizontalAlign.End : HorizontalAlign.Start)
        }
        .padding(8)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')

      if (this.vm.showAuthDialog) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .onClick(() => { this.vm.showAuthDialog = false; })
          .zIndex(2000)
          .position({ x: 0, y: 0 })

        Column() {
          this.authDialog()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .zIndex(2001)
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })
      }

      if (this.showAddDeviceDialog) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .onClick(() => { this.showAddDeviceDialog = false; })
          .zIndex(2000)
          .position({ x: 0, y: 0 })

        Column() {
          this.addDeviceDialog()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .zIndex(2001)
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })
      }

      if (this.showUpdateLog) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .onClick(() => { this.showUpdateLog = false; })
          .zIndex(999)
          .position({ x: 0, y: 0 })

        Column() {
          UpdateLogPopup({
            isPhone: this.isPhone(),
            onClose: () => { this.showUpdateLog = false; }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .zIndex(1000)
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })
      }
    }
  }
}