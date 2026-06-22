// PermissionsConfig.ts
import { Permissions } from '@kit.AbilityKit';

/**
 * BLE 蓝牙相关权限集合
 * - ACCESS_BLUETOOTH：蓝牙基础权限（user_grant）
 * - APPROXIMATELY_LOCATION / LOCATION：很多情况下扫描 BLE 设备需要定位权限
 */
export const BLE_PERMISSIONS: Permissions[] = [
  'ohos.permission.ACCESS_BLUETOOTH',
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION',
];

/**
 * Wi-Fi 扫描热点常用权限
 * - APPROXIMATELY_LOCATION / LOCATION：扫描附近 Wi-Fi 时通常需要定位权限
 *   （GET_WIFI_INFO 之类的多数是 system_grant，在 module.json5 里声明即可）
 */
export const WIFI_SCAN_PERMISSIONS: Permissions[] = [
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION',
];

/**
 * 相机权限
 * - CAMERA：使用相机预览/拍照需要（user_grant）
 */
export const CAMERA_PERMISSIONS: Permissions[] = [
  'ohos.permission.CAMERA',
];

/**
 * 麦克风权限
 * - MICROPHONE：录音、语音识别等需要（user_grant）
 */
export const MIC_PERMISSIONS: Permissions[] = [
  'ohos.permission.MICROPHONE',
];

/**
 * 星闪 (NearLink/SLE) 相关权限集合
 * - ACCESS_NEARLINK：星闪基础权限（user_grant）
 * - APPROXIMATELY_LOCATION / LOCATION：扫描星闪设备通常需要定位权限
 */
export const SLE_PERMISSIONS: Permissions[] = [
  'ohos.permission.ACCESS_NEARLINK',
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION',
];
