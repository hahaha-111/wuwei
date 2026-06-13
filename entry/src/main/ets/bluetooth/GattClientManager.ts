// GattClientManager.ts
import { util } from '@kit.ArkTS';
import { ble, constant } from '@kit.ConnectivityKit';
import { BusinessError } from '@ohos.base';
import { ProtocolParser, ProtocolFrame } from '../common/ProtocolParser';

const TAG: string = 'GattClientManager';

export class GattClientManager {
  device: string = '';
  gattClient: ble.GattClientDevice | undefined = undefined;
  connectState: ble.ProfileConnectionState = constant.ProfileConnectionState.STATE_DISCONNECTED;

  private serviceUuid: string = '0000FFF0-0000-1000-8000-00805F9B34FB';
  private writeCharUuid: string = '0000FFF2-0000-1000-8000-00805F9B34FB';
  private notifyCharUuid: string = '0000FFF1-0000-1000-8000-00805F9B34FB';
  private readonly cccUuid: string = '00002902-0000-1000-8000-00805F9B34FB';

  private writeChar?: ble.BLECharacteristic;
  private notifyChar?: ble.BLECharacteristic;
  private writeType: ble.GattWriteType = ble.GattWriteType.WRITE;


  private protocolParser: ProtocolParser = new ProtocolParser();
  private connStateCallback?: (state: ble.ProfileConnectionState, deviceId: string) => void;
  private rawDataCallback?: (data: Uint8Array) => void;
  private frameCallback?: (frame: ProtocolFrame) => void;

  private writeQueue: Uint8Array[] = [];
  private writeBusy: boolean = false;

  public setDebugLog(): void {
  }

  public updateTargetService(serviceUuid: string, writeUuid: string, notifyUuid: string) {
    this.serviceUuid = serviceUuid;
    this.writeCharUuid = writeUuid;
    this.notifyCharUuid = notifyUuid;
    this.resetCache();
  }

  public resetConfiguration() {
    this.serviceUuid = '0000FFF0-0000-1000-8000-00805F9B34FB';
    this.writeCharUuid = '0000FFF2-0000-1000-8000-00805F9B34FB';
    this.notifyCharUuid = '0000FFF1-0000-1000-8000-00805F9B34FB';
    this.resetCache();
  }

  private resetCache() {
    this.writeChar = undefined;
    this.notifyChar = undefined;
    this.writeBusy = false;
    this.writeType = ble.GattWriteType.WRITE;
    this.protocolParser = new ProtocolParser();
  }

  private checkService(services: Array<ble.GattService>) {
    for (const svc of services) {
      if (svc.serviceUuid !== this.serviceUuid) continue;

      for (const ch of svc.characteristics) {
        if (ch.characteristicUuid === this.writeCharUuid) {
          this.writeChar = ch;
          if (ch.properties.writeNoResponse) {
            this.writeType = ble.GattWriteType.WRITE_NO_RESPONSE;
          } else if (ch.properties.write) {
            this.writeType = ble.GattWriteType.WRITE;
          } else {
            this.writeType = ble.GattWriteType.WRITE;
          }
        }
        if (ch.characteristicUuid === this.notifyCharUuid) {
          this.notifyChar = ch;
          for (const des of ch.descriptors) {
            if (des.descriptorUuid === this.cccUuid) {
            }
          }
        }
      }
    }
  }

  public setOnConnectionStateChange(callback: (state: ble.ProfileConnectionState, deviceId: string) => void): void {
    this.connStateCallback = callback;
  }

  public setOnDataReceived(callback: (data: Uint8Array) => void): void {
    this.rawDataCallback = callback;
  }

  public setOnFrameReceived(callback: (frame: ProtocolFrame) => void): void {
    this.frameCallback = callback;
  }

  onGattClientStateChange = (stateInfo: ble.BLEConnectionChangeState) => {
    if (stateInfo.deviceId === this.device) {
      this.connectState = stateInfo.state;
    }
    if (this.connStateCallback) {
      this.connStateCallback(stateInfo.state, stateInfo.deviceId);
    }
  };

  public startConnect(peerDevice: string) {
    this.device = peerDevice;
    this.resetCache();
    this.gattClient = ble.createGattClientDevice(peerDevice);
    try {
      this.gattClient.on('BLEConnectionStateChange', this.onGattClientStateChange);
      this.gattClient.connect();
    } catch (err) {
      const e = err as BusinessError;
      console.error(TAG, `startConnect error: ${e.code}`);
    }
  }

  public async discoverServices(): Promise<Array<ble.GattService>> {
    if (!this.gattClient) return [];
    try {
      const serverService = await this.gattClient.getServices();
      this.checkService(serverService);
      return serverService;
    } catch (err) {
      return [];
    }
  }

