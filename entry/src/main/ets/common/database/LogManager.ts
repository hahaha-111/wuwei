// common/database/LogManager.ts
import { relationalStore, ValuesBucket } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LogEntity, LogCategory } from './LogEntity';

/**
 * 日志数据库管理器 (单例)
 * 负责日志的增删改查和导出
 */
export class LogManager {
  private static instance: LogManager;
  private rdbStore: relationalStore.RdbStore | null = null;
  private readonly STORE_CONFIG: relationalStore.StoreConfig = {
    name: 'AppLogs.db',
    securityLevel: relationalStore.SecurityLevel.S1
  };

  private readonly TABLE_NAME = 'operation_log';

  private constructor() {}

  public static getInstance(): LogManager {
    if (!LogManager.instance) {
      LogManager.instance = new LogManager();
    }
    return LogManager.instance;
  }

  /**
   * 初始化数据库 (在 EntryAbility 或 HomePage 中调用)
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.rdbStore) return;
    try {
      this.rdbStore = await relationalStore.getRdbStore(context, this.STORE_CONFIG);
      // 建表
      const sql = `CREATE TABLE IF NOT EXISTS ${this.TABLE_NAME} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER,
        time_str TEXT,
        category TEXT,
        action_type TEXT,
        device_name TEXT,
        device_id TEXT,
        content TEXT,
        result INTEGER
      )`;
      await this.rdbStore.executeSql(sql);
      console.info('LogManager init success');
    } catch (err) {
      console.error('LogManager init failed: ' + JSON.stringify(err));
    }
  }

  /**
   * 添加一条日志
   */
  async addLog(
    category: LogCategory,
    actionType: string,
    content: string,
    deviceInfo?: { name: string, id: string },
    result: boolean = true
  ): Promise<number> {
    if (!this.rdbStore) return -1;

    const now = new Date();
    const timeStr = this.formatDate(now);

    const log: LogEntity = {
      timestamp: now.getTime(),
      timeStr: timeStr,
      category: category,
      actionType: actionType,
      deviceName: deviceInfo?.name || '未知设备',
      deviceId: deviceInfo?.id || '-',
      content: content,
      result: result ? 1 : 0
    };

    const valueBucket: ValuesBucket = {
      timestamp: log.timestamp,
      time_str: log.timeStr,
      category: log.category,
      action_type: log.actionType,
      device_name: log.deviceName,
      device_id: log.deviceId,
      content: log.content,
      result: log.result
    };

    try {
      return await this.rdbStore.insert(this.TABLE_NAME, valueBucket);
    } catch (e) {
      console.error('LogManager insert failed: ' + e);
      return -1;
    }
  }

  /**
   * 查询日志 (支持简单的分类筛选，默认查全部)
   */
  async queryLogs(category?: string): Promise<LogEntity[]> {
    if (!this.rdbStore) return [];

    const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
    if (category && category !== '全部') {
      predicates.equalTo('category', category);
    }
    predicates.orderByDesc('timestamp'); // 最新在前

    try {
      const resultSet = await this.rdbStore.query(predicates);
      const list: LogEntity[] = [];

      while (resultSet.goToNextRow()) {
        list.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp')),
          timeStr: resultSet.getString(resultSet.getColumnIndex('time_str')),
          category: resultSet.getString(resultSet.getColumnIndex('category')),
          actionType: resultSet.getString(resultSet.getColumnIndex('action_type')),
          deviceName: resultSet.getString(resultSet.getColumnIndex('device_name')),
          deviceId: resultSet.getString(resultSet.getColumnIndex('device_id')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          result: resultSet.getLong(resultSet.getColumnIndex('result'))
        });
      }
      resultSet.close();
      return list;
    } catch (e) {
      console.error('LogManager query failed: ' + e);
      return [];
    }
  }

  /**
   * 清空所有日志
   */
  async clearAllLogs(): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      await this.rdbStore.delete(predicates);
    } catch (e) {
      console.error('LogManager clearAllLogs failed: ' + e);
    }
  }

  /**
   * 导出日志到 CSV 文件 (异步优化版)
   * @returns 导出文件的完整路径
   */
  async exportToCsv(context: common.UIAbilityContext): Promise<string> {
    const logs = await this.queryLogs();
    if (logs.length === 0) return '';

    // CSV BOM 防止乱码
    const header = '\uFEFF时间,分类,操作类型,设备名称,设备ID,详情,结果\n';
    let content = header;

    // 内存中拼接字符串在大数据量下可能也有压力，但在几千条规模下通常比 IO 阻塞好
    // 如果数据量极大（几万条），建议改为分批流式写入，这里保持逻辑简单直接拼接
    logs.forEach(log => {
      const safeContent = `"${log.content.replace(/"/g, '""')}"`;
      const resStr = log.result === 1 ? '成功' : '失败';
      content += `${log.timeStr},${log.category},${log.actionType},${log.deviceName},${log.deviceId},${safeContent},${resStr}\n`;
    });

    const fileName = `OperationLog_${Date.now()}.csv`;
    const targetDir = context.filesDir + '/ExportLogs';
    const filePath = targetDir + '/' + fileName;

    try {
      // 异步检查目录是否存在，不存在则创建
      const dirExists = await fs.access(targetDir);
      if (!dirExists) {
        await fs.mkdir(targetDir);
      }

      // 异步打开文件
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);

      // 异步写入
      await fs.write(file.fd, content);

      // 异步关闭
      await fs.close(file);

      return filePath;
    } catch (err) {
      console.error('Export CSV failed: ' + err);
      return '';
    }
  }

  private formatDate(date: Date): string {
    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }
}