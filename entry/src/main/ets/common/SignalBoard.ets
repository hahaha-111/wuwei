import { SignalBoardViewModel, SignalSample } from '../viewmodel/SignalBoardViewModel';
import { DeviceMode, FiberChannelMode } from '../viewmodel/MonitorViewModel';

interface WaveIntervalHost {
  setWaveIntervalMs(n: number): void;
}

@Component
export struct SignalBoard {
  @ObjectLink vm: SignalBoardViewModel;
  @Prop @Watch('onVersionChanged') version: number = 0;

  @Prop deviceMode: DeviceMode = 'RX';
  @Prop fiberChannelMode: FiberChannelMode = 'ALL';

  @Prop @Watch('onWaveIntervalPropChanged') waveIntervalMs: number = 20;
  @Prop hostVm: WaveIntervalHost;

  @State private displayCountLocal: number = 60;
  @State private waveIntervalLocal: number = 20;

  private waveIntervalDebounceTimer: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private offScreenCanvas: OffscreenCanvas | null = null;
  private offScreenContext: OffscreenCanvasRenderingContext2D | null = null;
  private isGridCached: boolean = false;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  onVersionChanged(): void { this.draw(); }
  onWaveIntervalPropChanged(): void { this.waveIntervalLocal = this.waveIntervalMs; }

  aboutToAppear(): void {
    this.displayCountLocal = this.vm.getDisplayCount();
    this.waveIntervalLocal = this.waveIntervalMs;
  }

  private draw(): void {
    if (this.canvasWidth === 0 || this.canvasHeight === 0) return;
    this.context.clearRect(0, 0, this.canvasWidth, this.canvasHeight);

    if (!this.isGridCached || !this.offScreenCanvas) {
      this.cacheGrid();
    }

    if (this.offScreenCanvas && this.offScreenContext) {
      const pixelMap = this.offScreenContext.getPixelMap(0, 0, this.canvasWidth, this.canvasHeight);
      this.context.drawImage(pixelMap, 0, 0);
      pixelMap.release();
    }

    this.drawSignalPath();
  }

  private cacheGrid(): void {
    this.offScreenCanvas = new OffscreenCanvas(this.canvasWidth, this.canvasHeight);
    this.offScreenContext = this.offScreenCanvas.getContext('2d', this.settings);
    const ctx = this.offScreenContext;
    if (!ctx) return;

    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    ctx.beginPath();
    ctx.lineWidth = 1;
    ctx.strokeStyle = '#E0E0E0';
    const ticks: number[] = [0, 51, 102, 153, 204, 255];
    ticks.forEach((val: number) => {
      const y = this.canvasHeight - (val / 255) * this.canvasHeight;
      ctx.moveTo(0, y);
      ctx.lineTo(this.canvasWidth, y);
    });
    for (let i = 1; i < 4; i++) {
      const x = (this.canvasWidth / 4) * i;
      ctx.moveTo(x, 0);
      ctx.lineTo(x, this.canvasHeight);
    }
    ctx.stroke();
    ctx.font = '24px sans-serif';
    ctx.fillStyle = '#666666';
    ticks.forEach((val: number) => {
      const y = this.canvasHeight - (val / 255) * this.canvasHeight;
      ctx.fillText(val.toString(), this.canvasWidth - 45, y - 5);
    });
    this.isGridCached = true;
  }

