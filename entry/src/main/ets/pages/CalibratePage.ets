import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI'; // ⭐ 修改：统一使用 ArkUI 下的现代 router API
import { SignalCalibrateViewModel } from '../viewmodel/SignalCalibrateViewModel';
import { MonitorPageParams } from '../viewmodel/MonitorViewModel';

@Extend(Text)
function navLabel(active: boolean) {
  .fontSize(14)
  // ⭐ 修改：未选中状态颜色加深，提升对比度 (#333333 -> #666666 只是示例，实际需求是更清晰)
  // 这里保持 #333333 其实对比度尚可，若要更深可用 #222222
  // 选中状态保持 Blue
  .fontColor(active ? '#1976D2' : '#616161')
  .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
}

@Entry
@Component
struct CalibratePage {
  @State vm: SignalCalibrateViewModel = new SignalCalibrateViewModel();

  // Canvas 相关配置
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasW: number = 0;
  private canvasH: number = 0;
  private drawTimer: number = 0;

  // 折线图 Canvas
  private historyContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private peakContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private historyW: number = 0;
  private historyH: number = 0;
  private peakW: number = 0;
  private peakH: number = 0;

  private currentTab: string = 'calibrate';
  
  // ⭐ 修复：删除了未被使用的 contextAbility 变量，消除 'never read' 警告

  aboutToAppear() {
    // ⭐ 修复：使用 API 13 专用的 getHostContext 代替已过时的全局 getContext(this)
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;

    try {
      // ⭐ 修复：使用 UIContext 下的安全路由获取参数
      const params = this.getUIContext().getRouter().getParams() as MonitorPageParams;
      this.vm.init(params, ctx);
    } catch (e) {
      this.vm.onAppear(ctx);
    }
  }

  onPageShow() {
    this.vm.registerCallbacks();
    this.startDrawLoop();
  }

  onPageHide() {
    this.vm.onPageHide(); // 这里会触发 stopCalibration 发送退出指令
    this.stopDrawLoop();
  }

  aboutToDisappear() {
    this.vm.onDisappear();
    this.stopDrawLoop();
  }

  private startDrawLoop() {
    this.stopDrawLoop();
    this.drawTimer = setInterval(() => {
      this.drawGauge();
      this.drawHistoryChart();
      this.drawPeakChart();
    }, 33);
  }

  private stopDrawLoop() {
    if (this.drawTimer) {
      clearInterval(this.drawTimer);
      this.drawTimer = 0;
    }
  }

  private getColorForValue(value: number): string {
    if (value < 100) return '#F44336';
    if (value <= 200) return '#FF9800';
    return '#4CAF50';
  }

  private drawGauge() {
    if (!this.context || this.canvasW <= 0 || this.canvasH <= 0) return;
    const w = this.canvasW;
    const h = this.canvasH;
    const cx = w / 2;
    const cy = h / 2;
    const r = Math.min(cx, cy) - 15;

    this.context.clearRect(0, 0, w, h);

    const startAngle = Math.PI * 0.75;
    const endAngle = Math.PI * 2.25;
    const totalAngle = endAngle - startAngle;
    const valToAngle = (v: number) => startAngle + (v / 255.0) * totalAngle;

    // 外环
    const rOuter = r;
    this.context.beginPath();
    this.context.arc(cx, cy, rOuter, startAngle, endAngle);
    this.context.lineWidth = 12;
    this.context.strokeStyle = '#F2F2F2';
    this.context.lineCap = 'round';
    this.context.stroke();

    if (this.vm.maxSignal > 0) {
      const maxAngle = valToAngle(this.vm.maxSignal);
      this.context.beginPath();
      this.context.arc(cx, cy, rOuter, startAngle, maxAngle);
      this.context.lineWidth = 12;
      this.context.strokeStyle = this.getColorForValue(this.vm.maxSignal);
      this.context.lineCap = 'round';
      this.context.stroke();
    }

    // 刻度文字
    this.context.font = '12px sans-serif';
    this.context.fillStyle = '#999999';
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    const labelR = rOuter + 15;
    const x0 = cx + labelR * Math.cos(startAngle);
    const y0 = cy + labelR * Math.sin(startAngle);
    this.context.fillText('0', x0, y0);
    const x255 = cx + labelR * Math.cos(endAngle);
    const y255 = cy + labelR * Math.sin(endAngle);
    this.context.fillText('255', x255, y255);

    // 内环刻度
    const rInner = rOuter - 20;
    const tickLenMain = 10;
    const tickLenSub = 5;
    const tickCount = 20;

    // 刻度线颜色
    this.context.strokeStyle = '#666666';
    for (let i = 0; i <= tickCount; i++) {
      const angle = startAngle + (totalAngle * i / tickCount);
      const isMain = (i % 5 === 0);
      const len = isMain ? tickLenMain : tickLenSub;
      this.context.lineWidth = isMain ? 2 : 1;

      const p1x = cx + rInner * Math.cos(angle);
      const p1y = cy + rInner * Math.sin(angle);
      const p2x = cx + (rInner - len) * Math.cos(angle);
      const p2y = cy + (rInner - len) * Math.sin(angle);

      this.context.beginPath();
      this.context.moveTo(p1x, p1y);
      this.context.lineTo(p2x, p2y);
      this.context.stroke();
    }

    // 指针
    const currentAngle = valToAngle(this.vm.currentSignal);
    this.context.save();
    this.context.translate(cx, cy);
    this.context.rotate(currentAngle);

    const ptrLen = rInner - 5;
    const ptrColor = this.getColorForValue(this.vm.currentSignal);
    this.context.fillStyle = ptrColor;

    this.context.beginPath();
    this.context.moveTo(0, -5);
    this.context.lineTo(ptrLen, 0);
    this.context.lineTo(0, 5);
    this.context.lineTo(-15, 0);
    this.context.closePath();
    this.context.fill();

    this.context.beginPath();
    this.context.arc(0, 0, 4, 0, Math.PI * 2);
    this.context.fillStyle = '#FFFFFF';
    this.context.fill();
    this.context.restore();
  }

