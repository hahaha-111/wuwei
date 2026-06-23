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
  WAIT_CONNECT_ACK, 
  WAIT_ERASE_ACK,   
  SENDING,          
  WAIT_RUN_ACK,     
  COMPLETE,
  ERROR
}

export interface StcOtaCallbacks {
  onSendData: (data: Uint8Array) => Promise<void>;
  onMessage: (msg: string) => void;
  onProgress: (progress: number) => void;
  onSuccess: (costTime: string) => void;
  onError: (reason: string) => void;
}

export class StcOtaController {
  public packetSize: number = 16; 
  public delayMs: number = 20;
  public maxRetries: number = 5;
  public baseAddress: number = 0x0000; 

  private state: OtaState = OtaState.IDLE;
  private fileBuffer: Uint8Array = new Uint8Array(0);
  private currentOffset: number = 0;
  private startTime: number = 0;
  private retryCount: number = 0;
  private timeoutTimer: number = -1;
  
  // 🌟 新增：用于 UI 节流的上次进度记录
  private lastProgress: number = -1; 

  private rxBuffer: number[] = [];
  private callbacks: StcOtaCallbacks;

  constructor(callbacks: StcOtaCallbacks) {
    this.callbacks = callbacks;
  }

  public getState(): OtaState { return this.state; }

  public isRunning(): boolean {
    return this.state !== OtaState.IDLE && this.state !== OtaState.COMPLETE && this.state !== OtaState.ERROR;
  }

  public stop(): void {
    this.clearTimeout();
    this.state = OtaState.IDLE;
    this.rxBuffer = [];
  }

