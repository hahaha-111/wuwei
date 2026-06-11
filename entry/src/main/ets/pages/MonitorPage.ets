import { SignalBoard } from '../common/SignalBoard';
import { MonitorViewModel } from '../viewmodel/MonitorViewModel';
import { common } from '@kit.AbilityKit';

@Extend(Text) function navText() { .fontSize(16).fontColor('#444444') }
@Extend(Text) function navTextActive() { .fontSize(16).fontColor('#1976D2').fontWeight(FontWeight.Bold) }
@Extend(Text) function smallLabel() { .fontSize(14).fontColor('#333333') }
@Extend(Text) function sectionTitle() { .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#222222') }

@Component
struct ParamListPanel {
  @ObjectLink vm: MonitorViewModel;
  @Prop listHeight: number;

  build() {
    Column() {
      Row() { Text('序号').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1); Text('名称').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(2); Text('数值').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(2) }.padding(4).backgroundColor('#F0F0F0')
      Column() {
        Row() { Text('1').fontSize(15).layoutWeight(1); Text('名称').fontSize(15).layoutWeight(2); Text(this.vm.deviceNameStr).fontSize(15).layoutWeight(2) }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
        Row() { Text('2').fontSize(15).layoutWeight(1); Text('阈值').fontSize(15).layoutWeight(2); Text(this.vm.deviceThresholdStr).fontSize(15).layoutWeight(2) }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
        Row() { Text('3').fontSize(15).layoutWeight(1); Text('通道').fontSize(15).layoutWeight(2); Text(this.vm.deviceChannelStr).fontSize(15).layoutWeight(2) }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
        Row() { Text('4').fontSize(15).layoutWeight(1); Text('时间').fontSize(15).layoutWeight(2); Text(this.vm.deviceTimeStr).fontSize(15).layoutWeight(2) }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
      }.width('100%').height(this.listHeight)
    }.margin({ left: 8, right: 16, top: 4 })
  }
}

@Component
struct TxParamPanel {
  @ObjectLink vm: MonitorViewModel;

  build() {
    Column() {
      Row() { Text('参数').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1); Text('数值').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(2) }.padding(4).backgroundColor('#F0F0F0')
      Column() {
        Row() { Text('名称').fontSize(15).layoutWeight(1); Text(this.vm.deviceNameStr).fontSize(15).layoutWeight(2) }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
        Row() { Text('MCU电压').fontSize(15).layoutWeight(1); Text(`${this.vm.txMcuVol}V`).fontSize(15).layoutWeight(2).fontColor('#00BCD4') }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
        Row() { Text('高频电压').fontSize(15).layoutWeight(1); Text(`${this.vm.txHighFreqVol}V`).fontSize(15).layoutWeight(2).fontColor('#FF9800') }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
        Row() { Text('输入电压').fontSize(15).layoutWeight(1); Text(`${this.vm.txInputVol}V`).fontSize(15).layoutWeight(2).fontColor('#9C27B0') }.padding(6).border({ width: { bottom: 0.5 }, color: '#DDDDDD' })
      }.width('100%')
    }.margin({ left: 8, right: 16, top: 4 })
  }
}

@Component
struct FiberDataPanel {
  @ObjectLink vm: MonitorViewModel;

