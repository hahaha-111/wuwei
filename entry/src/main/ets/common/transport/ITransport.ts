// ITransport.ts
// 修改接口定义，支持多播回调


export type TransportState = 'CONNECTED' | 'DISCONNECTED' | 'CONNECTING' | 'DISCONNECTING';

export type TransportStateCallback = (state: TransportState, deviceId: string) => void;
export type TransportDataCallback = (data: Uint8Array) => void;

/**
 * 统一通信接口
 * 屏蔽 BLE 和 TCP 的底层差异
 */
export interface ITransport {
  /**
   * 唯一标识 (BLE是MAC/ID, TCP是IP:Port)
   */
  getId(): string;

  /**
   * 是否已连接
   */
  isConnected(): boolean;

  /**
   * 发送 HEX 字符串
   */
  sendHexString(hex: string): Promise<void>;

  /**
   * 发送字节数组
   */
  sendBytes(data: Uint8Array): Promise<void>;

  /**
   * 断开连接
   */
  disconnect(): Promise<void>;

  /**
   * 注册状态回调 (支持多播)
   * @param key 唯一标识符，用于取消注册 (推荐使用页面名称或UUID)
   */
  setOnStateChange(key: string, callback: TransportStateCallback): void;

  /**
   * 取消注册状态回调
   */
  offStateChange(key: string): void;

  /**
   * 注册数据接收回调 (支持多播)
   * @param key 唯一标识符
   */
  setOnDataReceived(key: string, callback: TransportDataCallback): void;

  /**
   * 取消注册数据接收回调
   */
  offDataReceived(key: string): void;
}