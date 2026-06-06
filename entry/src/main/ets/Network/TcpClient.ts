import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

/**
 * TCP 客户端配置
 */
export interface TcpClientConfig {
  host: string;             // 服务器 IP
  port: number;             // 端口
  timeout?: number;         // 连接超时时间，ms
  family?: number;          // 1 = IPv4，2 = IPv6，不传默认 1
}

/**
 * 消息事件
 */
export interface TcpMessageEvent {
  message: ArrayBuffer;
  remoteInfo: socket.SocketRemoteInfo;
}

/**
 * 对外抛出的错误类型
 */
export class TcpClientError extends Error {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
    this.name = 'TcpClientError';
  }
}

// 回调类型
export type TcpConnectHandler = () => void;
export type TcpMessageHandler = (event: TcpMessageEvent) => void;
export type TcpCloseHandler = () => void;
export type TcpErrorHandler = (err: BusinessError) => void;

export class TcpClient {
  private config: TcpClientConfig;
  private tcpSocket: socket.TCPSocket;
  private _isConnected: boolean = false;

  private connectHandler?: TcpConnectHandler;
  private messageHandler?: TcpMessageHandler;
  private closeHandler?: TcpCloseHandler;
  private errorHandler?: TcpErrorHandler;

  constructor(config: TcpClientConfig) {
    this.config = config;
    this.tcpSocket = socket.constructTCPSocketInstance();
    this.initSocketListeners();
  }

  private initSocketListeners() {
    this.tcpSocket.on('message', (value: socket.SocketMessageInfo) => {
      if (this.messageHandler) {
        this.messageHandler({
          message: value.message,
          remoteInfo: value.remoteInfo
        });
      }
    });

    this.tcpSocket.on('close', () => {
      this._isConnected = false;
      if (this.closeHandler) {
        this.closeHandler();
      }
    });

    this.tcpSocket.on('error', (err: BusinessError) => {
      this._isConnected = false;
      if (this.errorHandler) {
        this.errorHandler(err);
      }
    });
  }

  public async connect(): Promise<void> {
    if (this._isConnected) return;

    const address: socket.NetAddress = {
      address: this.config.host,
      port: this.config.port,
      family: this.config.family || 1
    };

    const options: socket.TCPConnectOptions = {
      address: address,
      timeout: this.config.timeout || 5000
    };

    try {
      await this.tcpSocket.connect(options);
      // ⭐ 修复：连接成功后立即标记状态
      this._isConnected = true;
      if (this.connectHandler) {
        this.connectHandler();
      }
    } catch (error) {
      this._isConnected = false;
      const businessError: BusinessError = error as BusinessError;
      throw new TcpClientError(businessError.code, businessError.message);
    }
  }

  public async send(data: string, charset: string = 'utf-8'): Promise<void> {
    if (!this._isConnected) {
      throw new TcpClientError(-1, 'Socket not connected');
    }
    const buffer = this.encodeTextToBuffer(data, charset);
    await this.sendBuffer(buffer);
  }

  /**
   * ⭐ 修复：补回 sendTextGbk 方法，解决编译报错
   * 某些老设备可能需要 GBK 编码
   */
  public async sendTextGbk(text: string): Promise<void> {
    // 尝试使用 gbk 编码发送，如果系统不支持则回退到 utf-8
    try {
      return await this.send(text, 'gbk');
    } catch (e) {
      console.warn('GBK encoding not supported or failed, falling back to UTF-8');
      return await this.send(text, 'utf-8');
    }
  }

  public async sendHexString(hex: string): Promise<void> {
    const bytes = this.hexStringToBytes(hex);
    await this.sendBuffer(bytes.buffer as ArrayBuffer);
  }

  public async sendBuffer(buffer: ArrayBuffer): Promise<void> {
    if (!this._isConnected) {
      throw new TcpClientError(-1, 'Socket not connected');
    }
    const options: socket.TCPSendOptions = {
      data: buffer
    };
    try {
      await this.tcpSocket.send(options);
    } catch (error) {
      // 发送失败通常意味着连接断开
      this._isConnected = false;
      const businessError: BusinessError = error as BusinessError;
      throw new TcpClientError(businessError.code, businessError.message);
    }
  }

  public async close(): Promise<void> {
    if (!this._isConnected) return;
    try {
      await this.tcpSocket.close();
    } catch (e) {
      // ignore
    } finally {
      this._isConnected = false;
      if (this.closeHandler) this.closeHandler();
    }
  }

  public get isConnected(): boolean {
    return this._isConnected;
  }

  // Setters for listeners
  public setOnConnect(handler: TcpConnectHandler) { this.connectHandler = handler; }
  public setOnMessage(handler: TcpMessageHandler) { this.messageHandler = handler; }
  public setOnClose(handler: TcpCloseHandler) { this.closeHandler = handler; }
  public setOnError(handler: TcpErrorHandler) { this.errorHandler = handler; }

  // Utils
  private encodeTextToBuffer(text: string, charset: string): ArrayBuffer {
    const encoder: util.TextEncoder = new util.TextEncoder(charset);
    const bytes: Uint8Array = encoder.encodeInto(text);
    return bytes.buffer as ArrayBuffer;
  }

  private hexStringToBytes(hex: string): Uint8Array {
    const clean: string = hex.replace(/\s+/g, '').toUpperCase();
    if (clean.length === 0) return new Uint8Array(0);
    const result: number[] = [];
    for (let i = 0; i < clean.length; i += 2) {
      const byteStr = clean.substring(i, i + 2);
      const byte = parseInt(byteStr, 16);
      if (!isNaN(byte)) result.push(byte);
    }
    return new Uint8Array(result);
  }
}