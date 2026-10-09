/**
 * 应用上下文持有器。
 * 页面在 aboutToAppear 时安装 UIAbilityContext，供服务层（Preferences/RDB/files）使用。
 */
import { common } from '@kit.AbilityKit';

export class AppContextHolder {
  private static ctx: common.UIAbilityContext | undefined = undefined;

  static install(context: common.UIAbilityContext): void {
    AppContextHolder.ctx = context;
  }

  static has(): boolean {
    return AppContextHolder.ctx !== undefined;
  }

  static get(): common.UIAbilityContext {
    if (AppContextHolder.ctx === undefined) {
      throw new Error('AppContext not installed');
    }
    return AppContextHolder.ctx;
  }
}