import { common } from '@kit.AbilityKit';
import { ProtocolFrame, DeviceType, ProtocolParser } from '../common/ProtocolParser';
import { UIContext, router } from '@kit.ArkUI'; 
import { TransportManager } from '../common/transport/TransportManager';
import { ITransport } from '../common/transport/ITransport';
import { LogManager } from '../common/database/LogManager';
import { LogCategory } from '../common/database/LogEntity';
import { FileUtil } from '../common/utils/FileUtil';

export type AlarmLevel = 'high' | 'medium' | 'low';

enum ProtocolVersion {
  UNKNOWN = 0,
  OLD = 1,
  NEW = 2
}

export interface AlarmRecord {
  id: number;
  displayId: string;
  timeText: string;
  channel: string;
  triggerSignal: number;
  threshold: number;
  maxSignal: number;
  level: AlarmLevel;
  levelText: string;
  exported: boolean;
  alarmType: string;
  durationText: string;
  deviceId: string;
  hasWaveform: boolean;
}

// ⭐ 已删除死代码 AlarmPageParams 和 MonitorPageParams 的引入

interface AlarmLogState {
  alarmCount?: number;
  waveCount?: number;
}

@Observed
export class AlarmRecordViewModel {
  alarmList: Array<AlarmRecord> = [];
  selectedIndex: number = -1;
  selectedWaveform: Array<number> = [];

  playbackThreshold: number = 0;
  playbackSens: number = 0;
  waveDrawTrigger: number = 0;

  private waveChangeCallback?: () => void;

  tipText: string = '正在初始化...';

  deviceNameDisplay: string = '未知设备';
  currentSystemTime: string = '--:--:--';

  public totalAlarmCount: number = 0;
  public waveTotalCount: number = 0;

  public context: common.UIAbilityContext | null = null;
  public uiContext: UIContext | null = null;
  public deviceNameForExport: string = 'UnknownDevice';

  public connectionMode: 'BLE' | 'TCP' = 'BLE';
  public deviceType: DeviceType = DeviceType.Microwave;
  public currentDeviceAddress: number = 0x01;

  private protocolVersion: ProtocolVersion = ProtocolVersion.UNKNOWN;
  private queryTimer: number = 0;
  private waveQueryTimer: number = 0;
  private sysTimeTimer: number = 0;

  private isReadingRecords: boolean = false;
  private currentReadIndex: number = 0;
  private lastReadCount: number = -1;

  private recordReadTimer: number = 0;
  private recordRetryCount: number = 0;

  private protocolParser: ProtocolParser = new ProtocolParser();
  private transport: ITransport;

  private static logCache: Map<string, AlarmLogState> = new Map<string, AlarmLogState>();

  private readonly LISTENER_KEY = 'AlarmRecordVM';

  constructor() {
    this.transport = TransportManager.getInstance().getTransport();
  }

  private showToastMsg(msg: string): void {
    if (this.uiContext) {
      try {
        this.uiContext.getPromptAction().showToast({ message: msg });
      } catch (e) {
        // ignore
      }
    }
  }

  setOnWaveChange(cb: () => void): void {
    this.waveChangeCallback = cb;
  }

  private getLogState(): AlarmLogState {
    const id = this.transport.getId() || 'temp_session';
    if (!AlarmRecordViewModel.logCache.has(id)) {
      AlarmRecordViewModel.logCache.set(id, {});
    }
    return AlarmRecordViewModel.logCache.get(id)!;
  }

  private clearLogState(): void {
    const id = this.transport.getId();
    if (id && AlarmRecordViewModel.logCache.has(id)) {
      AlarmRecordViewModel.logCache.delete(id);
    }
  }

  private resetLogStateField(field: keyof AlarmLogState): void {
    const state = this.getLogState();
    if (field === 'alarmCount') {
      state.alarmCount = undefined;
    } else if (field === 'waveCount') {
      state.waveCount = undefined;
    }
  }

