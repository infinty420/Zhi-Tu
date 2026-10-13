/**
 * TtsService —— 端侧语音朗读（Wave 11）。
 * 封装 CoreSpeechKit 文本转语音：懒加载引擎、按 utterance 生成唯一 requestId，
 * 出错静默降级，供节点详情「朗读讲解」复用。无需联网亦可（视设备离线语音包）。
 */
import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class TtsService {
  private static engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private static reqSeq: number = 0;

  /** 朗读一段文本（端侧合成）。speak 为同步触发，真正的合成结果经引擎回调，错误静默忽略。 */
  static speak(text: string): void {
    if (!text || text.length === 0) {
      return;
    }
    const run = (eng: textToSpeech.TextToSpeechEngine): void => {
      TtsService.reqSeq = TtsService.reqSeq + 1;
      const reqId = `zhitu_tts_${TtsService.reqSeq}_${Date.now()}`;
      try {
        eng.speak(text, { requestId: reqId, extraParams: {} });
      } catch (e) {
        // 引擎不可用 / 无离线语音包：忽略
      }
    };
    if (TtsService.engine) {
      run(TtsService.engine);
      return;
    }
    textToSpeech.createEngine(
      { language: 'zh-CN', person: 0, online: 1, extraParams: {} },
      (err: BusinessError, eng: textToSpeech.TextToSpeechEngine) => {
        if (err || !eng) {
          return;
        }
        TtsService.engine = eng;
        run(eng);
      });
  }

  /** 停止朗读 */
  static stop(): void {
    if (TtsService.engine) {
      try {
        TtsService.engine.stop();
      } catch (e) {
        // 忽略
      }
    }
  }
}
