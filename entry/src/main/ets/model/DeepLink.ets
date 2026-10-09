/**
 * 深链参数结构体（spec 6.3）。
 * 作为专项子界面导航参数载体，禁止字符串拼装。
 */
import { NodeType } from './Constants';

export class DeepLink {
  nodeId: string = '';
  nodeType: NodeType = NodeType.GENERAL;
  payload: string = '';

  constructor() {
  }

  static create(nodeId: string, nodeType: NodeType, payload: string): DeepLink {
    const link = new DeepLink();
    link.nodeId = nodeId;
    link.nodeType = nodeType;
    link.payload = payload;
    return link;
  }
}