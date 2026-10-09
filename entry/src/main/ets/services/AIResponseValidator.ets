/**
 * AI 输出校验器。
 * 导图 JSON 合法性校验（title/layout/theme/nodes 四要素、字段完整、根唯一、无环、枚举合法、color 十六进制、文本长度上限）；
 * patch 引用完整性预检。
 */
import { Layout, NodeShape, NodeType, TEXT_MAX_LEN, TITLE_MAX_LEN } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { AIErrorCode, AIResult, MapPatchOp, aiFailure, aiSuccess } from './AIService';

const HEX_COLOR_RE: RegExp = /^#[0-9a-fA-F]{6}$/;

export class AIResponseValidator {
  /** 校验导图 JSON 字符串，返回校验后的 MindMap 实体 */
  static validateMindMapJson(text: string): AIResult<MindMap> {
    if (!text || text.length === 0) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, 'AI 返回内容为空', true);
    }
    const trimmed = AIResponseValidator.extractJson(text);
    if (!trimmed || trimmed.length === 0) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, '未能在 AI 输出中提取导图 JSON', true);
    }
    let map: MindMap | undefined = undefined;
    try {
      map = MindMap.fromJson(trimmed);
    } catch (err) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, '导图 JSON 无法解析', true);
    }
    if (!map) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, '导图 JSON 反序列化失败', true);
    }
    return AIResponseValidator.validateMindMap(map);
  }

  /** 从含代码块/说明文字的 AI 输出中提取 JSON */
  static extractJson(text: string): string {
    let t = text.trim();
    // 去掉 ```json ... ``` 围栏
    const fenceStart = t.indexOf('```');
    if (fenceStart >= 0) {
      const afterFence = t.substring(fenceStart + 3).trim();
      const newlineIdx = afterFence.indexOf('\n');
      const firstLine = newlineIdx >= 0 ? afterFence.substring(0, newlineIdx).trim() : afterFence.trim();
      if (firstLine.startsWith('json')) {
        const codeStart = afterFence.indexOf('\n');
        if (codeStart >= 0) {
          let code = afterFence.substring(codeStart + 1);
          const codeEnd = code.lastIndexOf('```');
          if (codeEnd >= 0) {
            code = code.substring(0, codeEnd);
          }
          t = code.trim();
        }
      }
    }
    // 提取第一个 { 或 [ 到对应的最后一个 } 或 ]（兼容对象与数组响应）
    const firstObj = t.indexOf('{');
    const firstArr = t.indexOf('[');
    let start = -1;
    let end = -1;
    if (firstArr >= 0 && (firstObj < 0 || firstArr < firstObj)) {
      start = firstArr;
      end = t.lastIndexOf(']');
    } else if (firstObj >= 0) {
      start = firstObj;
      end = t.lastIndexOf('}');
    }
    if (start >= 0 && end > start) {
      return t.substring(start, end + 1);
    }
    return t;
  }

  /** 校验导图实体 */
  static validateMindMap(map: MindMap): AIResult<MindMap> {
    if (!map || !map.title || map.title.length === 0) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, '导图缺少 title', true);
    }
    if (map.title.length > TITLE_MAX_LEN) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, 'title 超过 50 字符', true);
    }
    if (!map.nodes || map.nodes.length === 0) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, '导图缺少 nodes', true);
    }
    if (!AIResponseValidator.isLayoutValid(map.layout)) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, `layout 取值非法：${map.layout}`, true);
    }
    if (!map.theme || (map.theme !== 'ocean' && map.theme !== 'forest' && map.theme !== 'sunset')) {
      map.theme = 'ocean';
    }

    const seen = new Set<string>();
    let rootCount = 0;
    for (let i = 0; i < map.nodes.length; i++) {
      const node = map.nodes[i];
      if (!node.id || node.id.length === 0) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, `第 ${i} 个节点缺少 id`, true);
      }
      if (seen.has(node.id)) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, `节点 id 重复：${node.id}`, true);
      }
      seen.add(node.id);
      if (!node.text || node.text.length === 0) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, `节点 ${node.id} 缺少 text`, true);
      }
      if (node.text.length > TEXT_MAX_LEN) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, `节点 ${node.id} 文本超过 100 字符`, true);
      }
      if (node.parentId === null || node.parentId === undefined) {
        rootCount++;
      } else if (!map.findNode(node.parentId)) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, `节点 ${node.id} 的父节点 ${node.parentId} 不存在`, true);
      }
      if (!AIResponseValidator.isNodeTypeValid(node.type)) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, `节点 ${node.id} 的 type 非法：${node.type}`, true);
      }
      if (!AIResponseValidator.isShapeValid(node.style.shape)) {
        node.style.shape = NodeShape.ROUND;
      }
      if (!AIResponseValidator.isHexColor(node.style.color)) {
        node.style.color = '#1677ff';
      }
    }
    if (rootCount !== 1) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, `根节点数量非法：${rootCount}`, true);
    }
    // 环检测
    for (let i = 0; i < map.nodes.length; i++) {
      const node = map.nodes[i];
      let current: MindNode | undefined = map.findNode(node.id);
      let guard = 0;
      while (current && current.parentId && guard < map.nodes.length + 1) {
        if (current.parentId === node.id) {
          return aiFailure(AIErrorCode.INVALID_OUTPUT, `节点 ${node.id} 形成循环引用`, true);
        }
        current = map.findNode(current.parentId);
        guard++;
      }
    }
    return aiSuccess(map);
  }

  static isNodeTypeValid(value: NodeType): boolean {
    return value === NodeType.GENERAL || value === NodeType.MATH || value === NodeType.PHYSICS || value === NodeType.ENGLISH;
  }

  static isLayoutValid(value: Layout): boolean {
    return value === Layout.TREE_H || value === Layout.TREE_V || value === Layout.RADIAL;
  }

  static isShapeValid(value: NodeShape): boolean {
    return value === NodeShape.RECT || value === NodeShape.ROUND || value === NodeShape.ELLIPSE;
  }

  static isHexColor(color: string): boolean {
    return HEX_COLOR_RE.test(color);
  }

  /** patch 引用完整性预检：返回错误信息或 undefined（合法） */
  static precheckPatchOp(op: MapPatchOp, map: MindMap): string | undefined {
    if (!op) {
      return '空的修改指令';
    }
    if (op.op === 'layout') {
      const target = op.layout ? op.layout : '';
      if (target !== 'tree-h' && target !== 'tree-v' && target !== 'radial') {
        return `布局值非法：${target}`;
      }
      return undefined;
    }
    if (op.op === 'add') {
      const parentId = op.parentId ? op.parentId : '';
      if (parentId.length === 0) {
        return '新增节点缺少父节点';
      }
      if (!map.findNode(parentId)) {
        return `父节点不存在：${parentId}`;
      }
      if (!op.text || op.text.length === 0 || op.text.length > TEXT_MAX_LEN) {
        return '新增节点文本非法';
      }
      const type = op.type ? op.type : 'general';
      if (type !== 'general' && type !== 'math' && type !== 'physics' && type !== 'english') {
        return `节点类型非法：${type}`;
      }
      return undefined;
    }
    const nodeId = op.nodeId ? op.nodeId : '';
    if (nodeId.length === 0) {
      return '修改指令缺少目标节点';
    }
    if (!map.findNode(nodeId)) {
      return `节点不存在：${nodeId}`;
    }
    if (op.op === 'move') {
      const parentId = op.parentId ? op.parentId : '';
      if (!map.findNode(parentId)) {
        return `目标父节点不存在：${parentId}`;
      }
      if (parentId === nodeId) {
        return '不能移动到自身节点下';
      }
      // 环检测：nodeId 是否为新父节点的祖先
      let current: MindNode | undefined = map.findNode(parentId);
      let guard = 0;
      while (current && current.parentId && guard < map.nodes.length + 1) {
        if (current.parentId === nodeId) {
          return '不能移动到自身子树下';
        }
        current = map.findNode(current.parentId);
        guard++;
      }
      return undefined;
    }
    if (op.op === 'rename') {
      if (!op.text || op.text.length === 0 || op.text.length > TEXT_MAX_LEN) {
        return '重命名文本非法';
      }
      return undefined;
    }
    if (op.op === 'updateDetail') {
      if (op.detail === undefined || op.detail === null) {
        return '详情内容缺失';
      }
      return undefined;
    }
    if (op.op === 'restyle') {
      if (op.style === undefined || op.style === null) {
        return '样式内容缺失';
      }
      if (op.style.color && !AIResponseValidator.isHexColor(op.style.color)) {
        return `颜色非法：${op.style.color}`;
      }
      if (op.style.shape && !AIResponseValidator.isShapeValid(op.style.shape as NodeShape)) {
        return `形状非法：${op.style.shape}`;
      }
      return undefined;
    }
    if (op.op === 'patchRichContent') {
      if (!op.richContent) {
        return '富内容补丁缺少 richContent 字段';
      }
      return undefined;
    }
    return undefined;
  }
}