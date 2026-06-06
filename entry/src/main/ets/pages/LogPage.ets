import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { LogViewModel, LogGroup } from '../viewmodel/LogViewModel';
import { LogEntity, LogCategory } from '../common/database/LogEntity';
import { MonitorPageParams } from '../viewmodel/MonitorViewModel';
import { DeviceType } from '../common/ProtocolParser';

@Extend(Text) function navLabel(active: boolean) {
  .fontSize(16)
  .fontColor(active ? '#1976D2' : '#444444')
  .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
}

@Entry
@Component
struct LogPage {
  @State vm: LogViewModel = new LogViewModel();
  private currentTab: string = 'log';
  // 列表滚动控制器
  private listScroller: Scroller = new Scroller();

  // 保存上次选择的日期，避免每次打开都重置为今天
  @State pickedDate: Date = new Date();

  aboutToAppear() {
    const ctx = getContext(this) as common.UIAbilityContext;
    const params = router.getParams() as MonitorPageParams;
    this.vm.init(ctx, params);
  }

  private goTo(tab: string) {
    if (tab === this.currentTab) {
      return;
    }

    if (tab === 'calibrate' && this.vm.deviceType !== DeviceType.Microwave) {
      try { promptAction.showToast({ message: '当前设备不支持校准功能' }); } catch (err) {}
      return;
    }

    const navParams: MonitorPageParams = {
      deviceName: this.vm.deviceNameDisplay,
      deviceType: this.vm.deviceType,
      connectionMode: this.vm.connectionMode,
      deviceAddress: this.vm.currentDeviceAddress
    };

    if (tab === 'home') {
      router.replaceUrl({ url: 'pages/MonitorPage', params: navParams }).catch(() => {});
    }
    if (tab === 'calibrate') {
      router.replaceUrl({ url: 'pages/CalibratePage', params: navParams }).catch(() => {});
    }
    if (tab === 'alarm') {
      router.replaceUrl({ url: 'pages/AlarmRecordPage', params: navParams }).catch(() => {});
    }
    if (tab === 'setting') {
      router.replaceUrl({ url: 'pages/SettingPage', params: navParams }).catch(() => {});
    }
  }

  private showDatePickerDialog() {
    DatePickerDialog.show({
      start: new Date('2020-01-01'),
      end: new Date('2030-12-31'),
      selected: this.pickedDate,
      onAccept: (value: DatePickerResult) => {
        if (value.year !== undefined && value.month !== undefined && value.day !== undefined) {
          this.pickedDate.setFullYear(value.year, value.month, value.day);

          const monthStr = (value.month + 1).toString().padStart(2, '0');
          const dayStr = value.day.toString().padStart(2, '0');
          const targetDateStr = `${value.year}-${monthStr}-${dayStr}`;

          const flatIndex = this.vm.getFlattenedIndex(targetDateStr);

          if (flatIndex >= 0) {
            this.vm.expandGroup(targetDateStr);
            // 稍作延迟确保折叠动画/UI更新完毕后再滚动
            setTimeout(() => {
              this.listScroller.scrollToIndex(flatIndex, true, ScrollAlign.START);
            }, 100);
            promptAction.showToast({ message: `已跳转至 ${targetDateStr}` });
          } else {
            promptAction.showToast({ message: `日期 ${targetDateStr} 无记录` });
          }
        }
      }
    })
  }

