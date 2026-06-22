// SleSearch.ets   星闪 (NearLink/SLE) 设备搜索
// 参考 BleSearch.ts 架构，使用 @kit.NearLinkKit 的 nearLink 扫描 API

import { nearLink } from '@kit.NearLinkKit';

const TAG: string = 'SleScanManager';

// ★★★ 星闪广播数据类型常量（SLE AD Type） ★★★
const SLE_ADV_TYPE_LOCAL_NAME_SHORT = 0x08;
const SLE_ADV_TYPE_LOCAL_NAME_COMPLETE = 0x09;

/**
 * 提供给 UI 使用的简化星闪设备信息
 */
export interface SleDevice {
  id: string;
  name: string;
  rssi: number;
}

export class SleScanManager {
  private deviceFoundCallback?: (device: SleDevice) => void;

  public setOnDeviceFoundCallback(callback: (device: SleDevice) => void): void {
    this.deviceFoundCallback = callback;
  }

  onReceiveEvent = (results: Array<nearLink.SleDiscoveryResult>) => {
    if (!results || results.length === 0) {
      return;
    }

    for (const result of results) {
      const localNameFromAdv: string = this.parseAdvData(result.data);
      const name: string = (result.deviceName && result.deviceName.length > 0)
        ? result.deviceName
        : localNameFromAdv;

      const device: SleDevice = {
        id: result.deviceId,
        name: name,
        rssi: result.rssi
      };

      if (this.deviceFoundCallback) {
        this.deviceFoundCallback(device);
      }
    }
  };

  public parseAdvData(data: ArrayBuffer): string {
    const advData = new Uint8Array(data);
    if (advData.byteLength === 0) {
      return '';
    }

    let localName: string = '';
    let curPos = 0;
    while (curPos < advData.byteLength) {
      const length = advData[curPos++];
      if (length === 0) {
        break;
      }

      const advDataLength = length - 1;
      const advDataType = advData[curPos++];

      if (advDataType === SLE_ADV_TYPE_LOCAL_NAME_SHORT ||
          advDataType === SLE_ADV_TYPE_LOCAL_NAME_COMPLETE) {
        localName = advData.slice(curPos, curPos + advDataLength).toString();
        break;
      }
      curPos += advDataLength;
    }

    return localName;
  }

  public startScan(): void {
    const scanOptions: nearLink.SleScanOptions = {
      interval: 0,
      dutyMode: nearLink.SleScanDuty.SLE_SCAN_MODE_LOW_POWER,
      matchMode: nearLink.SleMatchMode.SLE_MATCH_MODE_AGGRESSIVE
    };

    try {
      nearLink.on('SleDeviceFind', this.onReceiveEvent);
      nearLink.startSleDiscovery(null, scanOptions);
      console.info(TAG, 'startSleDiscovery success');
    } catch (err) {
      console.error(TAG, 'startScan error: ' + JSON.stringify(err));
    }
  }

  public stopScan(): void {
    try {
      nearLink.off('SleDeviceFind', this.onReceiveEvent);
      nearLink.stopSleDiscovery();
      console.info(TAG, 'stopSleDiscovery success');
    } catch (err) {
      console.error(TAG, 'stopScan error: ' + JSON.stringify(err));
    }
  }
}

const sleScanManager = new SleScanManager();
export default sleScanManager as SleScanManager;
