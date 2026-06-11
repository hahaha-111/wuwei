import { FilterSettingViewModel, FilterSettingPageParams } from '../viewmodel/FilterSettingViewModel';

@Entry
@Component
struct FilterSettingPage {
@State vm: FilterSettingViewModel = new FilterSettingViewModel();

aboutToAppear(): void {
// ⭐ 修复警告：改用当前页面实例绑定的 UIContext 提取路由参数
const params = this.getUIContext().getRouter().getParams() as FilterSettingPageParams;
this.vm.init(params);
}

aboutToDisappear(): void {
this.vm.onDisappear();
}

build() {
Column() {
  // 顶部导航栏 (无底部导航，仅返回功能)
  Row() {
    Button('返回', { type: ButtonType.Normal })
      .borderRadius(6)
      .backgroundColor('#1976D2')
      // ⭐ 修复警告：改用不被弃用的 getRouter().back() API 完成安全页面返回
      .onClick((): void => { this.getUIContext().getRouter().back(); })
      .margin({ right: 16 })
      .height(36)
    Text('滤波高级设置')
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor('#333333')
  }
  .width('100%')
  .padding(16)
  .backgroundColor('#FFFFFF')
  .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
  .zIndex(1)

  // 核心设置操作区
  Scroll() {
    Column({ space: 12 }) {
          
      // 滤波开关
      Row() {
        Text('滤波开关').width('35%').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
        Checkbox({ name: 'filterSwitch' })
          .select(this.vm.filterSwitch)
          .onChange((v: boolean): void => {
            this.vm.setFilterSwitch(v);
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .shadow({ radius: 2, color: '#05000000', offsetY: 1 })

      // 起始时间
      Row() {
        Text('起始时间').width('35%').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
        TextInput({ text: this.vm.startHour })
          .width('15%')
          .type(InputType.Number)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F5F5F5')
          .onChange((v: string): void => { this.vm.startHour = v; })
        Text(' : ').fontSize(16).margin({ left: 8, right: 8 }).fontWeight(FontWeight.Bold)
        TextInput({ text: this.vm.startMinute })
          .width('15%')
          .type(InputType.Number)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F5F5F5')
          .onChange((v: string): void => { this.vm.startMinute = v; })
        Blank()
        Button('设置')
          .height(36)
          .backgroundColor('#E53935')
          .onClick((): void => { this.vm.setStartTime(); })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .shadow({ radius: 2, color: '#05000000', offsetY: 1 })

      // 结束时间
      Row() {
        Text('结束时间').width('35%').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
        TextInput({ text: this.vm.endHour })
          .width('15%')
          .type(InputType.Number)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F5F5F5')
          .onChange((v: string): void => { this.vm.endHour = v; })
        Text(' : ').fontSize(16).margin({ left: 8, right: 8 }).fontWeight(FontWeight.Bold)
        TextInput({ text: this.vm.endMinute })
          .width('15%')
          .type(InputType.Number)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F5F5F5')
          .onChange((v: string): void => { this.vm.endMinute = v; })
        Blank()
        Button('设置')
          .height(36)
          .backgroundColor('#E53935')
          .onClick((): void => { this.vm.setEndTime(); })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .shadow({ radius: 2, color: '#05000000', offsetY: 1 })

      // 预警时长
      Row() {
        Text('预警时长').width('35%').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
        TextInput({ text: this.vm.warnDuration })
          .width('25%')
          .type(InputType.Number)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F5F5F5')
          .onChange((v: string): void => { this.vm.warnDuration = v; })
        Text('秒').fontSize(14).margin({ left: 8 }).fontColor('#666')
        Blank()
        Button('设置')
          .height(36)
          .backgroundColor('#E53935')
          .onClick((): void => { this.vm.setWarnDuration(); })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .shadow({ radius: 2, color: '#05000000', offsetY: 1 })

      // 设备状态与全局刷新
      Row() {
        Text('设备状态').width('35%').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
            
        Row() {
          Circle({ width: 14, height: 14 })
            .fill(this.vm.inWindowStatus ? '#4CAF50' : '#9E9E9E')
            .margin({ right: 6 })
          Text('滤波窗内').fontSize(14).margin({ right: 16 }).fontColor('#555')

          Circle({ width: 14, height: 14 })
            .fill(this.vm.warnLedStatus ? '#F44336' : '#9E9E9E')
            .margin({ right: 6 })
          Text('预警灯').fontSize(14).fontColor('#555')
        }.layoutWeight(1)
            
        // ⭐ 刷新按钮加入防重复点击以及文字状态切换
        Button(this.vm.isReading ? '读取中...' : '刷新读取')
          .height(36)
          .backgroundColor(this.vm.isReading ? '#90CAF9' : '#2196F3')
          .enabled(!this.vm.isReading)
          .onClick((): void => { this.vm.readAll(); })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .shadow({ radius: 2, color: '#05000000', offsetY: 1 })

    }
    .width('100%')
    .padding(16)
  }
  .layoutWeight(1)
  .align(Alignment.Top)

}
.width('100%')
.height('100%')
.backgroundColor('#F5F7FA')
}
}