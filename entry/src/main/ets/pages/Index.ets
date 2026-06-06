import { common } from '@kit.AbilityKit';
import { BleDevice } from '../bluetooth/BleSearch';
import gattClientManager from '../bluetooth/GattClientManager';
import { DebugViewModel, MultiSendItem, ServiceViewItem, CharViewItem } from '../viewmodel/DebugViewModel';

// === 样式常量 ===
const COLOR_PRIMARY: string = '#1976D2';       // 选中：蓝底
const COLOR_PRIMARY_LIGHT: string = '#E0E0E0'; // 未选中：灰底
const COLOR_SUCCESS: string = '#43A047';
const COLOR_DANGER: string = '#E53935';
const COLOR_PANEL_BG: string = '#1a000000';
const COLOR_INPUT_BG: string = '#12ffffff';

const FONT_SIZE_TITLE: number = 14;
const FONT_SIZE_NORMAL: number = 10; // ⭐ 修改：调整为 10
const FONT_SIZE_HINT: number = 11;

// Tab 按钮
@Builder
function TabButton(text: string, active: boolean, onClick: () => void) {
  Button(text)
  // 当前通道：蓝底；其他：灰底
    .backgroundColor(active ? COLOR_PRIMARY : COLOR_PRIMARY_LIGHT)
    // ★ 为了确认新代码生效，先把字体改成「黑色」
    .fontColor(Color.Black)
    .width('48%')
    .height(36)
    .borderRadius(6)
    .onClick(onClick);
}

@Entry
@Component
struct Index {
  @State vm: DebugViewModel = new DebugViewModel();

  aboutToAppear() {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.vm.initBleCallbacks();
    this.vm.initWithContext(ctx); // 加载多字符串配置
  }

  aboutToDisappear() {
    this.vm.onDisappear();
  }

  /* ========== 顶部：提示 + BLE/TCP 切换 ========== */
  @Builder
  TopHeaderSection() {
    Column() {
      Text(this.vm.message)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 2, bottom: 4 })

      // ★ 调试用，直接显示当前通道
      Text('当前通道：' + this.vm.activeChannel)
        .fontSize(12)
        .fontColor(Color.Gray)
        .margin({ bottom: 4 })

