/**
 * 本地账号服务（v2.0）。Mock 登录：昵称 + 头像 + 学习画像（角色/年级/关注学科），持久化到 Preferences。
 */
import { preferences } from '@kit.ArkData';
import { Account, AccountProfilePatch, AccountRole } from '../model/Account';
import { AppContextHolder } from '../utils/AppContext';
import { GenUid } from '../utils/GenUid';
import { Logger } from '../utils/Logger';

const PREF_NAME = 'zhitu_account';
const KEY_ACCOUNT = 'zhitu_current_account';

export class AccountService {
  private static _instance: AccountService | undefined = undefined;
  private current: Account | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private ready: boolean = false;

  static getInstance(): AccountService {
    if (AccountService._instance === undefined) {
      AccountService._instance = new AccountService();
    }
    return AccountService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const raw = (await this.pref.get(KEY_ACCOUNT, '')) as string;
      if (raw && raw.length > 0) {
        try {
          this.current = AccountService.normalize(JSON.parse(raw) as Account);
        } catch (e) {
          this.current = undefined;
        }
      }
      this.ready = true;
    } catch (err) {
      Logger.error('AccountService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  isLoggedIn(): boolean {
    return this.current !== undefined;
  }

  getCurrent(): Account | undefined {
    return this.current;
  }

  async login(name: string): Promise<Account> {
    const n = name.trim();
    const acc: Account = AccountService.normalize({
      id: GenUid.next('u'),
      name: n.length > 0 ? n : '我',
      avatar: '🦊'
    });
    this.current = acc;
    await this.flush();
    return acc;
  }

  async logout(): Promise<void> {
    this.current = undefined;
    if (this.pref) {
      await this.pref.delete(KEY_ACCOUNT);
      await this.pref.flush();
    }
  }

  /** 更新学习画像（只改传入字段，未登录返回 undefined） */
  async updateProfile(patch: AccountProfilePatch): Promise<Account | undefined> {
    const cur = this.current;
    if (!cur) {
      return undefined;
    }
    const nameRaw = patch.name !== undefined ? patch.name.trim() : cur.name;
    const next: Account = {
      id: cur.id,
      name: nameRaw.length > 0 ? nameRaw : cur.name,
      avatar: patch.avatar !== undefined && patch.avatar.length > 0 ? patch.avatar : cur.avatar,
      role: patch.role !== undefined ? patch.role : (cur.role ? cur.role : 'student'),
      grade: patch.grade !== undefined ? patch.grade.trim() : (cur.grade ? cur.grade : ''),
      focusSubjects: patch.focusSubjects !== undefined ? patch.focusSubjects : (cur.focusSubjects ? cur.focusSubjects : [])
    };
    this.current = AccountService.normalize(next);
    await this.flush();
    return this.current;
  }

  /** 角色（缺省学生） */
  getRole(): AccountRole {
    const cur = this.current;
    if (cur && cur.role) {
      return cur.role;
    }
    return 'student';
  }

  /** 年级（缺省空串） */
  getGrade(): string {
    const cur = this.current;
    return cur && cur.grade ? cur.grade : '';
  }

  /** 关注学科（缺省空数组） */
  getFocusSubjects(): string[] {
    const cur = this.current;
    return cur && cur.focusSubjects ? cur.focusSubjects : [];
  }

  /** 补齐缺失字段，兼容旧版本持久化数据 */
  private static normalize(acc: Account): Account {
    const id = acc.id && acc.id.length > 0 ? acc.id : GenUid.next('u');
    const role: AccountRole = acc.role === 'teacher' || acc.role === 'parent' ? acc.role : 'student';
    const avatar = acc.avatar && acc.avatar.length > 0 ? acc.avatar : '🦊';
    return {
      id: id,
      name: acc.name && acc.name.length > 0 ? acc.name : '我',
      avatar: avatar,
      role: role,
      grade: acc.grade ? acc.grade : '',
      focusSubjects: acc.focusSubjects ? acc.focusSubjects : []
    };
  }

  private async flush(): Promise<void> {
    if (!this.pref || !this.current) {
      return;
    }
    try {
      await this.pref.put(KEY_ACCOUNT, JSON.stringify(this.current));
      await this.pref.flush();
    } catch (err) {
      Logger.error('AccountService', `flush failed: ${JSON.stringify(err)}`);
    }
  }
}
