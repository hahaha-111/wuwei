import { fileIo as fs } from '@kit.CoreFileKit';

// === STC OTA Protocol Constants ===
const STC_CMD_CONNECT = 0xA0;
const STC_CMD_ERASE_APP = 0xA1;
const STC_CMD_WRITE_DATA = 0xA2;
const STC_CMD_RUN_APP = 0xA3;
const STC_HEAD = 0x55;
const STC_TAIL = 0xAA;
const STC_STATUS_OK = 0x00;

export enum OtaState {
  IDLE,
  WAIT_CONNECT_ACK, // 等待握手响应 (0xA0)
  WAIT_ERASE_ACK,   // 等待擦除完成响应 (0xA1)
  SENDING,          // 正在发送数据 (0xA2)
  WAIT_RUN_ACK,     // 等待跳转响应 (0xA3)
  COMPLETE,
  ERROR
}

// 回调接口定义，用于解耦 UI 和发送逻辑
export interface StcOtaCallbacks {
  // 发送数据的底层接口 (BLE/TCP)
  onSendData: (data: Uint8Array) => Promise<void>;
  // UI 消息通知
  onMessage: (msg: string) => void;
  // 进度更新 (0-100)
  onProgress: (progress: number) => void;
  // 成功回调
  onSuccess: (costTime: string) => void;
  // 失败回调
  onError: (reason: string) => void;
}

export class StcOtaController {
  // 配置参数
  public packetSize: number = 64;
  public delayMs: number = 20;
  public maxRetries: number = 5;
  public baseAddress: number = 0x1000;

  // 运行状态
  private state: OtaState = OtaState.IDLE;
  private fileBuffer: Uint8Array = new Uint8Array(0);
  private currentOffset: number = 0;
  private startTime: number = 0;
  private retryCount: number = 0;
  private timeoutTimer: number = -1;

  private callbacks: StcOtaCallbacks;

  constructor(callbacks: StcOtaCallbacks) {
    this.callbacks = callbacks;
  }

  public getState(): OtaState {
    return this.state;
  }

  public isRunning(): boolean {
    return this.state !== OtaState.IDLE && this.state !== OtaState.COMPLETE && this.state !== OtaState.ERROR;
  }

  public stop(): void {
    this.clearTimeout();
    this.state = OtaState.IDLE;
  }