  build() {
    Column() {
      Row() { Text('光纤').layoutWeight(1).textAlign(TextAlign.Center).fontColor('#1976D2'); Text('信号').layoutWeight(1).textAlign(TextAlign.Center).fontColor('#1976D2'); Text('灵敏度').layoutWeight(1).textAlign(TextAlign.Center).fontColor('#1976D2') }
      .border({ width: 1, color: '#CCCCCC' }).padding(4).margin({ top: 4 })

      Column() {
        Row() { Text('光纤1').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber1Signal.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber1Sens.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
        Row() { Text('光纤2').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber2Signal.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber2Sens.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
        Row() { Text('光纤3').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber3Signal.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber3Sens.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
        Row() { Text('光纤4').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber4Signal.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.fiber4Sens.toString()).layoutWeight(1).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
      }.border({ width: 1, color: '#CCCCCC' }).margin({ bottom: 8 })

      Row() { Text('参数').layoutWeight(1).textAlign(TextAlign.Center).fontColor('#1976D2'); Text('数值').layoutWeight(2).textAlign(TextAlign.Center).fontColor('#1976D2') }
      .border({ width: 1, color: '#CCCCCC' }).padding(4)

      Column() {
        Row() { Text('名称').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.deviceNameStr).layoutWeight(2).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
        Row() { Text('通道').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.deviceChannelStr).layoutWeight(2).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
        Row() { Text('时间').layoutWeight(1).textAlign(TextAlign.Center).fontSize(14); Text(this.vm.deviceTimeStr).layoutWeight(2).textAlign(TextAlign.Center).fontSize(14) }.width('100%').padding(4).border({ width: { bottom: 1 }, color: '#EEEEEE' })
      }.border({ width: 1, color: '#CCCCCC' })
    }
  }
}

@Entry
@Component
struct MonitorPage {
  @State vm: MonitorViewModel = new MonitorViewModel();

  @State isAlarmUi: boolean = false;
  @State isTamperUi: boolean = false;

  @State fiberAlarm1Ui: boolean = false;
  @State fiberAlarm2Ui: boolean = false;
  @State fiberAlarm3Ui: boolean = false;
  @State fiberAlarm4Ui: boolean = false;

  @State recordOpacity: number = 1.0;

  aboutToAppear() {
    try {
      this.vm.uiContext = this.getUIContext();

      // ⭐ 核心修复：彻底解决 arkts-no-structural-typing 导致参数丢失的问题
      const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;

      this.vm.setOnStatusChange((alarm: boolean, tamper: boolean) => {
        this.isAlarmUi = alarm;
        this.isTamperUi = tamper;
      });

      this.vm.setOnFiberAlarmChange((a1: boolean, a2: boolean, a3: boolean, a4: boolean) => {
        this.fiberAlarm1Ui = a1;
        this.fiberAlarm2Ui = a2;
        this.fiberAlarm3Ui = a3;
        this.fiberAlarm4Ui = a4;
      });

      this.vm.init(params, ctx);

      setInterval(() => {
        if (this.vm.isRecording) {
          this.recordOpacity = this.recordOpacity === 1.0 ? 0.3 : 1.0;
        } else {
          this.recordOpacity = 1.0;
        }
      }, 800);

    } catch (e) {
      console.error('MonitorPage aboutToAppear error: ' + JSON.stringify(e));
    }
  }

  onPageShow() { this.vm.onPageShow(); }
  onPageHide() { this.vm.onPageHide(); }
  aboutToDisappear() { this.vm.destroy(); }

  private isPhone(): boolean { return this.vm.screenType === 'PHONE'; }
  private isTablet(): boolean { return this.vm.screenType === 'TABLET'; }
  private isFold(): boolean { return this.vm.screenType === 'FOLD'; }
  private isLargeScreen(): boolean { return this.vm.isLargeScreen; }

  private navHeight(): number { return this.isTablet() ? 72 : (this.isFold() ? 60 : 36); }
  private sliderWidth(): number { return this.isTablet() ? 160 : 50; }
  private waveTitleTopPadding(): number { return this.isPhone() ? 1 : 2; }
  private listHeight(): number { return this.isTablet() ? 230 : (this.isFold() ? 240 : 140); }
  private btnHeight(): number { return this.isPhone() ? 26 : 32; }
  private btnFontSize(): number { return this.isPhone() ? 11 : 13; }
  private bottomRowHeight(): number { return this.isPhone() ? 38 : 50; }

  @Builder navItem(title: string, index: number) {
    if (index === this.vm.currentTab) { Text(title).navTextActive(); }
    else { Text(title).navText().onClick(() => { this.vm.onNavClick(index); }); }
  }

  @Builder navBar() {
    Row() {
      this.navItem('主界面', 0);
      if (this.vm.deviceMode === 'RX') {
        this.navItem('校准', 1);
      }
      this.navItem('报警记录', 2);
      this.navItem('设置', 3);
      this.navItem('日志', 4);
    }
    .width('100%').height(this.navHeight()).padding(0).backgroundColor('#F5F5F5').justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder listenDialog() {
    Column() {
      Row() { Blank().layoutWeight(1); Text('X').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E53935').onClick(() => this.vm.closeListenDialog()) }.padding({ bottom: 4 })
      Text('测试设定').fontSize(16).fontWeight(FontWeight.Medium).margin({ bottom: 12 })
      Row() { Text('监听时间(分)').smallLabel(); Blank(); TextInput({ text: this.vm.listenTime.toString() }).width(80).height(32).borderRadius(4).border({ width: 1, color: '#CCCCCC' }).onChange(value => this.vm.updateListenTime(value)) }.padding({ bottom: 8 })
      Row() { Text('监听方差').smallLabel(); Blank(); TextInput({ text: this.vm.listenVariance.toString() }).width(80).height(32).borderRadius(4).border({ width: 1, color: '#CCCCCC' }).onChange(value => this.vm.updateListenVariance(value)) }.padding({ bottom: 8 })
      Row() { Checkbox({ name: 'listenEnable', group: 'listenGroup' }).select(this.vm.listenEnable).onChange(v => this.vm.setListenEnable(v)).margin({ right: 8 }); Text('监听启用').smallLabel() }.padding({ bottom: 12 })
      Row() { Blank(); Button('保存').borderRadius(18).height(34).fontSize(14).backgroundColor('#1976D2').fontColor(Color.White).onClick(() => this.vm.saveListenSettings()) }
    }.width(320).padding(20).backgroundColor('#FFFFFF').borderRadius(8).shadow({ radius: 8, color: '#33000000', offsetY: 2 })
  }

  @Builder statusRow() {
    Column() {
      Row() {
        if (this.vm.deviceMode === 'FIBER') {
          Row() {
            Circle({ width: 16, height: 16 }).fill(this.fiberAlarm1Ui ? '#FF3B30' : '#4CAF50').margin({ right: 6 })
            Text('光纤1').fontSize(15).fontColor('#333333')
          }.margin({ right: 16 })

          Row() {
            Circle({ width: 16, height: 16 }).fill(this.fiberAlarm2Ui ? '#FF3B30' : '#4CAF50').margin({ right: 6 })
            Text('光纤2').fontSize(15).fontColor('#333333')
          }.margin({ right: 16 })

          Row() {
            Circle({ width: 16, height: 16 }).fill(this.fiberAlarm3Ui ? '#FF3B30' : '#4CAF50').margin({ right: 6 })
            Text('光纤3').fontSize(15).fontColor('#333333')
          }.margin({ right: 16 })

          Row() {
            Circle({ width: 16, height: 16 }).fill(this.fiberAlarm4Ui ? '#FF3B30' : '#4CAF50').margin({ right: 6 })
            Text('光纤4').fontSize(15).fontColor('#333333')
          }.margin({ right: 16 })

          Row() {
            Text('TX').smallLabel().margin({ right: 4 })
            Circle({ width: 12, height: 12 }).fill(this.vm.txOn ? '#4CAF50' : '#CCCCCC').margin({ right: 16 })
            Text('RX').smallLabel().margin({ right: 4 })
            Circle({ width: 12, height: 12 }).fill(this.vm.rxOn ? '#4CAF50' : '#CCCCCC')
          }

          Blank().layoutWeight(1)

          Row() {
            Checkbox({ name: 'autoD', group: 'autoGroup' }).select(this.vm.autoDownload).onChange(v => this.vm.setAutoDownload(v))
            Text('自动下载报警图').smallLabel()
          }
        } else if (this.vm.deviceMode === 'TX') {
          Text(`温度: ${this.vm.txTemp}℃`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#E53935').margin({right: 12})
          Text(`湿度: ${this.vm.txHum}%`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#1976D2').margin({right: 12})
          Text(`MCU: ${this.vm.txMcuVol}V`).fontSize(13).fontColor('#00BCD4').margin({right: 8})
          Text(`高频: ${this.vm.txHighFreqVol}V`).fontSize(13).fontColor('#FF9800').margin({right: 8})
          Text(`输入: ${this.vm.txInputVol}V`).fontSize(13).fontColor('#9C27B0')
        } else {
          Row() {
            Circle({ width: 24, height: 24 }).fill(this.isAlarmUi ? '#FF3B30' : '#4CAF50').margin({ right: 6 })
            Text('报警').smallLabel()
          }.margin({ right: 24 })

          Row() {
            Circle({ width: 24, height: 24 }).fill(this.isTamperUi ? '#FF3B30' : '#4CAF50').margin({ right: 6 })
            Text('防拆').smallLabel()
          }.margin({ right: 40 })

          Row() {
            Text('TX').smallLabel().margin({ right: 4 })
            Row() { Circle({ width: 12, height: 12 }).fill(this.vm.txOn ? '#4CAF50' : '#CCCCCC') }.margin({ right: 16 })
            Text('RX').smallLabel().margin({ right: 4 })
            Row() { Circle({ width: 12, height: 12 }).fill(this.vm.rxOn ? '#4CAF50' : '#CCCCCC') }
          }

          Blank().layoutWeight(1)

          if (this.vm.listenEnable) {
            Row() { Text(this.vm.listenStatusText).fontSize(12).fontColor('#1976D2').fontWeight(FontWeight.Bold).margin({ right: 12 }) }
          }

          Row() {
            Text('自动下载报警图').smallLabel().margin({ right: 8 })
            Checkbox({ name: 'autoDownload', group: 'autoGroup' }).select(this.vm.autoDownload).onChange((v) => this.vm.setAutoDownload(v))
          }
        }
      }
      .width('100%').padding({ left: 16, right: 16, top: 0, bottom: 4 })
    }
    .margin({ top: this.isTablet() ? 18 : (this.isFold() ? 8 : 2) })
  }

  @Builder wavePanel() {
    Column() {
      Row() {
        if (this.vm.isPlaybackMode) {
          Text('正在回放...').fontSize(14).fontColor('#E53935').margin({ right: 12 })
        } else {
          Text(this.vm.currentTimeStr).fontSize(13).fontColor('#666666').margin({ right: 12 })
        }
        Text('监控波形').sectionTitle()
        Blank()
        Text(`平均: ${this.vm.avgValue.toFixed(2)}`).fontSize(13).fontColor('#1565C0').margin({ right: 12 })
        Text(`方差: ${this.vm.variance.toFixed(2)}`).fontSize(13).fontColor('#1565C0')
      }.padding({ left: 12, right: 12, top: this.waveTitleTopPadding(), bottom: 4 })

      if (this.vm.deviceMode === 'FIBER') {
        Row() {
          Button('全览').height(28).layoutWeight(1).margin({ right: 2, left: 2 }).fontSize(13)
            .backgroundColor(this.vm.fiberChannelMode === 'ALL' ? '#1976D2' : '#F5F5F5')
            .fontColor(this.vm.fiberChannelMode === 'ALL' ? Color.White : '#666666')
            .onClick(() => { this.vm.fiberChannelMode = 'ALL'; })
          Button('通道1').height(28).layoutWeight(1).margin({ right: 2, left: 2 }).fontSize(13)
            .backgroundColor(this.vm.fiberChannelMode === 'CH1' ? '#1976D2' : '#F5F5F5')
            .fontColor(this.vm.fiberChannelMode === 'CH1' ? Color.White : '#666666')
            .onClick(() => { this.vm.fiberChannelMode = 'CH1'; })
          Button('通道2').height(28).layoutWeight(1).margin({ right: 2, left: 2 }).fontSize(13)
            .backgroundColor(this.vm.fiberChannelMode === 'CH2' ? '#1976D2' : '#F5F5F5')
            .fontColor(this.vm.fiberChannelMode === 'CH2' ? Color.White : '#666666')
            .onClick(() => { this.vm.fiberChannelMode = 'CH2'; })
          Button('通道3').height(28).layoutWeight(1).margin({ right: 2, left: 2 }).fontSize(13)
            .backgroundColor(this.vm.fiberChannelMode === 'CH3' ? '#1976D2' : '#F5F5F5')
            .fontColor(this.vm.fiberChannelMode === 'CH3' ? Color.White : '#666666')
            .onClick(() => { this.vm.fiberChannelMode = 'CH3'; })
          Button('通道4').height(28).layoutWeight(1).margin({ right: 2, left: 2 }).fontSize(13)
            .backgroundColor(this.vm.fiberChannelMode === 'CH4' ? '#1976D2' : '#F5F5F5')
            .fontColor(this.vm.fiberChannelMode === 'CH4' ? Color.White : '#666666')
            .onClick(() => { this.vm.fiberChannelMode = 'CH4'; })
        }
        .width('100%').height(36).padding({ bottom: 4, left: 12, right: 12 })
      }

      Stack() {
        Row().width('100%').height('100%').backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DDDDDD' })
        SignalBoard({
          vm: this.vm.signalVm,
          version: this.vm.waveVersion,
          waveIntervalMs: this.vm.waveIntervalMs,
          hostVm: this.vm,
          deviceMode: this.vm.deviceMode,
          fiberChannelMode: this.vm.fiberChannelMode
        }).width('100%').height('100%')

        if (this.vm.showListenDialog) { this.listenDialog() }
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ bottom: this.isPhone() ? 2 : 8 })

    }
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
    .width('100%')
    .height('100%')
    .margin({ left: 16, right: 8, top: 4, bottom: this.isPhone() ? 2 : (this.isFold() ? 12 : 16) })
  }

  @Builder fiberBottomControlRow() {
    Row() {
      Row() {
        Radio({ value: 'Master', group: 'MasterGroup' }).checked(this.vm.isMaster).onChange(v => { if(v) this.vm.setMaster(true) })
        Text('主').smallLabel().margin({ right: 6 })
        Radio({ value: 'Slave', group: 'MasterGroup' }).checked(!this.vm.isMaster).onChange(v => { if(v) this.vm.setMaster(false) })
        Text('从').smallLabel()
      }.margin({ right: 12 })

      TextInput({ text: this.vm.sliderValue.toString() })
        .width(40).height(this.btnHeight()).fontSize(this.btnFontSize()).borderRadius(4).border({ width: 1, color: '#CCCCCC' })
        .margin({ right: 4 }).padding(0).textAlign(TextAlign.Center)
        .onChange(v => this.vm.updateThresholdFromInput(v))

      Slider({ value: this.vm.sliderValue, min: 0, max: this.vm.deviceMode === 'TX' ? 100 : 255, step: 1, style: SliderStyle.OutSet })
        .layoutWeight(1).margin({ right: 12 })
        .onChange((val, mode) => { if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.vm.updateThresholdFromSlider(val); } })

      Row() {
        Button('调灵').height(32).fontSize(13).backgroundColor('#1976D2').fontColor(Color.White).onClick(() => this.vm.onSetFiberSensitivity()).margin({right: 8})
        Button('设备重启').height(32).fontSize(13).backgroundColor('#E0E0E0').fontColor('#333').margin({ right: 8 }).onClick(() => this.vm.sendRebootCommand())
        Button('下载').height(32).fontSize(13).backgroundColor('#E0E0E0').fontColor('#333').margin({ right: 8 }).onClick(() => this.vm.manualSnapshot())
        Button('断连').height(32).fontSize(13).backgroundColor('#E53935').fontColor('#FFF').onClick(() => this.vm.disconnectAndGoHome())
      }
    }
    .padding({ left: 12, right: 12, top: 4, bottom: 8 })
    .height(this.bottomRowHeight() + 10)
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder bottomControlRow() {
    Row() {
      Row() {
        Row() {
          Text(this.vm.isMaster ? '主' : '从').smallLabel().margin({ right: 2 })
          Toggle({ type: ToggleType.Switch, isOn: this.vm.isMaster })
            .selectedColor('#1976D2')
            .switchPointColor('#FFFFFF')
            .onChange((isOn: boolean) => { this.vm.setMaster(isOn); })
            .height(this.isPhone() ? 20 : 24)
        }.margin({ right: this.isPhone() ? 4 : 8 })

        Text(this.vm.deviceMode === 'TX' ? '调压' : '阈值').smallLabel().margin({ right: 2 })
        TextInput({ text: this.vm.sliderValue.toString() })
          .width(40).height(this.btnHeight()).fontSize(this.btnFontSize()).borderRadius(4).border({ width: 1, color: '#CCCCCC' })
          .margin({ right: 4 }).padding(0).textAlign(TextAlign.Center)
          .onChange(v => this.vm.updateThresholdFromInput(v))

        Slider({ value: this.vm.sliderValue, min: 0, max: this.vm.deviceMode === 'TX' ? 100 : 255, step: 1, style: SliderStyle.OutSet })
          .width(this.sliderWidth()).height(this.btnHeight()).margin({ right: this.isPhone() ? 4 : 8 })
          .onChange((val, mode) => { if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.vm.updateThresholdFromSlider(val); } })
      }
      .alignItems(VerticalAlign.Center)

      Row() {
        Button(this.vm.deviceMode === 'TX' ? '调压' : '调灵').layoutWeight(1).height(this.btnHeight()).fontSize(this.btnFontSize()).backgroundColor('#1976D2').fontColor(Color.White).margin({ right: 2 }).padding(0).onClick(() => this.vm.onSetSensitivityClick())
        Button('巡检').layoutWeight(1).height(this.btnHeight()).fontSize(this.btnFontSize()).backgroundColor('#BDBDBD').fontColor('#333333').margin({ right: 2 }).padding(0).onClick(() => this.vm.onTestWaveButtonClickDebug())
        Button('监听').layoutWeight(1).height(this.btnHeight()).fontSize(this.btnFontSize()).backgroundColor('#FFA000').fontColor(Color.White).margin({ right: 2 }).padding(0).onClick(() => this.vm.openListenDialog())
        Button('下图').layoutWeight(1).height(this.btnHeight()).fontSize(this.btnFontSize()).backgroundColor('#388E3C').fontColor(Color.White).margin({ right: 2 }).padding(0).onClick(() => this.vm.manualSnapshot())
        Button('断连').layoutWeight(1).height(this.btnHeight()).fontSize(this.btnFontSize()).backgroundColor('#E53935').fontColor(Color.White).padding(0).onClick(() => this.vm.disconnectAndGoHome())
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .padding({ left: 12, right: 12, top: this.isPhone() ? 1 : 4, bottom: this.isPhone() ? 2 : 8 })
    .height(this.bottomRowHeight())
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder rightTopIcons() {
    Row() {
      Column() {
        Stack() {
          Row()
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.vm.isRecording ? '#FFEBEE' : '#EFEFEF')
            .border({ width: 1, color: this.vm.isRecording ? '#E53935' : '#CCCCCC' });

          if (this.vm.isRecording) {
            Rect().width(12).height(12).fill('#E53935')
          } else {
            Text('REC').fontSize(12).fontColor('#E53935')
          }
        }
        .margin({ bottom: 4 })
        .opacity(this.recordOpacity)
        .onClick(() => this.vm.toggleRecording());

        Text(this.vm.isRecording ? '停止' : '录像').fontSize(13).fontColor(this.vm.isRecording ? '#E53935' : '#444444')
      }.margin({ right: 16 })

      Column() { Stack() { Row().width(36).height(36).borderRadius(8).backgroundColor('#EFEFEF').border({ width: 1, color: '#CCCCCC' }); Text('📁').fontSize(18) }.margin({ bottom: 4 }); Text('文件').fontSize(13).fontColor('#444444') }.onClick(() => this.vm.openRunDirFolder())
      Blank()
    }.padding({ top: 10, left: 8, right: 8, bottom: 4 })
  }

  @Builder fiberRightPanel() {
    Column() {
      this.rightTopIcons()
      FiberDataPanel({ vm: this.vm })
      Blank().layoutWeight(1)
      this.muteButton()
    }.layoutWeight(this.isLargeScreen() ? 1.2 : 1.5).height('100%').padding({ right: 12, left: 12 })
  }

  @Builder playbackPanel() {
    Column() {
      Text('回放控制').sectionTitle().margin({bottom: 10})

      Row() {
        Text('进度').fontSize(14)
        Blank()
        Text(this.vm.playbackTotalDuration).fontSize(14).fontColor('#666')
      }.width('100%').padding(4)

      Slider({ value: this.vm.playbackProgress, min: 0, max: 100 })
        .width('100%')
        .margin({bottom: 10})
        .onChange((val, mode) => {
          if (mode === SliderChangeMode.Click || mode === SliderChangeMode.Moving) {
            this.vm.seekPlayback(val);
          }
        })

      Row() {
        Text('倍速').fontSize(14)
        Blank()
        Text(`${this.vm.playbackRate.toFixed(1)}x`).fontSize(14).fontColor('#1976D2')
      }.width('100%').padding({top: 10, bottom: 4})

      Slider({ value: this.vm.playbackRate, min: 0.5, max: 100, step: 0.5 })
        .width('100%')
        .margin({bottom: 20})
        .onChange((val) => {
          this.vm.setPlaybackRate(val);
        })

      Row() {
        Button(this.vm.isPlaybackPaused ? '继续' : '暂停')
          .width('40%')
          .height(36)
          .backgroundColor('#FFA000')
          .onClick(() => {
            this.vm.togglePlaybackPause();
          })

        Blank().width(10)

        Button('退出回放')
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#E53935')
          .onClick(() => {
            this.vm.stopPlayback();
            this.getUIContext().getRouter().back();
          })
      }.width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#FFF')
  }

  @Builder muteButton() {
    Column() {
      Stack() {
        Row().width(this.isPhone() ? 48 : 60).height(this.isPhone() ? 48 : 60).borderRadius(this.isPhone() ? 24 : 30)
          .backgroundColor(this.vm.isMute ? '#CCCCCC' : '#F2F2F2').border({ width: 1, color: '#CCCCCC' })
        Text(this.vm.isMute ? '🔇' : '🔊').fontSize(this.isPhone() ? 20 : 26)
      }.onClick(() => this.vm.toggleMute())
      Text(this.vm.isMute ? '已静音' : '声音开').fontSize(13).fontColor('#444444').margin({ top: 4 })
    }
    .alignSelf(ItemAlign.Center)
    .margin({ bottom: this.isPhone() ? 16 : 24 })
  }

  @Builder leftPanel() {
    Column() {
      this.statusRow()

      Column() {
        this.wavePanel()
      }
      .layoutWeight(1)
      .width('100%')

      if (this.vm.deviceMode === 'FIBER') {
        this.fiberBottomControlRow()
      } else {
        this.bottomControlRow()
      }
    }
    .layoutWeight(this.isLargeScreen() ? 3.8 : 3)
    .height('100%')
  }

  @Builder rightPanel() {
    Column() {
      if (this.vm.isPlaybackMode) {
        this.playbackPanel()
      } else if (this.vm.deviceMode === 'FIBER') {
        this.fiberRightPanel()
      } else if (this.vm.deviceMode === 'TX') {
        this.rightTopIcons()
        TxParamPanel({ vm: this.vm })
        Blank().layoutWeight(1)
        this.muteButton()
      } else {
        this.rightTopIcons()
        ParamListPanel({ vm: this.vm, listHeight: this.listHeight() })
        Blank().layoutWeight(1)
        this.muteButton()
      }
    }.layoutWeight(this.isLargeScreen() ? 1.2 : 1.5).height('100%')
  }

  build() {
    Column() {
      this.navBar()
      Row() {
        this.leftPanel()
        this.rightPanel()
      }.width('100%').layoutWeight(1).height('100%')
    }.backgroundColor('#FFFFFF').width('100%').height('100%')
  }
}