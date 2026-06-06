import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

// 扩展类型定义
export type FileSubDir = '报警图' | '数据录像' | '报警记录';

export class FileUtil {
  private static readonly ROOT_NAME = '无畏';

  /**
   * 获取标准存储根路径: /data/storage/.../files/无畏/{deviceName}/{dateStr}/{subDir}
   */
  public static getStandardPath(context: common.UIAbilityContext, deviceName: string, subDir: FileSubDir): string {
    const safeDeviceName = deviceName.replace(/[\/\\:*?"<>|]/g, '_') || '未知设备';
    const dateStr = FileUtil.getTodayStr();

    // 结构: filesDir/无畏/设备名/2025-12-12/报警记录
    const path = `${context.filesDir}/${FileUtil.ROOT_NAME}/${safeDeviceName}/${dateStr}/${subDir}`;

    if (!fs.accessSync(path)) {
      try {
        fs.mkdirSync(path, true);
      } catch (e) {
        console.error(`mkdir failed: ${path}, ${e}`);
      }
    }
    return path;
  }

  private static getTodayStr(): string {
    const now = new Date();
    const y = now.getFullYear();
    const m = (now.getMonth() + 1).toString().padStart(2, '0');
    const d = now.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  public static generateFileName(ext: string): string {
    const now = new Date();
    const h = now.getHours().toString().padStart(2, '0');
    const m = now.getMinutes().toString().padStart(2, '0');
    const s = now.getSeconds().toString().padStart(2, '0');
    const ms = now.getMilliseconds().toString().padStart(3, '0');
    return `${h}${m}${s}_${ms}${ext}`;
  }

  public static async writeText(path: string, content: string): Promise<void> {
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    await fs.write(file.fd, content);
    await fs.close(file);
  }
}