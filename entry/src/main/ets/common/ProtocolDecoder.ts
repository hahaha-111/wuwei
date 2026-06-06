import { util } from '@kit.ArkTS';
import {
  DecodedCommand,
  CommandPayload,
  StatusPayload,
  SensitivityPayload,
  DeviceTimePayload,
  ChannelPayload,
  DeviceNamePayload,
  AlarmThresholdPayload,
  FiberDataPayload,
  TempHumidityPayload,
  VoltagePayload,
  CalibrateSignalPayload,
  ConfigValuePayload,
  VersionPayload,
  ConfigSubtype
} from './protocol/ProtocolTypes';

type ParserFunction = (bytes: Uint8Array) => CommandPayload | null;

export class ProtocolDecoder {
  private static parsers: Map<number, { desc: string, fn: ParserFunction }> = new Map();

  static {
    ProtocolDecoder.register(0x0B, '设备状态', ProtocolDecoder.parseStatus);
    ProtocolDecoder.register(0x01, '校准信号', ProtocolDecoder.parseCalibrateSignal);
    ProtocolDecoder.register(0x19, '时间/阈值', ProtocolDecoder.parseCmd19Dynamic);
    ProtocolDecoder.register(0x15, '设备时间', ProtocolDecoder.parseDeviceTime);
    ProtocolDecoder.register(0x0D, '设备通道', ProtocolDecoder.parseChannel);
    ProtocolDecoder.register(0x03, '设备名称', ProtocolDecoder.parseDeviceName);
    ProtocolDecoder.register(0x05, '设置报警阈值', ProtocolDecoder.parseAlarmThreshold);
    ProtocolDecoder.register(0xAA, '光纤数据', ProtocolDecoder.parseFiberData);
    ProtocolDecoder.register(0x96, '温湿度', ProtocolDecoder.parseTempHumidity);
    ProtocolDecoder.register(0x97, '电压', ProtocolDecoder.parseVoltage);
    ProtocolDecoder.register(0x58, '设备版本', ProtocolDecoder.parseVersion);

    ProtocolDecoder.register(0x11, '报警持续时间', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('duration', b));
    ProtocolDecoder.register(0x42, '算法开关', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('algoSwitch', b));
    ProtocolDecoder.register(0x4E, '过滤开关', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('filterSwitch', b));
    ProtocolDecoder.register(0x46, '阈值算法', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('thresholdAlgo', b));
    ProtocolDecoder.register(0x4A, '算法时间', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('algoTime', b));
    ProtocolDecoder.register(0x4C, '过滤时间', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('filterTime', b));
    ProtocolDecoder.register(0x44, '算法选择', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('algoSelection', b));
    ProtocolDecoder.register(0x79, '通信方式', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('commMode', b));
    ProtocolDecoder.register(0x50, '心跳间隔', (b: Uint8Array) => ProtocolDecoder.parseOneByteConfig('heartbeat', b));
    ProtocolDecoder.register(0x0F, '报警因子', (b: Uint8Array) => ProtocolDecoder.parseLittleEndianConfig('alarmFactor', b));
    ProtocolDecoder.register(0x48, '因子算法', (b: Uint8Array) => ProtocolDecoder.parseTwoByteConfig('factorAlgo', b));
  }

  private static register(cmd: number, desc: string, fn: ParserFunction): void {
    ProtocolDecoder.parsers.set(cmd, { desc: desc, fn: fn });
  }

  /**
   * 从 0xFF BLE 合并帧中提取子帧原始字节数组
   * 子帧格式: C9 <len> <cmd> <payload...> <checksum>
   * 返回完整的子帧字节（含 cmd + payload + checksum），可直接喂给 decode()
   */
  public static parseMergeFrames(data: Uint8Array): Uint8Array[] {
    const results: Uint8Array[] = [];
    if (!data || data.length < 2) return results;
    const payload = data.slice(1); // 跳过 cmd=0xFF
    let i = 0;
    while (i < payload.length) {
      if (payload[i] === 0xC9 && i + 2 <= payload.length) {
        const subLen = payload[i + 1];
        const subStart = i + 2;
        const subEnd = subStart + subLen;
        if (subEnd <= payload.length) {
          results.push(payload.slice(subStart, subEnd));
          i = subEnd;
          continue;
        }
      }
      i++;
    }
    if (results.length > 0) {
      console.info('ProtocolDecoder', `parseMergeFrames: ${results.length} sub-frames from 0xFF merge`);
    }
    return results;
  }

