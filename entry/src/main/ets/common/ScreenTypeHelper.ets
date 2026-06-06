// entry/src/main/ets/common/ScreenTypeHelper.ets
// 统一处理屏幕类型的检测逻辑，供各页面复用

import display from '@ohos.display';
import deviceInfo from '@ohos.deviceInfo';

// 屏幕类型：手机 / 折叠屏展开 / 平板
export type ScreenType = 'PHONE' | 'FOLD' | 'TABLET';

export interface ScreenInfo {
  screenType: ScreenType;     // 屏幕类型
  isLargeScreen: boolean;     // 是否认为是大屏体验
  diagonalInch: number;       // 物理对角线尺寸（英寸）
  aspect: number;             // 宽高比（>=1）
}

/**
 * 统一屏幕识别逻辑：
 *
 * - 先用 display + dpi 算出物理尺寸 & 宽高比
 * - 再结合 deviceType（phone / tablet / 2in1）和 vp 断点做微调
 *
 * 规则大致：
 * 1）deviceType = tablet / 2in1 -> TABLET
 * 2）否则：
 *    - diagonal >= 8.5         -> TABLET（大平板）
 *    - else if aspect <= 1.6 && diagonal >= 6.0 -> FOLD（折叠屏展开 / 小方屏）
 *    - else                                   -> PHONE
 * 3）如果判断为 FOLD，但窗口特别大（minVp >= 840） -> TABLET
 * 4）如果判断为 FOLD，但特别细长（aspect >= 1.8） -> PHONE
 */
export function detectScreenInfo(): ScreenInfo {
  let screenType: ScreenType = 'PHONE';
  let isLargeScreen = false;
  let diagonalInch = 0;
  let aspect = 1;

  try {
    const d = display.getDefaultDisplaySync();
    const widthPx = d.width;
    const heightPx = d.height;
    const dpi = d.densityDPI;

    // 物理尺寸（英寸）
    const wInch = widthPx / dpi;
    const hInch = heightPx / dpi;
    const diagonal = Math.sqrt(wInch * wInch + hInch * hInch);
    diagonalInch = Number(diagonal.toFixed(2));

    // 宽高比（像素）
    aspect = Math.max(widthPx, heightPx) / Math.min(widthPx, heightPx);

    // 把 px 转成 vp（160 dpi 为基准）
    const widthVp = widthPx * 160 / dpi;
    const heightVp = heightPx * 160 / dpi;
    const minVp = Math.min(widthVp, heightVp);
    const maxVp = Math.max(widthVp, heightVp);
    const aspectVp = maxVp / minVp; // 理论上和 aspect 差不多，这里记录一下

    const devType = deviceInfo.deviceType; // 'phone' | 'tablet' | '2in1' | 'default'

    // 默认先按“手机”处理
    let type: ScreenType = 'PHONE';

    // 1. 物理设备类型：平板 / 2in1 直接视为 TABLET
    if (devType === 'tablet' || devType === '2in1') {
      type = 'TABLET';
    } else {
      // 2. 用物理尺寸 + 宽高比初步判断
      if (diagonal >= 8.5) {
        // 大平板
        type = 'TABLET';
      } else if (aspect <= 1.6 && diagonal >= 6.0) {
        // 接近方屏 + 对角约 6~7 寸：折叠屏展开
        type = 'FOLD';
      } else {
        type = 'PHONE';
      }

      // 3. 再结合 vp 断点微调一下
      //    超大窗口基本是平板体验
      if (minVp >= 840) {
        type = 'TABLET';
      }

      // 4. 折叠屏展开一般 aspect 在 1.0~1.4 左右，
      //    如果特别“细长”，说明更像普通手机横屏，收回为 PHONE
      if (type === 'FOLD' && aspect >= 1.8) {
        type = 'PHONE';
      }

      // （可选）如果你更信任 vp 断点，这里也可以：
      // else if (type === 'PHONE' && minVp >= 520 && minVp < 840 && aspectVp <= 1.6) {
      //   type = 'FOLD';
      // }
    }

    screenType = type;
    isLargeScreen = (type !== 'PHONE');

    console.info(
      `ScreenTypeHelper detectScreenInfo: ` +
        `devType=${devType}, widthPx=${widthPx}, heightPx=${heightPx}, dpi=${dpi}, ` +
        `diag=${diagonalInch}, aspect=${aspect.toFixed(2)}, ` +
        `widthVp=${widthVp.toFixed(1)}, heightVp=${heightVp.toFixed(1)}, aspectVp=${aspectVp.toFixed(2)}, ` +
        `screenType=${screenType}`
    );
  } catch (e) {
    console.error('ScreenTypeHelper detectScreenInfo error: ' + e);
    // 兜底：保持默认 PHONE + 非大屏
    screenType = 'PHONE';
    isLargeScreen = false;
    diagonalInch = 0;
    aspect = 1;
  }

  return {
    screenType,
    isLargeScreen,
    diagonalInch,
    aspect
  };
}

/** 一些辅助小函数，想用就用，不用也没关系 */
export function isFoldScreen(type: ScreenType): boolean {
  return type === 'FOLD';
}

export function isTabletScreen(type: ScreenType): boolean {
  return type === 'TABLET';
}

export function isLarge(type: ScreenType): boolean {
  return type !== 'PHONE';
}