  init(params: Record<string, Object> | undefined, ctx: common.UIAbilityContext): void {
    this.context = ctx;
    LogManager.getInstance().init(ctx);

    const globalMode = AppStorage.get<string>('GlobalConnectionMode');
    const globalType = AppStorage.get<DeviceType>('GlobalDeviceType');
    if (globalMode) this.connectionMode = globalMode === 'TCP' ? 'TCP' : 'BLE';
    if (globalType !== undefined) this.deviceType = globalType;

    if (params) {
      if (params['connectionMode']) this.connectionMode = params['connectionMode'] as ('BLE' | 'TCP');
      if (params['deviceType'] !== undefined) this.deviceType = params['deviceType'] as number;
      if (params['deviceAddress'] !== undefined) {
        this.currentDeviceAddress = params['deviceAddress'] as number;
      }

      if (params['deviceName']) {
        const dName = params['deviceName'] as string;
        if (dName.trim() !== '') {
          this.deviceNameDisplay = dName;
          this.deviceNameForExport = dName;
        }
      }
    }

    this.transport = TransportManager.getInstance().getTransport();

    if (this.deviceNameDisplay === '未知设备' || this.deviceNameDisplay === '[未命名]') {
      this.deviceNameDisplay = "未命名";
      this.deviceNameForExport = "UnnamedDevice";
    }

    this.registerCallbacks();
    this.startQueryLoop();
    this.startWaveCountLoop();
    this.startSystemTimeTimer();
  }

  onDisappear(): void {
    this.stopQueryLoop();
    this.stopWaveCountLoop();
    this.stopSystemTimeTimer();
    
    if (this.recordReadTimer) clearTimeout(this.recordReadTimer);

    this.transport.offDataReceived(this.LISTENER_KEY);
    this.transport.offStateChange(this.LISTENER_KEY);
  }

  getRecordIndexByDate(date: Date): number {
    if (!this.alarmList || this.alarmList.length === 0) return -1;
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const targetDateStr = `${year}/${month}/${day}`;
    return this.alarmList.findIndex(record => record.timeText.startsWith(targetDateStr));
  }

