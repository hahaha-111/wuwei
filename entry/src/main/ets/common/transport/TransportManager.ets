// 注意：文件后缀必须是 .ets
import { ITransport } from './ITransport';
import { BleTransport } from './BleTransport';
import { TcpTransport } from './TcpTransport';

export type TransportMode = 'BLE' | 'TCP' | 'SLE';

export class TransportManager {
  private static instance: TransportManager;
  private currentTransport: ITransport;
  private mode: TransportMode = 'BLE';

  private constructor() {
    this.currentTransport = BleTransport.getInstance();
  }

  public static getInstance(): TransportManager {
    if (!TransportManager.instance) {
      TransportManager.instance = new TransportManager();
    }
    return TransportManager.instance;
  }

  public switchMode(mode: TransportMode) {
    this.mode = mode;
    if (mode === 'TCP') {
      this.currentTransport = TcpTransport.getInstance();
    } else {
      this.currentTransport = BleTransport.getInstance();
    }
  }

  public getTransport(): ITransport {
    return this.currentTransport;
  }

  public getMode(): TransportMode {
    return this.mode;
  }
}