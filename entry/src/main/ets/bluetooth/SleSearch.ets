// SleSearch.ets   星闪 (NearLink/SLE) 设备扫描
// 官方文档: import { scan } from '@kit.NearLinkKit'

import { scan, manager } from '@kit.NearLinkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

const TAG: string = 'SleScanManager';

// 星闪广播数据类型常量（官方文档 2026-06-12）
const SLE_ADV_DATA_TYPE_SHORTENED_LOCAL_NAME = 0x0A;
const SLE_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME = 0x0B;

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

  /**
   * 检查当前设备是否支持星闪
   */
  public isNearLinkSupported(): boolean {
    try {
      return manager.isNearLinkSupported();
    } catch (err) {
      return false;
    }
  }

  onReceiveEvent = (data: Array<scan.ScanResults>) => {
    if (!data || data.length === 0) {
      return;
    }

    for (const result of data) {
      const localNameFromAdv: string = this.parseAdvData(result.data);
      const name: string = (result.deviceName && result.deviceName.length > 0)
        ? result.deviceName
        : localNameFromAdv;

      const device: SleDevice = {
        id: result.address,
        name: name,
        rssi: result.rssi ?? -100
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
      const advDataType = advData[curPos++];
      const advDataLength = advData[curPos++];
      if (advDataLength === 0) {
        break;
      }

      if (advDataType === SLE_ADV_DATA_TYPE_SHORTENED_LOCAL_NAME ||
          advDataType === SLE_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME) {
        const nameSlice = advData.slice(curPos, curPos + advDataLength);
        const decoder = util.TextDecoder.create('utf-8');
        localName = decoder.decodeToString(new Uint8Array(nameSlice));
        break;
      }
      curPos += advDataLength;
    }

    return localName;
  }

  public startScan(): void {
    // 1. 检查设备是否支持星闪
    let supported: boolean = false;
    try {
      supported = manager.isNearLinkSupported();
    } catch (err) {
      console.error(TAG, 'isNearLinkSupported failed: ' + ((err as BusinessError).message));
    }
    console.info(TAG, 'NearLink supported: ' + supported);
    if (!supported) {
      console.error(TAG, 'Device does NOT support NearLink, scan aborted');
      return;
    }

    // 2. 检查星闪开关状态
    try {
      let state = manager.getState();
      console.info(TAG, 'NearLink state: ' + JSON.stringify(state));
    } catch (err) {
      console.error(TAG, 'getState failed: ' + ((err as BusinessError).message));
    }

    // 3. 构造扫描参数
    // 过滤器至少需要一个条件，空字符串作为通配（匹配任意设备名）
    const scanFilter: scan.ScanFilters = {
      deviceName: ''  // 空字符串 = 扫描所有设备
    };
    const scanOptions: scan.ScanOptions = {
      scanMode: scan.ScanMode.SCAN_MODE_LOW_POWER
    };

    // 4. 开始扫描
    try {
      scan.on('deviceFound', this.onReceiveEvent);
      scan.startScan([scanFilter], scanOptions).then(() => {
        console.info(TAG, 'startScan success');
      }).catch((err: BusinessError) => {
        console.error(TAG, 'startScan rejected: code=' + err.code + ' msg=' + err.message);
      });
    } catch (err) {
      console.error(TAG, 'startScan exception: code=' + (err as BusinessError).code +
        ' msg=' + (err as BusinessError).message);
    }
  }

  public stopScan(): void {
    try {
      scan.off('deviceFound', this.onReceiveEvent);
      scan.stopScan().then(() => {
        console.info(TAG, 'stopScan success');
      }).catch((err: BusinessError) => {
        console.error(TAG, 'stopScan error: ' + err.message);
      });
    } catch (err) {
      console.error(TAG, 'stopScan error: ' + ((err as BusinessError).message));
    }
  }
}

const sleScanManager = new SleScanManager();
export default sleScanManager as SleScanManager;
