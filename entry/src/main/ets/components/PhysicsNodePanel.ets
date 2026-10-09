/**
 * PhysicsNodePanel —— 物理学科专项面板（Wave 2：补齐第 9 科内嵌呈现）。
 * 物理在 NodeRichContent 中无独立槽位（公式/要点由通用卡片承载），
 * 故本面板承载物理专有能力：按节点文本匹配仿真模型，并一键唤起 PhysicsSimPage。
 * 复用 PhysicsSimEngine 模型库与 DeepLinkRouter 深链，不引入新依赖 / 新 NavDestination。
 */
import { NodeType } from '../model/Constants';
import { PhysicsModelDef, PhysicsSimEngine } from '../engine/PhysicsSimEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';

@Component
export struct PhysicsNodePanel {
  @Prop nodeId: string = '';
  @Prop nodeText: string = '';
  onAi: () => void = () => {};

  /** 当前节点是否匹配到仿真模型 */
  private hasMatch(): boolean {
    return PhysicsSimEngine.matchModel(this.nodeText) !== undefined;
  }

  /** 匹配到的模型中文名（未匹配返回空串） */
  private matchedLabel(): string {
    const id = PhysicsSimEngine.matchModel(this.nodeText);
    if (!id) {
      return '';
    }
    const def = PhysicsSimEngine.findModel(id);
    return def ? def.label : '';
  }

  /** 匹配模型的可调参数说明（未匹配返回空串） */
  private matchedParams(): string {
    const id = PhysicsSimEngine.matchModel(this.nodeText);
    if (!id) {
      return '';
    }
    const def = PhysicsSimEngine.findModel(id);
    if (!def) {
      return '';
    }
    const names: string[] = [];
    for (let i = 0; i < def.params.length; i++) {
      names.push(def.params[i].label);
    }
    return names.join(' / ');
  }

  /** 唤起物理仿真页（payload 传模型中文名，PhysicsSimPage 侧 matchModel 命中） */
  private openSim(label: string): void {
    DeepLinkRouter.route(this.nodeId, NodeType.PHYSICS, label);
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('物理 · 仿真模型')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#f6ffed')
          .fontColor('#389e0d')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')

      if (this.hasMatch()) {
        Column({ space: 4 }) {
          Text(`已匹配模型：${this.matchedLabel()}`)
            .fontSize(14)
            .fontColor('#1a2333')
            .width('100%')
          if (this.matchedParams().length > 0) {
            Text(`可调参数：${this.matchedParams()}`)
              .fontSize(12)
              .fontColor('#8a94a6')
              .width('100%')
          }
          Button('打开仿真')
            .width('100%')
            .height(36)
            .fontSize(14)
            .backgroundColor('#00b96b')
            .onClick(() => {
              this.openSim(this.matchedLabel());
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .borderRadius(10)
        .backgroundColor('#f6ffed')
        .width('100%')
      } else {
        Column({ space: 6 }) {
          Text('该知识点暂未匹配到仿真模型，可任选一个模型进入体验：')
            .fontSize(12)
            .fontColor('#8a94a6')
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(PhysicsSimEngine.MODELS, (m: PhysicsModelDef) => {
              Text(m.label)
                .fontSize(13)
                .fontColor('#00b96b')
                .backgroundColor('#ffffff')
                .borderRadius(10)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .margin({ right: 6, bottom: 6 })
                .onClick(() => {
                  this.openSim(m.label);
                })
            }, (m: PhysicsModelDef) => m.id)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .borderRadius(10)
        .backgroundColor('#f6ffed')
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(12)
    .backgroundColor('#ffffff')
    .width('100%')
  }
}
