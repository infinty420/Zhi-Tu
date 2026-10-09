/**
 * 统一日志工具 —— 封装 hilog，供全工程复用。
 * 固定 DOMAIN=0x0000，标签统一为 Zhitu。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const DEFAULT_TAG: string = 'Zhitu';

export class Logger {
  static info(tag: string, message: string): void {
    try {
      hilog.info(DOMAIN, tag, '%{public}s', message);
    } catch (err) {
      // 日志失败不阻塞业务
    }
  }

  static warn(tag: string, message: string): void {
    try {
      hilog.warn(DOMAIN, tag, '%{public}s', message);
    } catch (err) {
      // ignore
    }
  }

  static error(tag: string, message: string): void {
    try {
      hilog.error(DOMAIN, tag, '%{public}s', message);
    } catch (err) {
      // ignore
    }
  }

  /** AI 请求埋点：发起 / 成功 / 失败 / 重试 */
  static aiRequest(service: string, action: string, detail: string): void {
    Logger.info(DEFAULT_TAG, `[AI:${service}] ${action} ${detail}`);
  }
}