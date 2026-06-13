import { common } from '@kit.AbilityKit';
import { BleDevice } from '../bluetooth/BleSearch';
import gattClientManager from '../bluetooth/GattClientManager';
import { DebugViewModel, MultiSendItem, ServiceViewItem, CharViewItem } from '../viewmodel/DebugViewModel';

// === 样式常量 ===
const COLOR_PRIMARY: string = '#1976D2';       
const COLOR_PRIMARY_LIGHT: string = '#E0E0E0'; 
const COLOR_SUCCESS: string = '#43A047';
const COLOR_DANGER: string = '#E53935';
const COLOR_PANEL_BG: string = '#1a000000';
const COLOR_INPUT_BG: string = '#12ffffff';

const FONT_SIZE_TITLE: number = 14;
const FONT_SIZE_NORMAL: number = 10; 
const FONT_SIZE_HINT: number = 11;

@Entry
@Component
struct Index {
  @State vm: DebugViewModel = new DebugViewModel();

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.uiContext = this.getUIContext();
    this.vm.initBleCallbacks();
    this.vm.initWithContext(ctx); 
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

      Row() {
        Button('BLE 调试')
          .backgroundColor(this.vm.activeChannel === 'BLE' ? COLOR_PRIMARY : COLOR_PRIMARY_LIGHT)
          .fontColor(this.vm.activeChannel === 'BLE' ? Color.White : Color.Black)
          .width('48%')
          .height(36)
          .borderRadius(6)
          .onClick(() => {
            this.vm.activeChannel = 'BLE';
          })

        Blank().width('4%')

        Button('TCP 调试')
          .backgroundColor(this.vm.activeChannel === 'TCP' ? COLOR_PRIMARY : COLOR_PRIMARY_LIGHT)
          .fontColor(this.vm.activeChannel === 'TCP' ? Color.White : Color.Black)
          .width('48%')
          .height(36)
          .borderRadius(6)
          .onClick(() => {
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
            .backgroundColor(this.vm.scanning ? COLOR_DANGER : COLOR_PRIMARY) 
            .fontColor(Color.White)
            .onClick(async () => {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
        
        Text(`本机验证码 (MQT): ${this.vm.virtualMqttCode || '生成中...'}`)
          .fontSize(FONT_SIZE_HINT)
          .fontColor(COLOR_PRIMARY)
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)
      } else {
        Row() {
          Text(`已连接到 TCP 服务器 | 本机 MQT: ${this.vm.virtualMqttCode}`)
            .fontSize(FONT_SIZE_HINT)
            .opacity(0.6)
            .layoutWeight(1)
          
          Button('发送 MQT 验证')
            .fontSize(10)
            .height(26)
            .backgroundColor('#FF9800')
            .onClick(() => { this.vm.sendMqttAuth(); })
        }.width('100%').alignItems(VerticalAlign.Center)
      }
    }
    .margin({ bottom: 8 })
  }

  /* ========== BLE 设备列表 ========== */
  @Builder
  DeviceListSection() {
    if (this.vm.devices.length === 0) {
      Column() {
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

              Column() {
                Text(item.name && item.name.length > 0 ? item.name : '未知设备')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#333')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(item.id)
                  .fontSize(11) 
                  .fontColor('#999')
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column() {
                Text(`${item.rssi} dBm`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(item.rssi > -60 ? COLOR_SUCCESS : (item.rssi > -80 ? '#FF9800' : COLOR_DANGER))

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
            .backgroundColor(Color.White) 
            .borderRadius(8)
            .shadow({ radius: 2, color: '#1a000000', offsetY: 1 }) 
          }
          .onClick(() => { this.vm.onSelectDevice(item); })
        }, (item: BleDevice) => item.id)
      }
      .height('55%')
      .width('100%')
      .edgeEffect(EdgeEffect.Spring) 
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
            Button('文本')
              .fontSize(FONT_SIZE_NORMAL)
              .backgroundColor(this.vm.recvDisplayMode === 'TEXT' ? COLOR_PRIMARY : '#FFFFFF')
              .fontColor(this.vm.recvDisplayMode === 'TEXT' ? Color.White : COLOR_PRIMARY)
              .borderRadius(4)
              .border({ width: 1, color: COLOR_PRIMARY })
              .height(26)
              .layoutWeight(1)
              .margin({ right: 4, bottom: 8 })
              .onClick(() => { this.vm.recvDisplayMode = 'TEXT'; })

            Button('HEX')
              .fontSize(FONT_SIZE_NORMAL)
              .backgroundColor(this.vm.recvDisplayMode === 'HEX' ? COLOR_PRIMARY : '#FFFFFF')
              .fontColor(this.vm.recvDisplayMode === 'HEX' ? Color.White : COLOR_PRIMARY)
              .borderRadius(4)
              .border({ width: 1, color: COLOR_PRIMARY })
              .height(26)
              .layoutWeight(1)
              .margin({ bottom: 8 })
              .onClick(() => { this.vm.recvDisplayMode = 'HEX'; })
          }

          Button('清空接收区')
            .fontSize(FONT_SIZE_NORMAL)
            .margin({ bottom: 4 })
            .width('100%')
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
            .width('100%')
            .onClick(async () => {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              await this.vm.saveCurrentRecv(ctx);
            })

          Button('复制当前缓冲') 
            .fontSize(FONT_SIZE_NORMAL)
            .width('100%')
            .onClick(() => {
              this.vm.copyRecvToArea();
            })
        }
        .width(130)
        .margin({ right: 6 })

        // 右侧统一显示区
        Column() {
          Text(this.vm.recvDisplayMode === 'HEX' ? 'HEX 视图' : '文本 视图')
            .fontSize(FONT_SIZE_HINT)
            .margin({ bottom: 4 })

          Scroll() {
            Text(this.vm.recvDisplayMode === 'HEX' 
              ? (this.vm.getCurrentRecvHexRaw().length > 0 ? this.vm.getCurrentRecvHexRaw() : '尚未收到 HEX 数据')
              : (this.vm.getCurrentRecvTextRaw().length > 0 ? this.vm.getCurrentRecvTextRaw() : '尚未收到文本数据'))
              .fontSize(FONT_SIZE_NORMAL)
              .opacity(0.85)
          }
          .width('100%')
          .height(180)
          .backgroundColor(COLOR_PANEL_BG)
          .padding(4)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .margin({ bottom: 8 })
  }

  /* ========== OTA 设置区域 ========== */
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
          max: 200, 
          step: 10,
          style: SliderStyle.OutSet
        })
          .blockColor(COLOR_PRIMARY)
          .trackColor(COLOR_PRIMARY_LIGHT)
          .selectedColor(COLOR_PRIMARY)
          .showSteps(true)
          .layoutWeight(2)
          .onChange((value: number) => {
            this.vm.otaDelayMs = Math.round(value);
          })
      }.width('100%').margin({bottom: 8})

      Row() {
        Text(`单包大小: ${this.vm.otaPacketSize} Bytes`)
          .fontSize(FONT_SIZE_NORMAL)
          .layoutWeight(1)

        Slider({
          value: this.vm.otaPacketSize,
          min: 64,
          max: 256, 
          step: 64, 
          style: SliderStyle.OutSet
        })
          .blockColor(COLOR_PRIMARY)
          .trackColor(COLOR_PRIMARY_LIGHT)
          .selectedColor(COLOR_PRIMARY)
          .showSteps(true)
          .layoutWeight(2)
          .onChange((value: number) => {
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

          Button('清空发送') 
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

      Row() {
        Text('启用').fontSize(FONT_SIZE_NORMAL).width(32).textAlign(TextAlign.Center)
        Text('行号').fontSize(FONT_SIZE_NORMAL).width(46).textAlign(TextAlign.Center).margin({ left: 4 })
        Text('内容').fontSize(FONT_SIZE_NORMAL).layoutWeight(2).margin({ left: 4 })
        Text('HEX').fontSize(FONT_SIZE_NORMAL).width(32).textAlign(TextAlign.Center).margin({ left: 4 })
        Text('备注').fontSize(FONT_SIZE_NORMAL).layoutWeight(1).margin({ left: 4 })
      }
      .margin({ bottom: 4 })
      .width('100%')

      Scroll() {
        Column() {
          ForEach(this.vm.multiSendList, (item: MultiSendItem, index: number) => {
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
                      hex: oldItem.hex,
                      remark: oldItem.remark
                    };
                  });
                })

              Button(item.id.toString())
                .fontSize(FONT_SIZE_NORMAL)
                .width(46)
                .height(32)
                .margin({ left: 4 })
                .backgroundColor(COLOR_SUCCESS)
                .fontColor(Color.White)
                .onClick(() => {
                  const freshItem = this.vm.multiSendList[index];
                  if (freshItem) { this.vm.sendOneMultiItem(freshItem); }
                })

              TextInput({
                text: this.vm.multiSendList[index]?.text ?? '',
                placeholder: '内容'
              })
                .height(32)
                .layoutWeight(2)
                .margin({ left: 4 })
                .onChange((v: string) => {
                  this.vm.updateMultiSendItem(item.id, (oldItem: MultiSendItem) => {
                    return {
                      id: oldItem.id,
                      enabled: oldItem.enabled,
                      text: v,
                      hex: oldItem.hex,
                      remark: oldItem.remark
                    };
                  });
                })

              Checkbox()
                .select(this.vm.multiSendList[index]?.hex ?? false)
                .width(32)
                .margin({ left: 4 })
                .onChange((v: boolean) => {
                  this.vm.updateMultiSendItem(item.id, (oldItem: MultiSendItem) => {
                    return {
                      id: oldItem.id,
                      enabled: oldItem.enabled,
                      text: oldItem.text,
                      hex: v,
                      remark: oldItem.remark
                    };
                  });
                })

              TextInput({
                text: this.vm.multiSendList[index]?.remark ?? '',
                placeholder: '备注'
              })
                .height(32)
                .layoutWeight(1)
                .margin({ left: 4 })
                .padding({ left: 6, right: 6 }) 
                .onChange((v: string) => {
                  this.vm.updateMultiSendItem(item.id, (oldItem: MultiSendItem) => {
                    return {
                      id: oldItem.id,
                      enabled: oldItem.enabled,
                      text: oldItem.text,
                      hex: oldItem.hex,
                      remark: v
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
      .height(260) 
      .width('100%')

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
      if (this.vm.isOtaLoading) {
        Column() {
          Row() {
            Text(`OTA 升级中: ${this.vm.otaProgress}%`).fontSize(12).fontColor(COLOR_PRIMARY)
            Blank()
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

        Button('OTA 升级')
          .fontSize(FONT_SIZE_NORMAL)
          .height(32)
          .backgroundColor('#FF9800') 
          .fontColor(Color.White)
          .onClick(() => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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

              // 特征值项
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
      .height('100%')

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
    .zIndex(1000) 
  }

  /* ========== 根 build ========== */
  build() {
    Stack() {
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
                  this.OtaSettingsSection();
                  this.SendPanelSection();
                }
                .width('60%') 
                .margin({ right: 6 })

                Column() {
                  this.MultiSendPanelSection();
                }
                .width('40%')
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
                  this.OtaSettingsSection();
                  this.SendPanelSection();
                }
                .width('60%')
                .margin({ right: 6 })

                Column() {
                  this.MultiSendPanelSection();
                }
                .width('40%')
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