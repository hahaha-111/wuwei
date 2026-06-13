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

export interface StcOtaCallbacks {
  onSendData: (data: Uint8Array) => Promise<void>;
  onMessage: (msg: string) => void;
  onProgress: (progress: number) => void;
  onSuccess: (costTime: string) => void;
  onError: (reason: string) => void;
}

export class StcOtaController {
  // --- 🟡 P1: 配置项 ---
  public packetSize: number = 64; // 注意: 如果是 BLE 且 MTU 未扩大，建议设为 16 或 20
  public delayMs: number = 20;
  public maxRetries: number = 5;
  // 支持动态配置 Bootloader 大小，AI8051U 32位模式(C251) 必须配置为 0x2000 (8KB)
  public baseAddress: number = 0x2000; 

  private state: OtaState = OtaState.IDLE;
  private fileBuffer: Uint8Array = new Uint8Array(0);
  private currentOffset: number = 0;
  private startTime: number = 0;
  private retryCount: number = 0;
  private timeoutTimer: number = -1;

  // --- 🔴 P0: 接收环形缓冲区，解决半包/粘包 ---
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
    this.stop(); // 重置状态和缓冲区
    this.state = OtaState.IDLE;
    this.startTime = Date.now();
    this.retryCount = 0;
    this.callbacks.onProgress(0);
    this.callbacks.onMessage('正在读取固件文件...');

