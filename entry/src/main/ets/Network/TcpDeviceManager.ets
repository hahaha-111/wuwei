import { TcpClient, TcpClientConfig, TcpMessageEvent } from './TcpClient';
import { TransportState } from '../common/transport/ITransport';

export type TcpDataHandler = (data: Uint8Array) => void;
export type TcpStateHandler = (state: TransportState) => void;

/**
 * TCP 设备连接管理器（单例）
 */
export class TcpDeviceManager {
  private static _instance: TcpDeviceManager;
  private client: TcpClient | undefined;
  private onDataCallback: TcpDataHandler | undefined;
  // ⭐ 新增：状态回调
  private onStateCallback: TcpStateHandler | undefined;

  private constructor() {}

  public static get instance(): TcpDeviceManager {
    if (!TcpDeviceManager._instance) {
      TcpDeviceManager._instance = new TcpDeviceManager();
    }
    return TcpDeviceManager._instance;
  }

  get isConnected(): boolean {
    return this.client ? this.client.isConnected : false;
  }

  /**
   * 注册数据回调
   */
  public setOnDataReceived(callback: TcpDataHandler) {
    this.onDataCallback = callback;
  }

  /**
   * ⭐ 新增：注册状态回调，透传连接状态
   */
  public setOnStateChange(callback: TcpStateHandler) {
    this.onStateCallback = callback;
  }

  /**
   * 连接具体的设备端口
   */
  public async connectDevice(ip: string, port: number): Promise<void> {
    // 1. 如果已有连接，先断开
    await this.close();

    const config: TcpClientConfig = {
      host: ip,
      port: port,
      timeout: 5000,
      family: 1
    };

    this.client = new TcpClient(config);

    // 2. 绑定底层事件
    this.client.setOnMessage((event: TcpMessageEvent) => {
      if (this.onDataCallback) {
        const data = new Uint8Array(event.message);
        this.onDataCallback(data);
      }
    });

    this.client.setOnClose(() => {
      this.notifyState('DISCONNECTED');
    });

    this.client.setOnError((err) => {
      console.error('TcpClient Error:', JSON.stringify(err));
      this.notifyState('DISCONNECTED');
    });

    // 3. 执行连接
    try {
      this.notifyState('CONNECTING');
      await this.client.connect();
      // ⭐ 连接成功，通知上层
      this.notifyState('CONNECTED');
    } catch (e) {
      this.notifyState('DISCONNECTED');
      // ⭐⭐ 修复 ArkTS Check 错误：必须断言为 Error 才能 throw ⭐⭐
      throw e as Error;
    }
  }

  public async sendHexString(hex: string): Promise<void> {
    if (this.client && this.client.isConnected) {
      await this.client.sendHexString(hex);
    } else {
      console.warn('TcpDeviceManager: 尝试发送数据但未连接');
    }
  }

  public async sendData(data: Uint8Array): Promise<void> {
    if (this.client && this.client.isConnected) {
      const buffer = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
      await this.client.sendBuffer(buffer);
    }
  }

  public async close(): Promise<void> {
    if (this.client) {
      await this.client.close();
      this.client = undefined;
      this.notifyState('DISCONNECTED');
    }
  }

  private notifyState(state: TransportState) {
    if (this.onStateCallback) {
      this.onStateCallback(state);
    }
  }
}