  public async start(fileUri: string): Promise<void> {
    this.stop(); 
    this.state = OtaState.IDLE;
    this.startTime = Date.now();
    this.retryCount = 0;
    this.lastProgress = -1; // 初始化重置
    this.callbacks.onProgress(0);
    this.callbacks.onMessage('正在读取固件文件...');

    try {
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      let finalBuffer = new Uint8Array(buf);

      if (finalBuffer.length > 0 && finalBuffer[0] === 0x3A) {
        throw new Error('检测到 HEX 文本格式！请使用 .bin 二进制文件。');
      }

      if (finalBuffer.length > this.baseAddress) {
        let isPadding = true;
        for (let i = 0; i < 128; i++) {
          if (finalBuffer[i] !== 0xFF && finalBuffer[i] !== 0x00) {
            isPadding = false;
            break;
          }
        }
        if (isPadding) {
          this.callbacks.onMessage(`自动裁剪 BIN 文件头部填充(0x${this.baseAddress.toString(16)})...`);
          finalBuffer = finalBuffer.slice(this.baseAddress);
        }
      }

      this.fileBuffer = finalBuffer;
      this.currentOffset = 0;

      this.callbacks.onMessage(`文件就绪 (${this.fileBuffer.byteLength} 字节)，发送握手...`);

      await this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_CONNECT, 0x00, STC_TAIL]));
      this.state = OtaState.WAIT_CONNECT_ACK;
      this.startTimeout(2000);

    } catch (e) {
      let errMsg = e instanceof Error ? e.message : JSON.stringify(e);
      this.handleError('启动失败: ' + errMsg);
    }
  }

  public processRxData(data: Uint8Array): void {
    if (!this.isRunning()) return;

    for (let i = 0; i < data.length; i++) {
      this.rxBuffer.push(data[i]);
    }

    while (this.rxBuffer.length >= 4) {
      const headIdx = this.rxBuffer.indexOf(STC_HEAD);
      if (headIdx === -1) {
        this.rxBuffer = []; 
        return;
      }
      if (headIdx > 0) {
        this.rxBuffer.splice(0, headIdx); 
      }

      if (this.rxBuffer.length < 4) return; 

      const cmd = this.rxBuffer[1];
      let expectedLen = 4; 
      if (cmd === STC_CMD_WRITE_DATA) {
        expectedLen = 6;
      }

      if (this.rxBuffer.length < expectedLen) return; 

      if (this.rxBuffer[expectedLen - 1] !== STC_TAIL) {
        this.rxBuffer.shift(); 
        continue;
      }

      const frame = this.rxBuffer.splice(0, expectedLen);
      this.handleValidFrame(frame, cmd);
    }
  }

  private handleValidFrame(frame: number[], cmd: number): void {
    switch (this.state) {
      case OtaState.WAIT_CONNECT_ACK:
        if (cmd === STC_CMD_CONNECT && frame[2] === STC_STATUS_OK) {
          this.clearTimeout();
          this.retryCount = 0;
          this.callbacks.onMessage('握手成功，正在擦除 APP 区 (请稍候)...');
          this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_ERASE_APP, 0x00, STC_TAIL]));
          this.state = OtaState.WAIT_ERASE_ACK;
          this.startTimeout(8000); 
        }
        break;

      case OtaState.WAIT_ERASE_ACK:
        if (cmd === STC_CMD_ERASE_APP && frame[2] === STC_STATUS_OK) {
          this.clearTimeout();
          this.retryCount = 0;
          this.callbacks.onMessage('擦除完成，开始写入数据...');
          this.state = OtaState.SENDING;
          this.sendNextPacket();
        }
        break;

      case OtaState.SENDING:
        if (cmd === STC_CMD_WRITE_DATA) {
          const ackAddrH = frame[2];
          const ackAddrL = frame[3];
          const status = frame[4];
          
          const ackAddr = (ackAddrH << 8) | ackAddrL;
          const currentTargetAddr = this.baseAddress + this.currentOffset;

          if (ackAddr !== currentTargetAddr) {
            return; 
          }

          if (status !== STC_STATUS_OK) {
            this.handleError(`单片机写入失败，状态码: ${status}`);
            return;
          }

          this.clearTimeout(); 
          this.retryCount = 0;

          const remaining = this.fileBuffer.byteLength - this.currentOffset;
          const justSentLen = (remaining > this.packetSize) ? this.packetSize : remaining;
          this.currentOffset += justSentLen; 

          // 🌟 强制给 UI 线程留出呼吸的时间片，哪怕设为了 0，也至少延时 1ms 交出主线程
          const actualDelay = this.delayMs > 0 ? this.delayMs : 1;
          setTimeout(() => this.sendNextPacket(), actualDelay);
        }
        break;

      case OtaState.WAIT_RUN_ACK:
        if (cmd === STC_CMD_RUN_APP && frame[2] === STC_STATUS_OK) {
          this.clearTimeout();
          this.retryCount = 0;
          this.handleSuccess();
        }
        break;
    }
  }

  private async sendNextPacket(): Promise<void> {
    if (this.currentOffset >= this.fileBuffer.byteLength) {
      this.callbacks.onMessage('写入完成，请求运行 APP...');
      await this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_RUN_APP, 0x00, STC_TAIL]));
      this.state = OtaState.WAIT_RUN_ACK;
      this.startTimeout(2000);
      return;
    }
    this.resendCurrentPacket();
  }

  private async resendCurrentPacket(): Promise<void> {
    const remaining = this.fileBuffer.byteLength - this.currentOffset;
    const len = (remaining > this.packetSize) ? this.packetSize : remaining;

    const packet = new Uint8Array(7 + len);
    const targetAddr = this.baseAddress + this.currentOffset;
    const addrH = (targetAddr >> 8) & 0xFF;
    const addrL = targetAddr & 0xFF;

    packet[0] = STC_HEAD;
    packet[1] = STC_CMD_WRITE_DATA;
    packet[2] = addrH;
    packet[3] = addrL;
    packet[4] = len;

    let checksum = STC_CMD_WRITE_DATA + addrH + addrL + len;
    for (let i = 0; i < len; i++) {
      const byte = this.fileBuffer[this.currentOffset + i];
      packet[5 + i] = byte;
      checksum += byte;
    }
    
    packet[5 + len] = checksum & 0xFF;
    packet[6 + len] = STC_TAIL;

    // 🌟 核心修复：UI 渲染节流 (Throttling)
    // 只有当百分比真正发生变化时，才去触发 UI 刷新，防止鸿蒙 UI 线程被高频刷新卡死
    const progress = Math.floor((this.currentOffset / this.fileBuffer.byteLength) * 100);
    if (progress !== this.lastProgress) {
      this.lastProgress = progress;
      this.callbacks.onProgress(progress);
      this.callbacks.onMessage(`正在写入: ${progress}% (Addr: 0x${targetAddr.toString(16)})`);
    }

    await this.sendRawData(packet);
    this.startTimeout(3000); 
  }

  
  
  private async sendRawData(data: Uint8Array): Promise<void> {
    try {
      await this.callbacks.onSendData(data);
    } catch (e) {
      console.error('OTA Send Error', JSON.stringify(e));
    }
  }

  private startTimeout(ms: number): void {
    this.clearTimeout();
    this.timeoutTimer = setTimeout(() => this.handleTimeout(), ms);
  }

  private clearTimeout(): void {
    if (this.timeoutTimer !== -1) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
  }

  private handleTimeout(): void {
    this.retryCount++;
    const reason = '无响应或丢包';

    if (this.retryCount > this.maxRetries) {
      this.handleError(`${reason} (超时超过 ${this.maxRetries} 次)`);
      return;
    }

    this.callbacks.onMessage(`OTA 重试 ${this.retryCount}/${this.maxRetries}...`);

    if (this.state === OtaState.SENDING) {
      this.resendCurrentPacket();
    } else if (this.state === OtaState.WAIT_CONNECT_ACK) {
      this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_CONNECT, 0x00, STC_TAIL]));
      this.startTimeout(2000);
    } else if (this.state === OtaState.WAIT_ERASE_ACK) {
      this.handleError('擦除无响应，设备可能已跑飞断联');
    } else if (this.state === OtaState.WAIT_RUN_ACK) {
      this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_RUN_APP, 0x00, STC_TAIL]));
      this.startTimeout(2000);
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