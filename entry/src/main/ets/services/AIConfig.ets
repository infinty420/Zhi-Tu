/**
 * AI 配置管理。
 * 从 utils/Config 读取 endpoint/apiKey/model/mode；isMockMode 判定；
 * 密钥仅经配置文件注入且不落日志。
 */
import { AIConfigRaw, Config } from '../utils/Config';

export class AIConfig {
  private raw: AIConfigRaw;

  constructor(raw: AIConfigRaw) {
    this.raw = raw;
  }

  static load(): AIConfig {
    return new AIConfig(Config.getConfig());
  }

  static reset(): void {
    // 供测试/重载配置使用
  }

  get endpoint(): string {
    return this.raw.endpoint;
  }

  get apiKey(): string {
    return this.raw.apiKey;
  }

  get model(): string {
    return this.raw.model;
  }

  get mode(): string {
    return this.raw.mode;
  }

  isMockMode(): boolean {
    return this.raw.mode !== 'openai' || this.raw.apiKey.length === 0;
  }

  /** 遮蔽密钥用于日志（不落完整密钥） */
  maskedKey(): string {
    if (this.raw.apiKey.length === 0) {
      return '<empty>';
    }
    if (this.raw.apiKey.length <= 6) {
      return '******';
    }
    const head = this.raw.apiKey.substring(0, 3);
    const tail = this.raw.apiKey.substring(this.raw.apiKey.length - 3);
    return `${head}***${tail}`;
  }
}