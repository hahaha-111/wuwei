// pages/SettingPage.ets
import { router } from '@kit.ArkUI'; 
import { common } from '@kit.AbilityKit';
import { SettingViewModel } from '../viewmodel/SettingViewModel'; // ⭐ 移除了 SettingPageParams
import { detectScreenInfo } from '../common/ScreenTypeHelper';
import { DeviceType } from '../common/ProtocolParser';

@Extend(Text) function navLabel(active: boolean) {
  .fontSize(16)
  .fontColor(active ? '#1976D2' : '#444444')
  .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
}

@Extend(Text) function formLabel(fontSize: number) {
  .fontSize(fontSize)
  .fontColor('#222222')
  .fontWeight(FontWeight.Medium)
  .maxLines(1)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
}

@Extend(TextInput) function formInput(height: number, fontSize: number) {
  .height(height)
  .borderRadius(4)
  .fontSize(fontSize)
  .backgroundColor('#F5F5F5')
  .border({ width: 1, color: '#E0E0E0' })
  .textAlign(TextAlign.Center)
  .padding(0)
}

@Extend(Button) function actionBtn(height: number, fontSize: number) {
  .height(height)
  .fontSize(fontSize)
  .backgroundColor('#E53935')
  .fontColor(Color.White)
  .padding({ left: 4, right: 4 })
  .borderRadius(4)
}

@Entry
@Component
struct SettingPage {
  @State vm: SettingViewModel = new SettingViewModel();

  @State isCompact: boolean = false;

  @State rowHeight: number = 32;
  @State fontSize: number = 14;
  @State smallFontSize: number = 11;
  @State btnFontSize: number = 12;
  @State labelWidth: string = '25%';

