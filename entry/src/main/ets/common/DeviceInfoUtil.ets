// common/DeviceInfoUtil.ets
// 功能：
//  - 生成一个“设备绑定”的虚拟序列号（不依赖系统权限，不需要 MDM）
//  - 虚拟序列号通过设备固有信息计算，应用重启不会变（同一设备保持一致）
//  - getSystemInfo() 返回 info 字符串：
//    model=HBN-AL00(Mate 60 Pro),phone=,manufacturer=HUAWEI,version=OpenHarmony-6.0.0.47,
//    mqt=D82403EDF874A289,1.0.0,

import { deviceInfo } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';

export interface SystemInfo {
  model: string;          // 型号 (含市场名称)
  manufacturer: string;   // 制造商
  imei: string;           // 假的 IMEI
  systemVersion: string;  // 系统版本
  appVersion: string;     // 软件版本号
  mqt: string;            // 虚拟设备序列号（绑定本设备，无前缀）
  info: string;           // 拼接后的字符串
}

/**
 * 获取应用 versionName，对应“当前软件版本”
 */
async function getAppVersion(): Promise<string> {
  let versionName: string = '';

  try {
    const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
    const bundleInfo = await bundleManager.getBundleInfoForSelf(flags);
    versionName = bundleInfo.versionName;
  } catch (_err) {
    versionName = '';
  }

  return versionName;
}

/**
 * 生成假的 IMEI（基于 versionId）
 */
function buildFakeImei(seed: string): string {
  let digits: string = '';

  // 从 seed 中抽取数字
  for (let i = 0; i < seed.length; i++) {
    const ch = seed.charAt(i);
    if (ch >= '0' && ch <= '9') {
      digits += ch;
      if (digits.length >= 14) break;
    }
  }

  // 不足补 0
  while (digits.length < 14) {
    digits += '0';
  }

  // 计算校验位 Luhn
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let n = Number(digits.charAt(i));
    if (i % 2 === 1) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
  }
  const check = (10 - (sum % 10)) % 10;

  return digits + check.toString();
}

/**
 * 把任意字符串变成 16 个十六进制字符（伪随机，但同一 seed 结果一致）
 */
function hashToHex16(seed: string): string {
  let h1 = 0x12345678;
  let h2 = 0x9abcdef0;

  for (let i = 0; i < seed.length; i++) {
    const c = seed.charCodeAt(i);
    h1 = (h1 * 31 + c) >>> 0;
    h2 = (h2 * 131 + c) >>> 0;
  }

  const bytes: number[] = [];

  for (let i = 0; i < 4; i++) {
    bytes.push((h1 >>> (i * 8)) & 0xff);
  }
  for (let i = 0; i < 4; i++) {
    bytes.push((h2 >>> (i * 8)) & 0xff);
  }

  return bytes
    .map((b: number) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase(); // 16 位 hex
}

/**
 * 生成“虚拟序列号”，同一台设备只要 deviceInfo.versionId 不变，它就不会变：
 * 修改前：EMUL-29A7A9322742C5BB
 * 修改后：29A7A9322742C5BB (只保留后面部分，去除 EMUL- 前缀)
 */
function buildVirtualSerial(): string {
  const modelRaw: string = deviceInfo.productModel ?? 'EMUL';

  // 原始逻辑已移除，不再生成前缀

  const seed: string =
    deviceInfo.versionId ??
      (deviceInfo.osFullName + '-' + modelRaw);

  const hexPart: string = hashToHex16(seed);

  // ⭐ 修改：直接返回 hexPart，不拼接 prefix
  return hexPart;
}

/**
 * 主函数：获取系统信息并拼接 info
 * - mqt 字段 = 虚拟序列号（绑定本设备）
 * - model 字段 = 内部型号 + (市场名称)
 * - 只在这里调用一次，结果缓存/复用即可
 */
export async function getSystemInfo(): Promise<SystemInfo> {
  // 1. 获取基础型号 (e.g. "HBN-AL00")
  let modelStr = deviceInfo.productModel;
  const manufacturer = deviceInfo.manufacture; // 制造商，例如 HUAWEI
  const systemVersion = deviceInfo.osFullName; // 系统版本，例如: OpenHarmony-6.0.0.47
  const appVersion = await getAppVersion();    // 软件版本号，例如: 1.0.0

  // 2. ⭐ 修改：尝试获取市场名称 (e.g. "Mate 60 Pro") 并拼接到 model 后面
  try {
    const marketName = deviceInfo.marketName; // 获取市场名称
    if (marketName && marketName.length > 0 && marketName !== modelStr) {
      // 格式：内部型号(市场名称)，例如：HBN-AL00(Mate 60 Pro)
      modelStr = `${modelStr}(${marketName})`;
    }
  } catch (e) {
    // 忽略获取市场名称失败，保持原样
  }

  // fake imei
  const imei = buildFakeImei(deviceInfo.versionId);

  // 虚拟 SN（绑定本设备），现在不带前缀
  const virtualSerial = buildVirtualSerial();

  // 最终 info 字符串，格式固定
  const info =
    'model=' + modelStr +
      ',phone=' + '' +
      ',manufacturer=' + manufacturer +
      ',version=' + systemVersion +
      ',mqt=' + virtualSerial +
      ',' + appVersion + ',';  // 末尾有一个逗号

  return {
    model: modelStr,
    manufacturer,
    imei,
    systemVersion,
    appVersion,
    mqt: virtualSerial,
    info,
  };
}