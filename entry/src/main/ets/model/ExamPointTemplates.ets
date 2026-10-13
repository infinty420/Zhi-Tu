/**
 * ExamPointTemplates —— 学科考点模板库（Wave 1 功能升级）。
 * 把出题意图收敛为学科考点关键词，用于：
 *   - Mock 出题时匹配考点提示（hint）；
 *   - ContentQualityChecker 计算「考点模板命中率」，反馈 AI 出题覆盖度。
 * 纯 model 层数据，不依赖 services / ArkUI，便于 model 与 storage 两层复用。
 */

/** 单个学科的考点模板 */
export interface ExamPointTemplate {
  /** 学科代码（math/physics/english…） */
  subject: string;
  /** 该学科高频考点关键词（用于命中率匹配） */
  topics: string[];
  /** 出题/复习提示文案 */
  hint: string;
}

/** 九学科考点模板（可随学科内容扩展） */
export const SUBJECT_EXAM_TEMPLATES: ExamPointTemplate[] = [
  { subject: 'math', topics: ['函数', '方程', '图像', '对称轴', '顶点', '公式', '最值', '判别式', '解析式'], hint: '注意定义、图像性质与公式套用。' },
  { subject: 'physics', topics: ['折射', '反射', '牛顿', '压强', '浮力', '电路', '能量', '力', '折射率', '全反射'], hint: '区分光密/光疏介质，注意方向判断。' },
  { subject: 'chemistry', topics: ['方程', '反应', '化合价', '酸碱', '氧化还原', '实验', '配平'], hint: '关注反应物/生成物与实验现象。' },
  { subject: 'biology', topics: ['结构', '功能', '分类', '遗传', '细胞', '系统', '进化'], hint: '结构与功能相适应，注意层级关系。' },
  { subject: 'english', topics: ['时态', '词汇', '句型', '语法', '阅读', '短语'], hint: '结合语境记忆搭配与用法。' },
  { subject: 'history', topics: ['事件', '年代', '原因', '影响', '人物', '改革'], hint: '理清时间线与因果链条。' },
  { subject: 'geo', topics: ['地形', '气候', '区位', '河流', '人口', '资源'], hint: '结合地图识记空间分布与成因。' },
  { subject: 'politics', topics: ['观点', '原理', '时政', '概念', '矛盾'], hint: '用原理分析现象，关注当前时事。' },
  { subject: 'chinese', topics: ['主旨', '修辞', '手法', '作者', '赏析', '意象'], hint: '从手法与情感入手赏析。' }
];

/** 取某学科的考点关键词列表（用于命中率匹配） */
export function subjectExamTopics(subject: string): string[] {
  for (let i = 0; i < SUBJECT_EXAM_TEMPLATES.length; i++) {
    if (SUBJECT_EXAM_TEMPLATES[i].subject === subject) {
      return SUBJECT_EXAM_TEMPLATES[i].topics;
    }
  }
  return [];
}

/** 按学科 + 节点文本匹配最相关的考点模板（节点文本命中任一关键词即匹配） */
export function matchExamTemplate(subject: string, nodeText: string): ExamPointTemplate | undefined {
  const t = nodeText ? nodeText : '';
  for (let i = 0; i < SUBJECT_EXAM_TEMPLATES.length; i++) {
    const tmpl = SUBJECT_EXAM_TEMPLATES[i];
    if (subject.length > 0 && tmpl.subject !== subject) {
      continue;
    }
    for (let j = 0; j < tmpl.topics.length; j++) {
      if (t.indexOf(tmpl.topics[j]) >= 0) {
        return tmpl;
      }
    }
  }
  // 未命中关键词时，回退到学科首条模板提供通用提示
  for (let i = 0; i < SUBJECT_EXAM_TEMPLATES.length; i++) {
    if (SUBJECT_EXAM_TEMPLATES[i].subject === subject) {
      return SUBJECT_EXAM_TEMPLATES[i];
    }
  }
  return undefined;
}

/** 单条测验是否命中某学科考点模板（题干或答案含任一关键词即算命中） */
export function quizMatchesTemplate(questionText: string, subject: string): boolean {
  const topics = subjectExamTopics(subject);
  if (topics.length === 0) {
    return false;
  }
  for (let i = 0; i < topics.length; i++) {
    if (questionText.indexOf(topics[i]) >= 0) {
      return true;
    }
  }
  return false;
}
