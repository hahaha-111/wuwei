import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI'; // ⭐ 修复：引入 UIContext 替代全局 promptAction
import { LogManager } from '../common/database/LogManager';
import { LogEntity, LogCategory } from '../common/database/LogEntity';
import { MonitorPageParams } from './MonitorViewModel';
import { DeviceType } from '../common/ProtocolParser';

@Observed
export class LogGroup {
  date: string;
  items: LogEntity[];
  expanded: boolean;

  constructor(date: string, items: LogEntity[], expanded: boolean) {
    this.date = date;
    this.items = items;
    this.expanded = expanded;
  }
}

@Observed
export class LogViewModel {
  // 扁平日志列表
  logList: LogEntity[] = [];

  // ⭐ 按日期分组后的日志
  groupedLogs: LogGroup[] = [];

  // 筛选状态
  selectedCategoryIndex: number = 0;
  categoryOptions: SelectOption[] = [
    { value: '全部' },
    { value: LogCategory.CONNECTION },
    { value: LogCategory.SETTING },
    { value: LogCategory.QUERY },
    { value: LogCategory.MAINTENANCE }
  ];

  // 搜索关键字
  filterText: string = '';

  private context?: common.UIAbilityContext;
  private navParams: MonitorPageParams | undefined = undefined;
  
  // ⭐ 注入的界面 UIContext
  public uiContext: UIContext | null = null;
  
  // ⭐ 用于页面路由上下文保留的公共属性
  public deviceType: DeviceType = DeviceType.Microwave;
  public connectionMode: 'BLE' | 'TCP' = 'BLE';
  public currentDeviceAddress: number = 0x01;
  public deviceNameDisplay: string = '未知设备';

  constructor() {}

  // ⭐ 安全弹窗辅助方法
  private safeShowToast(msg: string) {
    if (this.uiContext) {
      try {
        this.uiContext.getPromptAction().showToast({ message: msg });
      } catch (e) {}
    }
  }

  async init(context: common.UIAbilityContext, params?: MonitorPageParams) {
    this.context = context;
    this.navParams = params;

    if (params) {
      if (params.deviceType !== undefined) this.deviceType = params.deviceType;
      if (params.connectionMode !== undefined) this.connectionMode = params.connectionMode;
      if (params.deviceAddress !== undefined) this.currentDeviceAddress = params.deviceAddress;
      if (params.deviceName !== undefined) this.deviceNameDisplay = params.deviceName;
    }

    try {
      await LogManager.getInstance().init(context);
      this.refreshLogs();
    } catch (e) {
      console.error('LogManager init failed', e);
    }
  }

  private getDateKeyFromLog(item: LogEntity): string {
    const timeStr: string = item.timeStr || '';
    const idx: number = timeStr.indexOf(' ');
    if (idx > 0) {
      return timeStr.substring(0, idx);
    }
    return timeStr;
  }

  private rebuildGroups(list: LogEntity[]) {
    const oldGroups: LogGroup[] = this.groupedLogs || [];
    const oldExpandedMap: Map<string, boolean> = new Map<string, boolean>();
    oldGroups.forEach((g: LogGroup) => {
      oldExpandedMap.set(g.date, g.expanded);
    });

    const tempMap: Map<string, LogEntity[]> = new Map<string, LogEntity[]>();
    list.forEach((item: LogEntity) => {
      const key: string = this.getDateKeyFromLog(item);
      if (!tempMap.has(key)) {
        tempMap.set(key, []);
      }
      const arr: LogEntity[] | undefined = tempMap.get(key);
      if (arr !== undefined) {
        arr.push(item);
      }
    });

    const entries: [string, LogEntity[]][] = Array.from(tempMap.entries());

    // 日期倒序（最近日期在上）
    entries.sort((a: [string, LogEntity[]], b: [string, LogEntity[]]) => {
      return b[0].localeCompare(a[0]);
    });

    const groups: LogGroup[] = entries.map((entry: [string, LogEntity[]]) => {
      const date: string = entry[0];
      const items: LogEntity[] = entry[1];

      const expandedInOld: boolean | undefined = oldExpandedMap.get(date);
      // 默认为展开状态
      const expanded: boolean = expandedInOld !== undefined ? expandedInOld : true;

      return new LogGroup(date, items, expanded);
    });

    this.groupedLogs = groups;
  }

