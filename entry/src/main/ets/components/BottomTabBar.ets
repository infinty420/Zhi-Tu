/**
 * BottomTabBar —— 底部分区导航栏（Wave 9）。
 * 复用于四个分区 Hub 页底部：选中态高亮、点击切换分区；进入子页面时随 Hub 一起被 Navigation 覆盖而隐藏。
 */
interface TabDef {
  index: number;
  label: string;
  color: string;
}

@Component
export struct BottomTabBar {
  @Prop selectedTab: number = 0;
  onTabChange: (index: number) => void = () => {};

  build() {
    Row() {
      this.tabItem(0, '首页', '#13c2c2')
      this.tabItem(1, '学习', '#1677ff')
      this.tabItem(2, '社区', '#d4537e')
      this.tabItem(3, '我的', '#fa8c16')
    }
    .width('100%')
    .height(56)
    .backgroundColor('#ffffff')
    .borderWidth({ top: 0.5 })
    .borderColor('#e5e8ef')
  }

  @Builder
  tabItem(index: number, label: string, color: string) {
    Column({ space: 5 }) {
      Row() {
      }
      .width(22)
      .height(3)
      .borderRadius(2)
      .backgroundColor(this.selectedTab === index ? color : Color.Transparent)
      Text(label)
        .fontSize(12)
        .fontColor(this.selectedTab === index ? color : '#8a94a6')
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.selectedTab !== index) {
        this.onTabChange(index);
      }
    })
  }
}