    try {
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      let finalBuffer = new Uint8Array(buf);

      // 格式检查
      if (finalBuffer.length > 0 && finalBuffer[0] === 0x3A) {
        throw new Error('检测到 HEX 文本格式！请使用 .bin 二进制文件。');
      }

      // 自动裁剪 Bootloader 填充 (交由外部或UI判断更佳，这里保留基本探测)
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

      // 握手包 (去除 0x00 占位符，匹配 C251 Bootloader)
      await this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_CONNECT, STC_TAIL]));
      this.state = OtaState.WAIT_CONNECT_ACK;
      this.startTimeout(2000);

    } catch (e) {
      let errMsg = e instanceof Error ? e.message : JSON.stringify(e);
      this.handleError('启动失败: ' + errMsg);
    }
  }

  // --- 🔴 P0: 使用环形缓冲区解析数据，避免丢帧 ---
  public processRxData(data: Uint8Array): void {
    if (!this.isRunning()) return;

    // 1. 将新数据压入环形缓冲区
    for (let i = 0; i < data.length; i++) {
      this.rxBuffer.push(data[i]);
    }

    // 2. 循环解析完整帧
    while (this.rxBuffer.length >= 4) {
      // 寻找帧头 0x55
      const headIdx = this.rxBuffer.indexOf(STC_HEAD);
      if (headIdx === -1) {
        this.rxBuffer = []; // 全是垃圾数据，清空
        return;
      }
      if (headIdx > 0) {
        this.rxBuffer.splice(0, headIdx); // 丢弃帧头前面的脏数据
      }

      if (this.rxBuffer.length < 4) return; // 剩余长度不足以判断，等待更多数据

      const cmd = this.rxBuffer[1];
      
      // 🔴 P0: 根据命令类型确定预期帧长
      // CONNECT/ERASE/RUN 的 ACK: HEAD(1) + CMD(1) + STATUS(1) + TAIL(1) = 4 Bytes
      // WRITE_DATA 的 ACK:      HEAD(1) + CMD(1) + ADDR_H(1) + ADDR_L(1) + STATUS(1) + TAIL(1) = 6 Bytes
      let expectedLen = 4; 
      if (cmd === STC_CMD_WRITE_DATA) {
        expectedLen = 6;
      }

      if (this.rxBuffer.length < expectedLen) return; // 数据不够完整一帧，等待

      // 校验帧尾
      if (this.rxBuffer[expectedLen - 1] !== STC_TAIL) {
        // 帧尾不对，说明这是个假包头，丢掉这个假包头继续找
        this.rxBuffer.shift(); 
        continue;
      }

      // 提取出一帧完整数据
      const frame = this.rxBuffer.splice(0, expectedLen);
      this.handleValidFrame(frame, cmd);
    }
  }

  // 处理提取出的有效协议帧
  private handleValidFrame(frame: number[], cmd: number): void {
    switch (this.state) {
      case OtaState.WAIT_CONNECT_ACK:
        if (cmd === STC_CMD_CONNECT && frame[2] === STC_STATUS_OK) {
          this.clearTimeout();
          this.retryCount = 0;
          this.callbacks.onMessage('握手成功，正在擦除 APP 区 (请稍候)...');
          // 发送擦除指令 (去除 0x00 占位符)
          this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_ERASE_APP, STC_TAIL]));
          this.state = OtaState.WAIT_ERASE_ACK;
          this.startTimeout(8000); // 擦除 Flash 需要较长时间，放宽超时
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
          // 🔴 P0: 彻底解决幽灵 ACK (使用 Offset 比对而非 RTT)
          // ACK格式: [0x55, 0xA2, ADDR_H, ADDR_L, STATUS, 0xAA]
          const ackAddrH = frame[2];
          const ackAddrL = frame[3];
          const status = frame[4];
          
          const ackAddr = (ackAddrH << 8) | ackAddrL;
          const currentTargetAddr = this.baseAddress + this.currentOffset;

          if (ackAddr !== currentTargetAddr) {
            console.warn(`OTA: 拦截到过期或错位 ACK (Expected: 0x${currentTargetAddr.toString(16)}, Got: 0x${ackAddr.toString(16)})`);
            return; // 忽略此包，不清除定时器，等待真实 ACK 或超时
          }

          if (status !== STC_STATUS_OK) {
            this.handleError(`单片机写入失败，状态码: ${status}`);
            return;
          }

          // 是我们期待的当前包的 ACK
          this.clearTimeout(); // 先清除定时器，解决时序冲突
          this.retryCount = 0;

          const remaining = this.fileBuffer.byteLength - this.currentOffset;
          const justSentLen = (remaining > this.packetSize) ? this.packetSize : remaining;
          this.currentOffset += justSentLen; // 更新偏移量

          if (this.delayMs > 0) {
            setTimeout(() => this.sendNextPacket(), this.delayMs);
          } else {
            this.sendNextPacket();
          }
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
      // 请求运行 APP (去除 0x00 占位符)
      await this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_RUN_APP, STC_TAIL]));
      this.state = OtaState.WAIT_RUN_ACK;
      this.startTimeout(2000);
      return;
    }
    this.resendCurrentPacket();
  }

  private async resendCurrentPacket(): Promise<void> {
    const remaining = this.fileBuffer.byteLength - this.currentOffset;
    const len = (remaining > this.packetSize) ? this.packetSize : remaining;

    // 🔴 P0: 重构发送报文，加上严格的 HEAD 和 TAIL
    // 包结构: HEAD(1) + CMD(1) + ADDR_H(1) + ADDR_L(1) + LEN(1) + DATA(len) + CS(1) + TAIL(1) = 7 + len
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

    await this.sendRawData(packet);

    const progress = Math.floor((this.currentOffset / this.fileBuffer.byteLength) * 100);
    this.callbacks.onProgress(progress);
    this.callbacks.onMessage(`写入: ${progress}% (Addr: 0x${targetAddr.toString(16)})`);

    this.startTimeout(3000); // 发送完毕后启动定时器
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

    // 超时重传当前状态的包
    if (this.state === OtaState.SENDING) {
      this.resendCurrentPacket();
    } else if (this.state === OtaState.WAIT_CONNECT_ACK) {
      this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_CONNECT, STC_TAIL]));
      this.startTimeout(2000);
    } else if (this.state === OtaState.WAIT_ERASE_ACK) {
      this.handleError('擦除无响应，设备可能已跑飞断联');
    } else if (this.state === OtaState.WAIT_RUN_ACK) {
      this.sendRawData(new Uint8Array([STC_HEAD, STC_CMD_RUN_APP, STC_TAIL]));
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