  async refreshLogs() {
    try {
      const category: string = this.categoryOptions[this.selectedCategoryIndex].value as string;
      const allLogs: LogEntity[] = await LogManager.getInstance().queryLogs(category);

      let resultList: LogEntity[] = [];

      if (this.filterText && this.filterText.trim().length > 0) {
        const keyword: string = this.filterText.trim().toLowerCase();
        resultList = allLogs.filter((item: LogEntity) => {
          const contentMatch: boolean =
            !!item.content && item.content.toLowerCase().includes(keyword);
          const deviceMatch: boolean =
            !!item.deviceName && item.deviceName.toLowerCase().includes(keyword);
          const actionMatch: boolean =
            !!item.actionType && item.actionType.toLowerCase().includes(keyword);
          return contentMatch || deviceMatch || actionMatch;
        });
      } else {
        resultList = allLogs;
      }

      this.logList = resultList;
      this.rebuildGroups(resultList);
    } catch (e) {
      console.error('refreshLogs failed', e);
    }
  }

  onCategorySelect(index: number) {
    this.selectedCategoryIndex = index;
    this.refreshLogs();
  }

  setFilterText(text: string) {
    this.filterText = text;
    this.refreshLogs();
  }

  toggleGroup(date: string) {
    const index: number = this.groupedLogs.findIndex((g: LogGroup) => g.date === date);
    if (index < 0) {
      return;
    }

    const oldGroup: LogGroup = this.groupedLogs[index];
    const newGroup: LogGroup = new LogGroup(
      oldGroup.date,
      oldGroup.items,
      !oldGroup.expanded
    );

    this.groupedLogs[index] = newGroup;
    this.groupedLogs = [...this.groupedLogs];
  }

  expandGroup(date: string) {
    const index: number = this.groupedLogs.findIndex((g: LogGroup) => g.date === date);
    if (index >= 0 && !this.groupedLogs[index].expanded) {
      this.toggleGroup(date);
    }
  }

  getFlattenedIndex(dateStr: string): number {
    const targetGroupIndex = this.groupedLogs.findIndex(g => g.date === dateStr);

    if (targetGroupIndex < 0) {
      return -1;
    }

    let flattenedIndex = 0;
    for (let i = 0; i < targetGroupIndex; i++) {
      const group = this.groupedLogs[i];
      flattenedIndex += 1;
      if (group.expanded) {
        flattenedIndex += group.items.length;
      }
    }
    return flattenedIndex;
  }

  getCountByDate(date: string): number {
    const group: LogGroup | undefined = this.groupedLogs.find(
      (g: LogGroup) => g.date === date
    );
    return group ? group.items.length : 0;
  }

  async clearLogs() {
    // ⭐ 修复警告：底层清空方法需要被严密包裹
    try {
      await LogManager.getInstance().clearAllLogs();
      this.logList = [];
      this.groupedLogs = [];
      this.safeShowToast('日志已清空');
    } catch (e) {
      console.error('clearLogs failed', e);
      this.safeShowToast('日志清空失败');
    }
  }

  async exportLogs() {
    if (!this.context) {
      return;
    }
    try {
      const path: string | undefined = await LogManager.getInstance().exportToCsv(this.context);
      if (path && path.length > 0) {
        const index: number = path.indexOf('/files');
        const shortPath: string = index >= 0 ? path.substring(index) : path;
        // ⭐ 修复警告：替换废弃的全局弹窗调用
        if (this.uiContext) {
          try {
            this.uiContext.getPromptAction().showDialog({
              title: '导出成功',
              message: `日志已保存至应用私有目录:\n${shortPath}\n\n您可以使用文件管理器查看或连接电脑导出。`,
              buttons: [{ text: '确定', color: '#1976D2' }]
            }).catch(() => {});
          } catch (e) {}
        }
      } else {
        this.safeShowToast('暂无日志可导出');
      }
    } catch (e) {
      const msg: string = typeof e === 'string' ? e : String(e);
      this.safeShowToast('导出失败: ' + msg);
    }
  }

  getNavParams(): MonitorPageParams | undefined {
    return this.navParams;
  }
}