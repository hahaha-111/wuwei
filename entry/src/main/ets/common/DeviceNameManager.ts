import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 模拟易语言 "名称配置.ini" 的逻辑
 * 负责管理 DeviceID (10字节Hex) <-> 中文名称 的映射
 * 以及生成新的唯一 ID
 */
export class DeviceNameManager {
  private static readonly PREF_NAME = 'device_name_config';
  private static readonly KEY_MAX_ADDRESS = 'ccgs_max_address'; // 对应易语言 "ccgs"
  private static instance: DeviceNameManager;
  private pref: preferences.Preferences | null = null;
  private context: common.UIAbilityContext;

  private constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  public static async getInstance(context: common.UIAbilityContext): Promise<DeviceNameManager> {
    if (!DeviceNameManager.instance) {
      DeviceNameManager.instance = new DeviceNameManager(context);
      await DeviceNameManager.instance.init();
    }
    return DeviceNameManager.instance;
  }

  private async init() {
    this.pref = await preferences.getPreferences(this.context, DeviceNameManager.PREF_NAME);
  }

  /**
   * 根据 ID 获取名称
   * @param deviceIdHex 10字节 Hex 字符串
   * @returns 配置的名称 或 ""
   */
  public async getName(deviceIdHex: string): Promise<string> {
    if (!this.pref) return "";
    const name = await this.pref.get(deviceIdHex, "");
    return name as string;
  }

  /**
   * 保存名称映射
   * @param deviceIdHex
   * @param name
   */
  public async saveName(deviceIdHex: string, name: string): Promise<void> {
    if (!this.pref) return;
    await this.pref.put(deviceIdHex, name);
    await this.pref.flush();
  }

  /**
   * 生成新的唯一 ID (模拟易语言逻辑)
   * 逻辑：读取最大地址 -> +1 -> 转Hex -> 补F凑齐20位
   */
  public async generateNewId(): Promise<string> {
    if (!this.pref) return "FFFFFFFFFFFFFFFFFFFF";

    // 1. 读取 Max Address
    const currentMax = await this.pref.get(DeviceNameManager.KEY_MAX_ADDRESS, 0) as number;

    // 2. 增加 1
    const newAddress = currentMax + 1;

    // 3. 保存新的 Max Address
    await this.pref.put(DeviceNameManager.KEY_MAX_ADDRESS, newAddress);
    await this.pref.flush();

    // 4. 生成 Hex 字符串
    let hex = newAddress.toString(16).toUpperCase();

    // 5. 补 F (易语言逻辑: d = d & "F" 直到长度20)
    while (hex.length < 20) {
      hex += 'F';
    }

    return hex;
  }

  /**
   * 辅助：将 Hex 字符串转为 number[] 供发送
   */
  public static hexToBytes(hex: string): number[] {
    const bytes: number[] = [];
    for (let i = 0; i < hex.length; i += 2) {
      bytes.push(parseInt(hex.substring(i, i + 2), 16));
    }
    return bytes;
  }
}