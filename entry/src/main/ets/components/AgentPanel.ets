/**
 * AgentPanel —— 内置 AI Agent 对话面板。
 * 折叠抽屉 + 输入框 + 流式打字气泡 + 「气泡 + 应用结果摘要」；
 * 请求携带当前导图 JSON + 对话历史；patch 经 PatchApplier 增量应用并汇报未生效项。
 */
import { promptAction } from '@kit.ArkUI';
import { MindMap } from '../model/MindMap';
import { AgentMessage, AIResultFailure } from '../services/AIService';
import { AIConfig } from '../services/AIConfig';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { PatchApplier } from '../services/PatchApplier';
import { MindMapStore } from '../services/MindMapStore';
import { Logger } from '../utils/Logger';

interface AgentMsg {
  role: string;
  content: string;
}

@Component
export struct AgentPanel {
  @Prop mapSnapshot: MindMap | undefined = undefined;
  onClose?: () => void;

  @State messages: AgentMsg[] = [];
  @State inputText: string = '';
  @State sending: boolean = false;
  @State liveStream: string = '';
  @State contextTruncated: boolean = false;
  private store: MindMapStore = MindMapStore.getInstance();
  private history: AgentMessage[] = [];

  aboutToAppear(): void {
    if (this.messages.length === 0) {
      this.messages.push({ role: 'assistant', content: '我是 AI 导图助手。可以帮你：展开分支、补充要点、批量改样式、切换布局、回答知识点问题。' });
    }
  }

  private async send(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    this.sending = true;
    this.liveStream = '';
    this.messages.push({ role: 'user', content: text });
    this.history.push({ role: 'user', content: text });
    this.inputText = '';

    // 上下文超限截断：历史超过 20 条精简较早对话
    if (this.history.length > 20) {
      this.history.splice(0, 2);
      this.contextTruncated = true;
    }

    const snap = this.store.currentSnapshot();
    if (!snap) {
      this.messages.push({ role: 'assistant', content: '当前没有可编辑的导图。' });
      this.sending = false;
      return;
    }

    try {
      const config = AIConfig.load();
      const svc = AIServiceFactory.create(config);
      Logger.aiRequest('AgentPanel', 'request', text);
      const res = await svc.chatPatch({
        mapJson: snap.toJson(),
        history: this.history,
        instruction: text
      }, (chunk) => {
        this.liveStream += chunk.delta;
      });
      if (res.ok) {
        const report = await PatchApplier.apply(res.data.ops, this.store);
        let resultLine = report.summary;
        if (report.skipped.length > 0) {
          const skippedShort = report.skipped.slice(0, 3).join('；');
          resultLine = `已应用 ${report.applied} 项修改；部分指令未生效：${skippedShort}${report.skipped.length > 3 ? '…' : ''}`;
        }
        const replyText = res.data.reply.length > 0 ? res.data.reply : '已根据指令完成改图。';
        this.messages.push({ role: 'assistant', content: `${replyText}\n【结果】${resultLine}` });
        this.history.push({ role: 'assistant', content: replyText });
      } else {
        const failure: AIResultFailure = res as AIResultFailure;
        Logger.aiRequest('AgentPanel', 'failed', failure.error.message);
        this.messages.push({ role: 'assistant', content: 'Agent 暂时不可用，请稍后重试。' });
        this.inputText = text;
      }
    } catch (err) {
      Logger.aiRequest('AgentPanel', 'failed', JSON.stringify(err));
      this.messages.push({ role: 'assistant', content: 'Agent 暂时不可用，请稍后重试。' });
      this.inputText = text;
    }
    this.sending = false;
    this.liveStream = '';
  }

  build() {
    Column() {
      // 头部
      Row() {
        Text('AI 导图助手')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a2333')
        Blank()
        Button('收起')
          .height(28)
          .fontSize(13)
          .backgroundColor('#8a94a6')
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
          })
      }
      .padding(12)
      .width('100%')
      .border({ width: { bottom: 1 }, color: '#e6ebf2' })

      if (this.contextTruncated) {
        Text('为保持对话连续，已精简较早对话')
          .fontSize(12)
          .fontColor('#faad14')
          .padding(6)
          .width('100%')
      }

      // 消息列表
      List({ space: 8 }) {
        ForEach(this.messages, (msg: AgentMsg) => {
          ListItem() {
            this.bubble(msg)
          }
        }, (msg: AgentMsg, idx: number) => `${msg.role}_${msg.content}_${idx}`)
      }
      .layoutWeight(1)
      .padding(12)
      .scrollBar(BarState.Auto)

      // 流式进行中
      if (this.sending) {
        Row({ space: 6 }) {
          LoadingProgress()
            .width(20)
            .height(20)
          Text(this.liveStream.length > 0 ? this.liveStream : '正在思考…')
            .fontSize(13)
            .fontColor('#8a94a6')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .padding({ left: 12, right: 12, bottom: 4 })
      }

      // 输入区
      Row({ space: 8 }) {
        TextInput({ placeholder: '向 AI 输入改图指令，如「展开二次函数分支」', text: this.inputText })
          .layoutWeight(1)
          .height(44)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.send();
          })
        Button('发送')
          .height(44)
          .fontSize(14)
          .backgroundColor('#1677ff')
          .enabled(!this.sending)
          .onClick(() => {
            this.send();
          })
      }
      .padding(12)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }

  @Builder
  bubble(msg: AgentMsg) {
    Row() {
      if (msg.role === 'user') {
        Blank()
        Text(msg.content)
          .fontSize(14)
          .fontColor('#ffffff')
          .backgroundColor('#1677ff')
          .borderRadius(12)
          .padding(10)
          .constraintSize({ maxWidth: '80%' })
      } else {
        Text(msg.content)
          .fontSize(14)
          .fontColor('#1a2333')
          .backgroundColor('#f3f8ff')
          .borderRadius(12)
          .padding(10)
          .constraintSize({ maxWidth: '86%' })
        Blank()
      }
    }
    .width('100%')
  }
}