  public writeText(text: string): void {
    if (!this.gattClient || !this.writeChar) return;
    const encoder = new util.TextEncoder('utf-8');
    const encoded = encoder.encodeInto(text);
    const buffer = new ArrayBuffer(encoded.length);
    const view = new Uint8Array(buffer);
    view.set(encoded);

    const characteristic: ble.BLECharacteristic = {
      serviceUuid: this.serviceUuid,
      characteristicUuid: this.writeCharUuid,
      characteristicValue: buffer,
      descriptors: this.writeChar.descriptors ?? []
    };

    try {
      this.gattClient.writeCharacteristicValue(characteristic, this.writeType, (err?: BusinessError) => {
        if (err) console.error(TAG, `writeText error: ${err.code}`);
      });
    } catch (e) {
      console.error(TAG, `writeText exception: ${e}`);
    }
  }

  public writeBytes(data: Uint8Array) {
    if (!this.gattClient || !this.writeChar) return;

    this.writeQueue.push(data);
    this.processWriteQueue();
  }

  private processWriteQueue(): void {
    if (this.writeBusy || this.writeQueue.length === 0) {
      return;
    }

    this.writeBusy = true;
    const dataToSend = this.writeQueue.shift();
    if (!dataToSend || !this.gattClient) {
      this.writeBusy = false;
      this.processWriteQueue();
      return;
    }

    const characteristic: ble.BLECharacteristic = {
      serviceUuid: this.serviceUuid,
      characteristicUuid: this.writeCharUuid,
      characteristicValue: dataToSend.buffer,
      descriptors: this.writeChar?.descriptors ?? []
    };

    try {
      this.gattClient.writeCharacteristicValue(characteristic, this.writeType, (err?: BusinessError) => {
        this.writeBusy = false;
        if (err) console.error(TAG, `writeBytes error: ${err.code}`);
        this.processWriteQueue();
      });
    } catch (e) {
      this.writeBusy = false;
      console.error(TAG, `writeBytes exception: ${e}`);
      this.processWriteQueue();
    }
  }

  public writeHexString(hex: string): void {
    const clean = hex.replace(/\s+/g, '').toUpperCase();
    const result: number[] = [];
    for (let i = 0; i + 1 < clean.length; i += 2) {
      const byteStr = clean.substring(i, i + 2);
      const value = Number.parseInt(byteStr, 16);
      if (!Number.isNaN(value)) result.push(value & 0xff);
    }
    this.writeBytes(new Uint8Array(result));
  }

  onCharacteristicChange = (char: ble.BLECharacteristic) => {
    const bytes = new Uint8Array(char.characteristicValue);
    // [DEBUG removed] console.info(TAG, `notify UUID=${char.characteristicUuid}, expect=${this.notifyCharUuid}, len=${bytes.length}`);
    if (char.characteristicUuid !== this.notifyCharUuid) {
      // [DEBUG removed] console.warn(TAG, 'UUID mismatch, skip');
      return;
    }
    if (bytes.length === 0) {
      // [DEBUG removed] console.warn(TAG, 'empty notification');
      return;
    }
    // [DEBUG removed] const hex = ... console.info(TAG, `notify data: ${hex}`);
    if (this.rawDataCallback) this.rawDataCallback(bytes);
    const frames = this.protocolParser.feed(bytes);
    // [DEBUG removed] console.info(TAG, `parsed ${frames.length} frames`);
    if (this.frameCallback) frames.forEach(frame => this.frameCallback!(frame));
  };

  public Notify(enable: boolean): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.gattClient || !this.notifyChar) {
        reject(new Error('Notify failed: client or char not ready'));
        return;
      }

      try {
        this.gattClient.on('BLECharacteristicChange', this.onCharacteristicChange);
        // ⭐ 修复：增加异常捕获
        this.gattClient.setCharacteristicChangeNotification(
          this.notifyChar,
          enable,
          (err?: BusinessError) => {
            if (err) reject(err);
            else resolve();
          }
        );
      } catch (e) {
        const err = e as BusinessError;
        reject(err);
      }
    });
  }

  public stopConnect() {
    if (!this.gattClient) return;
    try {
      this.gattClient.disconnect();
      this.gattClient.off('BLEConnectionStateChange', this.onGattClientStateChange);
      this.gattClient.off('BLECharacteristicChange', this.onCharacteristicChange);
      this.gattClient.close();
      this.connectState = constant.ProfileConnectionState.STATE_DISCONNECTED;
      this.resetCache();
    } catch (e) {
      console.error(TAG, `stopConnect error: ${e}`);
    }
  }
}

const gattClientManager = new GattClientManager();
export default gattClientManager as GattClientManager;