  private drawSignalPath(): void {
    const samples = this.vm.getVisibleSamples();
    const count = samples.length;
    if (count < 2) return;

    const ctx = this.context;
    const stepX = this.canvasWidth / (this.vm.getDisplayCount() - 1);

    const getY = (val: number | undefined, range: number = 255): number => {
      return this.canvasHeight - ((val || 0) / range) * this.canvasHeight;
    };

    const drawLine = (color: string, width: number, extractor: (s: SignalSample) => number | undefined, range: number = 255): void => {
      let firstValidIndex = -1;
      for (let i = 0; i < count; i++) {
        if (extractor(samples[i]) !== undefined) {
          firstValidIndex = i;
          break;
        }
      }

      if (firstValidIndex === -1 || firstValidIndex >= count - 1) return;

      ctx.beginPath();
      ctx.lineWidth = width;
      ctx.strokeStyle = color;
      ctx.moveTo(firstValidIndex * stepX, getY(extractor(samples[firstValidIndex]), range));
      
      for (let i = firstValidIndex + 1; i < count; i++) {
        const val = extractor(samples[i]);
        if (val !== undefined) {
          ctx.lineTo(i * stepX, getY(val, range));
        }
      }
      ctx.stroke();
    };

    if (this.deviceMode === 'TX') {
      ctx.font = '18px sans-serif';
      ctx.fillStyle = '#E53935'; ctx.fillText('温度(0-100℃) - 红', 10, 24);
      ctx.fillStyle = '#1976D2'; ctx.fillText('湿度(0-100%) - 蓝', 180, 24);
      ctx.fillStyle = '#00BCD4'; ctx.fillText('MCU电压(0-5V) - 青', 350, 24);
      ctx.fillStyle = '#9C27B0'; ctx.fillText('输入电压(0-20V) - 紫', 520, 24);
      
      drawLine('#E53935', 3, (s: SignalSample): number | undefined => s.temperature, 100);
      drawLine('#1976D2', 3, (s: SignalSample): number | undefined => s.humidity, 100);
      drawLine('#00BCD4', 3, (s: SignalSample): number | undefined => s.mcuVoltage, 5);
      drawLine('#9C27B0', 3, (s: SignalSample): number | undefined => s.voltage, 20);
    }
    else if (this.deviceMode === 'FIBER') {
      ctx.font = '16px sans-serif';
      if (this.fiberChannelMode === 'ALL') {
        ctx.fillStyle = '#FF3B30'; ctx.fillText('光纤1 - 红', 10, 24);
        ctx.fillStyle = '#FF9800'; ctx.fillText('光纤2 - 橙', 100, 24);
        ctx.fillStyle = '#1976D2'; ctx.fillText('光纤3 - 蓝', 190, 24);
        ctx.fillStyle = '#4CAF50'; ctx.fillText('光纤4 - 绿', 280, 24);

        drawLine('#FF3B30', 2, (s: SignalSample): number | undefined => s.signal);
        drawLine('#FF9800', 2, (s: SignalSample): number | undefined => s.signal2);
        drawLine('#1976D2', 2, (s: SignalSample): number | undefined => s.signal3);
        drawLine('#4CAF50', 2, (s: SignalSample): number | undefined => s.signal4);
      } else {
        ctx.fillStyle = '#0000FF'; ctx.fillText('信号 - 蓝色', 10, 24);
        ctx.fillStyle = '#FF0000'; ctx.fillText('上下限 - 红色', 120, 24);

        if (this.fiberChannelMode === 'CH1') {
          drawLine('#0000FF', 3, (s: SignalSample): number | undefined => s.signal);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.alarmThreshold);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.limitDown1);
        } else if (this.fiberChannelMode === 'CH2') {
          drawLine('#0000FF', 3, (s: SignalSample): number | undefined => s.signal2);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.alarmThreshold2);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.limitDown2);
        } else if (this.fiberChannelMode === 'CH3') {
          drawLine('#0000FF', 3, (s: SignalSample): number | undefined => s.signal3);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.alarmThreshold3);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.limitDown3);
        } else if (this.fiberChannelMode === 'CH4') {
          drawLine('#0000FF', 3, (s: SignalSample): number | undefined => s.signal4);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.alarmThreshold4);
          drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.limitDown4);
        }
      }
    }
    else {
      drawLine('#0000FF', 3, (s: SignalSample): number | undefined => s.signal);
      drawLine('#FF0000', 2, (s: SignalSample): number | undefined => s.alarmThreshold);
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text('显示点数').fontSize(12).fontColor('#333')
          Slider({ value: this.displayCountLocal, min: 30, max: this.vm.getMaxDisplayCount() })
            .layoutWeight(1)
            .onChange((val: number) => {
              this.displayCountLocal = val;
              this.vm.setDisplayCount(val);
            })
          Text(this.displayCountLocal.toFixed(0)).fontSize(12).fontColor('#333').width(30).textAlign(TextAlign.End)
        }.layoutWeight(1).padding({ right: 8 })

        Row() {
          Text('速率(ms)').fontSize(12).fontColor('#333')
          Slider({ value: this.waveIntervalLocal, min: 20, max: 1000 })
            .layoutWeight(1)
            .onChange((val: number) => {
              this.waveIntervalLocal = val;
              if (this.waveIntervalDebounceTimer) clearTimeout(this.waveIntervalDebounceTimer);
              this.waveIntervalDebounceTimer = setTimeout(() => {
                if (this.hostVm) this.hostVm.setWaveIntervalMs(val);
              }, 300);
            })
          Text(this.waveIntervalLocal.toFixed(0)).fontSize(12).fontColor('#333').width(30).textAlign(TextAlign.End)
        }.layoutWeight(1).padding({ left: 8 })
      }.height(40).width('100%').padding({ left: 8, right: 8 })

      Canvas(this.context)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
        // ⭐ 修复核心：移除明确的 LengthAreaInfo 强类型声明，依靠 ArkUI 基础组件回调自动推断类型
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.canvasWidth = newValue.width as number;
          this.canvasHeight = newValue.height as number;
          this.isGridCached = false;
        })
        .onReady(() => {
          this.draw();
        })
    }
    .width('100%')
    .height('100%')
  }
}