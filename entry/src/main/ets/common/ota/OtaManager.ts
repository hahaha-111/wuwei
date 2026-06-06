// common/ota/OtaManager.ts
// 负责 OTA 文件的读取、分包与发送流程控制

import { fileIo as fs } from '@kit.CoreFileKit';

export class OtaManager {
  private isRunning: boolean = false;

  /**
   * 开始 OTA 升级流程
   * @param fileUri 文件 URI
   * @param sendCallback 发送数据的回调函数 (返回 Promise)
   * @param onProgress 进度回调 (0-100)
   * @param onMessage 状态消息回调
   * @param onComplete 完成回调
   * @param onError 错误回调
   */
  async startOTA(
    fileUri: string,
    sendCallback: (data: Uint8Array) => Promise<void>,
    onProgress: (progress: number) => void,
    onMessage: (msg: string) => void,
    onComplete: () => void,
    onError: (err: string) => void
  ) {
    if (this.isRunning) {
      onMessage('OTA 正在进行中，请勿重复操作');
      return;
    }

    this.isRunning = true;
    let file: fs.File | undefined;

    try {
      onMessage('正在读取 OTA 文件...');
      file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const totalSize = stat.size;

      if (totalSize === 0) {
        throw new Error('文件大小为 0');
      }

      onMessage(`开始 OTA: 文件大小 ${totalSize} 字节`);

      // 分包大小，BLE 通常建议 20-244 字节，这里保守取 200
      // 如果是 TCP 可以更大，这里为了通用性暂定 200，或者通过参数传入
      const chunkSize = 200;
      let offset = 0;
      let buffer = new ArrayBuffer(chunkSize);

      while (offset < totalSize && this.isRunning) {
        const readLen = fs.readSync(file.fd, buffer, { offset: offset });
        if (readLen <= 0) break;

        // 截取实际读取的数据
        const dataToSend = new Uint8Array(buffer.slice(0, readLen));

        // 调用外部传入的发送函数
        await sendCallback(dataToSend);

        offset += readLen;
        const progress = Math.floor((offset / totalSize) * 100);
        onProgress(progress);
      }

      if (this.isRunning) {
        onMessage('OTA 升级完成！');
        onComplete();
      } else {
        onMessage('OTA 升级已取消');
      }

    } catch (e) {
      const errMsg = 'OTA 失败: ' + JSON.stringify(e);
      console.error(errMsg);
      onError(errMsg);
      onMessage(errMsg);
    } finally {
      if (file) {
        fs.closeSync(file);
      }
      this.isRunning = false;
    }
  }

  stopOTA() {
    this.isRunning = false;
  }
}

// 导出单例方便调用，或者在 VM 中 new
export const otaManager = new OtaManager();