/**
 * StudyPage —— 引导式学习模式（NavDestination，v1.1）。
 * 根→叶逐节点看要点、标记掌握度；学完即调用 AI 自动出测验题并判分，
 * 答错自动进错题本 + 触发间隔复习排队（复用 MindMapStore / ReviewScheduler）。
 */

import { promptAction } from '@kit.ArkUI';
import { MasteryLevel } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { MindMapStore } from '../services/MindMapStore';
import { QuizQuestion } from '../services/AIService';
import { QuizService } from '../services/QuizService';
import { DeepLinkRouter } from '../services/DeepLinkRouter';

@Component
export struct StudyPage {
  @State mapId: string = '';
  @State mapSnapshot: MindMap | undefined = undefined;
  @State order: string[] = [];
  @State idx: number = 0;
  @State finished: boolean = false;
  @State phase: string = 'study'; // 'study' | 'quiz' | 'done'
  @State quizGenerating: boolean = false;
  @State questions: QuizQuestion[] = [];
  @State qIndex: number = 0;
  @State userAnswer: string = '';
  @State grading: boolean = false;
  @State graded: boolean = false;
  @State lastCorrect: boolean = false;
  @State lastScore: number = 0;
  @State lastExplanation: string = '';
  @State quizCorrectCount: number = 0;
  private store: MindMapStore = MindMapStore.getInstance();
  private quiz: QuizService = new QuizService();
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = this.store.subscribe((snapshot) => {
      this.mapSnapshot = snapshot;
    });
    this.store.openMapById(this.mapId).then((ok: boolean) => {
      if (!ok) {
        promptAction.showToast({ message: '导图不存在' });
        return;
      }
      const snap = this.store.currentSnapshot();
      this.mapSnapshot = snap;
      this.order = this.buildOrder(snap);
      this.idx = 0;
      this.finished = this.order.length === 0;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  /** 根→叶广度优先遍历顺序 */
  private buildOrder(map: MindMap | undefined): string[] {
    const result: string[] = [];
    if (!map) {
      return result;
    }
    let root: MindNode | undefined = undefined;
    for (let i = 0; i < map.nodes.length; i++) {
      if (map.nodes[i].parentId === null) {
        root = map.nodes[i];
        break;
      }
    }
    if (!root) {
      return result;
    }
    const queue: MindNode[] = [root];
    const visited: Set<string> = new Set<string>();
    visited.add(root.id);
    let head = 0;
    while (head < queue.length) {
      const node = queue[head];
      head = head + 1;
      result.push(node.id);
      for (let i = 0; i < map.nodes.length; i++) {
        const child = map.nodes[i];
        if (child.parentId === node.id && !visited.has(child.id)) {
          visited.add(child.id);
          queue.push(child);
        }
      }
    }
    return result;
  }

  private get currentNode(): MindNode | undefined {
    if (!this.mapSnapshot || this.idx >= this.order.length) {
      return undefined;
    }
    return this.mapSnapshot.findNode(this.order[this.idx]);
  }

  private get progressText(): string {
    if (this.order.length === 0) {
      return '';
    }
    return `进度 ${this.idx + 1}/${this.order.length}`;
  }

  private markMastery(level: MasteryLevel): void {
    const node = this.currentNode;
    if (!node) {
      return;
    }
    this.store.setMastery(node.id, level);
    this.advance();
  }

  private advance(): void {
    if (this.idx + 1 >= this.order.length) {
      this.finished = true;
    } else {
      this.idx = this.idx + 1;
    }
  }

  private prevNode(): void {
    if (this.idx > 0) {
      this.idx = this.idx - 1;
    }
  }

  private async startQuiz(): Promise<void> {
    const snap = this.mapSnapshot;
    if (!snap) {
      return;
    }
    this.quizGenerating = true;
    try {
      const questions = await this.quiz.generate({ mapJson: snap.toJson(), limit: 8 });
      if (questions.length > 0) {
        this.questions = questions;
        this.qIndex = 0;
        this.userAnswer = '';
        this.graded = false;
        this.quizCorrectCount = 0;
        this.phase = 'quiz';
      } else {
        promptAction.showToast({ message: '暂无法生成测验题' });
      }
    } catch (err) {
      promptAction.showToast({ message: '生成测验失败' });
    }
    this.quizGenerating = false;
  }

  private get currentQuestion(): QuizQuestion | undefined {
    if (this.qIndex >= this.questions.length) {
      return undefined;
    }
    return this.questions[this.qIndex];
  }

  private async grade(): Promise<void> {
    const q = this.currentQuestion;
    if (!q) {
      return;
    }
    this.grading = true;
    try {
      const res = this.quiz.grade(q, this.userAnswer);
      this.lastCorrect = res.correct;
      this.lastScore = res.score;
      this.lastExplanation = res.explanation;
      this.graded = true;
      if (res.correct) {
        this.quizCorrectCount = this.quizCorrectCount + 1;
      }
      // 归集：更新掌握度、答错进错题本、排复习（单一事实源经 NodeLearnService → MindMapStore）
      this.quiz.recordResult(q.nodeId, res.correct, q.prompt, q.answer, this.userAnswer);
    } catch (err) {
      promptAction.showToast({ message: '判分失败' });
    }
    this.grading = false;
  }

  private nextQuestion(): void {
    this.userAnswer = '';
    this.graded = false;
    if (this.qIndex + 1 >= this.questions.length) {
      this.phase = 'done';
    } else {
      this.qIndex = this.qIndex + 1;
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // 顶部栏
          Row({ space: 8 }) {
            Button($r('app.string.nav_back'))
              .height(32)
              .fontSize(14)
              .backgroundColor('#1677ff')
              .onClick(() => {
                DeepLinkRouter.pop();
              })
            Text($r('app.string.study_title'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1a2333')
            Blank()
            if (this.phase === 'study') {
              Text(this.progressText)
                .fontSize(13)
                .fontColor('#8a94a6')
            }
          }
          .padding(12)
          .width('100%')

          if (this.phase === 'study') {
            this.studyBody()
          } else if (this.phase === 'quiz') {
            this.quizBody()
          } else {
            this.quizDoneBody()
          }
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  @Builder
  studyBody() {
    if (this.finished || this.order.length === 0) {
      Column({ space: 16 }) {
        Text($r('app.string.study_done_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a2333')
        Text('已遍历全部节点。学完即测，巩固记忆。')
          .fontSize(14)
          .fontColor('#8a94a6')
        Button($r('app.string.study_start_quiz'))
          .width('70%')
          .height(44)
          .backgroundColor('#1677ff')
          .enabled(!this.quizGenerating)
          .onClick(() => {
            this.startQuiz();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: 16 }) {
        // 当前节点卡
        Column({ space: 10 }) {
          Text(this.currentNode ? this.currentNode.text : '')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
            .width('100%')
          Text(this.currentNode && this.currentNode.detail && this.currentNode.detail.length > 0
            ? this.currentNode.detail : $r('app.string.study_detail_empty'))
            .fontSize(15)
            .fontColor('#5a6473')
            .width('100%')
        }
        .padding(20)
        .backgroundColor('#ffffff')
        .borderRadius(16)
        .width('100%')

        // 掌握度标记
        Text($r('app.string.mastery_label'))
          .fontSize(14)
          .fontColor('#8a94a6')
          .alignSelf(ItemAlign.Start)
        Row({ space: 12 }) {
          Button($r('app.string.mastery_known'))
            .height(40)
            .fontSize(15)
            .backgroundColor('#52c41a')
            .onClick(() => {
              this.markMastery(MasteryLevel.KNOWN);
            })
          Button($r('app.string.mastery_fuzzy'))
            .height(40)
            .fontSize(15)
            .backgroundColor('#faad14')
            .onClick(() => {
              this.markMastery(MasteryLevel.FUZZY);
            })
          Button($r('app.string.mastery_unknown'))
            .height(40)
            .fontSize(15)
            .backgroundColor('#f5222d')
            .onClick(() => {
              this.markMastery(MasteryLevel.UNKNOWN);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        Blank()

        // 上/下导航
        Row({ space: 12 }) {
          Button($r('app.string.study_prev'))
            .height(38)
            .fontSize(14)
            .backgroundColor('#8a94a6')
            .enabled(this.idx > 0)
            .onClick(() => {
              this.prevNode();
            })
          Button($r('app.string.study_next'))
            .height(38)
            .fontSize(14)
            .backgroundColor('#1677ff')
            .onClick(() => {
              this.advance();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .padding(16)
      .layoutWeight(1)
      .width('100%')
    }
  }

  @Builder
  quizBody() {
    if (this.quizGenerating) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color('#1677ff')
        Text($r('app.string.quiz_generating'))
          .fontSize(14)
          .fontColor('#8a94a6')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 40 })
    } else {
      Column({ space: 14 }) {
        Text(`第 ${this.qIndex + 1}/${this.questions.length} 题`)
          .fontSize(13)
          .fontColor('#8a94a6')
        Text(this.currentQuestion ? this.currentQuestion.prompt : '')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
          .width('100%')
        if (this.currentQuestion && this.currentQuestion.hint && this.currentQuestion.hint.length > 0) {
          Text(`💡 ${this.currentQuestion.hint}`)
            .fontSize(13)
            .fontColor('#8a94a6')
            .width('100%')
        }
        if (this.currentQuestion && this.currentQuestion.options && this.currentQuestion.options.length > 0) {
          Column({ space: 6 }) {
            ForEach(this.currentQuestion.options, (opt: string) => {
              Text(opt)
                .fontSize(14)
                .fontColor('#5a6473')
                .width('100%')
            }, (opt: string) => opt)
          }
          .padding(10)
          .backgroundColor('#e6f4ff')
          .borderRadius(10)
          .width('100%')
        }
        TextArea({ placeholder: $r('app.string.quiz_your_answer'), text: this.userAnswer })
          .height(120)
          .onChange((value: string) => {
            this.userAnswer = value;
          })
        if (this.graded) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text(this.lastCorrect ? $r('app.string.quiz_correct') : $r('app.string.quiz_wrong'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.lastCorrect ? '#52c41a' : '#f5222d')
              Text(`得分 ${this.lastScore}`)
                .fontSize(14)
                .fontColor('#8a94a6')
            }
            Text(`${$r('app.string.quiz_explanation')}：${this.lastExplanation}`)
              .fontSize(14)
              .fontColor('#5a6473')
              .width('100%')
          }
          .padding(12)
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .width('100%')
        }
        Blank()
        if (!this.graded) {
          Button($r('app.string.quiz_submit'))
            .width('100%')
            .height(44)
            .backgroundColor('#1677ff')
            .enabled(!this.grading)
            .onClick(() => {
              this.grade();
            })
        } else {
          Button($r('app.string.quiz_next'))
            .width('100%')
            .height(44)
            .backgroundColor('#13c2c2')
            .onClick(() => {
              this.nextQuestion();
            })
        }
      }
      .padding(16)
      .layoutWeight(1)
      .width('100%')
    }
  }

  @Builder
  quizDoneBody() {
    Column({ space: 18 }) {
      Text($r('app.string.quiz_summary'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a2333')
      Text(`${this.quizCorrectCount}/${this.questions.length}`)
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1677ff')
      Text('答错的题目已自动进入错题本，并排入间隔复习。')
        .fontSize(14)
        .fontColor('#8a94a6')
        .textAlign(TextAlign.Center)
      Button($r('app.string.study_finish'))
        .width('70%')
        .height(44)
        .backgroundColor('#1677ff')
        .onClick(() => {
          DeepLinkRouter.pop();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
