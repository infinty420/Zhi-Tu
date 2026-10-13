/**
 * 师生协作服务（v2.0，Mock）。以 Preferences 持久化班级、成员与作业。
 * 真实环境可替换为远端接口，对外接口保持一致。
 */

import { preferences } from '@kit.ArkData';
import { AppContextHolder } from '../utils/AppContext';
import { GenUid } from '../utils/GenUid';
import { Logger } from '../utils/Logger';
import { Assignment, ClassInsight, ClassRoom, Student } from '../model/ClassModels';

const PREF_NAME = 'zhitu_class';
const KEY_LIST = 'zhitu_class_list';

/** 序列化结构（字段可能缺失，用 ESObject 兜底） */
interface ClassRoomRaw {
  id: ESObject;
  name: ESObject;
  teacher: ESObject;
  code: ESObject;
  createdAt: ESObject;
  students: ESObject[];
  assignments: ESObject[];
  insights?: ESObject[];
}

interface ClassInsightRaw {
  studentId: ESObject;
  studentName: ESObject;
  masteryRate: ESObject;
  weakCount: ESObject;
  weakText: ESObject;
  updatedAt: ESObject;
}

interface StudentRaw {
  id: ESObject;
  name: ESObject;
}

interface AssignmentRaw {
  id: ESObject;
  title: ESObject;
  dueAt: ESObject;
  submittedIds: ESObject[];
}

export class ClassService {
  private static _instance: ClassService | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private rooms: ClassRoom[] = [];
  private ready: boolean = false;

  static getInstance(): ClassService {
    if (ClassService._instance === undefined) {
      ClassService._instance = new ClassService();
    }
    return ClassService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const raw = (await this.pref.get(KEY_LIST, '[]')) as string;
      this.rooms = this.parseList(raw);
      this.ready = true;
    } catch (err) {
      Logger.error('ClassService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  private parseList(raw: string): ClassRoom[] {
    try {
      const arr = JSON.parse(raw) as ClassRoomRaw[];
      if (!arr || arr.length === 0) {
        return [];
      }
      const out: ClassRoom[] = [];
      for (let i = 0; i < arr.length; i++) {
        out.push(this.rebuild(arr[i]));
      }
      return out;
    } catch (err) {
      return [];
    }
  }

  private rebuild(r: ClassRoomRaw): ClassRoom {
    const room: ClassRoom = {
      id: ClassService.str(r.id),
      name: ClassService.str(r.name),
      teacher: ClassService.str(r.teacher),
      code: ClassService.str(r.code),
      createdAt: ClassService.num(r.createdAt),
      students: [],
      assignments: []
    };
    const students = r.students as StudentRaw[];
    if (students) {
      for (let i = 0; i < students.length; i++) {
        room.students.push({ id: ClassService.str(students[i].id), name: ClassService.str(students[i].name) });
      }
    }
    const assigns = r.assignments as AssignmentRaw[];
    if (assigns) {
      for (let i = 0; i < assigns.length; i++) {
        const a = assigns[i];
        const sub: ESObject[] = a.submittedIds as ESObject[];
        const ids: string[] = [];
        if (sub) {
          for (let j = 0; j < sub.length; j++) {
            ids.push(ClassService.str(sub[j]));
          }
        }
        room.assignments.push({
          id: ClassService.str(a.id),
          title: ClassService.str(a.title),
          dueAt: ClassService.num(a.dueAt),
          submittedIds: ids
        });
      }
    }
    const insights = r.insights as ClassInsightRaw[];
    room.insights = [];
    if (insights) {
      for (let k = 0; k < insights.length; k++) {
        const g = insights[k];
        room.insights.push({
          studentId: ClassService.str(g.studentId),
          studentName: ClassService.str(g.studentName),
          masteryRate: ClassService.num(g.masteryRate),
          weakCount: ClassService.num(g.weakCount),
          weakText: ClassService.str(g.weakText),
          updatedAt: ClassService.num(g.updatedAt)
        });
      }
    }
    return room;
  }

  private static str(v: ESObject): string {
    if (v === null || v === undefined) {
      return '';
    }
    return String(v);
  }

  private static num(v: ESObject): number {
    if (v === null || v === undefined) {
      return 0;
    }
    return Number(v);
  }

  private async persist(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(KEY_LIST, JSON.stringify(this.rooms));
      await this.pref.flush();
    } catch (err) {
      Logger.error('ClassService', `persist failed: ${JSON.stringify(err)}`);
    }
  }

