import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
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
  // ⭐ 用于页面路由上下文保留的公共属性
  public deviceType: DeviceType = DeviceType.Microwave;
  public connectionMode: 'BLE' | 'TCP' = 'BLE';
  public currentDeviceAddress: number = 0x01;
  public deviceNameDisplay: string = '未知设备';

  constructor() {}

  async init(context: common.UIAbilityContext, params?: MonitorPageParams) {
    this.context = context;
    this.navParams = params;

    // ⭐ 接收全局上下文变量，避免参数丢失
    if (params) {
      if (params.deviceType !== undefined) this.deviceType = params.deviceType;
      if (params.connectionMode !== undefined) this.connectionMode = params.connectionMode;
      if (params.deviceAddress !== undefined) this.currentDeviceAddress = params.deviceAddress;
      if (params.deviceName !== undefined) this.deviceNameDisplay = params.deviceName;
    }

    await LogManager.getInstance().init(context);
    this.refreshLogs();
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

    // 1. 替换对应位置的数据
    this.groupedLogs[index] = newGroup;

    // ⭐ 官方文档状态管理核心修复：
    // 因为外部使用的是 @State vm = new LogViewModel()，它只能监听到对象第一层属性的“赋值”。
    // 单纯修改数组内部元素无法改变数组的引用地址，UI 不会更新。
    // 这里必须通过解构重新分配一个新的数组对象，强制触发 ArkUI 的重绘。
    this.groupedLogs = [...this.groupedLogs];
  }

  // 辅助方法：确保某个分组是展开的（用于跳转后自动展开）
  expandGroup(date: string) {
    const index: number = this.groupedLogs.findIndex((g: LogGroup) => g.date === date);
    if (index >= 0 && !this.groupedLogs[index].expanded) {
      this.toggleGroup(date);
    }
  }

  /**
   * 获取目标日期在 List 组件中的真实扁平化索引
   */
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
    await LogManager.getInstance().clearAllLogs();
    this.logList = [];
    this.groupedLogs = [];
    promptAction.showToast({ message: '日志已清空' });
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
        promptAction.showDialog({
          title: '导出成功',
          message: `日志已保存至应用私有目录:\n${shortPath}\n\n您可以使用文件管理器查看或连接电脑导出。`,
          buttons: [{ text: '确定', color: '#1976D2' }]
        });
      } else {
        promptAction.showToast({ message: '暂无日志可导出' });
      }
    } catch (e) {
      const msg: string = typeof e === 'string' ? e : JSON.stringify(e);
      promptAction.showToast({ message: '导出失败: ' + msg });
    }
  }

  getNavParams(): MonitorPageParams | undefined {
    return this.navParams;
  }
}