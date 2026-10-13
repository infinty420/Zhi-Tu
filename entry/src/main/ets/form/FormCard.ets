/**
 * FormCard —— 智图桌面卡片 UI（Wave 6）。
 * 数据由 FormAbility.onAddForm 通过 @LocalStorageProp 注入；点击按钮经 postCardAction
 * 发送 router 事件，唤起 EntryAbility 并携带 action=review，由 Index 路由进复习。
 */

// 注：postCardAction / FlexAlign / FontWeight 在卡片(Form)上下文中为 ArkUI 全局符号，
// 不可从 @kit 导入；直接使用即可（与常规页面一致）。

@Entry
@Component
struct FormCard {
  @LocalStorageProp('title') title: string = '智图 · 今日复习';
  @LocalStorageProp('tip') tip: string = '点卡片，开始复习';
  @LocalStorageProp('reviewText') reviewText: string = '开始复习';

  build() {
    Column() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%')
      Text(this.tip)
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')
        .margin({ top: 6 })
      Button(this.reviewText)
        .width('100%')
        .height(32)
        .margin({ top: 10 })
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: {
              action: 'review',
              nodeId: ''
            }
          });
        })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
}