  private currentTab: string = 'setting';

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // ⭐ 使用 Record 字典接收路由参数
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    this.vm.init(params, ctx);
    this.adaptScreen();
  }

  private adaptScreen() {
    const info = detectScreenInfo();
    if (info.screenType === 'PHONE' || (info.screenType === 'FOLD' && !info.isLargeScreen)) {
      this.isCompact = true;
      this.rowHeight = 26;
      this.fontSize = 11;
      this.smallFontSize = 9;
      this.btnFontSize = 10;
      this.labelWidth = '28%';
    } else {
      this.isCompact = false;
      this.rowHeight = 32;
      this.fontSize = 14;
      this.smallFontSize = 11;
      this.btnFontSize = 12;
      this.labelWidth = '25%';
    }
  }

  aboutToDisappear() {
    this.vm.onDisappear();
  }

  private goTo(tab: string) {
    if (tab === this.currentTab) {
      return;
    }
    if (tab === 'calibrate' && this.vm.deviceType !== DeviceType.Microwave) {
      try { this.getUIContext().getPromptAction().showToast({ message: '当前设备不支持校准功能' }); } catch (err) {}
      return;
    }

    const finalName = (this.vm.deviceName !== '[读取中...]' && this.vm.deviceName !== '[未配置]')
      ? this.vm.deviceName
      : this.vm.originalDeviceName;

    // ⭐ 使用 Record 字典构建路由参数
    const navParams: Record<string, Object> = {};
    navParams['deviceName'] = finalName;
    navParams['deviceType'] = this.vm.deviceType;
    navParams['connectionMode'] = this.vm.connectionMode;
    navParams['deviceAddress'] = this.vm.currentAddress;

    const uiRouter = this.getUIContext().getRouter();

    if (tab === 'home') {
      uiRouter.replaceUrl({ url: 'pages/MonitorPage', params: navParams }, router.RouterMode.Standard).catch(() => {});
    }
    if (tab === 'calibrate') {
      uiRouter.replaceUrl({ url: 'pages/CalibratePage', params: navParams }, router.RouterMode.Standard).catch(() => {});
    }
    if (tab === 'alarm') {
      uiRouter.replaceUrl({ url: 'pages/AlarmRecordPage', params: navParams }, router.RouterMode.Standard).catch(() => {});
    }
    if (tab === 'log') {
      uiRouter.replaceUrl({ url: 'pages/LogPage', params: navParams }, router.RouterMode.Standard).catch(() => {});
    }
  }

  @Builder topNavBar() {
    Row() {
      Text('主界面').navLabel(false).onClick(() => this.goTo('home'))

      if (this.vm.deviceType === DeviceType.Microwave) {
        Text('校准').navLabel(false).onClick(() => this.goTo('calibrate'))
      }

      Text('报警记录').navLabel(false).onClick(() => this.goTo('alarm'))
      Text('设置').navLabel(true)
      Text('日志').navLabel(false).onClick(() => this.goTo('log'))
    }
    .width('100%')
    .height(this.isCompact ? 40 : 48)
    .backgroundColor('#FAFAFA')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: '#EEEEEE' })
  }

  @Builder leftColumn() {
    Column() {
      Column() {
        Row() {
          Text('设备名称').formLabel(this.fontSize).width(this.labelWidth)
          TextInput({ text: this.vm.deviceName })
            .formInput(this.rowHeight, this.fontSize)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.vm.updateDeviceNameInput(v);
            })
          if (!this.isCompact) {
            Text('').fontSize(11).width('10%')
          }
          Button('修改')
            .actionBtn(this.rowHeight, this.btnFontSize)
            .margin({ left: 2 })
            .onClick(() => {
              this.vm.applyDeviceName();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          Text('传感器时间').formLabel(this.fontSize).width(this.labelWidth)
          TextInput({ text: this.vm.sensorTime })
            .formInput(this.rowHeight, this.fontSize)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.vm.updateSensorTimeInput(v);
            })
          if (!this.isCompact) {
            Text('').fontSize(11).width('10%')
          }
          Button('修改')
            .actionBtn(this.rowHeight, this.btnFontSize)
            .margin({ left: 2 })
            .onClick(() => {
              this.vm.applySensorTime();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          Text('报警持续').formLabel(this.fontSize).width(this.labelWidth)

          TextInput({ text: this.vm.alarmDurationText })
            .formInput(this.rowHeight, this.fontSize)
            .width(this.isCompact ? '18%' : '15%')
            .margin({ right: 2 })
            .onChange((v: string) => {
              this.vm.updateAlarmDurationInput(v);
            })

          Slider({
            value: this.vm.alarmDuration,
            min: 1,
            max: 100,
            step: 1,
            style: SliderStyle.OutSet
          })
            .blockColor('#1976D2')
            .trackColor('#E0E0E0')
            .selectedColor('#1976D2')
            .showSteps(false)
            .showTips(false)
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.Moving || mode === SliderChangeMode.Click) {
                this.vm.setAlarmDurationFromSlider(value);
              }
            })

          Button('修改')
            .actionBtn(this.rowHeight, this.btnFontSize)
            .margin({ left: 2 })
            .onClick(() => {
              this.vm.applyAlarmDuration();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          Text('通道').formLabel(this.fontSize).width(this.labelWidth)

          TextInput({ text: this.vm.channelText })
            .formInput(this.rowHeight, this.fontSize)
            .width(this.isCompact ? '18%' : '15%')
            .margin({ right: 2 })
            .onChange((v: string) => {
              this.vm.updateChannelInput(v);
            })

          Text(this.vm.deviceType === DeviceType.Fiber ? '通道可选范围2-15' : '通道可调范围1-16')
            .fontSize(this.smallFontSize)
            .fontColor('#888')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button('修改')
            .actionBtn(this.rowHeight, this.btnFontSize)
            .margin({ left: 2 })
            .onClick(() => {
              this.vm.applyChannel();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          if (this.vm.deviceType === DeviceType.Fiber) {
            Text('自适应时间').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.fiberAdaptiveTimeText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFiberAdaptiveTimeInput(v); })
            Text('0~255').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '25%' : '20%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFiberAdaptiveTime(); })
          } else {
            Text('报警因子').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.alarmFactorText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateAlarmFactorInput(v); })
            Text('100~65535').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '25%' : '20%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyAlarmFactor(); })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          if (this.vm.deviceType === DeviceType.Fiber) {
            Text('数字增益').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.fiberDigitalGainText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFiberDigitalGainInput(v); })
            Text('0~100').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '25%' : '20%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFiberDigitalGain(); })
          } else {
            Text('锁定识别').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.lockIdText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateLockIdInput(v); })
            Text('20~255').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '25%' : '20%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyLockId(); })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column()
        .width('100%')
        .layoutWeight(1)
    }
    .width('49%')
    .height('100%')
    .padding({ right: this.isCompact ? 4 : 12 })
  }

  @Builder rightColumn() {
    Column() {
      if (this.vm.deviceType === DeviceType.Microwave) {
        Column() {
          Row() {
            Select(this.vm.algoOptions)
              .selected(this.vm.algoSelectionIndex)
              .value(this.vm.algoOptions[this.vm.algoSelectionIndex].value as string)
              .font({ size: this.fontSize })
              .optionFont({ size: this.fontSize })
              .onSelect((index: number) => {
                this.vm.updateAlgoSelection(index);
                this.vm.applyAlgorithmSelection();
              })
              .height(this.rowHeight)
              .layoutWeight(1)
              .backgroundColor('#F5F5F5')
              .borderRadius(4)
              .margin({ right: 4 })

            Select(this.vm.commOptions)
              .selected(this.vm.commModeIndex)
              .value(this.vm.commOptions[this.vm.commModeIndex].value as string)
              .font({ size: this.fontSize })
              .optionFont({ size: this.fontSize })
              .onSelect((index: number) => {
                this.vm.updateCommMode(index);
                this.vm.applyCommMode();
              })
              .height(this.rowHeight)
              .layoutWeight(1)
              .backgroundColor('#F5F5F5')
              .borderRadius(4)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Checkbox({ name: 'algo' })
              .select(this.vm.algorithmEnabled)
              .width(this.isCompact ? 14 : 20)
              .height(this.isCompact ? 14 : 20)
              .onChange((v: boolean) => {
                this.vm.setAlgorithmEnabled(v);
              })
            Text('算法').fontSize(this.fontSize).margin({ right: 4 })
            Button('应用')
              .actionBtn(this.rowHeight, this.btnFontSize)
              .padding({ left: 4, right: 4 })
              .onClick(() => {
                this.vm.applyAlgorithmEnabled();
              })
            Blank().layoutWeight(1)
            Checkbox({ name: 'filter' })
              .select(this.vm.filterEnabled)
              .width(this.isCompact ? 14 : 20)
              .height(this.isCompact ? 14 : 20)
              .onChange((v: boolean) => {
                this.vm.setFilterEnabled(v);
              })
            Text('过滤').fontSize(this.fontSize).margin({ right: 4 })
            Button('应用')
              .actionBtn(this.rowHeight, this.btnFontSize)
              .padding({ left: 4, right: 4 })
              .onClick(() => {
                this.vm.applyFilterEnabled();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }

      if (this.vm.deviceType === DeviceType.Fiber) {
        Column() {
          Row() {
            Text('光纤1增益').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.fiber1GainText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFiberGainInput(1, v); })
            Text('0~2').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFiberGain(1); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Text('光纤2增益').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.fiber2GainText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFiberGainInput(2, v); })
            Text('0~2').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFiberGain(2); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Text('光纤3增益').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.fiber3GainText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFiberGainInput(3, v); })
            Text('0~2').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFiberGain(3); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Text('光纤4增益').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.fiber4GainText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFiberGainInput(4, v); })
            Text('0~2').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFiberGain(4); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

      } else {

        Column() {
          Row() {
            Text('阈值计算').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.thresholdText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateThresholdInput(v); })
            Text('1~255').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyThreshold(); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Text('因子计算').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.factorValueText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFactorValueInput(v); })
            Text('1~65535').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFactorValue(); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Text('算法时间m').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.algorithmTimeText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateAlgorithmTimeInput(v); })
            Text('1~255').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyAlgorithmTime(); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        Column() {
          Row() {
            Text('过滤时间s').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.filterTimeText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => { this.vm.updateFilterTimeInput(v); })
            Text('1~255').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改').actionBtn(this.rowHeight, this.btnFontSize).margin({ left: 2 }).onClick(() => { this.vm.applyFilterTime(); })
          }.width('100%').alignItems(VerticalAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

      }

      if (this.vm.deviceType === DeviceType.Microwave) {
        Column() {
          Row() {
            Text('心跳间隔').formLabel(this.fontSize).width(this.labelWidth)
            TextInput({ text: this.vm.heartbeatIntervalText })
              .formInput(this.rowHeight, this.fontSize)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.vm.updateHeartbeatInput(v);
              })
            Text('秒').fontSize(this.smallFontSize).fontColor('#888').width(this.isCompact ? '20%' : '15%').textAlign(TextAlign.Center)
            Button('修改')
              .actionBtn(this.rowHeight, this.btnFontSize)
              .margin({ left: 2 })
              .onClick(() => {
                this.vm.applyHeartbeat();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column().layoutWeight(1)
        Column().layoutWeight(1)
      }

      Column() {
        Row() {
          Text(this.vm.tipText)
            .fontSize(this.fontSize)
            .fontColor(Color.Blue)
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('49%')
    .height('100%')
    .padding({ left: this.isCompact ? 4 : 12 })
    .border({ width: { left: 1 }, color: '#EEEEEE' })
  }

  build() {
    Column() {
      this.topNavBar()

      Row() {
        Text(`版本:${this.vm.deviceVersion}`)
          .fontSize(this.isCompact ? 11 : 13)
          .fontColor('#666666')

        Blank()

        Row() {
          Button('从设备读取')
            .height(this.isCompact ? 28 : 32)
            .fontSize(this.isCompact ? 11 : 13)
            .backgroundColor('#4CAF50')
            .onClick(() => {
              this.vm.readAllFromDevice();
            })
          Blank().width(this.isCompact ? 4 : 12)
          Button('刷新界面')
            .height(this.isCompact ? 28 : 32)
            .fontSize(this.isCompact ? 11 : 13)
            .backgroundColor('#9E9E9E')
            .onClick(() => {
              this.vm.refreshLocal();
            })
          Blank().width(this.isCompact ? 4 : 12)
          Button('保存全部设置')
            .height(this.isCompact ? 28 : 32)
            .fontSize(this.isCompact ? 11 : 13)
            .backgroundColor('#2196F3')
            .onClick(() => {
              this.vm.applyAllToDevice();
            })
          Blank().width(this.isCompact ? 4 : 12)
          Button('滤波设置')
            .height(this.isCompact ? 28 : 32)
            .fontSize(this.isCompact ? 11 : 13)
            .backgroundColor('#FF9800')
            .onClick(() => {
              // ⭐ 使用 Record 字典构建路由参数
              const navParams: Record<string, Object> = {};
              navParams['deviceName'] = this.vm.deviceName;
              navParams['deviceType'] = this.vm.deviceType;
              navParams['connectionMode'] = this.vm.connectionMode;
              navParams['deviceAddress'] = this.vm.currentAddress;
              
              this.getUIContext().getRouter().pushUrl({ url: 'pages/FilterSettingPage', params: navParams }, router.RouterMode.Standard).catch(() => {});
            })
        }

        Blank()

        Text(`通信:${this.vm.connectionTypeDisplay}`)
          .fontSize(this.isCompact ? 11 : 13)
          .fontColor('#1976D2')
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(this.isCompact ? 4 : 8)
      .alignItems(VerticalAlign.Center)

      Row() {
        this.leftColumn()
        this.rightColumn()
      }
      .width('100%')
      .layoutWeight(1)
      .padding(this.isCompact ? 4 : 12)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ left: this.isCompact ? 4 : 8, right: this.isCompact ? 4 : 8, bottom: this.isCompact ? 4 : 8 })
      .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DDDDDD')
  }
}