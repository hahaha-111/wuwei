// BleSearch.ts   蓝牙设备搜索
import { ble } from '@kit.ConnectivityKit';
import { BusinessError } from '@ohos.base';

const TAG: string = 'BleScanManager';

// 参考蓝牙标准协议规范 Core Assigned Numbers，定义各种广播字段类型
const BLE_ADV_TYPE_FLAG = 0x01;
const BLE_ADV_TYPE_16_BIT_SERVICE_UUIDS_INCOMPLETE = 0x02;
const BLE_ADV_TYPE_16_BIT_SERVICE_UUIDS_COMPLETE = 0x03;
const BLE_ADV_TYPE_32_BIT_SERVICE_UUIDS_INCOMPLETE = 0x04;
const BLE_ADV_TYPE_32_BIT_SERVICE_UUIDS_COMPLETE = 0x05;
const BLE_ADV_TYPE_128_BIT_SERVICE_UUIDS_INCOMPLETE = 0x06;
const BLE_ADV_TYPE_128_BIT_SERVICE_UUIDS_COMPLETE = 0x07;
const BLE_ADV_TYPE_LOCAL_NAME_SHORT = 0x08;
const BLE_ADV_TYPE_LOCAL_NAME_COMPLETE = 0x09;
const BLE_ADV_TYPE_TX_POWER_LEVEL = 0x0A;
const BLE_ADV_TYPE_16_BIT_SERVICE_SOLICITATION_UUIDS = 0x14;
const BLE_ADV_TYPE_128_BIT_SERVICE_SOLICITATION_UUIDS = 0x15;
const BLE_ADV_TYPE_32_BIT_SERVICE_SOLICITATION_UUIDS = 0x1F;
const BLE_ADV_TYPE_16_BIT_SERVICE_DATA = 0x16;
const BLE_ADV_TYPE_32_BIT_SERVICE_DATA = 0x20;
const BLE_ADV_TYPE_128_BIT_SERVICE_DATA = 0x21;
const BLE_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA = 0xFF;

const BLUETOOTH_UUID_16_BIT_LENGTH = 2;
const BLUETOOTH_UUID_32_BIT_LENGTH = 4;
const BLUETOOTH_UUID_128_BIT_LENGTH = 16;

const BLUETOOTH_MANUFACTURE_ID_LENGTH = 2;

/**
 * 提供给 UI 使用的简化设备信息
 * - id: 设备唯一标识（deviceId）
 * - name: 广播名称（可能为空字符串）
 * - rssi: 信号强度
 */
export interface BleDevice {
  id: string;
  name: string;
  rssi: number;
}

export class BleScanManager {
  // ✅ 这里不再使用 ble.createBleScanner()
  //    而是直接使用模块级别的 ble.startBLEScan / ble.stopBLEScan

  // UI 注册的“发现设备回调”，每发现一个设备就调用一次
  private deviceFoundCallback?: (device: BleDevice) => void;

  /**
   * 由 UI 调用，用来注册“发现设备时的回调函数”
   * 比如在 Index.ets 中：
   *   bleScanManager.setOnDeviceFoundCallback((device) => { this.devices.push(device); })
   */
  public setOnDeviceFoundCallback(callback: (device: BleDevice) => void): void {
    this.deviceFoundCallback = callback;
  }

  /**
   * 扫描结果上报回调（注册给 ble.on('BLEDeviceFind', ...)）
   *
   * ✅ 注意：这里的参数类型改为 Array<ble.ScanResult>
   *    对应文档中 Callback<Array<ScanResult>> 的定义
   */
  onReceiveEvent = (results: Array<ble.ScanResult>) => {
    // console.info(TAG, 'BLE scan device find result: ' + JSON.stringify(results));
    if (!results || results.length === 0) {
      // 本次上报没有任何设备，直接返回
      return;
    }

    // 遍历本次上报中的所有设备结果
    for (const result of results) {
      // console.info(TAG, 'BLE scan result: ' + result.deviceId + ', rssi: ' + result.rssi);

      // 解析广播，尝试从 adv data 中解析出 localName（设备名）
      const localNameFromAdv: string = this.parseScanResult(result.data);

      // 如果 ScanResult 本身已经带 deviceName，优先用它
      const name: string = (result.deviceName && result.deviceName.length > 0)
        ? result.deviceName
        : localNameFromAdv;

      // 封装成 UI 友好的 BleDevice 结构体
      const device: BleDevice = {
        id: result.deviceId,
        name: name,
        rssi: result.rssi
      };

      // 如果 UI 注册了回调，就把设备信息抛给 UI
      if (this.deviceFoundCallback) {
        this.deviceFoundCallback(device);
      }
    }
  };

