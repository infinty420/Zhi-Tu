/**
 * 账号与云端同步页（v2.0；Wave 3 增加学习画像：角色 / 年级 / 关注学科）。
 * 登录 / 退出、编辑学习画像、查看我的学情摘要、上传当前导图到云端、浏览并下载云端导图。
 */
import { promptAction } from '@kit.ArkUI';
import { AccountService } from '../services/AccountService';
import { CloudService } from '../services/CloudService';
import { MindMapStore } from '../services/MindMapStore';
import { StudyInsightService } from '../services/StudyInsightService';
import { ACCOUNT_ROLES, AVATAR_CHOICES, AccountRole, accountRoleLabel } from '../model/Account';
import { CloudMapMeta } from '../model/Account';
import { MasteryLevel, ModelFailure, SUBJECTS, SubjectItem } from '../model/Constants';

function formatTime(ts: number): string {
  const d = new Date(ts);
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${y}-${m < 10 ? '0' + m : '' + m}-${day < 10 ? '0' + day : '' + day}`;
}

@Component
export struct AccountPage {
  @State name: string = '';
  @State accountName: string = '';
  @State avatar: string = '🦊';
  @State loggedIn: boolean = false;
  @State cloudMaps: CloudMapMeta[] = [];
  @State syncing: boolean = false;
  // Wave 3：学习画像
  @State role: AccountRole = 'student';
  @State grade: string = '';
  @State focus: string[] = [];
  @State masteryText: string = '—';
  @State weakCount: number = 0;
  @State wrongCount: number = 0;

  aboutToAppear(): void {
    const acc = AccountService.getInstance().getCurrent();
    if (acc) {
      this.accountName = acc.name;
      this.avatar = acc.avatar;
      this.role = acc.role ? acc.role : 'student';
      this.grade = acc.grade ? acc.grade : '';
      this.focus = acc.focusSubjects ? acc.focusSubjects : [];
      this.loggedIn = true;
    }
    this.refreshStudy();
    this.refreshCloud();
  }

  /** 我的学情摘要（本机学习数据聚合） */
  private refreshStudy(): void {
    const store = MindMapStore.getInstance();
    const snap = store.currentSnapshot();
    this.wrongCount = store.getWrongItems().length;
    if (!snap) {
      this.masteryText = '—';
      this.weakCount = 0;
      return;
    }
    let known = 0;
    for (let i = 0; i < snap.nodes.length; i++) {
      if (snap.nodes[i].mastery === MasteryLevel.KNOWN) {
        known++;
      }
    }
    this.masteryText = snap.nodes.length > 0 ? `${Math.round((known / snap.nodes.length) * 100)}%` : '—';
    this.weakCount = StudyInsightService.buildWeakPoints(snap, store.getWrongItems()).length;
  }

  private async refreshCloud(): Promise<void> {
    this.cloudMaps = await CloudService.getInstance().list();
  }

  private async doLogin(): Promise<void> {
    const acc = await AccountService.getInstance().login(this.name);
    this.accountName = acc.name;
    this.avatar = acc.avatar;
    this.role = acc.role ? acc.role : 'student';
    this.loggedIn = true;
    promptAction.showToast({ message: `已登录：${acc.name}` });
  }

  private async doLogout(): Promise<void> {
    await AccountService.getInstance().logout();
    this.loggedIn = false;
    this.accountName = '';
    this.focus = [];
    promptAction.showToast({ message: '已退出登录' });
  }

  /** 保存学习画像 */
  private async saveProfile(): Promise<void> {
    const acc = await AccountService.getInstance().updateProfile({
      name: this.accountName,
      avatar: this.avatar,
      role: this.role,
      grade: this.grade,
      focusSubjects: this.focus
    });
    if (!acc) {
      promptAction.showToast({ message: '请先登录' });
      return;
    }
    promptAction.showToast({ message: '学习画像已保存' });
  }

  private toggleFocus(label: string): void {
    if (this.focus.indexOf(label) >= 0) {
      this.focus = this.focus.filter((s) => s !== label);
    } else {
      this.focus = this.focus.concat([label]);
    }
  }

  private async doUpload(): Promise<void> {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (!snap) {
      promptAction.showToast({ message: '当前没有可导出的导图' });
      return;
    }
    const acc = AccountService.getInstance().getCurrent();
    if (!acc) {
      promptAction.showToast({ message: '请先登录' });
      return;
    }
    this.syncing = true;
    await CloudService.getInstance().upload(snap, acc.name, false);
    this.syncing = false;
    await this.refreshCloud();
    promptAction.showToast({ message: '已同步到云端' });
  }

  private async doDownload(meta: CloudMapMeta): Promise<void> {
    const map = await CloudService.getInstance().download(meta.id);
    if (!map) {
      promptAction.showToast({ message: '下载失败' });
      return;
    }
    const res = MindMapStore.getInstance().importAsNew(map.toJson());
    if (res.ok) {
      promptAction.showToast({ message: `已导入：${meta.title}` });
      await this.refreshCloud();
    } else {
      const fail: ModelFailure = res as ModelFailure;
      promptAction.showToast({ message: `导入失败：${fail.message}` });
    }
  }

  build() {
    NavDestination() {
      Column({ space: 14 }) {
        if (this.loggedIn) {
          Row({ space: 12 }) {
            Text(this.avatar)
              .fontSize(36)
            Column({ space: 4 }) {
              Text(this.accountName)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
              Text(`已登录 · ${accountRoleLabel(this.role)}${this.grade.length > 0 ? ' · ' + this.grade : ''}`)
                .fontSize(12)
                .fontColor('#8a94a6')
            }
            .layoutWeight(1)
            .alignSelf(ItemAlign.Start)
          }
          .padding(12)
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .width('100%')

          // 我的学情摘要
          Row({ space: 10 }) {
            this.miniStat('掌握率', this.masteryText)
            this.miniStat('薄弱点', `${this.weakCount}`)
            this.miniStat('错题', `${this.wrongCount}`)
          }
          .width('100%')

          // 学习画像编辑
          Column({ space: 10 }) {
            Text('学习画像')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1a2333')
              .alignSelf(ItemAlign.Start)

            Row({ space: 8 }) {
              ForEach(ACCOUNT_ROLES, (r: AccountRole) => {
                Text(accountRoleLabel(r))
                  .fontSize(13)
                  .fontColor(this.role === r ? '#ffffff' : '#4a5468')
                  .backgroundColor(this.role === r ? '#1677ff' : '#f0f3f8')
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .onClick(() => {
                    this.role = r;
                  })
              }, (r: AccountRole) => r)
            }
            .width('100%')

            TextInput({ placeholder: '年级 / 学段，如 初二、高一', text: this.grade })
              .height(42)
              .onChange((v: string) => {
                this.grade = v;
              })

            Text('头像')
              .fontSize(12)
              .fontColor('#8a94a6')
              .alignSelf(ItemAlign.Start)
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(AVATAR_CHOICES, (a: string) => {
                Text(a)
                  .fontSize(20)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(8)
                  .backgroundColor(this.avatar === a ? '#e6f4ff' : Color.Transparent)
                  .onClick(() => {
                    this.avatar = a;
                  })
              }, (a: string) => a)
            }
            .width('100%')

            Text('关注学科（影响首页推荐排序）')
              .fontSize(12)
              .fontColor('#8a94a6')
              .alignSelf(ItemAlign.Start)
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(SUBJECTS, (s: SubjectItem) => {
                Text(s.label)
                  .fontSize(12)
                  .fontColor(this.focus.indexOf(s.label) >= 0 ? '#ffffff' : '#4a5468')
                  .backgroundColor(this.focus.indexOf(s.label) >= 0 ? '#1677ff' : '#f0f3f8')
                  .borderRadius(12)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    this.toggleFocus(s.label);
                  })
              }, (s: SubjectItem) => s.code)
            }
            .width('100%')

            Button('保存学习画像')
              .width('100%')
              .height(38)
              .backgroundColor('#52c41a')
              .onClick(() => {
                this.saveProfile();
              })
          }
          .padding(12)
          .backgroundColor('#f3f8ff')
          .borderRadius(12)
          .width('100%')

          Button(this.syncing ? '同步中…' : '上传当前导图到云端')
            .width('100%')
            .height(40)
            .backgroundColor('#1677ff')
            .enabled(!this.syncing)
            .onClick(() => {
              this.doUpload();
            })

          Button('退出登录')
            .width('100%')
            .height(40)
            .backgroundColor('#f5222d')
            .onClick(() => {
              this.doLogout();
            })
        } else {
          Text('登录智图账号（本地 Mock）')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
          TextInput({ placeholder: '输入昵称', text: this.name })
            .height(44)
            .onChange((value: string) => {
              this.name = value;
            })
          Button('登录')
            .width('100%')
            .height(40)
            .backgroundColor('#1677ff')
            .onClick(() => {
              this.doLogin();
            })
        }

        Text('云端导图')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
          .alignSelf(ItemAlign.Start)

        if (this.cloudMaps.length === 0) {
          Text('云端还没有导图，先上传一张吧')
            .fontSize(13)
            .fontColor('#8a94a6')
        } else {
          List() {
            ForEach(this.cloudMaps, (m: CloudMapMeta) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(m.title)
                      .fontSize(15)
                      .fontColor('#1a2333')
                    Text(`${m.owner} · ${formatTime(m.updatedAt)} · ${m.shared ? '已分享' : '私有'}`)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                  }
                  .layoutWeight(1)
                  .alignSelf(ItemAlign.Start)
                  Button('下载')
                    .height(32)
                    .fontSize(13)
                    .backgroundColor('#13c2c2')
                    .onClick(() => {
                      this.doDownload(m);
                    })
                }
                .padding(10)
              }
            }, (m: CloudMapMeta) => m.id)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
    }
    .title('账号与云端')
    .width('100%')
    .height('100%')
  }

  @Builder
  miniStat(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1677ff')
      Text(label)
        .fontSize(12)
        .fontColor('#8a94a6')
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor('#ffffff')
    .borderRadius(10)
  }
}