  public static decode(deviceType: number, data: Uint8Array): DecodedCommand | null {
    if (!data || data.length === 0) return null;
    const cmd: number = data[0];
    const payloadBytes: Uint8Array = data.slice(1);
    if (deviceType === -9999) return null;


    const parser = ProtocolDecoder.parsers.get(cmd);
    if (parser) {
      return { cmd: cmd, description: parser.desc, payload: parser.fn(payloadBytes) };
    }

    if (ProtocolDecoder.isSuccessCommand(cmd)) return { cmd: cmd, description: '设置成功', payload: null };
    return { cmd: cmd, description: '未知命令', payload: payloadBytes };
  }

  private static parseCmd19Dynamic(bytes: Uint8Array): CommandPayload {
    if (bytes.length >= 6) return ProtocolDecoder.parseDeviceTime(bytes);
    return ProtocolDecoder.parseSensitivity(bytes);
  }

  private static parseStatus(bytes: Uint8Array): StatusPayload {
    const statusByte: number = bytes.length > 0 ? bytes[0] : 0;
    const signal: number = bytes.length > 1 ? bytes[1] : 0;
    const alarmThreshold: number = bytes.length > 2 ? bytes[2] : 0;
    const bits: string = statusByte.toString(2).padStart(8, '0');
    return { type: 'status', statusRaw: statusByte, binary: bits, alarm: ((statusByte >> 2) & 0x01) === 0, tamper: ((statusByte >> 1) & 0x01) === 0, signal: signal, alarmThreshold: alarmThreshold };
  }

  private static parseFiberData(bytes: Uint8Array): FiberDataPayload {
    const channel = bytes.length > 0 ? bytes[0] : 0;
    let f1=0, f2=0, f3=0, f4=0;
    let up1=0, up2=0, up3=0, up4=0;
    let dn1=0, dn2=0, dn3=0, dn4=0;
    let sens1=0, sens2=0, sens3=0, sens4=0;
    let status=0;

    if (bytes.length >= 14) {
      f1 = bytes[1]; f2 = bytes[2]; f3 = bytes[3]; f4 = bytes[4];
      dn1 = bytes[5]; dn2 = bytes[6]; dn3 = bytes[7]; dn4 = bytes[8];
      sens1 = bytes[9]; sens2 = bytes[10]; sens3 = bytes[11]; sens4 = bytes[12];
      status = bytes[13]; // 对应数组第14位，正好是报警状态字节 80

      up1 = Math.min(255, dn1 + sens1 * 2);
      up2 = Math.min(255, dn2 + sens2 * 2);
      up3 = Math.min(255, dn3 + sens3 * 2);
      up4 = Math.min(255, dn4 + sens4 * 2);
    }
    else if (bytes.length >= 8) {
      f1 = bytes[1]; f2 = bytes[2];
      up1 = bytes[3]; up2 = bytes[4];
      dn1 = bytes[5]; dn2 = bytes[6];
      status = bytes[7];
      sens1 = Math.round((up1 - dn1) / 2);
      sens2 = Math.round((up2 - dn2) / 2);
    }

    return {
      type: 'fiber', channel,
      fiber1Signal: f1, fiber2Signal: f2, fiber3Signal: f3, fiber4Signal: f4,
      fiber1Up: up1, fiber2Up: up2, fiber3Up: up3, fiber4Up: up4,
      fiber1Down: dn1, fiber2Down: dn2, fiber3Down: dn3, fiber4Down: dn4,
      fiber1Sens: sens1, fiber2Sens: sens2, fiber3Sens: sens3, fiber4Sens: sens4,

      // ⭐ 修复报警判定位：基于真实的设备状态位 (0x80 -> 光纤1, 0x40 -> 光纤2)
      alarm1: (status & 0x80) !== 0,
      alarm2: (status & 0x40) !== 0,
      alarm3: (status & 0x20) !== 0,
      alarm4: (status & 0x10) !== 0,
      disconnect: (status & 0x08) !== 0,
      tamper: (status & 0x04) !== 0
    };
  }

  private static bcdToDec(hexVal: number): number {
    return parseInt(hexVal.toString(16), 10) || 0;
  }

  private static parseDeviceTime(bytes: Uint8Array): DeviceTimePayload {
    return {
      type: 'time',
      year: 2000 + ProtocolDecoder.bcdToDec(bytes[0] || 0),
      month: ProtocolDecoder.bcdToDec(bytes[1] || 1),
      day: ProtocolDecoder.bcdToDec(bytes[2] || 1),
      hour: ProtocolDecoder.bcdToDec(bytes[3] || 0),
      minute: ProtocolDecoder.bcdToDec(bytes[4] || 0),
      second: ProtocolDecoder.bcdToDec(bytes[5] || 0),
      week: 0
    };
  }

