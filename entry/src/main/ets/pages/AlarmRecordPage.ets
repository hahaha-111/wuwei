import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI'; 
import { AlarmRecordViewModel, AlarmRecord, AlarmLevel } from '../viewmodel/AlarmRecordViewModel';
import { DeviceType } from '../common/ProtocolParser';

@Extend(Text)
function navLabel(active: boolean) {
  .fontSize(14)
  .fontColor(active ? Color.Blue : '#333333')
}

@Entry
@Component
struct AlarmRecordPage {
  @State vm: AlarmRecordViewModel = new AlarmRecordViewModel();
  private currentTab: string = 'alarm';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  private listScroller: Scroller = new Scroller();
  @State pickedDate: Date = new Date();

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    
    // ⭐ 修复警告：使用 Record<string, Object> 处理从 router 接收参数
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;

    this.vm.uiContext = this.getUIContext();

    this.vm.init(params, ctx);

    this.vm.setOnWaveChange(() => {
      if (this.canvasWidth > 0 && this.canvasHeight > 0) {
        this.drawWaveform();
      }
    });
  }

  aboutToDisappear() {
    this.vm.onDisappear();
  }

  private getLevelColor(level: AlarmLevel): string {
    if (level === 'high') return '#F44336';
    if (level === 'medium') return '#FF9800';
    return '#4CAF50';
  }

  private goTo(tab: string) {
    if (tab === this.currentTab) return;

    if (tab === 'calibrate' && this.vm.deviceType !== DeviceType.Microwave) {
      try { this.getUIContext().getPromptAction().showToast({ message: '当前设备不支持校准功能' }); } catch (err) {}
      return;
    }

    // ⭐ 修复 arkts-no-untyped-obj-literals：使用 Record<string, Object> 构建跳转参数
    const navParams: Record<string, Object> = {};
    navParams['deviceName'] = this.vm.deviceNameDisplay;
    navParams['deviceType'] = this.vm.deviceType;
    navParams['connectionMode'] = this.vm.connectionMode;
    navParams['deviceAddress'] = this.vm.currentDeviceAddress;

    if (tab === 'home') this.getUIContext().getRouter().replaceUrl({ url: 'pages/MonitorPage', params: navParams }, router.RouterMode.Standard).catch(() => { });
    if (tab === 'calibrate') this.getUIContext().getRouter().replaceUrl({ url: 'pages/CalibratePage', params: navParams }, router.RouterMode.Standard).catch(() => { });
    if (tab === 'setting') this.getUIContext().getRouter().replaceUrl({ url: 'pages/SettingPage', params: navParams }, router.RouterMode.Standard).catch(() => { });
    if (tab === 'log') this.getUIContext().getRouter().replaceUrl({ url: 'pages/LogPage', params: navParams }, router.RouterMode.Standard).catch(() => { });
  }

  private showDatePickerDialog() {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-01-01'),
      end: new Date('2030-12-31'),
      selected: this.pickedDate,
      onAccept: (value: DatePickerResult) => {
        if (value.year !== undefined && value.month !== undefined && value.day !== undefined) {
          this.pickedDate.setFullYear(value.year, value.month, value.day);

          const targetDate = new Date(value.year, value.month, value.day);
          const index = this.vm.getRecordIndexByDate(targetDate);

          if (index >= 0) {
            this.listScroller.scrollToIndex(index, true, ScrollAlign.START);
            const m = (value.month + 1).toString().padStart(2, '0');
            const d = value.day.toString().padStart(2, '0');
            try {
              this.getUIContext().getPromptAction().showToast({ message: `已跳转至 ${value.year}/${m}/${d} 的记录` });
            } catch (error) {}
          } else {
            try {
              this.getUIContext().getPromptAction().showToast({ message: '未找到该日期的报警记录' });
            } catch (error) {}
          }
        }
      }
    })
  }

  private drawWaveform() {
    if (!this.context || this.canvasWidth <= 0 || this.canvasHeight <= 0) return;

    const ctx = this.context;
    const w = this.canvasWidth;
    const h = this.canvasHeight;
    const data = this.vm.selectedWaveform.slice();
    const threshold = this.vm.playbackThreshold;

    ctx.clearRect(0, 0, w, h);

    ctx.lineWidth = 0.5;
    ctx.strokeStyle = '#EEEEEE';
    ctx.beginPath();
    for (let i = 1; i < 5; i++) {
      const y = (h / 5) * i;
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
    }
    ctx.stroke();

    if (data.length === 0) {
      ctx.font = '14px sans-serif';
      ctx.fillStyle = '#999999';
      ctx.textAlign = 'center';
      ctx.fillText('暂无波形数据', w / 2, h / 2);
      return;
    }

    const maxVal = 255;
    const plotPadding = 10;
    const plotH = h - plotPadding * 2;
    const stepX = (w - plotPadding * 2) / Math.max(data.length - 1, 1);

    const getY = (val: number) => {
      let v = val;
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      return h - plotPadding - (v / maxVal) * plotH;
    };

    ctx.lineWidth = 2;
    ctx.strokeStyle = '#2196F3';
    ctx.lineJoin = 'round';
    ctx.beginPath();

    data.forEach((val, idx) => {
      const x = plotPadding + idx * stepX;
      const y = getY(val);
      if (idx === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    if (threshold > 0) {
      const thY = getY(threshold);

      ctx.lineWidth = 1.5;
      ctx.strokeStyle = '#F44336';
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(0, thY);
      ctx.lineTo(w, thY);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = '#F44336';
      ctx.font = '12px sans-serif';
      ctx.textAlign = 'right';

      if (this.vm.deviceType === DeviceType.Fiber) {
        ctx.fillText(`基准: ${threshold}`, w - 5, thY - 5);

        let highTh = threshold + 2 * this.vm.playbackSens;
        if (highTh > 255) highTh = 255;
        const thYHigh = getY(highTh);

        ctx.lineWidth = 1.5;
        ctx.strokeStyle = '#FF9800';
        ctx.setLineDash([5, 5]);
        ctx.beginPath();
        ctx.moveTo(0, thYHigh);
        ctx.lineTo(w, thYHigh);
        ctx.stroke();
        ctx.setLineDash([]);

        ctx.fillStyle = '#FF9800';
        ctx.fillText(`报警线: ${highTh}`, w - 5, thYHigh - 5);
      } else {
        ctx.fillText(`阈值: ${threshold}`, w - 5, thY - 5);
      }
    }
  }

  @Builder
  topNavBar() {
    Row() {
      Column({ space: 4 }) { Text('主页').navLabel(this.currentTab === 'home').onClick(() => this.goTo('home')) }.layoutWeight(1).justifyContent(FlexAlign.Center)

      if (this.vm.deviceType === DeviceType.Microwave) {
        Column({ space: 4 }) { Text('校准').navLabel(this.currentTab === 'calibrate').onClick(() => this.goTo('calibrate')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      }

      Column({ space: 4 }) { Text('报警记录').navLabel(this.currentTab === 'alarm').onClick(() => this.goTo('alarm')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Column({ space: 4 }) { Text('设置').navLabel(this.currentTab === 'setting').onClick(() => this.goTo('setting')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Column({ space: 4 }) { Text('日志').navLabel(this.currentTab === 'log').onClick(() => this.goTo('log')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
    }
    .width('100%').height(50).backgroundColor('#F5F5F5').justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder
  alarmListToolbar() {
    Column() {
      Row({ space: 8 }) {
        Button('从设备下载').height(32).fontSize(12).backgroundColor('#4CAF50').layoutWeight(1).onClick(() => this.vm.downloadFromDevice())
        Button('导出报警').height(32).fontSize(12).backgroundColor('#2196F3').layoutWeight(1).onClick(() => this.vm.exportAlarmRecords())
        Button('记录列表').height(32).fontSize(12).backgroundColor('#9E9E9E').layoutWeight(1).onClick(() => this.vm.goToRecordList())
        Button('清除记录').height(32).fontSize(12).backgroundColor('#FF5252').layoutWeight(1).onClick(() => this.vm.clearAllRecords())
        Button('清除波形').height(32).fontSize(12).backgroundColor('#D32F2F').layoutWeight(1).onClick(() => this.vm.clearWaveform())
      }
      .width('100%').margin({ bottom: 6 })

      Row() {
        Text(this.vm.deviceNameDisplay)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ left: 4 })

        Blank()

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row() {
            Text('📅 跳转')
              .fontSize(12)
              .fontColor('#333')
          }
        }
        .backgroundColor(Color.Transparent)
        .height(24)
        .margin({ right: 12 })
        .onClick(() => {
          this.showDatePickerDialog();
        })

        Text(`报警: ${this.vm.totalAlarmCount}`)
          .fontSize(11).fontColor('#666666').margin({ right: 8 })
        Text(`波形: ${this.vm.waveTotalCount}`)
          .fontSize(11).fontColor('#1976D2').margin({ right: 12 })

        Text(this.vm.currentSystemTime)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .margin({ right: 4 })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor('#FAFAFA')
      .borderRadius(4)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%').margin({ bottom: 8 })
  }

  @Builder
  alarmTableHeader() {
    Row() {
      Text('序号').fontSize(12).fontWeight(FontWeight.Bold).width('10%')
      Text('时间').fontSize(12).fontWeight(FontWeight.Bold).width('30%')
      Text(this.vm.deviceType === DeviceType.Microwave ? '类型' : '报警源').fontSize(12).fontWeight(FontWeight.Bold).width('15%')
      Text('幅值').fontSize(12).fontWeight(FontWeight.Bold).width('15%')
      Text(this.vm.deviceType === DeviceType.Fiber ? '灵敏度' : '阈值').fontSize(12).fontWeight(FontWeight.Bold).width('15%')
      Text('级别').fontSize(12).fontWeight(FontWeight.Bold).width('15%')
    }
    .height(28).padding({ left: 8, right: 8 }).backgroundColor('#EEEEEE')
  }

  @Builder
  alarmTableRow(record: AlarmRecord, index: number) {
    Row() {
      Text(record.displayId).fontSize(12).width('10%')
      Text(record.timeText).fontSize(11).width('30%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.vm.deviceType === DeviceType.Microwave ? record.alarmType : record.channel).fontSize(12).width('15%')
      Text(record.triggerSignal.toString()).fontSize(12).width('15%')
      Text(record.threshold.toString()).fontSize(12).width('15%')
      Text(record.levelText).fontSize(12).fontColor(this.getLevelColor(record.level)).width('15%')
    }
    .height(32).padding({ left: 8, right: 8 })
    .backgroundColor(index === this.vm.selectedIndex ? '#E3F2FD' : (index % 2 === 0 ? '#FFFFFF' : '#F9F9F9'))
    .onClick(() => this.vm.selectRecord(index))
  }

  @Builder
  alarmListPanel() {
    Column() {
      this.alarmListToolbar()
      this.alarmTableHeader()
      if (this.vm.alarmList.length === 0) {
        Column() { Text(this.vm.tipText).fontSize(13).fontColor('#888888').margin({ top: 40 }) }.width('100%').height(160).justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.listScroller }) {
          ForEach(this.vm.alarmList, (record: AlarmRecord, index: number) => {
            ListItem() { this.alarmTableRow(record, index) }
          }, (record: AlarmRecord) => `${record.id}`)
        }
        .width('100%')
        .height('100%') 
        .layoutWeight(1)
        .onReachStart(() => {
          this.vm.resumeReadingRecords();
        })
        .onReachEnd(() => {
          this.vm.resumeReadingRecords();
        })
      }
    }
    .height('100%')
    .backgroundColor(Color.White)
    .borderRadius(8)
    .border({ width: 1, color: '#DDDDDD' })
    .gesture(
      SwipeGesture({ direction: SwipeDirection.Vertical })
        .onAction(() => {
          this.vm.resumeReadingRecords();
        })
    )
  }

  @Builder
  alarmDetailPanel() {
    Column() {
      Text('报警波形回放')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      Stack() {
        Canvas(this.context)
          .width('100%')
          .height('100%')
          .onAreaChange((_o, n) => {
            this.canvasWidth = Number(n.width);
            this.canvasHeight = Number(n.height);
            this.drawWaveform();
          })
          .onReady(() => {
            this.drawWaveform();
          })
      }
      .layoutWeight(1)
      .backgroundColor('#FAFAFA')
      .border({ width: 1, color: '#EEEEEE' })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionEnd((event) => {
            const dx = event.offsetX;
            const threshold = 20;
            if (dx <= -threshold) {
              this.vm.prevWaveRecord();
            } else if (dx >= threshold) {
              this.vm.nextWaveRecord();
            }
          })
      )

      Row() {
        Button('上一条波形')
          .height(30)
          .fontSize(12)
          .backgroundColor('#90CAF9')
          .layoutWeight(1)
          .onClick(() => this.vm.prevWaveRecord())

        Blank().width(8)

        Button('下一条波形')
          .height(30)
          .fontSize(12)
          .backgroundColor('#42A5F5')
          .layoutWeight(1)
          .onClick(() => this.vm.nextWaveRecord())
      }
      .margin({ top: 6 })

      Text(this.vm.tipText).fontSize(12).fontColor('#999').margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .border({ width: 1, color: '#DDDDDD' })
  }

  build() {
    Column() {
      this.topNavBar()
      Row() {
        Column() { this.alarmListPanel() }.layoutWeight(3).padding({ left: 12, top: 8, bottom: 8 }).height('100%')
        Column() {
          this.alarmDetailPanel()
        }.layoutWeight(2).padding({ left: 8, right: 12, top: 8, bottom: 8 }).height('100%')
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor('#F0F0F0')
  }
}