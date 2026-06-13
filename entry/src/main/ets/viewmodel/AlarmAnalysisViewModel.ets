// viewmodel/AlarmAnalysisViewModel.ets
import { TcpClient, TcpMessageEvent } from '../Network/TcpClient';
import { TcpDeviceManager } from '../Network/TcpDeviceManager';
import { getSystemInfo } from '../common/DeviceInfoUtil';
import { UIContext } from '@kit.ArkUI'; // ⭐ 修改：导入 UIContext，统一配合 API 13 路由与弹窗
import { BusinessError } from '@ohos.base';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit'; 

import { TcpTransport } from '../common/transport/TcpTransport';
import { ProtocolParser, ProtocolFrame } from '../common/ProtocolParser';
import { FileUtil } from '../common/utils/FileUtil';

export interface AlarmRowData {
  port: string;
  items: string[];
  severity: number;
  bgColor: string;
}

export type ConnectedDeviceKind = 'MICROWAVE_RX' | 'MICROWAVE_TX' | 'FIBER' | 'UNKNOWN';

@Observed
export class AlarmAnalysisViewModel {
  headerList: string[] = [];
  rowList: AlarmRowData[] = [];
  
  emailText: string = '';
  isSubscribed: boolean = false;
  
  loadStatusText: string = '正在加载数据...';
  isUpdating: boolean = false; // 控制页面刷新读取等待态
  
  private readonly SERVER_IP: string = '43.138.24.214';
  private readonly SERVER_PORT: number = 10000;

  private localParser: ProtocolParser = new ProtocolParser();
  private readonly LISTENER_KEY = 'AlarmAnalysisVM';
  private detectingDevice: boolean = false;
  private detectPhase: 'IDLE' | 'MICROWAVE_RX' | 'FIBER' | 'MICROWAVE_TX' = 'IDLE';
  private currentPhaseResolve?: (kind: ConnectedDeviceKind) => void;

  // ⭐ 新增：存放从 Page 传进来的界面上下文对象，完美适配 HarmonyOS API 13+ 多窗口标准
  public uiContext: UIContext | null = null;

  // 用于申请更新的长数据包缓冲区与防截断定时器
  private receiveBuffer: string = '';
  private receiveTimer: number = 0;

  // ⭐ 新增：安全的 Prompt 辅助方法，避开已过时的全局 promptAction.showToast 调用
  private showToastMsg(msg: string): void {
    if (this.uiContext) {
      try {
        this.uiContext.getPromptAction().showToast({ message: msg });
      } catch (e) {
        // ignore
      }
    }
  }

  // ⭐ 优化：ViewModel 不再直接导入任何废弃的路由接口，由 View 层获取安全 Params 后经此初始化
  initData(params: Record<string, string>): void {
    if (params) {
      console.info('AlarmAnalysis', '👉 路由参数解析成功: ' + JSON.stringify(params));
    }
    
    if (params && params.alarmData) {
      console.info('AlarmAnalysis', '👉 收到的原始报警数据:\n' + params.alarmData);
      this.parseAlarmData(params.alarmData);
    } else {
      console.error('AlarmAnalysis', '❌ 没有收到 alarmData 参数！');
      this.loadStatusText = '未收到任何数据，请返回重试';
    }
  }

