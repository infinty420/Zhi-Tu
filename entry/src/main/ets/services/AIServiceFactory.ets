/**
 * AIService 工厂与模式切换。
 * 按 config.mode 返回 MockAIService / OpenAICompatAIService；
 * 未配置密钥或首次失败（retryable）时自动降级 Mock，业务层不感知实现差异。
 */
import { AIConfig } from './AIConfig';
import { AIErrorCode, AIResult, AIResultFailure, AgentChatRequest, AgentChatResponse, AgentStreamChunk, AIService, ExamplesRequest, ExamplesResponse, MindMapGenRequest, MindMapGenResponse, MindMapStreamChunk, QuizGradeRequest, QuizGradeResponse, QuizRequest, QuizResponse, RichContentGenRequest, RichContentGenResponse, SimilarQuizRequest, StreamHandler, TutorChunk, TutorMode, TutorRequest, TutorResponse, aiSuccess } from './AIService';
import { MockAIService } from './MockAIService';
import { OpenAICompatAIService } from './OpenAICompatAIService';
import { AICacheService } from './AICacheService';
import { Logger } from '../utils/Logger';

export class AIServiceFactory {
  static create(config: AIConfig): AIService {
    if (config.isMockMode()) {
      return new MockAIService();
    }
    const real = new OpenAICompatAIService(config);
    const mock = new MockAIService();
    return new FailoverAIService(real, mock);
  }

  static createMock(): AIService {
    return new MockAIService();
  }
}

/** 降级包装：OpenAI 失败且 retryable 时用 Mock 兜底 */
class FailoverAIService implements AIService {
  private real: AIService;
  private mock: AIService;

  constructor(real: AIService, mock: AIService) {
    this.real = real;
    this.mock = mock;
  }

  /** 缓存键：辅导按「节点 + 学科 + 模式」，相似题按「节点 + 难度」 */
  private static tutorKey(req: TutorRequest): string {
    return `${req.nodeText}|${req.nodeType}|${req.mode}`;
  }

  private static similarKey(req: SimilarQuizRequest): string {
    const diff = req.difficulty !== undefined ? req.difficulty : 3;
    return `${req.nodeId}|${req.nodeText}|${diff}`;
  }

  async generateMindMap(req: MindMapGenRequest, onStream: StreamHandler<MindMapStreamChunk>): Promise<AIResult<MindMapGenResponse>> {
    const res = await this.real.generateMindMap(req, onStream);
    if (res.ok) {
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.generateMindMap(req, onStream);
  }

  async chatPatch(req: AgentChatRequest, onStream: StreamHandler<AgentStreamChunk>): Promise<AIResult<AgentChatResponse>> {
    const res = await this.real.chatPatch(req, onStream);
    if (res.ok) {
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.chatPatch(req, onStream);
  }

  async generateExamples(req: ExamplesRequest): Promise<AIResult<ExamplesResponse>> {
    const res = await this.real.generateExamples(req);
    if (res.ok) {
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.generateExamples(req);
  }

  async generateQuiz(req: QuizRequest): Promise<AIResult<QuizResponse>> {
    const res = await this.real.generateQuiz(req);
    if (res.ok) {
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.generateQuiz(req);
  }

  async generateSimilarQuiz(req: SimilarQuizRequest): Promise<AIResult<QuizResponse>> {
    const res = await this.real.generateSimilarQuiz(req);
    if (res.ok) {
      // 联网成功即落缓存，供后续离线命中
      await AICacheService.getInstance().put('similar', FailoverAIService.similarKey(req), JSON.stringify(res.data));
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    const cached = await this.readCache('similar', FailoverAIService.similarKey(req));
    if (cached.length > 0) {
      try {
        const parsed = JSON.parse(cached) as QuizResponse;
        if (parsed && parsed.questions && parsed.questions.length > 0) {
          Logger.aiRequest('Failover', 'offline-cache-hit', 'similar');
          return aiSuccess(parsed);
        }
      } catch (err) {
        Logger.aiRequest('Failover', 'offline-cache-broken', 'similar');
      }
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.generateSimilarQuiz(req);
  }

  async gradeAnswer(req: QuizGradeRequest): Promise<AIResult<QuizGradeResponse>> {
    const res = await this.real.gradeAnswer(req);
    if (res.ok) {
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.gradeAnswer(req);
  }

  async tutorNode(req: TutorRequest, onStream: StreamHandler<TutorChunk>): Promise<AIResult<TutorResponse>> {
    const res = await this.real.tutorNode(req, onStream);
    if (res.ok) {
      // 联网成功即落缓存，供后续离线命中
      await AICacheService.getInstance().put('tutor', FailoverAIService.tutorKey(req), res.data.text);
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    const cached = await this.readCache('tutor', FailoverAIService.tutorKey(req));
    if (cached.length > 0) {
      Logger.aiRequest('Failover', 'offline-cache-hit', 'tutor');
      const chunk: TutorChunk = { text: cached, done: true };
      onStream(chunk);
      const data: TutorResponse = { text: cached };
      return aiSuccess(data);
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.tutorNode(req, onStream);
  }

  /** 读取离线缓存（内部完成初始化） */
  private async readCache(bucket: string, key: string): Promise<string> {
    const cache = AICacheService.getInstance();
    await cache.init();
    return cache.get(bucket, key);
  }

  async generateRichContentForNode(req: RichContentGenRequest): Promise<AIResult<RichContentGenResponse>> {
    const res = await this.real.generateRichContentForNode(req);
    if (res.ok) {
      return res;
    }
    const failure: AIResultFailure = res as AIResultFailure;
    if (failure.error.code === AIErrorCode.AUTH) {
      return failure;
    }
    Logger.aiRequest('Failover', 'fallback-to-mock', failure.error.message);
    return this.mock.generateRichContentForNode(req);
  }
}