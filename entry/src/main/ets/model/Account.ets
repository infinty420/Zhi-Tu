/**
 * 账号与云端数据模型（v2.0 一起学）。
 */

/** 账号角色：学生 / 老师 / 家长（家长只读学情报告，不出题） */
export type AccountRole = 'student' | 'teacher' | 'parent';

/** 角色下拉选项（顺序即展示顺序） */
export const ACCOUNT_ROLES: AccountRole[] = ['student', 'teacher', 'parent'];

/** 头像候选（emoji，无新依赖） */
export const AVATAR_CHOICES: string[] = ['🦊', '🐼', '🐯', '🐨', '🦁', '🐧', '🐵', '🦉'];

/** 账号资料补丁：只传需要修改的字段 */
export interface AccountProfilePatch {
  name?: string;
  avatar?: string;
  role?: AccountRole;
  grade?: string;
  focusSubjects?: string[];
}

/** 本地账号（Mock 登录，昵称 + 头像 + 学习画像） */
export interface Account {
  id: string;
  name: string;
  avatar: string;
  /** 角色，缺省按学生处理（旧数据兼容） */
  role?: AccountRole;
  /** 年级 / 学段，如「初二」「高一」 */
  grade?: string;
  /** 关注学科，用于首页推荐排序与学情画像加权 */
  focusSubjects?: string[];
}

/** 角色中文名 */
export function accountRoleLabel(role: AccountRole): string {
  if (role === 'teacher') {
    return '老师';
  }
  if (role === 'parent') {
    return '家长';
  }
  return '学生';
}

/** 同步状态 */
export enum SyncState {
  LOCAL = 'local',
  SYNCING = 'syncing',
  SYNCED = 'synced'
}

/** 云端导图元信息（Mock 云端） */
export interface CloudMapMeta {
  id: string;
  title: string;
  owner: string;
  updatedAt: number;
  shared: boolean;
}