  private drawLineChart(ctx: CanvasRenderingContext2D, w: number, h: number, data: number[]) {
    if (!ctx || w <= 0 || h <= 0) return;
    ctx.clearRect(0, 0, w, h);
    this.drawChartGrid(ctx, w, h);

    if (!data || data.length === 0) return;

    const maxVal = 255;
    const stepX = w / (Math.max(data.length, 2) - 1);

    ctx.beginPath();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#2196F3';
    ctx.lineJoin = 'round';

    data.forEach((val, index) => {
      const x = index * stepX;
      const y = h - (val / maxVal) * h;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fillStyle = '#2196F333';
    ctx.fill();
  }

  private drawChartGrid(ctx: CanvasRenderingContext2D, w: number, h: number) {
    ctx.lineWidth = 0.5;
    ctx.strokeStyle = '#EEEEEE';
    for (let i = 0; i <= 4; i++) {
      const y = (h / 4) * i;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
  }

  private drawHistoryChart() {
    this.drawLineChart(this.historyContext, this.historyW, this.historyH, this.vm.signalHistory);
  }

  private drawPeakChart() {
    this.drawLineChart(this.peakContext, this.peakW, this.peakH, this.vm.peakWindowHistory);
  }

  private goTo(tab: string) {
    if (tab === this.currentTab) return;

    this.vm.stopCalibration(); // 切换前发送退出指令

    const params = this.vm.getNavParams();
    const routerInstance = this.getUIContext().getRouter();
    
    // ⭐ 修复：直接挂载 .catch()，接管 Promise 的异常抛出，同时满足 Standard 路由模式和严格语法
    switch (tab) {
      case 'home':
        routerInstance.replaceUrl({ url: 'pages/MonitorPage', params: params }, router.RouterMode.Standard).catch(() => {});
        break;
      case 'alarm':
        routerInstance.replaceUrl({ url: 'pages/AlarmRecordPage', params: params }, router.RouterMode.Standard).catch(() => {});
        break;
      case 'setting':
        routerInstance.replaceUrl({ url: 'pages/SettingPage', params: params }, router.RouterMode.Standard).catch(() => {});
        break;
      case 'log':
        routerInstance.replaceUrl({ url: 'pages/LogPage', params: params }, router.RouterMode.Standard).catch(() => {});
        break;
    }
  }

  @Builder
  topNavBar() {
    Row() {
      Column({ space: 4 }) { Text('主页').navLabel(this.currentTab === 'home').onClick(() => this.goTo('home')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Column({ space: 4 }) { Text('校准').navLabel(this.currentTab === 'calibrate').onClick(() => this.goTo('calibrate')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Column({ space: 4 }) { Text('报警记录').navLabel(this.currentTab === 'alarm').onClick(() => this.goTo('alarm')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Column({ space: 4 }) { Text('设置').navLabel(this.currentTab === 'setting').onClick(() => this.goTo('setting')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Column({ space: 4 }) { Text('日志').navLabel(this.currentTab === 'log').onClick(() => this.goTo('log')) }.layoutWeight(1).justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(50)
    // ⭐ 修改：底部导航背景色加深一点点，提升对比
    .backgroundColor('#F0F0F0')
    .border({ width: { bottom: 1 }, color: '#E0E0E0' })
  }

  @Builder
  signalHistoryBoard() {
    Column() {
      Column() {
        Text('信号整体变化趋势')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12, top: 10, right: 12, bottom: 6 })

        Canvas(this.historyContext)
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_o, n) => {
            this.historyW = Number(n.width);
            this.historyH = Number(n.height);
          })
          .onReady(() => this.drawHistoryChart())
      }
      .width('100%')
      .layoutWeight(2)
      .backgroundColor(Color.White)
      .border({ width: 1, color: '#DDDDDD' })
      .borderRadius(8)

      Column() {
        Text('最近一次最大值附近趋势')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12, top: 10, right: 12, bottom: 4 })

        Canvas(this.peakContext)
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_o, n) => {
            this.peakW = Number(n.width);
            this.peakH = Number(n.height);
          })
          .onReady(() => this.drawPeakChart())

        Text(`峰值：${this.vm.maxSignal}，出现时间：${this.vm.peakTime}`)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ left: 12, right: 12, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .border({ width: 1, color: '#DDDDDD' })
      .borderRadius(8)
      .margin({ top: 8 })

      Text('最后更新时间：' + this.vm.lastUpdateTime)
        .fontSize(12)
        .fontColor('#666666')
        .margin({ top: 6 })
    }
    .height('100%')
  }

  @Builder
  signalInfoPanel() {
    Column() {
      Text('信号强度仪表盘')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4, top: 4 })

      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.context)
          .width('100%')
          .height('100%')
          .onAreaChange((_o, n) => {
            this.canvasW = Number(n.width);
            this.canvasH = Number(n.height);
            this.drawGauge();
          })
          .onReady(() => {
            this.drawGauge();
          })

        Column() {
          Text(this.vm.currentSignal.toString())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColorForValue(this.vm.currentSignal))
            .margin({ top: 40 })

          Text('当前信号')
            .fontSize(12)
            .fontColor('#666666')

          Text(`最大值: ${this.vm.maxSignal}`)
            .fontSize(12)
            .fontColor(this.getColorForValue(this.vm.maxSignal))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      .layoutWeight(1)
      .width('100%')

      Column() {
        Row() {
          // ⭐ 修改：优化按钮禁用态的背景色
          // '开始校准' 禁用时 (isCalibrating=true)：颜色设为较深的灰色 #9E9E9E，而非之前的 #ffbbbbbb (太浅看不清)
          // 启用时：#4CAF50
          Button(this.vm.isCalibrating ? '校准中...' : '开始校准')
            .enabled(!this.vm.isCalibrating)
            .height(30)
            .fontSize(12)
            .backgroundColor(this.vm.isCalibrating ? '#9E9E9E' : '#4CAF50')
            .fontColor(Color.White)
            .layoutWeight(1)
            .onClick(() => { this.vm.startCalibration(); })

          Blank().width(8)

          Button('清除最大值')
            .height(30)
            .fontSize(12)
            .backgroundColor('#B0BEC5') // 稍微深一点的蓝灰
            .fontColor('#333333')
            .layoutWeight(1)
            .onClick(() => this.vm.clearMax())

          Blank().width(8)

          // ⭐ 修改：'停止校准' 禁用时 (isCalibrating=false)：颜色设为较深的灰色 #9E9E9E
          // 启用时：#E53935
          Button('停止校准')
            .enabled(this.vm.isCalibrating)
            .height(30)
            .fontSize(12)
            .backgroundColor(this.vm.isCalibrating ? '#E53935' : '#9E9E9E')
            .fontColor(Color.White)
            .layoutWeight(1)
            .onClick(() => { this.vm.stopCalibration(); })
        }
        .width('100%')
        .margin({ bottom: 6 })


      }.padding({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .border({ width: 1, color: '#DDDDDD' })
  }

  build() {
    Column() {
      this.topNavBar()
      Row() {
        Column() { this.signalHistoryBoard() }.layoutWeight(3).padding({ left: 8, top: 8, bottom: 8 }).height('100%')
        Column() { this.signalInfoPanel() }.layoutWeight(2).padding({ left: 8, right: 8, top: 8, bottom: 8 }).height('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DDDDDD')
  }
}