  private registerCallbacks(): void {
    this.transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array) => {
      const frames = this.protocolParser.feed(data);
      frames.forEach(frame => this.handleFrame(frame));
    });

    this.transport.setOnStateChange(this.LISTENER_KEY, (state) => {
      if (state === 'DISCONNECTED') {
        this.clearLogState();
      }
    });
  }

  private startSystemTimeTimer(): void {
    this.stopSystemTimeTimer();
    this.updateSystemTime();
    this.sysTimeTimer = setInterval((): void => {
      this.updateSystemTime();
    }, 1000);
  }

  private stopSystemTimeTimer(): void {
    if (this.sysTimeTimer) { clearInterval(this.sysTimeTimer); this.sysTimeTimer = 0; }
  }

  private updateSystemTime(): void {
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    this.currentSystemTime = `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
  }

  private startQueryLoop(): void {
    this.stopQueryLoop();
    this.queryTimer = setInterval((): void => {
      if (this.isReadingRecords) return;
      this.sendQueryCommand();
    }, 1000);
  }

  private stopQueryLoop(): void {
    if (this.queryTimer) { clearInterval(this.queryTimer); this.queryTimer = 0; }
  }

  private startWaveCountLoop(): void {
    this.stopWaveCountLoop();
    this.waveQueryTimer = setInterval((): void => {
      this.sendWaveCountQuery();
    }, 1000); 
  }

  private stopWaveCountLoop(): void {
    if (this.waveQueryTimer) { clearInterval(this.waveQueryTimer); this.waveQueryTimer = 0; }
  }

  private sendWaveCountQuery(): void {
    if (this.deviceType === DeviceType.Microwave) {
      this.sendHexCommand(0x01, 0xC9, 0x01, 0x6C, []);
    } else {
      this.sendHexCommand(this.currentDeviceAddress, 0x66, 0x01, 0x6C, []);
    }
  }

  private sendQueryCommand(): void {
    if (this.deviceType === DeviceType.Microwave) {
      if (this.protocolVersion === ProtocolVersion.UNKNOWN) {
        this.sendHexCommand(0x01, 0xC9, 0x02, 0x6B, [0x03]);
      } else if (this.protocolVersion === ProtocolVersion.NEW) {
        this.sendHexCommand(0x01, 0xC9, 0x02, 0x6B, [0x03]);
      } else {
        this.sendHexCommand(0x01, 0xC9, 0x02, 0x6A, [0x03]);
      }
    } else {
      this.sendHexCommand(this.currentDeviceAddress, 0x66, 0x01, 0x6B, []);
    }
  }

  private parseDeviceTime(yearByte: number, monthByte: number, dayByte: number, hourByte: number, minuteByte: number, secondByte: number): string {
    const hasHexChar = (b: number) => (b & 0x0F) > 9 || (b >> 4) > 9;
    let isHexMode = false;

    if (hasHexChar(yearByte) || hasHexChar(monthByte) || hasHexChar(dayByte) ||
        hasHexChar(hourByte) || hasHexChar(minuteByte) || hasHexChar(secondByte)) {
      isHexMode = true;
    } else {
      const hexYear = yearByte;
      const bcdYear = parseInt(yearByte.toString(16), 10);
      const currentYear = new Date().getFullYear() % 100;
      const hexReasonable = hexYear <= currentYear + 1;
      const bcdReasonable = bcdYear <= currentYear + 1;

      if (hexReasonable && !bcdReasonable) {
        isHexMode = true;
      } else if (!hexReasonable && bcdReasonable) {
        isHexMode = false;
      } else {
        isHexMode = Math.abs(currentYear - hexYear) < Math.abs(currentYear - bcdYear);
      }
    }

    const format = (val: number, max: number, useHex: boolean) => {
      if (useHex) {
        if (val > max) return val.toString(16).padStart(2, '0');
        return val.toString(10).padStart(2, '0');
      } else {
        return val.toString(16).padStart(2, '0');
      }
    };

    const y = format(yearByte, 99, isHexMode);
    const m = format(monthByte, 12, isHexMode);
    const d = format(dayByte, 31, isHexMode);
    const h = format(hourByte, 23, isHexMode);
    const min = format(minuteByte, 59, isHexMode);
    const s = secondByte.toString(16).padStart(2, '0');

    return `20${y}/${m}/${d} ${h}:${min}:${s}`;
  }

  private handleFrame(frame: ProtocolFrame): void {
    const raw = frame.raw;
    if (raw.length < 5) return;
    const cmd = raw[4];

    if (cmd === 0x6A) {
      this.protocolVersion = ProtocolVersion.OLD;
      this.handleAlarmCount(raw[5]);
    } else if (cmd === 0x6B) {
      this.protocolVersion = ProtocolVersion.NEW;
      let count = 0;
      if (raw.length >= 7) count = (raw[5] << 8) | raw[6];
      else count = raw[5];
      this.handleAlarmCount(count);
    } else if (cmd === 0x6D || cmd === 0x6E) {
      this.parseOneRecord(raw);
    }
    else if (cmd === 0x6C) {
      const count = raw[5];
      if (this.waveTotalCount !== count) {
        this.waveTotalCount = count;
        const logState = this.getLogState();
        if (logState.waveCount !== count) {
          logState.waveCount = count;
          LogManager.getInstance().addLog(
            LogCategory.QUERY,
            '查询波形条数',
            `设备当前波形记录数: ${count}`,
            { name: this.deviceNameDisplay, id: this.transport.getId() || '-' }
          );
        }
      }
    }
    else if (cmd === 0x73) {
      this.parseWaveformPlayback(frame.data);
    }
    else if (cmd === 0x70) {
      this.tipText = '波形清除成功';
      this.waveTotalCount = 0;
      this.resetLogStateField('waveCount');
      this.selectedWaveform = [];
      this.playbackThreshold = 0;
      this.waveDrawTrigger++;
      if (this.waveChangeCallback) this.waveChangeCallback();
    }
  }

  private parseWaveformPlayback(payload: Uint8Array): void {
    if (!payload || payload.length === 0) return;
    if (payload[0] !== 0x73) return;

    const len = payload.length;
    if (len < 9) {
      this.tipText = '波形数据长度不足';
      return;
    }

    const seq = payload[1];
    const timeStr = this.parseDeviceTime(payload[7], payload[6], payload[5], payload[4], payload[3], payload[2]);
    const seqStr = seq.toString(10).padStart(2, '0').toUpperCase();

    if (this.deviceType === DeviceType.Microwave) {
      const threshold = payload[len - 1];
      this.playbackThreshold = threshold;
      const waveData = payload.slice(8, len - 1);
      this.selectedWaveform = Array.from(waveData);
      this.tipText = `第${seqStr}条 ${timeStr}  阈值: ${threshold}`;
    } else {
      const lowThreshold = payload[len - 1];
      this.playbackThreshold = lowThreshold;

      let waveCount = 55;
      if (len - 10 < 55) waveCount = len - 10;
      if (waveCount < 0) waveCount = 0;

      const waveData = payload.slice(8, 8 + waveCount);
      this.selectedWaveform = Array.from(waveData);

      let statusStr = '';
      if (len > 8 + 55) {
        let statusByte = payload[8 + 55];
        if (this.deviceType as number === 0x66) {
          statusStr = this.getFiberAlarmChannel(statusByte);
        } else {
          statusStr = this.getLaserAlarmChannel(statusByte);
        }
      }

      let devNameStr = (this.deviceType as number === 0x66) ? '光纤' : '激光';
      this.tipText = `第${seqStr}条 ${timeStr} ${devNameStr}基准: ${lowThreshold} ${statusStr ? '['+statusStr+']' : ''}`;
    }

    this.waveDrawTrigger++;
    if (this.waveChangeCallback) this.waveChangeCallback();
  }

  private handleAlarmCount(count: number): void {
    if (this.totalAlarmCount !== count) {
      this.totalAlarmCount = count;
      const logState = this.getLogState();
      if (logState.alarmCount !== count) {
        logState.alarmCount = count;
        LogManager.getInstance().addLog(
          LogCategory.QUERY,
          '查询报警条数',
          `设备当前报警记录数: ${count}`,
          { name: this.deviceNameDisplay, id: this.transport.getId() || '-' }
        );
      }
    }
    if (count > 0 && count !== this.lastReadCount && !this.isReadingRecords) {
      this.lastReadCount = count;
      this.startReadingSequence();
    } else if (count === 0 && this.alarmList.length > 0) {
      this.alarmList = [];
      this.lastReadCount = 0;
      this.tipText = '设备记录为空';
    }
  }

  private startReadingSequence(): void {
    this.isReadingRecords = true;
    this.stopQueryLoop();
    this.stopWaveCountLoop();
    this.currentReadIndex = this.totalAlarmCount;
    this.alarmList = [];
    this.tipText = `发现 ${this.totalAlarmCount} 条记录，正在下载...`;
    this.readNextRecord();
  }

  resumeReadingRecords(): void {
    if (this.isReadingRecords) {
      this.showToastMsg('正在读取中，请稍候...');
      return;
    }
    if (this.totalAlarmCount === 0) {
      this.showToastMsg('当前无报警记录可读');
      return;
    }
    if (this.alarmList.length >= this.totalAlarmCount) {
      this.showToastMsg('记录已全部加载完毕');
      return;
    }

    this.currentReadIndex = this.totalAlarmCount - this.alarmList.length;
    this.isReadingRecords = true;
    this.stopQueryLoop();
    this.stopWaveCountLoop();
    this.tipText = `正在续读剩余的 ${this.currentReadIndex} 条记录...`;
    this.recordRetryCount = 0;
    
    if (this.recordReadTimer) {
      clearTimeout(this.recordReadTimer);
    }
    this.sendRecordRequest();
  }

  private sendRecordRequest(): void {
    if (this.recordRetryCount >= 3) {
      console.warn(`AlarmVM`, `读取记录 [${this.currentReadIndex}] 超时失败，跳过`);
      this.currentReadIndex--;
      setTimeout((): void => { this.readNextRecord(); }, 20);
      return;
    }

    this.recordRetryCount++;
    const index = this.currentReadIndex;
    const addr = this.currentDeviceAddress;
    console.info('AlarmVM', `▶ 发送0x6E查询: index=${index}, 重试=${this.recordRetryCount}`);

    if (this.deviceType === DeviceType.Microwave && this.protocolVersion === ProtocolVersion.OLD) {
      this.sendHexCommand(addr, 0xC9, 0x02, 0x6D, [index]);
    } else if (this.deviceType === DeviceType.Microwave) {
      this.sendHexCommand(addr, 0xC9, 0x03, 0x6E, [(index >> 8) & 0xFF, index & 0xFF]);
    } else {
      this.sendHexCommand(addr, 0x66, 0x03, 0x6E, [(index >> 8) & 0xFF, index & 0xFF]);
    }

    if (this.recordReadTimer) {
      clearTimeout(this.recordReadTimer);
    }
    this.recordReadTimer = setTimeout((): void => {
      this.sendRecordRequest();
    }, 300);
  }

  private readNextRecord(): void {
    if (this.currentReadIndex < 1) {
      this.isReadingRecords = false;
      this.tipText = `下载完成，共 ${this.alarmList.length} 条记录`;
      if (this.recordReadTimer) clearTimeout(this.recordReadTimer);
      this.startQueryLoop();
      this.startWaveCountLoop();
      return;
    }
    this.recordRetryCount = 0;
    this.sendRecordRequest();
  }

  private getFiberAlarmChannel(state: number): string {
    const binary = state.toString(2).padStart(8, '0');
    const res: string[] = [];
    if (binary[0] === '1') res.push('光纤1');
    if (binary[1] === '1') res.push('光纤2');
    if (binary[2] === '1') res.push('光纤3');
    if (binary[3] === '1') res.push('光纤4');
    if (binary[4] === '1') res.push('门磁');
    if (binary[5] === '1') res.push('防剪');
    if (binary[6] === '1') res.push('输入1');
    if (binary[7] === '1') res.push('输入2');
    return res.length > 0 ? res.join('/') : `状态(${state})`;
  }

  private getLaserAlarmChannel(state: number): string {
    const binary = state.toString(2).padStart(8, '0');
    const res: string[] = [];
    if (binary[0] === '1') res.push('激光1');
    if (binary[1] === '1') res.push('激光2');
    if (binary[2] === '1') res.push('激光3');
    if (binary[3] === '1') res.push('输入1');
    if (binary[4] === '1') res.push('输入2');
    if (binary[5] === '1') res.push('输入3');
    if (binary[6] === '1') res.push('输入4');
    if (binary[7] === '1') res.push('错误');
    return res.length > 0 ? res.join('/') : `状态(${state})`;
  }

  private parseOneRecord(raw: Uint8Array): void {
    if (!this.isReadingRecords) return;

    try {
      const cmd = raw[4];
      const rawHex = Array.from(raw).map(b => b.toString(16).padStart(2, '0').toUpperCase()).join(' ');
      console.info('AlarmVM', `📦 0x6E响应帧: ${rawHex}`);

      const offset = (cmd === 0x6E) ? 1 : 0;

      let currentPacketId = -1;
      if (this.deviceType === DeviceType.Microwave && cmd === 0x6E && raw[3] === 0x0D) {
        currentPacketId = raw[5];
      } else {
        currentPacketId = (cmd === 0x6E) ? ((raw[5] << 8) | raw[6]) : raw[5];
      }

      const expectedId16 = this.currentReadIndex;
      const expectedId8 = this.currentReadIndex & 0xFF; 

      if (currentPacketId !== expectedId16 && currentPacketId !== expectedId8 && currentPacketId !== 0xFF) {
        console.warn('AlarmVM', `⏭ 拦截幽灵重复包 (期待ID:${expectedId16}, 实际收到:${currentPacketId})`);
        return; 
      }

      if (this.recordReadTimer) {
        clearTimeout(this.recordReadTimer);
        this.recordReadTimer = 0;
      }

      if (this.deviceType === DeviceType.Microwave && cmd === 0x6E && raw[3] === 0x0D) {
        if (raw.length < 18) {
          this.currentReadIndex--;
          setTimeout((): void => { this.readNextRecord(); }, 20); 
          return;
        }

        if (currentPacketId === 0xFF) {
          console.info('AlarmVM', `⏭ 跳过空记录 index=${this.currentReadIndex} id=0xFF`);
          this.currentReadIndex--;
          setTimeout((): void => { this.readNextRecord(); }, 20);
          return;
        }

        const year = raw[6].toString().padStart(2, '0');
        const month = raw[7].toString().padStart(2, '0');
        const day = raw[8].toString().padStart(2, '0');
        const hour = raw[9].toString().padStart(2, '0');
        const minute = raw[10].toString().padStart(2, '0');
        const second = raw[11].toString().padStart(2, '0');
        const adc_in = raw[13];
        const adc_vcc = raw[14];

        const timeStr = `20${year}/${month}/${day} ${hour}:${minute}:${second}`;

        const record: AlarmRecord = {
          id: currentPacketId,
          displayId: this.pad3(currentPacketId),
          timeText: timeStr,
          channel: `VIN:${adc_in} MCU:${adc_vcc}`,
          triggerSignal: adc_in,
          threshold: 0,
          maxSignal: adc_vcc,
          level: 'medium',
          levelText: '中',
          exported: false,
          alarmType: '电压波动报警',
          durationText: '-',
          deviceId: this.toHex(this.currentDeviceAddress),
          hasWaveform: false
        };

        this.alarmList.push(record);
        this.currentReadIndex--;
        setTimeout((): void => { this.readNextRecord(); }, 20);
        return;
      }

      if (raw.length < 17 + offset) {
        this.currentReadIndex--;
        setTimeout((): void => { this.readNextRecord(); }, 20);
        return;
      }

      const timeStr = this.parseDeviceTime(raw[12 + offset], raw[10 + offset], raw[9 + offset], raw[8 + offset], raw[7 + offset], raw[6 + offset]);
      const typeCode = raw[13 + offset];
      const statusOrAvg = raw[14 + offset];
      const threshold = raw[15 + offset];
      const ampVal = raw[16 + offset];

      let alarmTypeStr = '';
      let channelStr = 'CH1';
      let level: AlarmLevel = 'medium';
      let levelText: string = '中';

      if (this.deviceType === DeviceType.Fiber) {
        alarmTypeStr = `光纤报警`;
        channelStr = this.getFiberAlarmChannel(statusOrAvg);
        if (ampVal > threshold + 20) {
          level = 'high'; levelText = '高';
        } else {
          level = 'low'; levelText = '低';
        }
      } else if (this.deviceType === DeviceType.Laser) {
        alarmTypeStr = `激光报警`;
        channelStr = this.getLaserAlarmChannel(statusOrAvg);
        level = 'high'; levelText = '高';
      } else {
        alarmTypeStr = this.getMicrowaveAlarmType(typeCode);
        channelStr = 'CH1';
        if (typeCode === 0x00) {
          level = 'high'; levelText = '高';
        } else if (typeCode === 0xCC || typeCode === 0xC2) {
          level = 'low'; levelText = '低';
        } else {
          level = 'medium'; levelText = '中';
        }
      }

      const record: AlarmRecord = {
        id: currentPacketId,
        displayId: this.pad3(currentPacketId),
        timeText: timeStr,
        channel: channelStr,
        triggerSignal: ampVal,
        threshold: threshold,
        maxSignal: statusOrAvg,
        level: level,
        levelText: levelText,
        exported: false,
        alarmType: alarmTypeStr,
        durationText: '-',
        deviceId: this.toHex(this.currentDeviceAddress),
        hasWaveform: this.protocolVersion === ProtocolVersion.NEW
      };

      this.alarmList.push(record);
      this.currentReadIndex--;

      setTimeout((): void => {
        this.readNextRecord();
      }, 20); 

    } catch (e) {
      console.error('Parse record failed: ' + e);
      this.currentReadIndex--;
      setTimeout((): void => { this.readNextRecord(); }, 20);
    }
  }

  downloadFromDevice(): void {
    this.tipText = '重新启动查询...';
    this.lastReadCount = -1;
    this.isReadingRecords = false;
    if (this.recordReadTimer) clearTimeout(this.recordReadTimer); 
    this.protocolVersion = ProtocolVersion.UNKNOWN;
    this.sendHexCommand(0x01, 0xC9, 0x02, 0x6B, [0x03]);

    LogManager.getInstance().addLog(
      LogCategory.QUERY,
      '下载报警记录',
      '用户手动请求下载设备记录',
      { name: this.deviceNameDisplay, id: this.transport.getId() || '-' }
    );
  }

  async exportAlarmRecords(): Promise<void> {
    if (this.alarmList.length === 0) {
      this.showToastMsg('无记录可导出');
      return;
    }

    try {
      if (!this.context) return;
      let content = '\uFEFF序号,时间,类型/通道,幅值,阈值,级别,设备ID\n';
      this.alarmList.forEach(rec => {
        const safeTime = rec.timeText.replace(',', ' ');
        const typeOrChannel = (this.deviceType === DeviceType.Microwave) ? rec.alarmType : rec.channel;
        content += `${rec.displayId},${safeTime},${typeOrChannel},${rec.triggerSignal},${rec.threshold},${rec.levelText},${rec.deviceId}\n`;
      });

      const pathDir = FileUtil.getStandardPath(this.context, this.deviceNameForExport, '报警记录');
      const fileName = FileUtil.generateFileName('.csv');
      const fullPath = `${pathDir}/${fileName}`;

      await FileUtil.writeText(fullPath, content);

      this.alarmList.forEach(r => r.exported = true);
      this.showToastMsg('导出成功');
      this.tipText = `已导出至: ${fileName}`;

      LogManager.getInstance().addLog(
        LogCategory.MAINTENANCE,
        '导出报警记录',
        `成功导出 ${this.alarmList.length} 条记录至: ${fileName}`,
        { name: this.deviceNameForExport, id: this.transport.getId() || '-' }
      );

    } catch (e) {
      let msg = '';
      if (e instanceof Error) msg = e.message;
      this.showToastMsg('导出失败: ' + msg);
    }
  }

  goToRecordList(): void {
    if (this.uiContext) {
      const p: Record<string, Object> = {};
      p['deviceName'] = this.deviceNameDisplay;

      this.uiContext.getRouter().pushUrl({
        url: 'pages/RecordListPage',
        params: p
      }, router.RouterMode.Standard).catch(() => {});
    }
  }

  clearAllRecords(): void {
    this.isReadingRecords = false; 
    if (this.recordReadTimer) clearTimeout(this.recordReadTimer);

    if (this.deviceType === DeviceType.Microwave) {
      this.sendRawHex('FF01C9016F39');
    } else {
      const addrHex = this.toHex(this.currentDeviceAddress);
      this.sendRawHex(`FF${addrHex}66016FD6`);
    }
    this.alarmList = [];
    this.totalAlarmCount = 0;
    this.resetLogStateField('alarmCount');
    this.tipText = '已发送清除记录指令';

    LogManager.getInstance().addLog(
      LogCategory.MAINTENANCE,
      '清空报警记录',
      '执行清空所有历史报警指令',
      { name: this.deviceNameDisplay, id: this.transport.getId() || '-' }
    );
  }

  clearWaveform(): void {
    if (this.deviceType !== DeviceType.Microwave && this.deviceType !== DeviceType.Fiber) return;

    if (this.deviceType === DeviceType.Microwave) {
      this.sendRawHex('FF01C901703A');
    } else {
      this.sendHexCommand(this.currentDeviceAddress, 0x66, 0x01, 0x70, []);
    }

    this.waveTotalCount = 0;
    this.resetLogStateField('waveCount');
    this.selectedWaveform = [];
    this.playbackThreshold = 0;
    this.waveDrawTrigger++;
    this.tipText = '已发送清除波形指令';
    this.showToastMsg('已发送清除波形指令');
    if (this.waveChangeCallback) this.waveChangeCallback();

    LogManager.getInstance().addLog(
      LogCategory.MAINTENANCE,
      '清空波形',
      '执行清空波形数据指令',
      { name: this.deviceNameDisplay, id: this.transport.getId() || '-' }
    );
  }

  selectRecord(index: number): void {
    if (index >= 0 && index < this.alarmList.length) {
      this.selectedIndex = index;
      this.playbackSens = this.alarmList[index].threshold;
      try { this.playWaveform(index); } catch (error) {}
    }
  }

  prevWaveRecord(): void {
    if (this.alarmList.length === 0) return;
    if (this.selectedIndex <= 0) {
      this.selectedIndex = 0;
      this.showToastMsg('已经是第一条报警');
      return;
    }
    this.selectRecord(this.selectedIndex - 1);
  }

  nextWaveRecord(): void {
    if (this.alarmList.length === 0) return;
    if (this.selectedIndex < 0) { this.selectRecord(0); return; }
    if (this.selectedIndex >= this.alarmList.length - 1) {
      this.selectedIndex = this.alarmList.length - 1;
      this.showToastMsg('已经是最后一条报警');
      return;
    }
    this.selectRecord(this.selectedIndex + 1);
  }

  private playWaveform(listIndex: number): void {
    if (this.waveTotalCount <= 0) { this.tipText = '设备无波形数据'; return; }
    let targetWaveIndex = this.waveTotalCount - listIndex;
    if (targetWaveIndex <= 0) {
      targetWaveIndex = this.waveTotalCount;
      this.showToastMsg('波形记录不匹配，已加载最新波形');
    }

    if (this.deviceType === DeviceType.Microwave) {
      this.sendHexCommand(0x01, 0xC9, 0x02, 0x73, [targetWaveIndex]);
    } else {
      this.sendHexCommand(this.currentDeviceAddress, 0x66, 0x02, 0x73, [targetWaveIndex]);
    }
    this.tipText = `正在请求第 ${targetWaveIndex} 条波形...`;
  }

  private sendRawHex(hex: string): void {
    this.transport.sendHexString(hex);
  }

  private sendHexCommand(addr: number, type: number, len: number, cmd: number, data: number[]): void {
    let sum = type + len + cmd;
    for (let b of data) sum += b;
    const cs = sum & 0xFF;
    let hex = `FF${this.toHex(addr)}${this.toHex(type)}${this.toHex(len)}${this.toHex(cmd)}`;
    for (let b of data) hex += this.toHex(b);
    hex += this.toHex(cs);
    if (cmd === 0x6E) console.info('AlarmVM', `📤 发送hex: ${hex}`);
    this.sendRawHex(hex);
  }

  private toHex(n: number): string {
    return n.toString(16).padStart(2, '0').toUpperCase();
  }

  private pad3(n: number): string {
    return n.toString().padStart(3, '0');
  }

  private getMicrowaveAlarmType(code: number): string {
    switch (code) {
      case 0xCC: return '防拆报警';
      case 0xC2: return '防拆复位';
      case 0x00: return '入侵报警';
      case 0x11: return '屏蔽报警';
      case 0x22: return '拦截报警';
      case 0x33: return '警因报警';
      case 0x44: return '警阈报警';
      default: return `类型(${this.toHex(code)})`;
    }
  }
}