  @Builder topNavBar() {
    Row() {
      Text('主界面').navLabel(false).onClick(() => this.goTo('home'))
      if (this.vm.deviceType === DeviceType.Microwave) {
        Text('校准').navLabel(false).onClick(() => this.goTo('calibrate'))
      }
      Text('报警记录').navLabel(false).onClick(() => this.goTo('alarm'))
      Text('设置').navLabel(false).onClick(() => this.goTo('setting'))
      Text('日志').navLabel(true)
    }
    .width('100%')
    .height(48)
    .backgroundColor('#FAFAFA')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: '#EEEEEE' })
  }

  private getCategoryColor(cat: string): string {
    switch (cat) {
      case LogCategory.MAINTENANCE:
        return '#D32F2F';
      case LogCategory.SETTING:
        return '#1976D2';
      case LogCategory.CONNECTION:
        return '#388E3C';
      default:
        return '#616161';
    }
  }

  // ⭐ 新增：根据设备名称自动生成不同的标签背景色，以区分不同设备
  private getDeviceTagColor(deviceName: string): string {
    const colors = ['#007DFF', '#E84026', '#00BFA5', '#FF9900', '#8E24AA', '#D81B60', '#00897B', '#3949AB'];
    if (!deviceName) return '#9E9E9E';
    let hash = 0;
    for (let i = 0; i < deviceName.length; i++) {
      hash = deviceName.charCodeAt(i) + ((hash << 5) - hash);
    }
    return colors[Math.abs(hash) % colors.length];
  }

  @Builder logItemBuilder(item: LogEntity) {
    Row() {
      Text(item.timeStr)
        .fontSize(11)
        .fontColor('#666')
        .width(120)
        .textAlign(TextAlign.Start)

      Text(item.category)
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor(this.getCategoryColor(item.category))
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .borderRadius(4)
        .width(40)
        .textAlign(TextAlign.Center)
        .margin({ left: 4, right: 8 })

      Column() {
        Row() {
          // ⭐ 修改：将原来的普通文本替换为带有背景色的专属设备标签
          Text(item.deviceName || '未知设备')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(this.getDeviceTagColor(item.deviceName))
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin({ right: 8 })

          Text(item.actionType)
            .fontSize(12)
            .fontColor('#333')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(item.content)
          .fontSize(11)
          .fontColor('#888')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 12, right: 12 })
    .backgroundColor(Color.White)
    .border({ width: { bottom: 1 }, color: '#F5F5F5' })
  }

  @Builder dateHeaderBuilder(date: string, expanded: boolean) {
    Row() {
      Text('▶')
        .fontSize(14)
        .fontColor('#666')
        .margin({ right: 6 })
        .rotate({ angle: expanded ? 90 : 0 })
        .animation({ duration: 200, curve: Curve.EaseOut })

      Text(date)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333')
        .layoutWeight(1)

      Text(`${this.vm.getCountByDate(date)} 条`)
        .fontSize(12)
        .fontColor('#999')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#F5F5F5')
    .border({ width: { bottom: 1 }, color: '#E0E0E0' })
    .onClick(() => {
      animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
        this.vm.toggleGroup(date);
      });
    })
  }

  build() {
    Column() {
      this.topNavBar()

      // 工具与筛选栏
      Column() {
        Row() {
          Text('操作日志')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)

          Select(this.vm.categoryOptions)
            .selected(this.vm.selectedCategoryIndex)
            .value(this.vm.categoryOptions[this.vm.selectedCategoryIndex].value as string)
            .font({ size: 12 })
            .selectedOptionFont({ size: 12 })
            .optionFont({ size: 12 })
            .onSelect((index: number) => {
              this.vm.onCategorySelect(index);
            })
            .height(28)
            .backgroundColor('#F5F5F5')
            .borderRadius(4)
            .margin({ right: 12 })

          Button('导出')
            .height(28)
            .fontSize(12)
            .backgroundColor('#2196F3')
            .margin({ right: 8 })
            .onClick(() => this.vm.exportLogs())

          Button('清空')
            .height(28)
            .fontSize(12)
            .backgroundColor('#E53935')
            .onClick(() => {
              AlertDialog.show({
                title: '清空日志',
                message: '确定要清空所有操作日志吗？此操作不可恢复。',
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '清空',
                  fontColor: '#D32F2F',
                  action: () => {
                    this.vm.clearLogs()
                  }
                }
              })
            })
        }
        .width('100%')
        .margin({ bottom: 8 })

        // 搜索框区域
        Row() {
          TextInput({
            text: this.vm.filterText,
            placeholder: '搜索日志内容/设备/操作...'
          })
            .height(36)
            .fontSize(13)
            .backgroundColor('#F5F5F5')
            .borderRadius(18)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.vm.setFilterText(value);
            })
            .layoutWeight(1)

          // 日历跳转按钮
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Text('📅')
              .fontSize(18)
          }
          .width(36)
          .height(36)
          .backgroundColor('#F0F0F0')
          .margin({ left: 8 })
          .onClick(() => {
            this.showDatePickerDialog();
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Color.White)
      .border({ width: { bottom: 1 }, color: '#EEEEEE' })

      // 日志列表
      List({ scroller: this.listScroller }) {
        if (this.vm.groupedLogs.length === 0) {
          ListItem() {
            Column() {
              Image($r('app.media.icon_foreground'))
                .width(40)
                .height(40)
                .opacity(0.3)
                .margin({ bottom: 8 })

              Text('暂无日志记录')
                .fontSize(14)
                .fontColor('#999')
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          }
        } else {
          ForEach(
            this.vm.groupedLogs,
            (group: LogGroup) => {
              // 1. 日期头 ListItem
              ListItem() {
                this.dateHeaderBuilder(group.date, group.expanded)
              }

              // 2. 若展开，渲染子项
              if (group.expanded) {
                ForEach(
                  group.items,
                  (item: LogEntity) => {
                    ListItem() {
                      this.logItemBuilder(item)
                    }
                    .transition({ type: TransitionType.All, opacity: 0, scale: { y: 0.95 } })
                  },
                  // 使用 item 的 id 作为唯一键，防止列表刷新闪烁
                  (item: LogEntity, index: number) => item.id ? item.id.toString() : `${index}_${item.timeStr}`
                )
              }
            },
            // 使用 group.date 作为外层唯一键
            (group: LogGroup) => group.date
          )
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F3F5')
  }
}