import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { BusinessError } from '@ohos.base';
import { deviceInfo } from '@kit.BasicServicesKit';

// ⭐ 必须与注册机 KeygenPage.ets 保持完全一致
const LICENSE_SECRET: string = 'RODA_LICENSE_SECRET_2025';
const BASE_YEAR: number = 2020;
const BASE_MONTH: number = 0;
const BASE_DAY: number = 1;

const PREF_NAME: string = 'app_license_v1';
const KEY_LICENSE_CODE = 'license_code';
const KEY_USED_COUNT = 'used_count';
const KEY_LAST_RUN_TIME = 'last_run_time';
// ⭐ 新增：持久化保存的机器码种子，防止系统升级后机器码变更
const KEY_MACHINE_SEED = 'machine_seed_persistent';

export interface LicenseCheckResult {
  ok: boolean;          // 是否授权通过
  msg?: string;         // 错误信息
  isNearExpiry?: boolean; // 是否临期（<3天 或 <50次）
  expiryMsg?: string;   // 临期提示语
}

export class LicenseManager {
  private static context: common.UIAbilityContext | null = null;
  private static prefs: dataPreferences.Preferences | null = null;
  private static cachedMachineSeed: string = '';

  /** 初始化，获取 Preferences 实例并加载/生成持久化机器码种子 */
  static async init(context: common.UIAbilityContext) {
    LicenseManager.context = context;
    if (!LicenseManager.prefs) {
      try {
        LicenseManager.prefs = await dataPreferences.getPreferences(context, PREF_NAME);

        // ⭐ 优化核心：检查是否有持久化的种子
        let seed = await LicenseManager.prefs.get(KEY_MACHINE_SEED, '') as string;
        if (!seed || seed.length === 0) {
          // 如果没有（首次运行），生成一个 UUID 并保存
          // 结合 productModel 增加一点硬件绑定属性，但主要依赖 UUID 的不变性
          seed = deviceInfo.productModel + '_' + util.generateRandomUUID(true);
          await LicenseManager.prefs.put(KEY_MACHINE_SEED, seed);
          await LicenseManager.prefs.flush();
        }
        LicenseManager.cachedMachineSeed = seed;

      } catch (e) {
        console.error('LicenseManager init failed:', e);
      }
    }
  }

  /** 获取本机机器码 (8位大写字母数字) */
  static getMachineCode(): string {
    // ⭐ 优化：不再使用 unstable 的 versionId，而是使用持久化的 cachedMachineSeed
    let seed = LicenseManager.cachedMachineSeed;

    // 兜底：如果 init 失败或尚未调用，临时回退到旧逻辑（防止崩溃），
    // 但建议业务层确保先调用 await init()
    if (!seed) {
      seed = deviceInfo.productModel + 'RODA_FALLBACK';
    }

    return LicenseManager.hashToHex8(seed);
  }

  /** 验证并保存注册码 */
  static async verifyAndSaveLicense(inputCode: string): Promise<boolean> {
    const code = inputCode.trim();
    if (!code) return false;

    const res = await LicenseManager.validateLicenseInternal(code, false); // 验证但不消耗次数
    if (res.ok) {
      if (LicenseManager.prefs) {
        const oldCode = await LicenseManager.prefs.get(KEY_LICENSE_CODE, '');

        await LicenseManager.prefs.put(KEY_LICENSE_CODE, code);

        if (oldCode !== code) {
          await LicenseManager.prefs.put(KEY_USED_COUNT, 0);
        }
        await LicenseManager.prefs.flush();
      }
      return true;
    }
    return false;
  }

  /** * 检查授权状态，并可选消耗一次使用次数
   * @param consume 是否消耗次数 (App启动时传 false, 连接设备成功时传 true)
   */
  static async checkLicenseAndConsumeOne(consume: boolean): Promise<LicenseCheckResult> {
    if (!LicenseManager.prefs) {
      return { ok: false, msg: 'Context not ready' };
    }

    const code = await LicenseManager.prefs.get(KEY_LICENSE_CODE, '') as string;
    if (!code) {
      return { ok: false, msg: '无授权记录' };
    }

    // 验证
    const res = await LicenseManager.validateLicenseInternal(code, consume);

    if (res.ok && consume) {
      const currentCount = await LicenseManager.prefs.get(KEY_USED_COUNT, 0) as number;
      await LicenseManager.prefs.put(KEY_USED_COUNT, currentCount + 1);
      await LicenseManager.prefs.flush();
    }

    return res;
  }

  // ================= 私有算法实现 (对应注册机) =================

