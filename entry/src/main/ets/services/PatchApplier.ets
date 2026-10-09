/**
 * PatchApplier —— 解析并增量应用 AI Agent 返回的结构化 patch。
 * 预检 → 挑拣 → 逐条应用 → 汇报；保留用户编辑标记（userEdited 节点重命名/覆盖型详情跳过并报告）；
 * 引用不存在节点或与现结构冲突时跳过并报告原因，绝不静默丢弃。
 */
import { Layout, ModelFailure, NodeShape, NodeType } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MapPatchOp } from './AIService';
import { AIResponseValidator } from './AIResponseValidator';
import { MindMapStore } from './MindMapStore';
import { Logger } from '../utils/Logger';

export interface PatchReport {
  applied: number;
  skipped: string[];
  summary: string;
}

interface ApplyOpResult {
  ok: boolean;
  message: string;
}

export class PatchApplier {
  static async apply(patchOps: MapPatchOp[], store: MindMapStore): Promise<PatchReport> {
    const skipped: string[] = [];
    let applied = 0;
    if (!patchOps || patchOps.length === 0) {
      return { applied: 0, skipped: [], summary: '未收到可应用的修改指令' };
    }

    for (let i = 0; i < patchOps.length; i++) {
      const op = patchOps[i];
      const mapForCheck = store.currentSnapshot();
      const current = mapForCheck ? mapForCheck : undefined;
      if (!current) {
        skipped.push(`当前无导图，无法应用指令`);
        continue;
      }
      const err = AIResponseValidator.precheckPatchOp(op, current);
      if (err) {
        // restyle 支持 type 选择器批量
        if (op.op === 'restyle' && (!op.nodeId || op.nodeId.length === 0) && op.type && op.type.length > 0) {
          const ids: string[] = [];
          const nodes = current.nodes;
          for (let j = 0; j < nodes.length; j++) {
            if (PatchApplier.typeMatches(nodes[j].type, op.type!)) {
              ids.push(nodes[j].id);
            }
          }
          if (ids.length > 0 && op.style) {
            const appliedCount = store.restyleNodesByIds(ids, {
              color: op.style.color,
              shape: op.style.shape ? PatchApplier.parseShape(op.style.shape) : undefined
            });
            if (appliedCount > 0) {
              applied++;
              continue;
            }
          }
        }
        skipped.push(op.reason && op.reason.length > 0 ? `${op.reason}（${err}）` : err);
        continue;
      }
      // 保留用户编辑：对 userEdited 节点的覆盖型操作跳过
      if (op.nodeId && op.nodeId.length > 0) {
        const target = current.findNode(op.nodeId);
        if (target && target.userEdited) {
          if (op.op === 'rename' || op.op === 'updateDetail') {
            skipped.push(`为保留你的手动编辑，已跳过「${op.op}」：${target.text}`);
            continue;
          }
        }
      }
      const result = PatchApplier.applyOp(op, store);
      if (result.ok) {
        applied++;
      } else {
        skipped.push(result.message);
      }
    }
    const summary = skipped.length > 0
      ? `已应用 ${applied} 项，${skipped.length} 项未生效`
      : `已应用 ${applied} 项修改`;
    Logger.aiRequest('PatchApplier', 'done', summary);
    return { applied: applied, skipped: skipped, summary: summary };
  }

  private static applyOp(op: MapPatchOp, store: MindMapStore): ApplyOpResult {
    try {
      switch (op.op) {
        case 'add': {
          const parentId = op.parentId ? op.parentId : '';
          const text = op.text ? op.text : '';
          const type = PatchApplier.parseType(op.type);
          const res = store.addNode(parentId, text, type);
          if (res.ok) {
            return { ok: true, message: '' };
          }
          const addFailure: ModelFailure = res as ModelFailure;
          return { ok: false, message: addFailure.message };
        }
        case 'remove': {
          if (!op.nodeId) {
            return { ok: false, message: '删除指令缺少节点' };
          }
          const res = store.removeNode(op.nodeId, true);
          if (res.ok) {
            return { ok: true, message: '' };
          }
          const rmFailure: ModelFailure = res as ModelFailure;
          return { ok: false, message: rmFailure.message };
        }
        case 'rename': {
          if (!op.nodeId) {
            return { ok: false, message: '重命名指令缺少节点' };
          }
          store.renameNode(op.nodeId, op.text ? op.text : '');
          return { ok: true, message: '' };
        }
        case 'move': {
          if (!op.nodeId || !op.parentId) {
            return { ok: false, message: '移动指令缺少节点或目标' };
          }
          const res = store.moveNode(op.nodeId, op.parentId, op.index !== undefined && op.index !== null ? op.index : -1);
          if (res.ok) {
            return { ok: true, message: '' };
          }
          const mvFailure: ModelFailure = res as ModelFailure;
          return { ok: false, message: mvFailure.message };
        }
        case 'restyle': {
          if (!op.nodeId) {
            return { ok: false, message: '样式指令缺少节点' };
          }
          if (op.style) {
            store.restyleNode(op.nodeId, {
              color: op.style.color,
              shape: op.style.shape ? PatchApplier.parseShape(op.style.shape) : undefined
            });
          }
          return { ok: true, message: '' };
        }
        case 'layout': {
          const layout = PatchApplier.parseLayout(op.layout);
          store.setLayout(layout);
          return { ok: true, message: '' };
        }
        case 'updateDetail': {
          if (!op.nodeId) {
            return { ok: false, message: '详情指令缺少节点' };
          }
          store.updateDetail(op.nodeId, op.detail ? op.detail : '', 'append');
          return { ok: true, message: '' };
        }
        case 'patchRichContent': {
          if (!op.nodeId) {
            return { ok: false, message: '富内容补丁缺少节点' };
          }
          if (!op.richContent) {
            return { ok: false, message: '富内容补丁缺少 richContent' };
          }
          // 追加语义：不覆盖已有要点/公式，只合并新增（与 updateDetail 'append' 一致）
          store.updateRichContent(op.nodeId, op.richContent, op.richMode === 'replace' ? 'replace' : 'append');
          return { ok: true, message: '' };
        }
        default: {
          if (!op.nodeId) {
            return { ok: false, message: '未知指令' };
          }
          return { ok: true, message: '' };
        }
      }
    } catch (err) {
      Logger.error('PatchApplier', `applyOp failed: ${JSON.stringify(err)}`);
      return { ok: false, message: '应用指令时发生异常' };
    }
  }

  private static parseType(value: string | undefined): NodeType {
    if (value === 'math') {
      return NodeType.MATH;
    } else if (value === 'physics') {
      return NodeType.PHYSICS;
    } else if (value === 'english') {
      return NodeType.ENGLISH;
    }
    return NodeType.GENERAL;
  }

  private static typeMatches(actual: NodeType, selector: string): boolean {
    if (selector === 'math') {
      return actual === NodeType.MATH;
    } else if (selector === 'physics') {
      return actual === NodeType.PHYSICS;
    } else if (selector === 'english') {
      return actual === NodeType.ENGLISH;
    }
    return false;
  }

  private static parseShape(value: string | undefined): NodeShape {
    const v = value ? value : '';
    if (v === 'rect') {
      return NodeShape.RECT;
    }
    if (v === 'ellipse') {
      return NodeShape.ELLIPSE;
    }
    return NodeShape.ROUND;
  }

  private static parseLayout(value: string | undefined): Layout {
    const v = value ? value : '';
    if (v === 'tree-v') {
      return Layout.TREE_V;
    }
    if (v === 'radial') {
      return Layout.RADIAL;
    }
    return Layout.TREE_H;
  }
}