  private parseAlarmData(rawData: string): void {
    const lines = rawData.split(/\r?\n/).filter((line: string): boolean => line.trim().length > 0);
    if (lines.length === 0) {
      this.loadStatusText = '数据内容为空';
      return;
    }

    let headerLine = lines[0];
    headerLine = headerLine.replace(/年|月/g, '/').replace(/日/g, '');
    this.headerList = headerLine.split('|').filter((item: string): boolean => item.trim() !== '');

    if (lines.length === 1) {
      this.loadStatusText = '当前设备暂无报警记录数据';
      return; 
    }

    const tempRows: AlarmRowData[] = [];
  
    for (let i = 1; i < lines.length; i++) {
      let content = lines[i];
      const firstPipeIndex = content.indexOf('|');
      if (firstPipeIndex === -1) continue;
      
      const port = content.substring(0, firstPipeIndex);
      content = content.substring(firstPipeIndex + 1); 
      const parts = content.split('|');
      
      if (parts.length > 3) {
        let severity = 0;
        const loopCount = parts.length - 6; // 对齐E4A: 剔除后面多余列

        // ⭐ j 从 1 开始，避开 index 0 的设备名称(如"微波接收")。从而完美解决 "0->2->2" 误算为 2 天新增的 Bug
        for (let j = 1; j <= loopCount; j++) {
          const data1 = parts[j].replace(/\s/g, '');
          const data2 = parts[j + 1].replace(/\s/g, '');
          if (data1 !== '' && data2 !== '' && data1 !== data2) {
            severity++;
          }
        }
        
        let bgColor = '#FF66FFCC'; // 严重程度=0: 蓝绿 (安全，无变化)
        if (severity === 1) bgColor = '#FF00E0FF';      // 严重程度=1: 浅蓝 (1天有新增)
        else if (severity === 2) bgColor = '#FFFFFFCC'; // 严重程度=2: 浅黄 (2天有新增)
        else if (severity === 3) bgColor = '#FFFF9933'; // 严重程度=3: 浅橘 (3天有新增)
        else if (severity > 3) bgColor = '#FFFC1E1E';   // 严重程度>3: 红 (高危，大于3天新增)

        tempRows.push({ port, items: parts, severity, bgColor });
      }
    }
    
    this.rowList = tempRows;
    this.loadStatusText = this.rowList.length > 0 ? '加载完成' : '没有找到符合条件的数据行';
  }

  async connectDevice(portStr: string): Promise<ConnectedDeviceKind> {
    const port = parseInt(portStr);
    if (isNaN(port)) {
      throw new Error('该行无有效端口标记');
    }

    this.showToastMsg(`正在连接端口 ${port} ...`);
    this.localParser = new ProtocolParser();
    
    await TcpDeviceManager.instance.connectDevice(this.SERVER_IP, port);
    
    const transport = TcpTransport.getInstance();
    transport.setOnDataReceived(this.LISTENER_KEY, (data: Uint8Array): void => {
      const frames = this.localParser.feed(data);
      frames.forEach((frame: ProtocolFrame): void => this.handleDeviceDetectFrame(frame));
    });

    return await this.detectDeviceTypeByProtocol();
  }

  private handleDeviceDetectFrame(frame: ProtocolFrame): void {
    if (!this.detectingDevice) return;
    
    if (frame.deviceType === 0x66) {
      this.resolveDetectedKind('FIBER');
    } else if (frame.deviceType === 0xC9 && frame.data.length >= 1) {
      const echoedCmd = frame.data[0];
      if (echoedCmd === 0x96 || echoedCmd === 0x97) {
        this.resolveDetectedKind('MICROWAVE_TX');
      } else if (echoedCmd === 0x0B) {
        if (this.detectPhase === 'MICROWAVE_RX') {
          this.resolveDetectedKind('MICROWAVE_RX');
        }
      }
    }
  }

  private resolveDetectedKind(kind: ConnectedDeviceKind): void {
    if (!this.detectingDevice) return;
    if (this.currentPhaseResolve) {
      const cb = this.currentPhaseResolve;
      this.currentPhaseResolve = undefined;
      cb(kind);
    }
  }

  private runDetectPhase(phase: 'MICROWAVE_RX' | 'FIBER' | 'MICROWAVE_TX', sendFn: () => void, timeoutMs: number): Promise<ConnectedDeviceKind | null> {
    return new Promise<ConnectedDeviceKind | null>((resolve: (value: ConnectedDeviceKind | null) => void): void => {
      let done = false;
      let timer: number;
      
      const finish = (kind: ConnectedDeviceKind | null): void => {
        if (done) return;
        done = true;
        this.detectingDevice = false;
        this.detectPhase = 'IDLE';
        this.currentPhaseResolve = undefined;
        clearTimeout(timer);
        resolve(kind);
      };
      
      this.detectPhase = phase;
      this.detectingDevice = true;
      this.currentPhaseResolve = finish;
      
      try { 
        sendFn(); 
      } catch (e) { 
        finish(null); 
        return; 
      }
      
      timer = setTimeout((): void => finish(null), timeoutMs);
    });
  }