  private static async validateLicenseInternal(license: string, dryRun: boolean): Promise<LicenseCheckResult> {
    // 格式: V1-PAYLOAD-SIGN8
    const parts = license.split('-');
    if (parts.length !== 3 || parts[0] !== 'V1') {
      return { ok: false, msg: '格式错误' };
    }

    const payloadStr = parts[1];
    const signStr = parts[2];
    const machineCode = LicenseManager.getMachineCode();

    // 1. 校验签名
    const signPlain = machineCode + '|' + payloadStr + '|' + LICENSE_SECRET;
    const calcSign = await LicenseManager.md5Hex8(signPlain);

    if (calcSign !== signStr) {
      return { ok: false, msg: '机器码不匹配或签名无效' };
    }

    // 2. 解密 Payload
    const xorKey = await LicenseManager.calcXorKey(machineCode);

    let cipher = 0;
    try {
      cipher = parseInt(payloadStr, 36);
    } catch(e) {
      return { ok: false, msg: '数据损坏' };
    }

    const raw32 = (cipher ^ xorKey) >>> 0;
    const daysOffset = (raw32 >>> 16) & 0xFFFF;
    const maxRuns = raw32 & 0xFFFF;

    // 3. 检查有效期
    const baseDate = new Date(BASE_YEAR, BASE_MONTH, BASE_DAY, 0, 0, 0, 0);
    const expireDate = new Date(baseDate.getTime() + daysOffset * 24 * 60 * 60 * 1000);

    const systemNow = new Date().getTime();
    let lastRunTime = 0;
    if (LicenseManager.prefs) {
      lastRunTime = await LicenseManager.prefs.get(KEY_LAST_RUN_TIME, 0) as number;
    }

    let effectiveNow = Math.max(systemNow, lastRunTime);

    if (systemNow > lastRunTime && LicenseManager.prefs) {
      await LicenseManager.prefs.put(KEY_LAST_RUN_TIME, systemNow);
      if (!dryRun) {
        await LicenseManager.prefs.flush();
      }
    }

    const diffMs = expireDate.getTime() - effectiveNow;
    const daysLeft = Math.ceil(diffMs / (24 * 3600 * 1000));

    if (diffMs < 0) {
      if (systemNow < lastRunTime) {
        return { ok: false, msg: '系统时间异常(检测到回拨)，授权已过期' };
      }
      return { ok: false, msg: '授权已过期' };
    }

    // 4. 检查次数
    let currentCount = 0;
    if (LicenseManager.prefs) {
      currentCount = await LicenseManager.prefs.get(KEY_USED_COUNT, 0) as number;
    }

    let runsLeft = -1;
    if (maxRuns > 0) {
      if (currentCount >= maxRuns) {
        return { ok: false, msg: '授权次数已用完' };
      }
      runsLeft = maxRuns - currentCount;
    }

    // 5. 检查临期状态
    let isNearExpiry = false;
    let expiryMsg = '';

    if (daysLeft < 3) {
      isNearExpiry = true;
      expiryMsg = `授权即将过期 (剩余 ${daysLeft} 天)`;
    }

    if (maxRuns > 0 && runsLeft < 50) {
      isNearExpiry = true;
      const msg = `授权次数不足 (剩余 ${runsLeft} 次)`;
      expiryMsg = expiryMsg ? `${expiryMsg}，${msg}` : msg;
    }

    return {
      ok: true,
      isNearExpiry: isNearExpiry,
      expiryMsg: expiryMsg
    };
  }

  // --- 辅助加密 ---

  private static async md5Hex8(content: string): Promise<string> {
    const encoder = new util.TextEncoder();
    const data = encoder.encodeInto(content);
    try {
      const md = cryptoFramework.createMd('MD5');
      await md.update({ data: data });
      const output = await md.digest();
      let hex = '';
      for (let i = 0; i < output.data.length; i++) {
        const v = output.data[i] & 0xff;
        hex += v.toString(16).padStart(2, '0');
      }
      return hex.substring(0, 8).toUpperCase();
    } catch (e) {
      return '00000000';
    }
  }

  // 生成 8位机器码
  private static hashToHex8(content: string): string {
    let h = 0x811c9dc5;
    for (let i = 0; i < content.length; i++) {
      h ^= content.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
    h = h >>> 0;
    const hex = h.toString(16).toUpperCase().padStart(8, '0');
    return hex.substring(0, 8);
  }

  private static async calcXorKey(machineCode: string): Promise<number> {
    const plain = machineCode + '|' + LICENSE_SECRET;
    const hex8 = await LicenseManager.md5Hex8(plain);
    const key = parseInt(hex8, 16);
    return Number.isNaN(key) ? 0x5A5A5A5A : key;
  }
}