  // 启动 OTA 流程
  public async start(fileUri: string): Promise<void> {
    this.state = OtaState.IDLE;
    this.startTime = Date.now();
    this.retryCount = 0;
    this.callbacks.onProgress(0);
    this.callbacks.onMessage('正在读取固件文件...');

    try {
      // 1. 读取文件
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const size = stat.size;
      const buf = new ArrayBuffer(size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      let finalBuffer = new Uint8Array(buf);

      // 2. 格式检查 (HEX 文本检测)
      if (finalBuffer.length > 0 && finalBuffer[0] === 0x3A) {
        throw new Error('检测到 HEX 文本格式！请使用 .bin 二进制文件。');
      }

      // 3. 头部检查 (调试用)
      if (finalBuffer.length > 16) {
        const headBytes = finalBuffer.slice(0, 16);
        const headStr = Array.from(headBytes).map((b: number): string => b.toString(16).padStart(2, '0')).join(' ');
        console.warn('OTA_DEBUG: BIN Head: ' + headStr);
      }

      // 4. 自动裁剪 (Keil 填充处理)
      if (finalBuffer.length > this.baseAddress) {
        let isPadding = true;
        // 采样检测前 128 字节
        for (let i = 0; i < 128; i++) {
          if (finalBuffer[i] !== 0xFF && finalBuffer[i] !== 0x00) {
            isPadding = false;
            break;
          }
        }
        if (isPadding) {
          this.callbacks.onMessage('自动裁剪 BIN 文件头部填充(4KB)...');
          finalBuffer = finalBuffer.slice(this.baseAddress);
        }
      }

      this.fileBuffer = finalBuffer;
      this.currentOffset = 0;

      this.callbacks.onMessage(`文件准备就绪 (${this.fileBuffer.byteLength} bytes)，发送握手指令...`);

      // 5. 发送握手
      await this.sendRawData(new Uint8Array([STC_CMD_CONNECT]));

      this.state = OtaState.WAIT_CONNECT_ACK;
      this.startTimeout(2000);

    } catch (e) {
      let errMsg = '未知错误';
      if (e instanceof Error) {
        errMsg = e.message;
      } else {
        errMsg = JSON.stringify(e);
      }
      this.handleError('启动失败: ' + errMsg);
    }
  }

  // 处理接收到的数据 (在 ViewModel 的 onDataReceived 中调用)
  public processRxData(data: Uint8Array): void {
    if (!this.isRunning()) return;

    // 协议格式: HEAD(0x55) CMD STATUS TAIL(0xAA)
    if (data.length < 4) return;

    // 寻找帧头
    let idx = -1;
    for (let i = 0; i < data.length - 3; i++) {
      if (data[i] === STC_HEAD && data[i + 3] === STC_TAIL) {
        idx = i;
        break;
      }
    }

    if (idx === -1) return; // 无效帧

    const cmd = data[idx + 1];
    const status = data[idx + 2];

    if (status !== STC_STATUS_OK) {
      this.callbacks.onMessage(`指令 0x${cmd.toString(16)} 返回错误码: ${status}`);
      return;
    }

    // 清除超时，重置重试
    this.clearTimeout();
    this.retryCount = 0;

    // 状态机流转
    switch (this.state) {
      case OtaState.WAIT_CONNECT_ACK:
        if (cmd === STC_CMD_CONNECT) {
          this.callbacks.onMessage('握手成功，正在擦除 App 区 (请稍候)...');
          this.sendRawData(new Uint8Array([STC_CMD_ERASE_APP]));
          this.state = OtaState.WAIT_ERASE_ACK;
          this.startTimeout(5000); // 擦除需要时间
        }
        break;

      case OtaState.WAIT_ERASE_ACK:
        if (cmd === STC_CMD_ERASE_APP) {
          this.callbacks.onMessage('擦除完成，开始写入...');
          this.state = OtaState.SENDING;
          this.sendNextPacket();
        }
        break;

      case OtaState.SENDING:
        if (cmd === STC_CMD_WRITE_DATA) {
          // 收到 ACK，更新 Offset
          const remaining = this.fileBuffer.byteLength - this.currentOffset;
          const justSentLen = (remaining > this.packetSize) ? this.packetSize : remaining;
          this.currentOffset += justSentLen;

          // 延时发送下一包
          if (this.delayMs > 0) {
            setTimeout((): void => { this.sendNextPacket(); }, this.delayMs);
          } else {
            this.sendNextPacket();
          }
        }
        break;

      case OtaState.WAIT_RUN_ACK:
        if (cmd === STC_CMD_RUN_APP) {
          this.handleSuccess();
        }
        break;
    }
  }

  private async sendNextPacket(): Promise<void> {
    // 检查是否结束
    if (this.currentOffset >= this.fileBuffer.byteLength) {
      this.callbacks.onMessage('写入完成，请求运行 App...');
      await this.sendRawData(new Uint8Array([STC_CMD_RUN_APP]));
      this.state = OtaState.WAIT_RUN_ACK;
      this.startTimeout(2000);
      return;
    }

    this.resendCurrentPacket();
  }

  private async resendCurrentPacket(): Promise<void> {
    const remaining = this.fileBuffer.byteLength - this.currentOffset;
    const len = (remaining > this.packetSize) ? this.packetSize : remaining;

    // 包结构: CMD + ADDR_H + ADDR_L + LEN + DATA... + CS
    const packet = new Uint8Array(5 + len);
    const targetAddr = this.baseAddress + this.currentOffset;
    const addrH = (targetAddr >> 8) & 0xFF;
    const addrL = targetAddr & 0xFF;

    packet[0] = STC_CMD_WRITE_DATA;
    packet[1] = addrH;
    packet[2] = addrL;
    packet[3] = len;

    let checksum = STC_CMD_WRITE_DATA + addrH + addrL + len;
    for (let i = 0; i < len; i++) {
      const byte = this.fileBuffer[this.currentOffset + i];
      packet[4 + i] = byte;
      checksum += byte;
    }
    packet[4 + len] = checksum & 0xFF;

    await this.sendRawData(packet);

    // 更新进度
    const progress = Math.floor((this.currentOffset / this.fileBuffer.byteLength) * 100);
    this.callbacks.onProgress(progress);
    this.callbacks.onMessage(`写入: ${progress}% (Addr: 0x${targetAddr.toString(16)})`);

    this.startTimeout(3000);
  }

  private async sendRawData(data: Uint8Array): Promise<void> {
    try {
      await this.callbacks.onSendData(data);
    } catch (e) {
      console.error('OTA Send Error', JSON.stringify(e));
      // 发送异常不中断，等待超时重试
    }
  }

  private startTimeout(ms: number): void {
    this.clearTimeout();
    this.timeoutTimer = setTimeout((): void => {
      this.handleTimeout();
    }, ms);
  }

  private clearTimeout(): void {
    if (this.timeoutTimer !== -1) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
  }

  private handleTimeout(): void {
    this.retryCount++;
    const reason = '等待响应超时';

    if (this.retryCount > this.maxRetries) {
      this.handleError(`${reason} (超过最大重试次数)`);
      return;
    }

    this.callbacks.onMessage(`OTA 重试 ${this.retryCount}/${this.maxRetries}: ${reason}`);

    if (this.state === OtaState.SENDING) {
      this.resendCurrentPacket();
    } else if (this.state === OtaState.WAIT_CONNECT_ACK) {
      this.sendRawData(new Uint8Array([STC_CMD_CONNECT]));
      this.startTimeout(2000);
    } else if (this.state === OtaState.WAIT_ERASE_ACK) {
      this.handleError('擦除指令无响应，设备可能异常');
    }
  }

  private handleSuccess(): void {
    this.state = OtaState.COMPLETE;
    this.clearTimeout();
    const cost = ((Date.now() - this.startTime) / 1000).toFixed(1);
    this.callbacks.onSuccess(cost);
  }

  private handleError(err: string): void {
    this.state = OtaState.ERROR;
    this.clearTimeout();
    this.callbacks.onError(err);
  }
}