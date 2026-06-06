export interface CommandPayload {
  type: string;
}

export interface StatusPayload extends CommandPayload {
  type: 'status';
  statusRaw: number;
  binary: string;
  alarm: boolean;
  tamper: boolean;
  signal: number;
  alarmThreshold: number;
}

// ⭐ 扩充：加入底层直接解析好的灵敏度字段
export interface FiberDataPayload extends CommandPayload {
  type: 'fiber';
  channel: number;
  fiber1Signal: number;
  fiber2Signal: number;
  fiber3Signal?: number;
  fiber4Signal?: number;
  fiber1Up: number;
  fiber2Up: number;
  fiber3Up?: number;
  fiber4Up?: number;
  fiber1Down: number;
  fiber2Down: number;
  fiber3Down?: number;
  fiber4Down?: number;
  fiber1Sens: number;    // ⭐ 灵敏度直接取自报文
  fiber2Sens: number;
  fiber3Sens?: number;
  fiber4Sens?: number;
  alarm1: boolean;
  alarm2: boolean;
  alarm3?: boolean;
  alarm4?: boolean;
  disconnect: boolean;
  tamper: boolean;
}

export interface TempHumidityPayload extends CommandPayload {
  type: 'tempHumidity';
  humidity: number;
  temperature: number;
}

export interface VoltagePayload extends CommandPayload {
  type: 'voltage';
  mcuVoltage: number;
  highFreqVoltage: number;
  inputVoltage: number;
}

export interface SensitivityPayload extends CommandPayload {
  type: 'sensitivity';
  sensitivity: number;
}

export interface DeviceTimePayload extends CommandPayload {
  type: 'time';
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  week: number;
}

export interface ChannelPayload extends CommandPayload {
  type: 'channel';
  channel: number;
}

export interface DeviceNamePayload extends CommandPayload {
  type: 'name';
  name: string;
  deviceIdHex: string;
  isConfigured: boolean;
}

export interface AlarmThresholdPayload extends CommandPayload {
  type: 'alarmThreshold';
  threshold: number;
}

export interface CalibrateSignalPayload extends CommandPayload {
  type: 'calibrateSignal';
  signal: number;
}

export type ConfigSubtype =
  | 'duration'
    | 'alarmFactor'
    | 'lockId'
    | 'thresholdAlgo'
    | 'factorAlgo'
    | 'algoTime'
    | 'filterTime'
    | 'algoSwitch'
    | 'filterSwitch'
    | 'heartbeat'
    | 'algoSelection'
    | 'commMode';

export interface ConfigValuePayload extends CommandPayload {
  type: 'configValue';
  subtype: ConfigSubtype;
  value: number;
}

export interface VersionPayload extends CommandPayload {
  type: 'version';
  version: string;
}

export interface DecodedCommand {
  cmd: number;
  description: string;
  payload: CommandPayload | Uint8Array | null;
}