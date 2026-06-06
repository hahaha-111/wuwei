import { StatusPayload, FiberDataPayload } from '../common/protocol/ProtocolTypes';

export interface SignalSample {
  signal?: number;           // 微波信号 / 光纤 CH1
  alarmThreshold?: number;   // 微波阈值 / 光纤 CH1 上限
  limitDown1?: number;       // 光纤 CH1 下限

  signal2?: number;          // 光纤 CH2
  alarmThreshold2?: number;  // 光纤 CH2 上限
  limitDown2?: number;       // 光纤 CH2 下限

  signal3?: number;          // 光纤 CH3
  alarmThreshold3?: number;  // 光纤 CH3 上限
  limitDown3?: number;       // 光纤 CH3 下限

  signal4?: number;          // 光纤 CH4
  alarmThreshold4?: number;  // 光纤 CH4 上限
  limitDown4?: number;       // 光纤 CH4 下限

  temperature?: number;      // 发射端温度
  humidity?: number;         // 发射端湿度
  voltage?: number;          // 发射端电压（输入电压VIN）
  mcuVoltage?: number;       // 发射端MCU电压
  highFreqVoltage?: number;  // 发射端高频电压
}

export class SignalBoardViewModel {
  private buffer: SignalSample[] = [];
  private readonly maxBufferSize: number = 2000;
  private readonly maxDisplayCount: number = 300;
  private displayCount: number = 60;
  private lastTxSample: SignalSample = { temperature: 0, humidity: 0, voltage: 0, mcuVoltage: 0, highFreqVoltage: 0 };

  pushStatus(s: StatusPayload): void {
    this.buffer.push({ signal: s.signal, alarmThreshold: s.alarmThreshold });
    this.trimBuffer();
  }

  pushFiber(f: FiberDataPayload): void {
    this.buffer.push({
      signal: f.fiber1Signal,
      signal2: f.fiber2Signal,
      signal3: f.fiber3Signal,
      signal4: f.fiber4Signal,
      alarmThreshold: f.fiber1Up,
      limitDown1: f.fiber1Down,
      alarmThreshold2: f.fiber2Up,
      limitDown2: f.fiber2Down,
      alarmThreshold3: f.fiber3Up,
      limitDown3: f.fiber3Down,
      alarmThreshold4: f.fiber4Up,
      limitDown4: f.fiber4Down,
    });
    this.trimBuffer();
  }

  pushTempHum(temp: number, hum: number): void {
    this.lastTxSample.temperature = temp;
    this.lastTxSample.humidity = hum;
    this.buffer.push({ ...this.lastTxSample });
    this.trimBuffer();
  }

  pushVoltages(mcuVol: number, hfVol: number, inputVol: number): void {
    this.lastTxSample.mcuVoltage = mcuVol;
    this.lastTxSample.highFreqVoltage = hfVol;
    this.lastTxSample.voltage = inputVol;
    this.buffer.push({ ...this.lastTxSample });
    this.trimBuffer();
  }

  private trimBuffer(): void {
    if (this.buffer.length > this.maxBufferSize) {
      this.buffer.shift();
    }
  }

  setDisplayCount(n: number): void {
    let val = Math.floor(n);
    if (val < 30) val = 30;
    if (val > this.maxDisplayCount) val = this.maxDisplayCount;
    this.displayCount = val;
  }

  getDisplayCount(): number { return this.displayCount; }
  getMaxDisplayCount(): number { return this.maxDisplayCount; }

  getVisibleSamples(): SignalSample[] {
    const len = this.buffer.length;
    if (len === 0) return [];
    return this.buffer.slice(Math.max(0, len - this.displayCount), len);
  }

  getBufferSnapshot(count?: number): SignalSample[] {
    if (count === undefined || count >= this.buffer.length) return [...this.buffer];
    return this.buffer.slice(this.buffer.length - count);
  }

  clearBuffer(): void {
    this.buffer = [];
  }
}