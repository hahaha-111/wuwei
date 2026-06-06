import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { SignalSample } from '../../viewmodel/SignalBoardViewModel';

/**
 * 报警快照元数据接口
 */
export interface SnapshotInfo {
  deviceName: string;
  threshold: number;
  channel: string;
  alarmTime: string;
}

/**
 * 后台并发任务：绘制波形并保存图片
 * 加上 @Concurrent 装饰器后，此函数会在 TaskPool 的工作线程中执行
 */
@Concurrent
async function saveTask(
  samples: SignalSample[],
  info: SnapshotInfo,
  savePath: string,
  width: number,
  height: number
): Promise<void> {
  // 1. 创建离屏画布 (在 Worker 线程中创建)
  const offCanvas = new OffscreenCanvas(width, height);
  const ctx = offCanvas.getContext('2d', new RenderingContextSettings(true));

  // 2. 绘制背景
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, width, height);

  // 3. 绘制网格 (内联逻辑，避免嵌套函数)
  ctx.beginPath();
  ctx.lineWidth = 1;
  ctx.strokeStyle = '#E0E0E0';

  const ticks = [0, 50, 100, 150, 200, 250];
  ticks.forEach(val => {
    const y = height - (val / 255) * height;
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
  });

  for (let i = 1; i < 4; i++) {
    const x = (width / 4) * i;
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
  }
  ctx.stroke();

  ctx.font = '24px sans-serif';
  ctx.fillStyle = '#666666';
  ticks.forEach(val => {
    const y = height - (val / 255) * height;
    ctx.fillText(val.toString(), width - 50, y - 5);
  });

  // 4. 绘制波形 (内联逻辑)
  if (samples.length > 1) {
    const range = 255;
    const count = samples.length;
    const stepX = width / (count - 1);
    const hFactor = height / range;

    // 波形 (蓝)
    ctx.beginPath();
    ctx.lineWidth = 3;
    ctx.strokeStyle = '#0000FF';
    // ⭐ 修复 Error 1-2: 增加 ?? 0 避免 undefined 报错
    ctx.moveTo(0, height - (samples[0].signal ?? 0) * hFactor);
    for (let i = 1; i < count; i++) {
      ctx.lineTo(i * stepX, height - (samples[i].signal ?? 0) * hFactor);
    }
    ctx.stroke();

    // 阈值 (红)
    ctx.beginPath();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#FF0000';
    // ⭐ 修复 Error 3-4: 增加 ?? 0 避免 undefined 报错
    ctx.moveTo(0, height - (samples[0].alarmThreshold ?? 0) * hFactor);
    for (let i = 1; i < count; i++) {
      ctx.lineTo(i * stepX, height - (samples[i].alarmThreshold ?? 0) * hFactor);
    }
    ctx.stroke();

    // 水印
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.font = 'bold 30px sans-serif';
    ctx.fillText('无畏监控系统 - 报警快照', 20, 40);

    ctx.font = '20px sans-serif';
    const lineHeight = 28;
    const startY = 75;

    ctx.fillText(`设备名称: ${info.deviceName}`, 20, startY);
    ctx.fillText(`设备通道: ${info.channel}`, 20, startY + lineHeight);
    ctx.fillText(`灵敏/阈值: ${info.threshold}`, 20, startY + lineHeight * 2);
    ctx.fillText(`报警时间: ${info.alarmTime}`, 20, startY + lineHeight * 3);
  }

  // 5. 生成图片文件 (CPU 密集操作)
  try {
    const pixelMap = ctx.getPixelMap(0, 0, width, height);
    const packer = image.createImagePacker();
    const packOpts: image.PackingOption = { format: "image/png", quality: 100 };
    // ⭐ 修复警告：将 packing 改为最新 API packToData
    const buffer = await packer.packToData(pixelMap, packOpts);

    const file = await fs.open(savePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    await fs.write(file.fd, buffer);
    await fs.close(file);

    pixelMap.release();
  } catch (e) {
    console.error(`[ImageGenerator] Task failed: ${JSON.stringify(e)}`);
  }
}

/**
 * 负责在后台利用 OffscreenCanvas 绘制波形并保存为图片
 * 使用 TaskPool 解决主线程卡顿问题
 */
export class ImageGenerator {

  /**
   * 生成波形图片并保存到指定路径 (异步，非阻塞)
   */
  public static async saveWaveformImage(
    samples: SignalSample[],
    info: SnapshotInfo,
    savePath: string,
    width: number = 800,
    height: number = 600
  ): Promise<void> {
    // 构造 Task
    const task = new taskpool.Task(saveTask, samples, info, savePath, width, height);
    // 放入 TaskPool 执行
    await taskpool.execute(task);
  }
}