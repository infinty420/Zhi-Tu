/**
 * AI 配置加载器。
 * 从 resources/rawfile/ai_config.json 读取 endpoint / apiKey / model / mode；
 * 密钥仅经配置文件注入，禁止硬编码；未配置时 mode 置为 mock。
 */
import { common } from '@kit.AbilityKit';

export interface AIConfigRaw {
  endpoint: string;
  apiKey: string;
  model: string;
  mode: string; // 'mock' | 'openai'
}

export const DEFAULT_CONFIG: AIConfigRaw = {
  endpoint: 'https://api.openai.com/v1/chat/completions',
  apiKey: '',
  model: 'gpt-4o-mini',
  mode: 'mock'
};

export class Config {
  private static cached: AIConfigRaw | undefined = undefined;

  /** 由页面在 aboutToAppear 时调用一次，注入 context 用于读取 rawfile */
  static async init(context: common.UIAbilityContext): Promise<AIConfigRaw> {
    if (Config.cached !== undefined) {
      return Config.cached;
    }
    try {

      // 优先使用同步读取，失败时降级默认配置
      try {
        const data: Uint8Array = context.resourceManager.getRawFileContentSync('ai_config.json');
        const text = Config.bytesToString(data);
        const parsed = JSON.parse(text) as AIConfigRaw;
        Config.cached = Config.normalize(parsed);
        return Config.cached;
      } catch (syncErr) {
        // 同步读取失败尝试异步
      }
      const dataAsync: Uint8Array = await context.resourceManager.getRawFileContent('ai_config.json');
      const textAsync = Config.bytesToString(dataAsync);
      const parsedAsync = JSON.parse(textAsync) as AIConfigRaw;
      Config.cached = Config.normalize(parsedAsync);
      return Config.cached;
    } catch (err) {
      Config.cached = Config.normalize(DEFAULT_CONFIG);
      return Config.cached;
    }
  }

  static getConfig(): AIConfigRaw {
    if (Config.cached === undefined) {
      return Config.normalize(DEFAULT_CONFIG);
    }
    return Config.cached;
  }

  static isMockMode(): boolean {
    const cfg = Config.getConfig();
    return cfg.mode !== 'openai' || cfg.apiKey.length === 0;
  }

  private static normalize(raw: AIConfigRaw): AIConfigRaw {
    const mode: string = raw.mode === 'openai' ? 'openai' : 'mock';
    return {
      endpoint: raw.endpoint && raw.endpoint.length > 0 ? raw.endpoint : DEFAULT_CONFIG.endpoint,
      apiKey: raw.apiKey ? raw.apiKey : '',
      model: raw.model && raw.model.length > 0 ? raw.model : DEFAULT_CONFIG.model,
      mode: mode
    };
  }

  private static bytesToString(data: Uint8Array): string {
    let result = '';
    for (let i = 0; i < data.length; i++) {
      result += String.fromCharCode(data[i]);
    }
    return result;
  }
}