      Row() {
        TabButton('BLE 调试', this.vm.activeChannel === 'BLE', () => {
          this.vm.activeChannel = 'BLE';
        })

        Blank().width('4%')

        TabButton('TCP 调试', this.vm.activeChannel === 'TCP', () => {
          this.vm.activeChannel = 'TCP';
        })
      }
      .margin({ bottom: 6 })
    }
  }

  /* ========== BLE 头部 ========== */
  @Builder
  BleHeaderSection() {
    Column() {
      Text('BLE 状态：' + this.vm.connectStateText)
        .fontSize(FONT_SIZE_TITLE)
        .opacity(0.9)
        .margin({ bottom: 4 })

      if (!this.vm.connectedDeviceId) {
        Row() {
          Button(this.vm.scanning ? '停止扫描' : '扫描设备')
            .fontSize(FONT_SIZE_NORMAL)
            .backgroundColor(this.vm.scanning ? COLOR_DANGER : COLOR_PRIMARY) // ⭐ 优化：扫描中变色
            .fontColor(Color.White)
            .onClick(async () => {
              const ctx = getContext(this) as common.UIAbilityContext;
              if (this.vm.scanning) {
                this.vm.stopBleScan();
              } else {
                await this.vm.startBleScan(ctx);
              }
            })
        }
        .margin({ bottom: 4 })

        if (this.vm.scanning) {
          Row() {
            LoadingProgress().width(16).height(16).color(COLOR_PRIMARY).margin({right: 4})
            Text('正在扫描附近 BLE 设备...')
              .fontSize(FONT_SIZE_HINT)
              .opacity(0.7)
          }
        } else {
          Text('点击上方按钮开始扫描，点击列表连接')
            .fontSize(FONT_SIZE_HINT)
            .opacity(0.7)
        }
      }
    }
    .margin({ bottom: 8 })
  }

  /* ========== TCP 头部 ========== */
  @Builder
  TcpHeaderSection() {
    Column() {
      Text('TCP 状态：' + this.vm.tcpConnectStateText)
        .fontSize(FONT_SIZE_TITLE)
        .opacity(0.9)
        .margin({ bottom: 4 })

      if (!this.vm.tcpConnected) {
        Row() {
          Column() {
            Text('服务器 IP')
              .fontSize(FONT_SIZE_HINT)
              .opacity(0.7)
            TextInput({ text: this.vm.tcpHost, placeholder: '例如：192.168.1.100' })
              .height(32)
              .onChange((v: string) => { this.vm.tcpHost = v; })
          }
          .layoutWeight(2)
          .margin({ right: 6 })

          Column() {
            Text('端口')
              .fontSize(FONT_SIZE_HINT)
              .opacity(0.7)
            TextInput({ text: this.vm.tcpPortText, placeholder: '例如：9000' })
              .height(32)
              .onChange((v: string) => { this.vm.tcpPortText = v; })
          }
          .layoutWeight(1)
          .margin({ right: 6 })

          Button('连接')
            .fontSize(FONT_SIZE_NORMAL)
            .width(80)
            .height(36)
            .backgroundColor(COLOR_PRIMARY)
            .fontColor(Color.White)
            .onClick(async () => { await this.vm.onTcpConnectClick(); })
        }
      } else {
        Text('已连接到 TCP 服务器，断开请使用下方控制区按钮')
          .fontSize(FONT_SIZE_HINT)
          .opacity(0.6)
      }
    }
    .margin({ bottom: 8 })
  }

  /* ========== BLE 设备列表 (⭐ 已美化，不影响其他部分) ========== */
  @Builder
  DeviceListSection() {
    if (this.vm.devices.length === 0) {
      Column() {
        // 使用 Path 绘制简单的蓝牙图标，替代缺失的图片资源
        Stack() {
          Circle({ width: 60, height: 60 })
            .fill('#F5F5F5')
          Path()
            .commands('M22 14 L34 26 L28 32 L28 8 L34 14 L22 26')
            .stroke('#BDBDBD')
            .strokeWidth(2)
            .fill(Color.Gray)
            .width(56)
            .height(40)
        }.margin({ bottom: 10 })

        Text(this.vm.scanning ? '正在搜索中...' : '暂无设备，请点击扫描')
          .fontSize(14)
          .opacity(0.6);
      }
      .width('100%')
      .height('50%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.vm.devices, (item: BleDevice) => {
          ListItem() {
            Row() {
              // 1. 设备图标
              Column() {
                Text('BLE')
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
              .justifyContent(FlexAlign.Center)
              .width(36)
              .height(36)
              .backgroundColor(COLOR_PRIMARY)
              .borderRadius(18)
              .margin({ right: 10 })

              // 2. 设备信息
              Column() {
                Text(item.name && item.name.length > 0 ? item.name : '未知设备')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#333')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(item.id)
                  .fontSize(11) // 略微调大ID字体
                  .fontColor('#999')
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              // 3. 信号强度
              Column() {
                Text(`${item.rssi} dBm`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(item.rssi > -60 ? COLOR_SUCCESS : (item.rssi > -80 ? '#FF9800' : COLOR_DANGER))

                // 信号条动画
                Row({ space: 2 }) {
                  Rect().width(3).height(4).fill(item.rssi > -90 ? '#666' : '#eee')
                  Rect().width(3).height(6).fill(item.rssi > -80 ? '#666' : '#eee')
                  Rect().width(3).height(8).fill(item.rssi > -70 ? '#666' : '#eee')
                  Rect().width(3).height(10).fill(item.rssi > -60 ? '#666' : '#eee')
                }.margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Color.White) // 卡片背景
            .borderRadius(8)
            .shadow({ radius: 2, color: '#1a000000', offsetY: 1 }) // 轻微阴影
          }
          .onClick(() => { this.vm.onSelectDevice(item); })
        }, (item: BleDevice) => item.id)
      }
      .height('55%')
      .width('100%')
      .edgeEffect(EdgeEffect.Spring) // 增加回弹效果
    }
  }

  /* ========== 接收缓冲区 ========== */
  @Builder
  ReceivePanelSection() {
    Column() {
      Text('接收缓冲区')
        .fontSize(FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4 })

      Row() {
        // 左侧控制
        Column() {
          Text('显示模式')
            .fontSize(FONT_SIZE_HINT)
            .opacity(0.7)
            .margin({ bottom: 4 })

          Row() {
            Checkbox()
              .select(this.vm.recvShowText)
              .onChange((value: boolean) => { this.vm.recvShowText = value; })

            Text('文本模式')
              .fontSize(FONT_SIZE_NORMAL)
              .margin({ left: 4 })
          }
          .margin({ bottom: 4 })

          Row() {
            Checkbox()
              .select(this.vm.recvShowHex)
              .onChange((value: boolean) => { this.vm.recvShowHex = value; })

            Text('HEX模式')
              .fontSize(FONT_SIZE_NORMAL)
              .margin({ left: 4 })
          }
          .margin({ bottom: 8 })

          Button('清空接收区')
            .fontSize(FONT_SIZE_NORMAL)
            .margin({ bottom: 4 })
            .onClick(() => {
              if (this.vm.activeChannel === 'BLE') {
                this.vm.bleReceiveHex = '';
                this.vm.bleReceiveText = '';
              } else {
                this.vm.tcpReceiveHex = '';
                this.vm.tcpReceiveText = '';
              }
            })

          Button('保存接收数据')
            .fontSize(FONT_SIZE_NORMAL)
            .margin({ bottom: 4 })
            .onClick(async () => {
              const ctx = getContext(this) as common.UIAbilityContext;
              await this.vm.saveCurrentRecv(ctx);
            })

          Button('复制接收数据') // ⭐ 修复：现在点击此按钮会调用系统剪贴板
            .fontSize(FONT_SIZE_NORMAL)
            .onClick(() => {
              this.vm.copyRecvToArea();
            })
        }
        .width(110)
        .margin({ right: 6 })

        // 右侧显示区
        Column() {
          if (this.vm.recvShowText && this.vm.recvShowHex) {
            Row() {
              Text('文本缓冲区')
                .fontSize(FONT_SIZE_HINT)
                .layoutWeight(1)
                .margin({ bottom: 4 })

              Text('HEX缓冲区')
                .fontSize(FONT_SIZE_HINT)
                .layoutWeight(1)
                .margin({ left: 4, bottom: 4 })
            }
            .width('100%')

            Row() {
              Scroll() {
                Text(this.vm.getCurrentRecvTextRaw().length > 0 ? this.vm.getCurrentRecvTextRaw() : '尚未收到文本数据')
                  .fontSize(FONT_SIZE_NORMAL)
                  .opacity(0.85)
              }
              .layoutWeight(1)
              .width('100%')
              .height(260)
              .backgroundColor(COLOR_PANEL_BG)
              .padding(4)

              Blank().width(4)

              Scroll() {
                Text(this.vm.getCurrentRecvHexRaw().length > 0 ? this.vm.getCurrentRecvHexRaw() : '尚未收到 HEX 数据')
                  .fontSize(FONT_SIZE_NORMAL)
                  .opacity(0.85)
              }
              .layoutWeight(1)
              .width('100%')
              .height(260)
              .backgroundColor(COLOR_PANEL_BG)
              .padding(4)
            }
            .width('100%')
          } else if (this.vm.recvShowText) {
            Text('文本缓冲区')
              .fontSize(FONT_SIZE_HINT)
              .margin({ bottom: 4 })

            Scroll() {
              Text(this.vm.getCurrentRecvTextRaw().length > 0 ? this.vm.getCurrentRecvTextRaw() : '尚未收到文本数据')
                .fontSize(FONT_SIZE_NORMAL)
                .opacity(0.85)
            }
            .width('100%')
            .height(260)
            .backgroundColor(COLOR_PANEL_BG)
            .padding(4)
          } else if (this.vm.recvShowHex) {
            Text('HEX缓冲区')
              .fontSize(FONT_SIZE_HINT)
              .margin({ bottom: 4 })

            Scroll() {
              Text(this.vm.getCurrentRecvHexRaw().length > 0 ? this.vm.getCurrentRecvHexRaw() : '尚未收到 HEX 数据')
                .fontSize(FONT_SIZE_NORMAL)
                .opacity(0.85)
            }
            .width('100%')
            .height(260)
            .backgroundColor(COLOR_PANEL_BG)
            .padding(4)
          } else {
            Scroll() {
              Text('未选择任何显示模式')
                .fontSize(FONT_SIZE_NORMAL)
                .opacity(0.7)
            }
            .width('100%')
            .height(260)
            .backgroundColor(COLOR_PANEL_BG)
            .padding(4)
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .margin({ bottom: 8 })
  }

  /* ========== OTA 设置区域 (新增) ========== */
  @Builder
  OtaSettingsSection() {
    Column() {
      Text('OTA 设置')
        .fontSize(FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4 })

      Row() {
        Text(`包间延时: ${this.vm.otaDelayMs} ms`)
          .fontSize(FONT_SIZE_NORMAL)
          .layoutWeight(1)

        Slider({
          value: this.vm.otaDelayMs,
          min: 0,
          max: 200, // ⭐ 修改：最大延时改为 200ms
          step: 10,
          style: SliderStyle.OutSet
        })
          .blockColor(COLOR_PRIMARY)
          .trackColor(COLOR_PRIMARY_LIGHT)
          .selectedColor(COLOR_PRIMARY)
          .showSteps(true)
          .layoutWeight(2)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.vm.otaDelayMs = Math.round(value);
          })
      }.width('100%').margin({bottom: 8})

      // ⭐ 新增：单包大小控制 (64 - 256)
      Row() {
        Text(`单包大小: ${this.vm.otaPacketSize} Bytes`)
          .fontSize(FONT_SIZE_NORMAL)
          .layoutWeight(1)

        Slider({
          value: this.vm.otaPacketSize,
          min: 64,
          max: 256, // 解锁到 256
          step: 64, // 建议按 64 倍数调整
          style: SliderStyle.OutSet
        })
          .blockColor(COLOR_PRIMARY)
          .trackColor(COLOR_PRIMARY_LIGHT)
          .selectedColor(COLOR_PRIMARY)
          .showSteps(true)
          .layoutWeight(2)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.vm.otaPacketSize = Math.round(value);
          })
      }.width('100%').margin({bottom: 8})

      Text('说明: 增加包长可提高速率，但需单片机支持 (缓冲区>=256)')
        .fontSize(10)
        .fontColor(Color.Gray)
        .width('100%')
    }
    .margin({ bottom: 12 })
  }

  /* ========== 发送缓冲区 ========== */
  @Builder
  SendPanelSection() {
    Column() {
      Text('发送缓冲区')
        .fontSize(FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4 })

      Row() {
        // 左侧控制区
        Column() {
          Text('发送模式')
            .fontSize(FONT_SIZE_HINT)
            .opacity(0.7)
            .margin({ bottom: 4 })

          Button('文本模式')
            .fontSize(FONT_SIZE_NORMAL)
            .backgroundColor(this.vm.sendAsHex ? '#FFFFFF' : COLOR_PRIMARY)
            .fontColor(this.vm.sendAsHex ? COLOR_PRIMARY : Color.White)
            .borderRadius(14)
            .border({ width: 1, color: COLOR_PRIMARY })
            .height(26)
            .width(80)
            .margin({ bottom: 6 })
            .onClick(() => {
              this.vm.sendAsHex = false;
              this.vm.message = '当前发送模式： 文本';
            })

          Button('HEX模式')
            .fontSize(FONT_SIZE_NORMAL)
            .backgroundColor(this.vm.sendAsHex ? COLOR_PRIMARY : '#FFFFFF')
            .fontColor(this.vm.sendAsHex ? Color.White : COLOR_PRIMARY)
            .borderRadius(14)
            .border({ width: 1, color: COLOR_PRIMARY })
            .height(26)
            .width(80)
            .margin({ bottom: 8 })
            .onClick(() => {
              this.vm.sendAsHex = true;
              this.vm.message = '当前发送模式： HEX';
            })

          Button('清空发送') // ⭐ 修改：文字改为“清空发送”
            .fontSize(FONT_SIZE_NORMAL)
            .width(80)
            .onClick(() => { this.vm.sendText = ''; })
        }
        .width(110)
        .margin({ right: 6 })
        .alignItems(HorizontalAlign.Start)

        // 右侧输入框
        Scroll() {
          TextInput({ text: this.vm.sendText, placeholder: '在此输入要发送的数据' })
            .height(90)
            .onChange((value: string) => { this.vm.sendText = value; })
        }
        .height(100)
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(COLOR_INPUT_BG)
        .padding(4)
      }
    }
  }

  /* ========== 多字符串发送区域 ========== */
  @Builder
  MultiSendPanelSection() {
    Column() {
      Text('多字符串发送')
        .fontSize(FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 2 })

      // 标题行
      Row() {
        Blank().width(32)

        Text('发送')
          .fontSize(FONT_SIZE_NORMAL)
          .width(48)

        Text('行')
          .fontSize(FONT_SIZE_NORMAL)
          .width(26)

        Text('内容')
          .fontSize(FONT_SIZE_NORMAL)
          .layoutWeight(1)

        Text('HEX')
          .fontSize(FONT_SIZE_NORMAL)
          .width(40)
          .margin({ left: 8 })
      }
      .margin({ bottom: 4 })
      .width('100%')

      // 每一行
      Scroll() {
        Column() {
          ForEach(this.vm.multiSendList, (item: MultiSendItem, index: number) => {
            Row() {
              Row() {
                Checkbox()
                  .select(this.vm.multiSendList[index]?.enabled ?? false)
                  .width(32)
                  .onChange((v: boolean) => {
                    this.vm.updateMultiSendItem(item.id, (oldItem: MultiSendItem) => {
                      return {
                        id: oldItem.id,
                        enabled: v,
                        text: oldItem.text,
                        hex: oldItem.hex
                      };
                    });
                  })

                Blank().width(4)

                Button(item.id.toString())
                  .fontSize(FONT_SIZE_NORMAL)
                  .width(64)
                  .height(40)
                  .backgroundColor(COLOR_SUCCESS)
                  .fontColor(Color.White)
                  .onClick(() => {
                    const freshItem = this.vm.multiSendList[index];
                    if (freshItem) {
                      this.vm.sendOneMultiItem(freshItem);
                    }
                  })

                Blank().width(8)

                TextInput({
                  text: this.vm.multiSendList[index]?.text ?? '',
                  placeholder: ''
                })
                  .onChange((v: string) => {
                    this.vm.updateMultiSendItem(item.id, (oldItem: MultiSendItem) => {
                      return {
                        id: oldItem.id,
                        enabled: oldItem.enabled,
                        text: v,
                        hex: oldItem.hex
                      };
                    });
                  })
                  .height(32)
                  .layoutWeight(1)
              }
              .layoutWeight(1)

              Checkbox()
                .select(this.vm.multiSendList[index]?.hex ?? false)
                .width(40)
                .margin({ left: 8 })
                .onChange((v: boolean) => {
                  this.vm.updateMultiSendItem(item.id, (oldItem: MultiSendItem) => {
                    return {
                      id: oldItem.id,
                      enabled: oldItem.enabled,
                      text: oldItem.text,
                      hex: v
                    };
                  });
                })
            }
            .margin({ bottom: 6 })
            .width('100%')
          }, (item: MultiSendItem) => item.id.toString())
        }
        .padding({ right: 4 })
      }
      .height(220)
      .width('100%')

      // 清空 & 自动循环
      Row() {
        Button('清空全部数据')
          .fontSize(FONT_SIZE_NORMAL)
          .height(36)
          .backgroundColor(COLOR_DANGER)
          .fontColor(Color.White)
          .onClick(() => {
            this.vm.clearAllMultiSend();
          })

        Blank().width(8)

        Button(this.vm.multiAutoEnabled ? '停止自动循环发送' : '自动循环发送')
          .fontSize(FONT_SIZE_NORMAL)
          .height(36)
          .onClick(() => {
            this.vm.toggleMultiAutoSend();
          })
      }
      .margin({ top: 40 })
      .width('100%')

      // 自动发送 + 周期(ms)
      Row() {
        Button(this.vm.autoSendEnabled ? '停止自动发送' : '自动发送')
          .fontSize(FONT_SIZE_NORMAL)
          .height(34)
          .backgroundColor(COLOR_SUCCESS)
          .fontColor(Color.White)
          .onClick(() => { this.vm.toggleAutoSend(); })

        Blank().width(8)

        Text('周期(ms)')
          .fontSize(FONT_SIZE_HINT)
          .margin({ right: 4 })

        TextInput({ text: this.vm.autoSendIntervalText })
          .height(30)
          .width(80)
          .onChange((v: string) => { this.vm.autoSendIntervalText = v; })
      }
      .margin({ top: 8 })
      .width('100%')

      // 多串间隔 + 循环次数
      Row() {
        Text('多串间隔(ms)')
          .fontSize(FONT_SIZE_HINT)
          .margin({ right: 4 })

        TextInput({ text: this.vm.multiAutoIntervalText })
          .height(30)
          .width(80)
          .onChange((v: string) => { this.vm.setMultiAutoIntervalText(v); })

        Blank().width(12)

        Text('循环次数')
          .fontSize(FONT_SIZE_HINT)
          .margin({ right: 4 })

        TextInput({ text: this.vm.multiAutoLoopCountText })
          .height(30)
          .width(80)
          .onChange((v: string) => { this.vm.setMultiAutoLoopCountText(v); })
      }
      .margin({ top: 6 })
      .width('100%')
    }
  }

  /* ========== 底部控制区 ========== */
  @Builder
  BottomControlSection() {
    Column() {
      // ⭐ 移除：原本用于展示“复制内容”的区域已删除

      // ⭐ OTA 进度条 (只有 OTA 进行时显示)
      if (this.vm.isOtaLoading) {
        Column() {
          Row() {
            Text(`OTA 升级中: ${this.vm.otaProgress}%`).fontSize(12).fontColor(COLOR_PRIMARY)
            Blank()
            // ⭐ 显示实时耗时
            Text(`耗时: ${this.vm.otaCostTime} s`).fontSize(12).fontColor('#666')
          }.width('100%').justifyContent(FlexAlign.Start)

          Progress({ value: this.vm.otaProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(10)
            .color(COLOR_PRIMARY)
            .margin({ bottom: 8 })
        }.width('100%')
      }

      Row() {
        if ((this.vm.activeChannel === 'TCP' && this.vm.tcpConnected) ||
          (this.vm.activeChannel === 'BLE' && this.vm.connectedDeviceId)) {
          Button('断开连接')
            .fontSize(FONT_SIZE_NORMAL)
            .height(32)
            .backgroundColor(COLOR_DANGER)
            .fontColor(Color.White)
            .onClick(async () => {
              if (this.vm.activeChannel === 'TCP') {
                await this.vm.onTcpConnectClick();
                this.vm.tcpConnected = false;
                this.vm.tcpConnectStateText = '未连接';
              } else {
                gattClientManager.stopConnect();
                this.vm.connectedDeviceId = '';
                this.vm.connectStateText = '未连接';
                this.vm.scanning = false;
              }
            })

          Blank().width(4)
        }

        Button('发送数据')
          .fontSize(FONT_SIZE_NORMAL)
          .height(32)
          .backgroundColor(COLOR_SUCCESS)
          .fontColor(Color.White)
          .onClick(() => { this.vm.onSendClick(); })

        Blank().width(4)

        Button('发送回车')
          .fontSize(FONT_SIZE_NORMAL)
          .height(32)
          .onClick(async () => { await this.vm.sendNewLine(); })

        Blank().width(4)

        // ⭐ OTA 升级入口
        Button('OTA 升级')
          .fontSize(FONT_SIZE_NORMAL)
          .height(32)
          .backgroundColor('#FF9800') // 橙色区分
          .fontColor(Color.White)
          .onClick(() => {
            const ctx = getContext(this) as common.UIAbilityContext;
            this.vm.pickFileAndStartOTA(ctx);
          })
      }
    }
    .margin({ top: 0 })
  }

  /* ========== 弹窗：服务选择器 ========== */
  @Builder
  ServiceSelector() {
    Column() {
      Text('请选择服务与特征值')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      List() {
        ForEach(this.vm.serviceList, (svc: ServiceViewItem) => {
          ListItem() {
            Column() {
              // 服务项
              Row() {
                Text(svc.uuid)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.vm.currentServiceUuid === svc.uuid ? COLOR_PRIMARY : '#333333')
                Blank()
                if (svc.isPrimary) {
                  Text('Primary').fontSize(10).fontColor('#999999')
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .onClick(() => {
                this.vm.currentServiceUuid = svc.uuid;
              })

              // 特征值项 (如果选中该服务，或者全部展开)
              if (this.vm.currentServiceUuid === svc.uuid) {
                Column() {
                  ForEach(svc.characteristics, (ch: CharViewItem) => {
                    Row() {
                      Column() {
                        Text(ch.uuid).fontSize(12).fontColor('#666666')
                        Text(ch.properties).fontSize(10).fontColor('#999999')
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      // 勾选写
                      if (ch.canWrite) {
                        Row() {
                          Checkbox()
                            .select(this.vm.selectedWriteUuid === ch.uuid)
                            .onChange((v) => {
                              if (v) this.vm.selectedWriteUuid = ch.uuid;
                            })
                          Text('W').fontSize(10)
                        }.margin({ left: 4 })
                      }

                      // 勾选Notify
                      if (ch.canNotify) {
                        Row() {
                          Checkbox()
                            .select(this.vm.selectedNotifyUuid === ch.uuid)
                            .onChange((v) => {
                              if (v) this.vm.selectedNotifyUuid = ch.uuid;
                            })
                          Text('N').fontSize(10)
                        }.margin({ left: 4 })
                      }
                    }
                    .width('100%')
                    .padding({ top: 4, bottom: 4, left: 16 })
                    .backgroundColor('#FAFAFA')
                  })
                }
              }
            }
          }
        })
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        Button('取消')
          .fontSize(14)
          .backgroundColor(COLOR_PRIMARY_LIGHT)
          .fontColor('#333333')
          .onClick(() => { this.vm.cancelServiceSelection(); })
          .layoutWeight(1)

        Blank().width(12)

        Button('确定连接')
          .fontSize(14)
          .backgroundColor(COLOR_PRIMARY)
          .fontColor(Color.White)
          .onClick(() => { this.vm.confirmServiceSelection(); })
          .layoutWeight(1)
      }
      .margin({ top: 12 })
      .width('100%')
    }
    .width('90%')
    .height('70%')
    .backgroundColor(Color.White)
    .borderRadius(12)
    .padding(16)
    .shadow({ radius: 10, color: '#33000000', offsetY: 4 })
    .zIndex(1000) // ⭐ 关键修复：提升层级，确保在蒙层之上，且颜色正常
  }

  /* ========== 根 build：左侧收发 + 右侧多字符串 ========== */
  build() {
    Stack() {
      // 主内容
      Scroll() {
        Column() {
          this.TopHeaderSection();

          if (this.vm.activeChannel === 'BLE') {
            this.BleHeaderSection();

            if (!this.vm.connectedDeviceId) {
              this.DeviceListSection();
            } else {
              Row() {
                Column() {
                  this.ReceivePanelSection();
                  // ⭐ 新增：OTA 设置放在左侧栏
                  this.OtaSettingsSection();
                  this.SendPanelSection();
                }
                .width('65%')
                .margin({ right: 6 })

                Column() {
                  this.MultiSendPanelSection();
                }
                .width('35%')
                .margin({ left: 8 })
              }
              .alignItems(VerticalAlign.Top)

              this.BottomControlSection();
            }
          } else {
            this.TcpHeaderSection();

            if (this.vm.tcpConnected) {
              Row() {
                Column() {
                  this.ReceivePanelSection();
                  // ⭐ 新增：OTA 设置放在左侧栏
                  this.OtaSettingsSection();
                  this.SendPanelSection();
                }
                .width('65%')
                .margin({ right: 6 })

                Column() {
                  this.MultiSendPanelSection();
                }
                .width('35%')
                .margin({ left: 8 })
              }
              .alignItems(VerticalAlign.Top)

              this.BottomControlSection();
            }
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 0, bottom: 8 })
      }
      .width('100%')
      .height('100%')

      // 服务选择弹窗蒙层
      if (this.vm.showServiceSelector) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => { /* block clicks */ })
          .zIndex(999)

        this.ServiceSelector()
      }
    }
  }
}