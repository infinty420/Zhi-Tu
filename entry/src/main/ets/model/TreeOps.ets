/**
 * 树结构操作纯函数工具。
 * 被 MindMapStore / PatchApplier / LayoutEngine 复用。
 */
import { MindNode } from './MindNode';

export class TreeOps {
  /** 收集以 rootId 为根的整个子树 id（含自身），级联删除用 */
  static collectSubtreeIds(nodes: MindNode[], rootId: string): string[] {
    const result: string[] = [];
    const stack: string[] = [rootId];
    while (stack.length > 0) {
      const current = stack.pop();
      if (!current) {
        continue;
      }
      result.push(current);
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].parentId === current) {
          stack.push(nodes[i].id);
        }
      }
    }
    return result;
  }

  /** 判断 aId 是否为 bId 的祖先（O(depth) 祖先链），拖拽环检测用 */
  static isAncestorOf(nodes: MindNode[], aId: string, bId: string): boolean {
    if (aId === bId) {
      return true;
    }
    const index = new Map<string, MindNode>();
    for (let i = 0; i < nodes.length; i++) {
      index.set(nodes[i].id, nodes[i]);
    }
    let current: MindNode | undefined = index.get(bId);
    let guard = 0;
    while (current && current.parentId && guard < nodes.length + 1) {
      if (current.parentId === aId) {
        return true;
      }
      current = index.get(current.parentId);
      guard++;
    }
    return false;
  }

  /** 构建 children 索引：parentId -> 子节点列表（保持原数组顺序） */
  static buildChildrenIndex(nodes: MindNode[]): Map<string, MindNode[]> {
    const index = new Map<string, MindNode[]>();
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (node.parentId === null) {
        continue;
      }
      let list = index.get(node.parentId);
      if (!list) {
        list = [];
        index.set(node.parentId, list);
      }
      list.push(node);
    }
    return index;
  }

  /** 将节点 id 移动到 newParentId 下指定兄弟序号（index 可为 -1 表示追加到末尾） */
  static reorderSiblings(nodes: MindNode[], id: string, newParentId: string, index: number): MindNode[] {
    const result: MindNode[] = nodes.map((n) => n);
    const target: MindNode | undefined = result.find((n) => n.id === id);
    if (!target) {
      return result;
    }
    target.parentId = newParentId;
    const siblings = result.filter((n) => n.parentId === newParentId);
    if (index >= 0 && index < siblings.length) {
      // 挪到指定位置：先移除再插入
      const selfIndex = result.findIndex((n) => n.id === id);
      if (selfIndex >= 0) {
        result.splice(selfIndex, 1);
      }
      let insertAt = -1;
      for (let i = 0; i < result.length; i++) {
        if (result[i].parentId === newParentId) {
          if (result[i].id === siblings[index].id) {
            insertAt = i;
            break;
          }
        }
      }
      if (insertAt < 0) {
        result.push(target);
      } else {
        result.splice(insertAt, 0, target);
      }
    }
    return result;
  }

  static findNode(nodes: MindNode[], id: string): MindNode | undefined {
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].id === id) {
        return nodes[i];
      }
    }
    return undefined;
  }
}