  private static parseTempHumidity(bytes: Uint8Array): TempHumidityPayload {
    if (bytes.length < 4) return { type: 'tempHumidity', humidity: 0, temperature: 0 };
    let humidity = ((bytes[0] << 8) | bytes[1]) / 10.0;
    let tempRaw = (bytes[2] << 8) | bytes[3];
    if (tempRaw > 6000) tempRaw -= 65535;
    let temperature = tempRaw / 10.0;
    return { type: 'tempHumidity', humidity: Math.round(humidity * 10) / 10, temperature: Math.round(temperature * 10) / 10 };
  }

  private static parseVoltage(bytes: Uint8Array): VoltagePayload {
    if (bytes.length < 3) {
      return { type: 'voltage', mcuVoltage: 0, highFreqVoltage: 0, inputVoltage: 0 };
    }
    let mcuVoltage = Math.round((bytes[0] / 255.0 * 5.0) * 100) / 100;
    let highFreqVoltage = Math.round((bytes[1] / 255.0 * 5.0) * 100) / 100;
    let inputRaw = bytes[2] / 255.0 * 5.0;
    let inputVoltage = Math.round((inputRaw * 11) * 100) / 100;
    return { type: 'voltage', mcuVoltage, highFreqVoltage, inputVoltage };
  }
  private static parseCalibrateSignal(bytes: Uint8Array): CalibrateSignalPayload { return { type: 'calibrateSignal', signal: bytes.length > 0 ? bytes[0] : 0 }; }
  private static parseSensitivity(bytes: Uint8Array): SensitivityPayload { return { type: 'sensitivity', sensitivity: bytes.length > 0 ? bytes[0] : 0 }; }
  private static parseChannel(bytes: Uint8Array): ChannelPayload { return { type: 'channel', channel: bytes.length > 0 ? bytes[0] : 0 }; }

  private static parseDeviceName(bytes: Uint8Array): DeviceNamePayload {
    let name = '';
    let isConfigured = false;
    let deviceIdStr = '';

    if (bytes.length > 1) {
      let hexStr = Array.from(bytes).map(b => b.toString(16).padStart(2, '0').toUpperCase()).join('');
      deviceIdStr = hexStr.replace(/F/g, '');
      if (deviceIdStr.startsWith('0')) {
        deviceIdStr = deviceIdStr.substring(1);
      }
      name = deviceIdStr;

      let nameBytes = bytes.length >= 11 ? bytes.slice(1, 11) : bytes.slice(1);
      isConfigured = !nameBytes.every(b => b === 0xFF);
    }
    return { type: 'name', name: name || '[未命名]', deviceIdHex: deviceIdStr, isConfigured: isConfigured };
  }

  private static parseAlarmThreshold(bytes: Uint8Array): AlarmThresholdPayload { return { type: 'alarmThreshold', threshold: bytes.length > 0 ? bytes[0] : 0 }; }
  private static parseVersion(bytes: Uint8Array): VersionPayload { let ver = '1.0'; if (bytes.length >= 2) ver = `${bytes[0]}.${bytes[1]}`; else if (bytes.length === 1) ver = `${bytes[0]}`; return { type: 'version', version: ver }; }
  private static parseOneByteConfig(subtype: ConfigSubtype, bytes: Uint8Array): ConfigValuePayload { return { type: 'configValue', subtype: subtype, value: bytes.length > 0 ? bytes[0] : 0 }; }
  private static parseTwoByteConfig(subtype: ConfigSubtype, bytes: Uint8Array): ConfigValuePayload { return { type: 'configValue', subtype: subtype, value: bytes.length >= 2 ? (bytes[0] << 8) | bytes[1] : (bytes.length > 0 ? bytes[0] : 0) }; }
  private static parseLittleEndianConfig(subtype: ConfigSubtype, bytes: Uint8Array): ConfigValuePayload { return { type: 'configValue', subtype: subtype, value: bytes.length >= 2 ? (bytes[1] << 8) | bytes[0] : (bytes.length > 0 ? bytes[0] : 0) }; }
  private static isSuccessCommand(cmd: number): boolean { return [0x1D, 0x23, 0x3D, 0x07, 0x2D, 0x37, 0x47, 0x49, 0x4B, 0x4D, 0x7A, 0x2B].includes(cmd); }
}