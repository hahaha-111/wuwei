// BleTransport.ts
// 升级为多播模式

import { ITransport, TransportState, TransportStateCallback, TransportDataCallback } from './ITransport';
import gattClientManager from '../../bluetooth/GattClientManager';
import { constant, ble } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class BleTransport implements ITransport {
  private static instance: BleTransport;

  // ⭐ 改为 Map 存储多个回调
  private stateCallbacks: Map<string, TransportStateCallback> = new Map();
  private dataCallbacks: Map<string, TransportDataCallback> = new Map();

  private constructor() {
    this.initListeners();
  }

  public static getInstance(): BleTransport {
    if (!BleTransport.instance) {
      BleTransport.instance = new BleTransport();
    }
    return BleTransport.instance;
  }

  private initListeners() {
    // 这里只注册一次到底层 GattClientManager
    gattClientManager.setOnConnectionStateChange((state: ble.ProfileConnectionState, deviceId: string) => {
      const tsState = this.mapBleState(state);
      // 分发给所有监听者
      this.stateCallbacks.forEach((cb) => {
        try { cb(tsState, deviceId); } catch (e) { console.error('BleState callback error:', e); }
      });
    });

    gattClientManager.setOnDataReceived((data: Uint8Array) => {
      // 分发给所有监听者
      this.dataCallbacks.forEach((cb) => {
        try { cb(data); } catch (e) { console.error('BleData callback error:', e); }
      });
    });
  }

  private mapBleState(s: ble.ProfileConnectionState): TransportState {
    switch (s) {
      case constant.ProfileConnectionState.STATE_CONNECTED: return 'CONNECTED';
      case constant.ProfileConnectionState.STATE_DISCONNECTED: return 'DISCONNECTED';
      case constant.ProfileConnectionState.STATE_CONNECTING: return 'CONNECTING';
      case constant.ProfileConnectionState.STATE_DISCONNECTING: return 'DISCONNECTING';
      default: return 'DISCONNECTED';
    }
  }

  getId(): string {
    return gattClientManager.device;
  }

  isConnected(): boolean {
    return gattClientManager.connectState === constant.ProfileConnectionState.STATE_CONNECTED;
  }

  async sendHexString(hex: string): Promise<void> {
    try {
      gattClientManager.writeHexString(hex);
    } catch (error) {
      console.error(`BleTransport sendHexString error: ${JSON.stringify(error)}`);
    }
  }

  async sendBytes(data: Uint8Array): Promise<void> {
    try {
      gattClientManager.writeBytes(data);
    } catch (error) {
      console.error(`BleTransport sendBytes error: ${JSON.stringify(error)}`);
    }
  }

  async disconnect(): Promise<void> {
    try {
      gattClientManager.stopConnect();
    } catch (error) {
      console.error(`BleTransport disconnect error: ${JSON.stringify(error)}`);
    }
  }

  // ⭐ 新增多播实现
  setOnStateChange(key: string, callback: TransportStateCallback): void {
    this.stateCallbacks.set(key, callback);
  }

  offStateChange(key: string): void {
    this.stateCallbacks.delete(key);
  }

  setOnDataReceived(key: string, callback: TransportDataCallback): void {
    this.dataCallbacks.set(key, callback);
  }

  offDataReceived(key: string): void {
    this.dataCallbacks.delete(key);
  }
}