  /**
   * 解析广播数据，返回 localName（如果有的话）
   */
  public parseScanResult(data: ArrayBuffer): string {
    const advData = new Uint8Array(data);
    if (advData.byteLength === 0) {
      // 这个 warn 一般不会太频繁，保留
      console.warn(TAG, 'adv data length is 0');
      return '';
    }

    let localName: string = '';
    const serviceUuids: string[] = [];
    const serviceSolicitationUuids: string[] = [];
    const manufactureSpecificDatas: Record<number, Uint8Array> = {};
    const serviceDatas: Record<string, Uint8Array> = {};

    let curPos = 0;
    while (curPos < advData.byteLength) {
      // 当前广播字段的 (长度 + 内容) 总长度
      const length = advData[curPos++];
      if (length === 0) {
        break;
      }

      // 实际数据长度（除去类型字节）
      const advDataLength = length - 1;
      // 广播字段类型
      const advDataType = advData[curPos++];

      switch (advDataType) {
        case BLE_ADV_TYPE_FLAG:
          break;
        case BLE_ADV_TYPE_LOCAL_NAME_SHORT:
        case BLE_ADV_TYPE_LOCAL_NAME_COMPLETE:
          // 设备的广播名称（可能为空）
          localName = advData.slice(curPos, curPos + advDataLength).toString();
          break;
        case BLE_ADV_TYPE_TX_POWER_LEVEL:
          break;
        case BLE_ADV_TYPE_16_BIT_SERVICE_UUIDS_INCOMPLETE:
        case BLE_ADV_TYPE_16_BIT_SERVICE_UUIDS_COMPLETE:
          this.parseServiceUuid(BLUETOOTH_UUID_16_BIT_LENGTH, curPos, advDataLength, advData, serviceUuids);
          break;
        case BLE_ADV_TYPE_32_BIT_SERVICE_UUIDS_INCOMPLETE:
        case BLE_ADV_TYPE_32_BIT_SERVICE_UUIDS_COMPLETE:
          this.parseServiceUuid(BLUETOOTH_UUID_32_BIT_LENGTH, curPos, advDataLength, advData, serviceUuids);
          break;
        case BLE_ADV_TYPE_128_BIT_SERVICE_UUIDS_INCOMPLETE:
        case BLE_ADV_TYPE_128_BIT_SERVICE_UUIDS_COMPLETE:
          this.parseServiceUuid(BLUETOOTH_UUID_128_BIT_LENGTH, curPos, advDataLength, advData, serviceUuids);
          break;
        case BLE_ADV_TYPE_16_BIT_SERVICE_SOLICITATION_UUIDS:
          this.parseServiceSolicitationUuid(BLUETOOTH_UUID_16_BIT_LENGTH, curPos, advDataLength,
            advData, serviceSolicitationUuids);
          break;
        case BLE_ADV_TYPE_32_BIT_SERVICE_SOLICITATION_UUIDS:
          this.parseServiceSolicitationUuid(BLUETOOTH_UUID_32_BIT_LENGTH, curPos, advDataLength,
            advData, serviceSolicitationUuids);
          break;
        case BLE_ADV_TYPE_128_BIT_SERVICE_SOLICITATION_UUIDS:
          this.parseServiceSolicitationUuid(BLUETOOTH_UUID_128_BIT_LENGTH, curPos, advDataLength,
            advData, serviceSolicitationUuids);
          break;
        case BLE_ADV_TYPE_16_BIT_SERVICE_DATA:
          this.parseServiceData(BLUETOOTH_UUID_16_BIT_LENGTH, curPos, advDataLength, advData, serviceDatas);
          break;
        case BLE_ADV_TYPE_32_BIT_SERVICE_DATA:
          this.parseServiceData(BLUETOOTH_UUID_32_BIT_LENGTH, curPos, advDataLength, advData, serviceDatas);
          break;
        case BLE_ADV_TYPE_128_BIT_SERVICE_DATA:
          this.parseServiceData(BLUETOOTH_UUID_128_BIT_LENGTH, curPos, advDataLength, advData, serviceDatas);
          break;
        case BLE_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA:
          this.parseManufactureData(curPos, advDataLength, advData, manufactureSpecificDatas);
          break;
        default:
        // 其它不关心的类型可以直接跳过
          break;
      }
      // 移动游标到下一个字段
      curPos += advDataLength;
    }

    /*
    // 如需调试广播内容，可暂时打开这些日志
    console.info(TAG, 'advertiseFlags: ' + advertiseFlags);
    console.info(TAG, 'txPowerLevel: ' + txPowerLevel);
    console.info(TAG, 'localName: ' + localName);
    console.info(TAG, 'serviceUuids: ' + JSON.stringify(serviceUuids));
    console.info(TAG, 'serviceSolicitationUuids: ' + JSON.stringify(serviceSolicitationUuids));
    console.info(TAG, 'manufactureSpecificDatas: ' + JSON.stringify(manufactureSpecificDatas));
    console.info(TAG, 'serviceDatas: ' + JSON.stringify(serviceDatas));
    */

    // 最终返回 localName 给调用方使用
    return localName;
  }

