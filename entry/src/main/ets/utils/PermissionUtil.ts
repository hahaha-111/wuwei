// PermissionUtil.ts  权限管理
// 导入 Ability 相关能力控制 & 包管理 & 权限请求结果 & 权限类型
import { abilityAccessCtrl, bundleManager, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
// 导入 UIAbility 上下文类型，用于传入上下文 context
import { common } from '@kit.AbilityKit';

export class PermissionUtil {

  /**
   * 单个权限检查：判断某个权限当前是否已被授予
   * @param permission 需要检查的权限名（如 'ohos.permission.LOCATION'）
   * @returns true：已授权；false：未授权
   */
  static async checkPermission(permission: Permissions): Promise<boolean> {
    const status = await PermissionUtil.checkAccessToken(permission); // 调用内部方法，通过 accessToken 检查权限状态
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED; // 返回是否为“已授权”状态
  }

  /**
   * 一组权限的“检查 + 申请”总入口（对外推荐使用这个）
   * 逻辑：
   *   1. 遍历 permissions，找出未授权的权限 needRequest
   *   2. 如果都已授权 -> 直接返回 true
   *   3. 如果有未授权 -> 调用 requestPermissionsFromUser 触发系统弹框
   *   4. 若用户仍未全部授权 -> 再调用 requestPermissionOnSetting，引导到设置页
   *   5. 最终返回：是否已经具备所有权限
   *
   * @param context UIAbility 的上下文（由调用方传入）
   * @param permissions 需要检查/申请的一组权限
   */
  static async checkAndRequestPermissions(
    context: common.UIAbilityContext,
    permissions: Permissions[]
  ): Promise<boolean> {
    // 收集“当前还未被授权”的权限列表
    const needRequest: Permissions[] = [];

    // 遍历所有权限，逐个检查是否已经授权
    for (const p of permissions) {
      const ok = await PermissionUtil.checkPermission(p);
      if (!ok) {
        // 如果没有授权，加入待申请列表
        needRequest.push(p);
      }
    }

    // 如果待申请列表为空，说明所有权限已经具备，直接返回 true
    if (needRequest.length === 0) {
      return true;
    }

    // 第一步：调用系统弹框申请这些权限
    const first = await PermissionUtil.requestPermissionsFromUser(context, needRequest);
    if (first) {
      // 如果用户在弹框中全部授权了，返回 true
      return true;
    }

    // 第二步：如果还有未授权的权限，则引导用户到设置页中手动开启
    return await PermissionUtil.requestPermissionOnSetting(context, needRequest);
  }

  /**
   * 封装：调用系统的 requestPermissionsFromUser 接口，弹出权限申请对话框
   *
   * @param context UIAbility 上下文，用于弹出系统对话框
   * @param permissions 实际需要申请的权限列表
   * @returns true：用户在弹框中已授予所有权限；false：还有权限未授权或调用失败
   */
  private static async requestPermissionsFromUser(
    context: common.UIAbilityContext,
    permissions: Permissions[]
  ): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager(); // 创建权限控制管理器

    try {
      // 调用系统接口，向用户弹出权限申请弹框
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(context, permissions);

      // result.authResults 是一个数组，对应每个权限的授予结果
      // 使用 every() 判断所有结果是否都是“已授权”
      return result.authResults.every(r => r === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    } catch (e) {
      // 如果调用接口异常，视为申请失败，返回 false
      // 真实项目可补充 console.error(e)
      return false;
    }
  }

  /**
   * 二次引导：打开应用设置页，让用户手动开启权限
   * 注意：
   *  - 为避免跨权限组导致 12100001 等错误，这里是对权限逐个 requestPermissionOnSetting
   *
   * @param context UIAbility 上下文
   * @param permissions 仍然需要引导的权限列表
   * @returns true：所有权限最终都被授予；false：仍有未授权/调用失败
   */
  private static async requestPermissionOnSetting(
    context: common.UIAbilityContext,
    permissions: Permissions[]
  ): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager(); // 创建权限控制管理器

    // 对每一个权限逐一进行“到设置页开启”的操作
    for (const p of permissions) {
      // 再检查一遍，防止这期间用户已经在其他地方开了
      const has = await PermissionUtil.checkPermission(p);
      if (has) {
        // 如果已经有权限了，就不用再去设置页了
        continue;
      }

      try {
        // 调用系统接口，引导用户进入设置页打开该权限
        const arr = await atManager.requestPermissionOnSetting(context, [p]);

        // requestPermissionOnSetting 返回的是一个状态数组，这里也用 every() 判断全部是否为“已授权”
        const ok = arr.every(v => v === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
        if (!ok) {
          // 一旦有某个权限仍未授权，直接返回 false
          return false;
        }
      } catch {
        // 调用失败也直接返回 false
        return false;
      }
    }

    // 如果所有权限都已经确认授权，返回 true
    return true;
  }

  /**
   * 内部工具方法：通过 accessToken 检查某个权限的授予状态
   * 步骤：
   *   1. 使用 bundleManager.getBundleInfoForSelf 获取自身应用信息，拿到 accessTokenId
   *   2. 使用 atManager.checkAccessToken(tokenId, permission) 向系统查询授权状态
   *
   * @param permission 需要检查的权限名
   * @returns GrantStatus：PERMISSION_GRANTED / PERMISSION_DENIED
   */
  private static async checkAccessToken(permission: Permissions) {
    const atManager = abilityAccessCtrl.createAtManager(); // 创建权限管理器
    let tokenId = 0; // 应用的 accessTokenId

    try {
      // 获取当前应用自身的包信息，包含 appInfo
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      // 从 appInfo 中取出 accessTokenId，用于后续权限检查
      tokenId = bundleInfo.appInfo.accessTokenId;
    } catch {
      // 如果获取包信息失败，无法继续检查权限，直接当作“未授权”返回
      return abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    }

    try {
      // 使用 accessTokenId + 权限名，向系统查询该权限的授予状态
      return await atManager.checkAccessToken(tokenId, permission);
    } catch {
      // 如果检查过程中抛异常，同样视为“未授权”
      return abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    }
  }
}
