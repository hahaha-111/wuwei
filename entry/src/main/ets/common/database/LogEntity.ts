// common/database/LogEntity.ts

/**
 * 日志大类枚举
 */
export enum LogCategory {
  CONNECTION = '连接',
  SETTING = '设置',
  QUERY = '查询',
  MAINTENANCE = '维护'
}

/**
 * 日志实体接口 (对应数据库字段)
 */
export interface LogEntity {
  id?: number;            // 自增主键
  timestamp: number;      // 时间戳
  timeStr: string;        // 格式化时间 "yyyy-MM-dd HH:mm:ss"
  category: string;       // 分类 (LogCategory)
  actionType: string;     // 具体动作
  deviceName: string;     // 设备名称
  deviceId: string;       // 设备ID/地址
  content: string;        // 详细内容
  result: number;         // 1:成功, 0:失败
}