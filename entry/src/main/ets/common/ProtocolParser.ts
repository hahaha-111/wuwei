
export enum DeviceType {
  Microwave = 0xC9,
  Fiber = 0x66,
  Laser = 0x19
}

export interface ProtocolFrame {
  raw: Uint8Array;
  address: number;
  deviceType: number;
  dataLength: number;
  data: Uint8Array;
  checksum: number;
  checksumOk: boolean;
}

export class ProtocolParser {
  private buffer: number[] = [];

  public feed(input: Uint8Array): Array<ProtocolFrame> {
    for (let i = 0; i < input.length; i++) {
      this.buffer.push(input[i]);
    }

    const frames: Array<ProtocolFrame> = [];

    // 循环解析：FF(0)+Addr(1)+Type(2)+Len(3)+Data(4...)+CS
    while (this.buffer.length >= 5) {
      if (this.buffer[0] !== 0xFF) {
        this.buffer.shift();
        continue;
      }

      const len = this.buffer[3];
      const totalFrameLen = 5 + len;

      if (this.buffer.length < totalFrameLen) {
        break;
      }

      const frameBytes = this.buffer.slice(0, totalFrameLen);

      // ⭐ 校验规则：从 DeviceType(索引2) 开始，到 Data 结束 (不含CS)
      // FF 01 C9 01 19 E3 -> Sum(C9,01,19) = E3
      let sum = 0;
      for (let i = 2; i < totalFrameLen - 1; i++) {
        sum += frameBytes[i];
      }
      const calcChecksum = sum & 0xFF;
      const recvChecksum = frameBytes[totalFrameLen - 1];

      // 移除已解析帧
      this.buffer.splice(0, totalFrameLen);

      // 提取数据区：从索引4开始，长度len
      const dataBytes = new Uint8Array(frameBytes.slice(4, 4 + len));

      const frame: ProtocolFrame = {
        raw: new Uint8Array(frameBytes),
        address: frameBytes[1],
        deviceType: frameBytes[2],
        dataLength: len,
        data: dataBytes,
        checksum: recvChecksum,
        checksumOk: calcChecksum === recvChecksum
      };

      frames.push(frame);
    }

    return frames;
  }

  public static hexStringToBytes(hex: string): Uint8Array {
    const clean: string = hex.replace(/[\s:]/g, '').toUpperCase();
    if (clean.length % 2 !== 0 && clean.length > 0) {
      // 容错处理：如果长度奇数，前面补0
      const safeHex = '0' + clean;
      const len = safeHex.length / 2;
      const bytes = new Uint8Array(len);
      for (let i = 0; i < len; i++) {
        bytes[i] = parseInt(safeHex.substr(i * 2, 2), 16);
      }
      return bytes;
    }

    if (clean.length === 0) return new Uint8Array(0);

    const len = clean.length / 2;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = parseInt(clean.substr(i * 2, 2), 16);
    }
    return bytes;
  }

  // ⭐ 新增：补充缺失的方法，修复 DebugViewModel 报错
  public static bytesToHexString(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      let b = bytes[i].toString(16).toUpperCase();
      if (b.length === 1) {
        b = '0' + b;
      }
      hex += b;
    }
    return hex;
  }
}