  /** 创建班级（教师） */
  async createClass(name: string, teacher: string): Promise<ClassRoom> {
    await this.init();
    const code = ClassService.genCode();
    const room: ClassRoom = {
      id: GenUid.next('c'),
      name: name.trim().length > 0 ? name.trim() : '未命名班级',
      teacher: teacher.trim().length > 0 ? teacher.trim() : '老师',
      code: code,
      students: [],
      assignments: [],
      insights: [],
      createdAt: Date.now()
    };
    this.rooms.push(room);
    await this.persist();
    return room;
  }

  /** 加入班级（学生，按邀请码） */
  async joinClass(code: string, studentName: string): Promise<ClassRoom | undefined> {
    await this.init();
    const room = this.findRoomByCode(code.trim().toUpperCase());
    if (!room) {
      return undefined;
    }
    const name = studentName.trim().length > 0 ? studentName.trim() : '同学';
    if (!room.students.some((s) => s.name === name)) {
      room.students.push({ id: GenUid.next('s'), name: name });
      await this.persist();
    }
    return room;
  }

  listClasses(): ClassRoom[] {
    return this.rooms;
  }

  getClass(id: string): ClassRoom | undefined {
    for (let i = 0; i < this.rooms.length; i++) {
      if (this.rooms[i].id === id) {
        return this.rooms[i];
      }
    }
    return undefined;
  }

  /** 布置作业 */
  async createAssignment(classId: string, title: string, dueAt: number): Promise<boolean> {
    const room = this.getClass(classId);
    if (!room) {
      return false;
    }
    room.assignments.push({
      id: GenUid.next('a'),
      title: title.trim().length > 0 ? title.trim() : '新作业',
      dueAt: dueAt,
      submittedIds: []
    });
    await this.persist();
    return true;
  }

  /** 提交作业（学生） */
  async submitAssignment(classId: string, assignmentId: string, studentId: string): Promise<boolean> {
    const room = this.getClass(classId);
    if (!room) {
      return false;
    }
    const a = room.assignments.find((x) => x.id === assignmentId);
    if (!a) {
      return false;
    }
    if (!a.submittedIds.includes(studentId)) {
      a.submittedIds.push(studentId);
      await this.persist();
    }
    return true;
  }

  /** 学情回传：同一学生只保留最新一条快照 */
  async submitInsight(classId: string, insight: ClassInsight): Promise<boolean> {
    const room = this.getClass(classId);
    if (!room) {
      return false;
    }
    if (!room.insights) {
      room.insights = [];
    }
    const list = room.insights.filter((g) => g.studentId !== insight.studentId);
    list.push(insight);
    room.insights = list;
    await this.persist();
    return true;
  }

  /** 班级学情快照列表（按回传时间倒序） */
  getInsights(classId: string): ClassInsight[] {
    const room = this.getClass(classId);
    if (!room || !room.insights) {
      return [];
    }
    return room.insights.slice().sort((a, b) => b.updatedAt - a.updatedAt);
  }

  private findRoomByCode(code: string): ClassRoom | undefined {
    for (let i = 0; i < this.rooms.length; i++) {
      if (this.rooms[i].code === code) {
        return this.rooms[i];
      }
    }
    return undefined;
  }

  private static genCode(): string {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let s = '';
    for (let i = 0; i < 6; i++) {
      s += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return s;
  }
}