  private async detectDeviceTypeByProtocol(): Promise<ConnectedDeviceKind> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 150);
    });
    
    let kind: ConnectedDeviceKind | null;

    kind = await this.runDetectPhase('MICROWAVE_TX', (): void => { TcpDeviceManager.instance.sendHexString('FF01C9019660'); }, 800);
    if (kind) return kind;
    
    kind = await this.runDetectPhase('MICROWAVE_TX', (): void => { TcpDeviceManager.instance.sendHexString('FF01C9019660'); }, 800);
    if (kind) return kind;

    kind = await this.runDetectPhase('MICROWAVE_RX', (): void => { TcpDeviceManager.instance.sendHexString('FF01C9010BD5'); }, 800);
    if (kind) {
      const recheck = await this.runDetectPhase('MICROWAVE_TX', (): void => { TcpDeviceManager.instance.sendHexString('FF01C9019660'); }, 500);
      if (recheck === 'MICROWAVE_TX') return 'MICROWAVE_TX';
      return 'MICROWAVE_RX';
    }
    
    kind = await this.runDetectPhase('MICROWAVE_RX', (): void => { TcpDeviceManager.instance.sendHexString('FF01C9010BD5'); }, 800);
    if (kind) {
      const recheck = await this.runDetectPhase('MICROWAVE_TX', (): void => { TcpDeviceManager.instance.sendHexString('FF01C9019660'); }, 500);
      if (recheck === 'MICROWAVE_TX') return 'MICROWAVE_TX';
      return 'MICROWAVE_RX';
    }

    for (let addr = 0x00; addr <= 0x0F; addr++) {
      if (!TcpDeviceManager.instance.isConnected) return 'UNKNOWN';
      
      const addrHex = addr.toString(16).padStart(2, '0').toUpperCase();
      const sum = addr + 0x66 + 0x01 + 0xAA;
      const csHex = (sum & 0xFF).toString(16).padStart(2, '0').toUpperCase();
      const cmdHex = `FF${addrHex}6601AA${csHex}`;
      
      kind = await this.runDetectPhase('FIBER', (): void => { TcpDeviceManager.instance.sendHexString(cmdHex); }, 200);
      if (kind) return kind;
    }
    
    return 'UNKNOWN';
  }

  onDestroy(): void {
    TcpTransport.getInstance().offDataReceived(this.LISTENER_KEY);
  }

  async requestUpdate(): Promise<void> {
    if (this.isUpdating) {
      this.showToastMsg('正在更新中，请稍候...');
      return;
    }

    this.isUpdating = true;
    this.receiveBuffer = '';
    
    if (this.receiveTimer) {
      clearTimeout(this.receiveTimer);
      this.receiveTimer = 0;
    }

    try {
      this.showToastMsg('正在申请更新数据,请稍等....');
      let tcpClient = new TcpClient({ host: this.SERVER_IP, port: this.SERVER_PORT, timeout: 5000 });
      
      tcpClient.setOnConnect((): void => {
        const executeUpdate = async (): Promise<void> => {
          try {
            const sysInfo = await getSystemInfo();
            await tcpClient.sendTextGbk(sysInfo.info);
            
            let imei = 'default_imei';
            const match = sysInfo.info.match(/mqt=([^,]+)/);
            if (match && match[1]) imei = match[1].trim();

            await new Promise<void>((resolve: () => void): void => {
              setTimeout(resolve, 150);
            });

            const cmd = `${imei}|申请更新`;
            await tcpClient.sendTextGbk(cmd);
          } catch (e) {
            const err = e as BusinessError;
            this.showToastMsg(`发送指令失败: ${err.message}`);
            this.isUpdating = false;
          }
        };

        executeUpdate().catch((err: BusinessError): void => {
           console.error('AlarmAnalysis', `执行更新逻辑异常: ${err.message}`);
           this.isUpdating = false;
        });
      });

      tcpClient.setOnMessage((event: TcpMessageEvent): void => {
        const data = new Uint8Array(event.message);
        try {
          const decoder = new util.TextDecoder('gbk', { ignoreBOM: true });
          this.receiveBuffer += decoder.decodeToString(data);
        } catch (e) {
          console.error('GBK解码异常', e);
        }

        if (this.receiveTimer) {
          clearTimeout(this.receiveTimer);
        }

        this.receiveTimer = setTimeout((): void => {
          console.info('AlarmAnalysis', '👉 申请更新后获得的新数据:\n' + this.receiveBuffer);
          
          if (this.receiveBuffer.includes('设备名')) {
            this.parseAlarmData(this.receiveBuffer);
            this.showToastMsg('更新数据成功!');
          } else {
            this.showToastMsg('未收到有效的设备统计更新数据');
          }

          tcpClient.close();
          this.isUpdating = false;
        }, 400); 
      });
      
      tcpClient.setOnError((err: BusinessError): void => {
        this.showToastMsg(`连接服务器失败: ${err.message}`);
        this.isUpdating = false;
      });

      tcpClient.setOnClose((): void => {
        this.isUpdating = false;
      });
      
      await tcpClient.connect();
    } catch (e) {
      this.showToastMsg('TCP连接初始化失败');
      this.isUpdating = false;
    }
  }

  async sendSubscriptionCommand(checked: boolean): Promise<void> {
    const email = this.emailText.trim();
    const emailRegex = /^\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$/;
    if (!emailRegex.test(email)) {
      this.showToastMsg('邮箱输入不合法!请检查输入邮箱是否有误!');
      this.isSubscribed = !checked;
      return;
    }

    try {
      let tcpClient = new TcpClient({ host: this.SERVER_IP, port: this.SERVER_PORT, timeout: 5000 });
      
      tcpClient.setOnConnect((): void => {
        const executeSubscribe = async (): Promise<void> => {
          try {
            const sysInfo = await getSystemInfo();
            await tcpClient.sendTextGbk(sysInfo.info);
            
            let imei = 'default_imei';
            const match = sysInfo.info.match(/mqt=([^,]+)/);
            if (match && match[1]) imei = match[1].trim();

            await new Promise<void>((resolve: () => void): void => {
              setTimeout(resolve, 150);
            });

            const action = checked ? '订阅更新' : '取消订阅';
            const cmd = `${imei}|${action}|${email}`;
            
            await tcpClient.sendTextGbk(cmd);
            
            if (checked) {
              this.showToastMsg('已订阅报警周报,每周数据将发送到指定邮箱!');
            } else {
              this.showToastMsg('已取消订阅周报,将不再接收数据!');
            }

            setTimeout((): void => {
              tcpClient.close();
            }, 500);
          } catch (e) {
            this.showToastMsg('下发订阅请求指令失败');
          }
        };

        executeSubscribe().catch(() => {});
      });

      await tcpClient.connect();
    } catch (e) {
      this.showToastMsg('TCP服务连接超时，订阅失败');
    }
  }

  async exportAnalysisReport(context: common.UIAbilityContext | null): Promise<void> {
    if (this.headerList.length === 0 || this.rowList.length === 0) {
      this.showToastMsg('无分析记录可供导出');
      return;
    }
    if (!context) return;

    try {
      let csvContent = '\uFEFF';
      csvContent += this.headerList.join(',') + '\n';
      
      this.rowList.forEach((row: AlarmRowData): void => {
        csvContent += row.items.join(',') + '\n';
      });

      const pathDir = FileUtil.getStandardPath(context, '报警分析', '报警记录');
      const fileName = FileUtil.generateFileName('.csv');
      const fullPath = `${pathDir}/${fileName}`;

      await FileUtil.writeText(fullPath, csvContent);
      this.showToastMsg(`CSV 报表导出成功! \n文件名: ${fileName}`);
    } catch (e) {
      const err = e as Error;
      this.showToastMsg(`导出失败: ${err.message}`);
    }
  }
}