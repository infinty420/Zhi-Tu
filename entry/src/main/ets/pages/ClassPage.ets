/**
 * 师生协作页（v2.0 一起学 · 师生协作）。创建/加入班级、布置作业、查看提交情况。
 * 数据以 Mock 持久化（Preferences），单设备演示师生两种角色。
 */
import { promptAction } from '@kit.ArkUI';
import { ClassService } from '../services/ClassService';
import { AccountService } from '../services/AccountService';
import { ClassInsightService, AssignmentProgress, ClassSummary } from '../services/ClassInsightService';
import { MindMapStore } from '../services/MindMapStore';
import { Assignment, ClassInsight, ClassRoom } from '../model/ClassModels';
import { GenUid } from '../utils/GenUid';

function formatTime(ts: number): string {
  if (!ts || ts <= 0) {
    return '未设置';
  }
  const d = new Date(ts);
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${y}-${m < 10 ? '0' + m : '' + m}-${day < 10 ? '0' + day : '' + day}`;
}

@Component
export struct ClassPage {
  @State rooms: ClassRoom[] = [];
  @State view: string = 'list';
  @State className: string = '';
  @State joinCode: string = '';
  @State studentName: string = '';
  @State assignDays: string = '3';
  @State assignTitle: string = '';
  @State current: ClassRoom | undefined = undefined;
  /** 本班学情回传记录 */
  @State insights: ClassInsight[] = [];
  /** 各作业完成率 */
  @State progress: AssignmentProgress[] = [];
  /** 班级整体画像 */
  @State summary: ClassSummary = { reportedCount: 0, avgMastery: 0, weakTotal: 0, topWeakText: '' };
  /** 当前以「学生」身份加入时使用的名字 */
  private myName: string = '我';

  aboutToAppear(): void {
    const acc = AccountService.getInstance().getCurrent();
    if (acc && acc.name.length > 0) {
      this.myName = acc.name;
    }
    this.refresh();
  }

  private refresh(): void {
    this.rooms = ClassService.getInstance().listClasses();
  }

  /** 进入班级详情时一并刷新学情数据 */
  private openRoom(room: ClassRoom): void {
    this.current = room;
    this.view = 'detail';
    this.refreshInsight();
  }

  private refreshInsight(): void {
    const room = this.current;
    if (!room) {
      return;
    }
    this.progress = ClassInsightService.assignmentProgress(room);
    this.insights = ClassService.getInstance().getInsights(room.id);
    this.summary = ClassInsightService.summarize(this.insights);
  }

  /** 把本机学情回传给当前班级 */
  private async doReportInsight(): Promise<void> {
    const room = this.current;
    if (!room) {
      return;
    }
    let student = room.students.find((s) => s.name === this.myName);
    if (!student) {
      student = { id: GenUid.next('s'), name: this.myName };
      room.students.push(student);
    }
    const store = MindMapStore.getInstance();
    const insight = ClassInsightService.buildMyInsight(store.currentSnapshot(), store.getWrongItems(), student.id, student.name);
    const ok = await ClassService.getInstance().submitInsight(room.id, insight);
    if (ok) {
      promptAction.showToast({ message: '学情已回传给老师' });
      this.current = ClassService.getInstance().getClass(room.id);
      this.refreshInsight();
    } else {
      promptAction.showToast({ message: '回传失败' });
    }
  }

  private async doCreate(): Promise<void> {
    const acc = AccountService.getInstance().getCurrent();
    const teacher = acc ? acc.name : '老师';
    const room = await ClassService.getInstance().createClass(this.className, teacher);
    promptAction.showToast({ message: `班级已创建，邀请码：${room.code}` });
    this.className = '';
    this.view = 'list';
    this.refresh();
  }

  private async doJoin(): Promise<void> {
    const name = this.studentName.trim().length > 0 ? this.studentName.trim() : '我';
    const room = await ClassService.getInstance().joinClass(this.joinCode, name);
    if (!room) {
      promptAction.showToast({ message: '邀请码无效' });
      return;
    }
    this.myName = name;
    promptAction.showToast({ message: `已加入「${room.name}」` });
    this.joinCode = '';
    this.studentName = '';
    this.view = 'list';
    this.refresh();
  }

  private async doCreateAssignment(): Promise<void> {
    if (!this.current) {
      return;
    }
    const days = Number(this.assignDays);
    const due = Date.now() + (isNaN(days) ? 3 : days) * 24 * 60 * 60 * 1000;
    const ok = await ClassService.getInstance().createAssignment(this.current.id, this.assignTitle, due);
    if (ok) {
      promptAction.showToast({ message: '作业已布置' });
      this.assignTitle = '';
      this.assignDays = '3';
      this.current = ClassService.getInstance().getClass(this.current.id);
      this.refreshInsight();
    } else {
      promptAction.showToast({ message: '布置失败' });
    }
  }

  private async doSubmit(assignment: Assignment): Promise<void> {
    if (!this.current) {
      return;
    }
    const room = this.current;
    let student = room.students.find((s) => s.name === this.myName);
    if (!student) {
      student = { id: GenUid.next('s'), name: this.myName };
      room.students.push(student);
    }
    const ok = await ClassService.getInstance().submitAssignment(room.id, assignment.id, student.id);
    if (ok) {
      promptAction.showToast({ message: '已提交' });
      this.current = ClassService.getInstance().getClass(room.id);
      this.refreshInsight();
    } else {
      promptAction.showToast({ message: '提交失败' });
    }
  }

  build() {
    NavDestination() {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Button('创建班级')
            .fontSize(13)
            .height(36)
            .backgroundColor('#1677ff')
            .onClick(() => {
              this.view = 'create';
            })
          Button('加入班级')
            .fontSize(13)
            .height(36)
            .backgroundColor('#13c2c2')
            .onClick(() => {
              this.view = 'join';
            })
        }
        .width('100%')

        if (this.view === 'create') {
          Column({ space: 10 }) {
            TextInput({ placeholder: '班级名称', text: this.className })
              .height(44)
              .onChange((v: string) => {
                this.className = v;
              })
            Button('确定创建')
              .width('100%')
              .height(40)
              .backgroundColor('#1677ff')
              .onClick(() => {
                this.doCreate();
              })
          }
          .padding(12)
          .backgroundColor('#f3f8ff')
          .borderRadius(12)
          .width('100%')
        } else if (this.view === 'join') {
          Column({ space: 10 }) {
            TextInput({ placeholder: '邀请码（6 位）', text: this.joinCode })
              .height(44)
              .onChange((v: string) => {
                this.joinCode = v.trim().toUpperCase();
              })
            TextInput({ placeholder: '你的名字', text: this.studentName })
              .height(44)
              .onChange((v: string) => {
                this.studentName = v;
              })
            Button('确定加入')
              .width('100%')
              .height(40)
              .backgroundColor('#13c2c2')
              .onClick(() => {
                this.doJoin();
              })
          }
          .padding(12)
          .backgroundColor('#f3f8ff')
          .borderRadius(12)
          .width('100%')
        } else if (this.view === 'detail' && this.current) {
          this.detailView(this.current)
        } else {
          if (this.rooms.length === 0) {
            Text('还没有班级，创建一个或输入邀请码加入吧')
              .fontSize(13)
              .fontColor('#8a94a6')
          } else {
            List() {
              ForEach(this.rooms, (r: ClassRoom) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Column({ space: 3 }) {
                      Text(r.name)
                        .fontSize(15)
                        .fontColor('#1a2333')
                        .fontWeight(FontWeight.Medium)
                      Text(`班主任 ${r.teacher} · ${r.students.length} 人 · ${r.assignments.length} 项作业 · 码 ${r.code}`)
                        .fontSize(12)
                        .fontColor('#8a94a6')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Button('进入')
                      .height(32)
                      .fontSize(13)
                      .backgroundColor('#1677ff')
                      .onClick(() => {
                        this.openRoom(r);
                      })
                  }
                  .padding(12)
                }
              }, (r: ClassRoom) => r.id)
            }
            .width('100%')
            .layoutWeight(1)
          }
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
    }
    .title('师生协作')
    .width('100%')
    .height('100%')
  }

  @Builder
  detailView(room: ClassRoom) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(`邀请码：${room.code}`)
          .fontSize(13)
          .fontColor('#fa8c16')
          .backgroundColor('#fff7e6')
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        Blank()
        Button('返回')
          .fontSize(12)
          .height(30)
          .backgroundColor(Color.Transparent)
          .fontColor('#1677ff')
          .onClick(() => {
            this.view = 'list';
            this.current = undefined;
          })
      }
      .width('100%')

      Text(`成员（${room.students.length}）`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1a2333')
        .alignSelf(ItemAlign.Start)
      Text(room.students.length > 0 ? room.students.map((s) => s.name).join('、') : '暂无成员')
        .fontSize(13)
        .fontColor('#8a94a6')
        .width('100%')

      // 本班学情（Wave 3）：作业完成率 + 学情回传画像
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('本班学情')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1a2333')
            .layoutWeight(1)
          Button('回传我的学情')
            .height(30)
            .fontSize(12)
            .backgroundColor('#52c41a')
            .onClick(() => {
              this.doReportInsight();
            })
        }
        .width('100%')

        if (this.summary.reportedCount > 0) {
          Text(`已回传 ${this.summary.reportedCount} 人 · 平均掌握 ${ClassInsightService.percent(this.summary.avgMastery)}% · 薄弱点 ${this.summary.weakTotal} 个`)
            .fontSize(12)
            .fontColor('#4a5468')
            .width('100%')
          if (this.summary.topWeakText.length > 0) {
            Text(`典型薄弱：${this.summary.topWeakText}`)
              .fontSize(12)
              .fontColor('#cf1322')
              .width('100%')
          }
        } else {
          Text('还没有同学回传学情，点「回传我的学情」生成一份')
            .fontSize(12)
            .fontColor('#8a94a6')
            .width('100%')
        }

        ForEach(this.progress, (p: AssignmentProgress) => {
          Column({ space: 4 }) {
            Row() {
              Text(p.title)
                .fontSize(13)
                .fontColor('#1a2333')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${p.submitted}/${p.total} · ${ClassInsightService.percent(p.rate)}%`)
                .fontSize(11)
                .fontColor('#8a94a6')
            }
            .width('100%')
            Stack({ alignContent: Alignment.Start }) {
              Rect()
                .width('100%')
                .height(5)
                .radius(3)
                .fill('#eef1f6')
              Rect()
                .width(`${ClassInsightService.percent(p.rate)}%`)
                .height(5)
                .radius(3)
                .fill(p.rate >= 1 ? '#52c41a' : '#1677ff')
            }
            .width('100%')
            .height(5)
          }
          .width('100%')
        }, (p: AssignmentProgress) => p.id)

        ForEach(this.insights, (g: ClassInsight) => {
          Row({ space: 6 }) {
            Text(g.studentName)
              .fontSize(13)
              .fontColor('#1a2333')
              .fontWeight(FontWeight.Medium)
            Text(`掌握 ${ClassInsightService.percent(g.masteryRate)}%`)
              .fontSize(11)
              .fontColor('#52c41a')
            if (g.weakCount > 0) {
              Text(`薄弱 ${g.weakCount}`)
                .fontSize(11)
                .fontColor('#cf1322')
            }
          }
          .width('100%')
        }, (g: ClassInsight) => g.studentId)
      }
      .padding(12)
      .backgroundColor('#f6ffed')
      .borderRadius(12)
      .width('100%')

      // 布置作业
      Column({ space: 8 }) {
        Text('布置作业（老师）')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
          .alignSelf(ItemAlign.Start)
        Row({ space: 8 }) {
          TextInput({ placeholder: '作业标题', text: this.assignTitle })
            .layoutWeight(1)
            .height(40)
            .onChange((v: string) => {
              this.assignTitle = v;
            })
          TextInput({ placeholder: '天数', text: this.assignDays })
            .width(70)
            .height(40)
            .type(InputType.Number)
            .onChange((v: string) => {
              this.assignDays = v;
            })
        }
        Button('布置')
          .width('100%')
          .height(36)
          .backgroundColor('#1677ff')
          .onClick(() => {
            this.doCreateAssignment();
          })
      }
      .padding(12)
      .backgroundColor('#f3f8ff')
      .borderRadius(12)
      .width('100%')

      Text(`作业（${room.assignments.length}）`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1a2333')
        .alignSelf(ItemAlign.Start)
      if (room.assignments.length === 0) {
        Text('暂无作业')
          .fontSize(13)
          .fontColor('#8a94a6')
      } else {
        List() {
          ForEach(room.assignments, (a: Assignment) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(a.title)
                    .fontSize(14)
                    .fontColor('#1a2333')
                  Text(`截止 ${formatTime(a.dueAt)} · 已交 ${a.submittedIds.length}/${room.students.length}`)
                    .fontSize(12)
                    .fontColor('#8a94a6')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Button('提交')
                  .height(30)
                  .fontSize(12)
                  .backgroundColor('#13c2c2')
                  .onClick(() => {
                    this.doSubmit(a);
                  })
              }
              .padding(10)
            }
          }, (a: Assignment) => a.id)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
