//AdapterManager.ts  蓝牙状态管理


import { access } from '@kit.ConnectivityKit';//从ConnectivityKit中导入access模块，用于处理与网络连接相关的操作。
import { BusinessError } from '@kit.BasicServicesKit';//从BasicServicesKit中导入BusinessError模块，用于处理业务错误。

export class AdapterManager {
  // 定义蓝牙开关状态变化函数回调
  onReceiveEvent = (data: access.BluetoothState) => {
    let btStateMessage = '';
    switch (data) {
      case access.BluetoothState.STATE_OFF:
        // 表示蓝牙是关闭的
        btStateMessage += 'STATE_OFF';
        break;
      case access.BluetoothState.STATE_TURNING_ON:
        btStateMessage += 'STATE_TURNING_ON';
        break;
      case access.BluetoothState.STATE_ON:
        // 表示蓝牙是开启的，此时应用才可以使用蓝牙其他功能
        btStateMessage += 'STATE_ON';
        break;
      case access.BluetoothState.STATE_TURNING_OFF:
        btStateMessage += 'STATE_TURNING_OFF';
        break;
      case access.BluetoothState.STATE_BLE_TURNING_ON:
        btStateMessage += 'STATE_BLE_TURNING_ON';
        break;
      case access.BluetoothState.STATE_BLE_ON:
        btStateMessage += 'STATE_BLE_ON';
        break;
      case access.BluetoothState.STATE_BLE_TURNING_OFF:
        btStateMessage += 'STATE_BLE_TURNING_OFF';
        break;
      default:
        btStateMessage += 'unknown state';
        break;
    }
    console.info('bluetooth state: ' + btStateMessage);
  };
  // 提供一个对外的查询接口
  public isBluetoothOn(): boolean {
    try {
      const state = access.getState();
      return state === access.BluetoothState.STATE_ON ||
        state === access.BluetoothState.STATE_BLE_ON;
    } catch (err) {
      console.error('getState error: ' + (err as BusinessError).code);
      return false;
    }
  }
  // 开启蓝牙
  public openBluetooth() {
    try {
      // 注册蓝牙状态变化事件监听器，当蓝牙状态变化时触发回调函数
      access.on('stateChange', this.onReceiveEvent);
    } catch (err) {
      console.error('errCode: ' + (err as BusinessError).code + ', errMessage: ' + (err as BusinessError).message);
    }
    try {
      // 主动获取蓝牙当前的开关状态
      let state = access.getState();
      if (state == access.BluetoothState.STATE_OFF) {
        // 若蓝牙是关闭的，则主动开启蓝牙
        access.enableBluetooth();
      }
    } catch (err) {
      console.error('errCode: ' + (err as BusinessError).code + ', errMessage: ' + (err as BusinessError).message);
    }
  }

  // 关闭蓝牙
  public closeBluetooth() {
    try {
      // 主动获取蓝牙当前的开关状态
      let state = access.getState();
      if (state == access.BluetoothState.STATE_ON) {
        // 若蓝牙是开启的，则主动关闭蓝牙
        access.disableBluetooth();
      }
    } catch (err) {
      console.error('errCode: ' + (err as BusinessError).code + ', errMessage: ' + (err as BusinessError).message);
    }
  }
}

let adapterManager = new AdapterManager(); //class类，需要创建一个单例导出
export default adapterManager as AdapterManager;//创建 AdapterManager 的单例对象，也就是全局只有一个 AdapterManager 实例