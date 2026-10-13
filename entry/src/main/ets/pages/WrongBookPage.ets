/**
 * WrongBookPage —— 错题本 / 生词本（NavDestination，v1.1）。
 * 自测答错自动归集错题本；英语例句收藏沉淀到生词本。支持查看与移除。
 */

import { promptAction } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { VocabItem, WrongItem } from '../model/StudyModels';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { StudyInsightService } from '../services/StudyInsightService';
import { QuizService } from '../services/QuizService';
import { QuizQuestion } from '../services/AIService';

@Component
export struct WrongBookPage {
  @State activeTab: number = 0; // 0=错题本 1=生词本
  @State wrong: WrongItem[] = [];
  @State vocab: VocabItem[] = [];
  // Wave 2：智能组卷（错题本按遗忘曲线出复习卷）
  @State wbActive: boolean = false;
  @State wbQuiz: QuizQuestion[] = [];
  @State wbIndex: number = 0;
  @State wbNodeId: string = '';
  @State wbPrompt: string = '';
  @State wbAnswer: string = '';
  @State wbHint: string = '';
  @State wbInput: string = '';
  @State wbResult: string = '';
  private store: MindMapStore = MindMapStore.getInstance();

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.wrong = this.store.getWrongItems();
    this.vocab = this.store.getVocabItems();
  }

  private removeWrong(id: string): void {
    this.store.removeWrongItem(id);
    this.refresh();
  }

  private removeVocab(id: string): void {
    this.store.removeVocabItem(id);
    this.refresh();
  }

  /** 智能组卷：按遗忘曲线从错题本去重出一套复习卷 */
  private startWrongQuiz(): void {
    const qs = StudyInsightService.composeWrongBookQuiz(this.wrong, 5);
    if (qs.length === 0) {
      promptAction.showToast({ message: '暂无错题可组卷' });
      return;
    }
    this.wbQuiz = qs;
    this.wbIndex = 0;
    this.wbActive = true;
    this.loadWbQuestion();
  }

  /** 载入当前序号的题目（字段拆到 @State，避免 builder 内取联合类型） */
  private loadWbQuestion(): void {
    if (this.wbIndex < this.wbQuiz.length) {
      const q = this.wbQuiz[this.wbIndex];
      this.wbNodeId = q.nodeId;
      this.wbPrompt = q.prompt;
      this.wbAnswer = q.answer;
      this.wbHint = q.hint ? q.hint : '';
    }
    this.wbInput = '';
    this.wbResult = '';
  }

  /** 组卷判分：复用 QuizService，结果归集经 NodeLearnService → MindMapStore */
  private submitWbAnswer(): void {
    const user = this.wbInput.trim();
    if (user.length < 2) {
      promptAction.showToast({ message: '请输入至少 2 个字的答案' });
      return;
    }
    const q: QuizQuestion = {
      id: `wb_${this.wbNodeId}`,
      kind: 'qa',
      nodeId: this.wbNodeId,
      prompt: this.wbPrompt,
      answer: this.wbAnswer,
      hint: this.wbHint
    };
    const quiz = new QuizService();
    const grade = quiz.grade(q, user);
    quiz.recordResult(this.wbNodeId, grade.correct, this.wbPrompt, this.wbAnswer, user);
    this.wbResult = grade.correct
      ? `回答正确（${grade.score} 分），该错题已消项。`
      : `仍未通过（${grade.score} 分）。${grade.explanation}`;
    this.refresh();
  }

  private nextWbQuestion(): void {
    if (this.wbIndex + 1 >= this.wbQuiz.length) {
      this.wbActive = false;
      this.wbQuiz = [];
      this.wbIndex = 0;
      this.wbResult = '';
      promptAction.showToast({ message: '本轮组卷复习完成' });
      return;
    }
    this.wbIndex = this.wbIndex + 1;
    this.loadWbQuestion();
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Button($r('app.string.nav_back'))
            .height(32)
            .fontSize(14)
            .backgroundColor('#1677ff')
            .onClick(() => {
              DeepLinkRouter.pop();
            })
          Text($r('app.string.wrong_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
        }
        .padding(12)
        .width('100%')

        // 切换标签
        Row({ space: 12 }) {
          this.tabButton($r('app.string.tab_wrong'), this.activeTab === 0, () => {
            this.activeTab = 0;
          })
          this.tabButton($r('app.string.tab_vocab'), this.activeTab === 1, () => {
            this.activeTab = 1;
          })
        }
        .padding({ left: 16, right: 16 })
        .width('100%')

        if (this.activeTab === 0) {
          this.wrongQuizCard()
          this.wrongList()
        } else {
          this.vocabList()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  @Builder
  wrongQuizCard() {
    if (this.wrong.length > 0) {
      Column({ space: 10 }) {
        if (!this.wbActive) {
          Button('智能组卷复习（按遗忘曲线出 5 题）')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#722ed1')
            .onClick(() => {
              this.startWrongQuiz();
            })
        } else {
          Row() {
            Text(`组卷复习 ${this.wbIndex + 1}/${this.wbQuiz.length}`)
              .fontSize(13)
              .fontColor('#5f6b7f')
              .layoutWeight(1)
            Button('结束')
              .height(28)
              .fontSize(12)
              .backgroundColor('#8a94a6')
              .onClick(() => {
                this.wbActive = false;
                this.wbQuiz = [];
                this.wbIndex = 0;
                this.wbInput = '';
                this.wbResult = '';
              })
          }
          .width('100%')
          Text(this.wbPrompt)
            .fontSize(14)
            .fontColor('#1a2333')
            .width('100%')
          if (this.wbHint.length > 0) {
            Text(this.wbHint)
              .fontSize(12)
              .fontColor('#8a94a6')
              .width('100%')
          }
          TextArea({ text: this.wbInput, placeholder: '写下你的答案…' })
            .fontSize(14)
            .height(70)
            .width('100%')
            .onChange((v: string) => {
              this.wbInput = v;
            })
          Row({ space: 8 }) {
            Button('提交判分')
              .layoutWeight(1)
              .height(36)
              .fontSize(13)
              .backgroundColor('#1677ff')
              .onClick(() => {
                this.submitWbAnswer();
              })
            Button('下一题')
              .layoutWeight(1)
              .height(36)
              .fontSize(13)
              .fontColor('#1677ff')
              .backgroundColor('#ffffff')
              .border({ width: 1, color: '#1677ff' })
              .onClick(() => {
                this.nextWbQuestion();
              })
          }
          .width('100%')
          if (this.wbResult.length > 0) {
            Text(this.wbResult)
              .fontSize(13)
              .fontColor('#d48806')
              .width('100%')
          }
        }
      }
      .padding(12)
      .backgroundColor('#ffffff')
      .borderRadius(12)
      .width('100%')
      .margin({ left: 16, right: 16, bottom: 8 })
    }
  }

  @Builder
  tabButton(label: Resource, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(15)
      .fontColor(active ? '#ffffff' : '#1a2333')
      .backgroundColor(active ? '#1677ff' : '#e6f4ff')
      .borderRadius(16)
      .padding({ left: 18, right: 18, top: 6, bottom: 6 })
      .onClick(onTap)
  }

  @Builder
  wrongList() {
    if (this.wrong.length === 0) {
      Text($r('app.string.wrong_empty'))
        .fontSize(14)
        .fontColor('#8a94a6')
        .margin({ top: 40 })
        .width('100%')
        .textAlign(TextAlign.Center)
    } else {
      List({ space: 10 }) {
        ForEach(this.wrong, (w: WrongItem) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(w.nodeText)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1a2333')
                .width('100%')
              Row({ space: 4 }) {
                Text($r('app.string.wrong_question') + '：')
                  .fontSize(13)
                  .fontColor('#8a94a6')
                Text(w.question)
                  .fontSize(13)
                  .fontColor('#5a6473')
                  .layoutWeight(1)
              }
              .width('100%')
              Row({ space: 4 }) {
                Text($r('app.string.wrong_answer') + '：')
                  .fontSize(13)
                  .fontColor('#52c41a')
                Text(w.answer)
                  .fontSize(13)
                  .fontColor('#5a6473')
                  .layoutWeight(1)
              }
              .width('100%')
              Row({ space: 4 }) {
                Text($r('app.string.wrong_your_answer') + '：')
                  .fontSize(13)
                  .fontColor('#f5222d')
                Text(w.userAnswer)
                  .fontSize(13)
                  .fontColor('#5a6473')
                  .layoutWeight(1)
              }
              .width('100%')
              Row() {
                Blank()
                Button($r('app.string.wrong_remove'))
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#f5222d')
                  .onClick(() => {
                    this.removeWrong(w.id);
                  })
              }
              .width('100%')
            }
            .padding(12)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .width('100%')
          }
        }, (w: WrongItem) => w.id)
      }
      .layoutWeight(1)
      .padding(16)
      .width('100%')
    }
  }

  @Builder
  vocabList() {
    if (this.vocab.length === 0) {
      Text($r('app.string.vocab_empty'))
        .fontSize(14)
        .fontColor('#8a94a6')
        .margin({ top: 40 })
        .width('100%')
        .textAlign(TextAlign.Center)
    } else {
      List({ space: 10 }) {
        ForEach(this.vocab, (v: VocabItem) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(v.english)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1a2333')
                .width('100%')
              Text(v.chinese)
                .fontSize(14)
                .fontColor('#5a6473')
                .width('100%')
              if (v.analysis && v.analysis.length > 0) {
                Text(v.analysis)
                  .fontSize(13)
                  .fontColor('#1677ff')
                  .backgroundColor('#e6f4ff')
                  .borderRadius(8)
                  .padding(8)
                  .width('100%')
              }
              Row() {
                Blank()
                Button($r('app.string.wrong_remove'))
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#f5222d')
                  .onClick(() => {
                    this.removeVocab(v.id);
                  })
              }
              .width('100%')
            }
            .padding(12)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .width('100%')
          }
        }, (v: VocabItem) => v.id)
      }
      .layoutWeight(1)
      .padding(16)
      .width('100%')
    }
  }
}