  private parseServiceUuid(uuidLength: number, curPos: number, advDataLength: number,
    advData: Uint8Array, serviceUuids: string[]): void {
    let remain = advDataLength;
    let pos = curPos;
    while (remain > 0) {
      const tmpData: Uint8Array = advData.slice(pos, pos + uuidLength);
      serviceUuids.push(this.getUuidFromUint8Array(uuidLength, tmpData));
      remain -= uuidLength;
      pos += uuidLength;
    }
  }

  private parseServiceSolicitationUuid(uuidLength: number, curPos: number, advDataLength: number,
    advData: Uint8Array, serviceSolicitationUuids: string[]): void {
    let remain = advDataLength;
    let pos = curPos;
    while (remain > 0) {
      const tmpData: Uint8Array = advData.slice(pos, pos + uuidLength);
      serviceSolicitationUuids.push(this.getUuidFromUint8Array(uuidLength, tmpData));
      remain -= uuidLength;
      pos += uuidLength;
    }
  }

  private getUuidFromUint8Array(uuidLength: number, uuidData: Uint8Array): string {
    let uuid = '';
    let temp = '';
    for (let i = uuidLength - 1; i >= 0; i--) {
      temp += uuidData[i].toString(16).padStart(2, '0');
    }
    switch (uuidLength) {
      case BLUETOOTH_UUID_16_BIT_LENGTH:
        uuid = `0000${temp}-0000-1000-8000-00805F9B34FB`;
        break;
      case BLUETOOTH_UUID_32_BIT_LENGTH:
        uuid = `${temp}-0000-1000-8000-00805F9B34FB`;
        break;
      case BLUETOOTH_UUID_128_BIT_LENGTH:
        uuid = `${temp.substring(0, 8)}-${temp.substring(8, 12)}-${temp.substring(12, 16)}-${temp.substring(16, 20)}-${temp.substring(20, 32)}`;
        break;
      default:
        break;
    }
    return uuid;
  }

  private parseServiceData(uuidLength: number, curPos: number, advDataLength: number,
    advData: Uint8Array, serviceDatas: Record<string, Uint8Array>): void {
    const uuidBytes: Uint8Array = advData.slice(curPos, curPos + uuidLength);
    const data: Uint8Array = advData.slice(curPos + uuidLength, curPos + advDataLength);
    const key = this.getUuidFromUint8Array(uuidLength, uuidBytes);
    serviceDatas[key] = data;
  }

  private parseManufactureData(curPos: number, advDataLength: number,
    advData: Uint8Array, manufactureSpecificDatas: Record<number, Uint8Array>): void {
    const manufactureId: number = (advData[curPos + 1] << 8) + advData[curPos];
    const data: Uint8Array = advData.slice(curPos + BLUETOOTH_MANUFACTURE_ID_LENGTH, curPos + advDataLength);
    manufactureSpecificDatas[manufactureId] = data;
  }

  /**
   * 开启扫描（使用模块级 API：ble.startBLEScan）
   */
  public startScan(): void {
    const scanOptions: ble.ScanOptions = {
      interval: 0,
      dutyMode: ble.ScanDuty.SCAN_MODE_LOW_POWER,
      matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
    };

    try {
      // 订阅扫描结果事件
      ble.on('BLEDeviceFind', this.onReceiveEvent);
      // 启动扫描
      ble.startBLEScan(null, scanOptions);

      // console.info(TAG, 'startBLEScan success (use ble.startBLEScan with null filter)');
    } catch (err) {
      const e = err as BusinessError;
      console.error('startScan error, code: ' + e.code + ', message: ' + e.message);
    }
  }

  /**
   * 停止扫描（对应模块级 API：ble.stopBLEScan）
   */
  public stopScan(): void {
    try {
      // 取消订阅扫描结果事件
      ble.off('BLEDeviceFind', this.onReceiveEvent);
      // 停止扫描
      ble.stopBLEScan();
      // console.info(TAG, 'stopBLEScan success');
    } catch (err) {
      const e = err as BusinessError;
      console.error('stopScan error, code: ' + e.code + ', message: ' + e.message);
    }
  }
}

// 单例导出，方便全局复用
const bleScanManager = new BleScanManager();
export default bleScanManager as BleScanManager;
