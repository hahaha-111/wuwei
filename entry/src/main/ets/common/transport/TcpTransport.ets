// TcpTransport.ets
import { ITransport, TransportState, TransportStateCallback, TransportDataCallback } from './ITransport';
import { TcpDeviceManager } from '../../Network/TcpDeviceManager';

export class TcpTransport implements ITransport {
  private static instance: TcpTransport;

  private stateCallbacks: Map<string, TransportStateCallback> = new Map();
  private dataCallbacks: Map<string, TransportDataCallback> = new Map();

  private currentId: string = 'TCP_Device';

  private constructor() {
    this.initListeners();
  }

  public static getInstance(): TcpTransport {
    if (!TcpTransport.instance) {
      TcpTransport.instance = new TcpTransport();
    }
    return TcpTransport.instance;
  }

  private initListeners() {
    const manager = TcpDeviceManager.instance;

    // 1. 数据回调
    manager.setOnDataReceived((data: Uint8Array) => {
      this.dataCallbacks.forEach((cb) => {
        try { cb(data); } catch (e) { console.error('TcpData callback error:', e); }
      });
    });

    // 2. ⭐ 状态回调适配
    manager.setOnStateChange((state: TransportState) => {
      this.notifyStateChange(state);
    });
  }

  // 分发状态给所有监听者 (MonitorVM 等)
  notifyStateChange(state: TransportState) {
    this.stateCallbacks.forEach((cb) => {
      try { cb(state, this.currentId); } catch (e) { console.error('TcpState callback error:', e); }
    });
  }

  getId(): string {
    return this.currentId;
  }

  isConnected(): boolean {
    return TcpDeviceManager.instance.isConnected;
  }

  async sendHexString(hex: string): Promise<void> {
    await TcpDeviceManager.instance.sendHexString(hex);
  }

  async sendBytes(data: Uint8Array): Promise<void> {
    await TcpDeviceManager.instance.sendData(data);
  }

  async disconnect(): Promise<void> {
    await TcpDeviceManager.instance.close();
    // 状态回调会由 TcpDeviceManager 的 close -> notifyState 触发，
    // 但为了保险，如果上层手动调用 disconnect，这里也可以触发一次（虽然 TcpDeviceManager 也会发）
  }

  setOnStateChange(key: string, callback: TransportStateCallback): void {
    this.stateCallbacks.set(key, callback);
    // ⭐ 补充逻辑：注册时如果已经连接，立即回调一次状态
    if (this.isConnected()) {
      callback('CONNECTED', this.currentId);
    }
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