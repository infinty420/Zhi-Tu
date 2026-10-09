/**
 * 精品市场模板库（v2.0 一起学 · 分享与市场）。
 * 模拟「社区精选导图」：更完整、更深度的学科导图，用户可一键导入到本地。
 * 结构与 Templates.ets 一致：MarketItem 元信息 + 按需 build 出合法 MindMap。
 */

import { Layout, NodeType } from './Constants';
import { MindMap } from './MindMap';
import { MindNode } from './MindNode';
import { GenUid } from '../utils/GenUid';

/** 精品导图元信息（列表展示用） */
export interface MarketItem {
  id: string;
  title: string;
  author: string;
  subject: string;
  summary: string;
  downloads: number;
}

/** 用户发布的导图（UGC，本地持久化到 Preferences） */
export interface MarketUserItem extends MarketItem {
  /** 导图 JSON 全量，导入时直接 importAsNew */
  payload: string;
  createdAt: number;
}

interface MarketDef {
  item: MarketItem;
  build: () => MindMap;
}

interface MChild {
  text: string;
  detail?: string;
  type?: NodeType;
}

interface MBranch {
  text: string;
  detail?: string;
  type?: NodeType;
  children?: MChild[];
}

function mnode(text: string, parentId: string | null, type: NodeType = NodeType.GENERAL, detail: string = ''): MindNode {
  const n = MindNode.create(GenUid.nextNodeId(), text, parentId, type);
  n.detail = detail;
  return n;
}

function mskeleton(title: string, subject: string, branches: MBranch[]): MindMap {
  const map = MindMap.create(GenUid.nextMapId(), title, subject, '社区精品导图');
  const root = mnode(title, null, NodeType.GENERAL, '中心主题');
  map.nodes.push(root);
  for (let i = 0; i < branches.length; i++) {
    const b = branches[i];
    const bn = mnode(b.text, root.id, b.type || NodeType.GENERAL, b.detail || '');
    map.nodes.push(bn);
    if (b.children) {
      for (let j = 0; j < b.children.length; j++) {
        const c = b.children[j];
        map.nodes.push(mnode(c.text, bn.id, c.type || NodeType.GENERAL, c.detail || ''));
      }
    }
  }
  return map;
}

const DEFS: MarketDef[] = [
  {
    item: { id: 'mkt_math_quad', title: '中考数学 · 二次函数压轴', author: '李老师', subject: '数学', summary: '图像 / 顶点 / 根与系数 / 最值综合', downloads: 1280 },
    build: () => mskeleton('二次函数压轴', '数学', [
      { text: '三种解析式', type: NodeType.MATH, children: [
        { text: '一般式 y=ax²+bx+c', type: NodeType.MATH, detail: 'a≠0' },
        { text: '顶点式 y=a(x-h)²+k', type: NodeType.MATH, detail: '顶点(h,k)' },
        { text: '交点式 y=a(x-x₁)(x-x₂)', type: NodeType.MATH, detail: '与x轴交点' }
      ] },
      { text: '核心性质', type: NodeType.MATH, children: [
        { text: '对称轴 x=-b/2a', type: NodeType.MATH, detail: '对称轴' },
        { text: '开口方向由 a 决定', detail: 'a>0 向上' },
        { text: '最值', detail: '顶点处取得' }
      ] },
      { text: '根与系数', type: NodeType.MATH, detail: 'x₁+x₂=-b/a, x₁x₂=c/a' },
      { text: '常见压轴题型', children: [
        { text: '面积最值', detail: '结合几何图形求面积' },
        { text: '动点问题', detail: '设参数表示坐标' },
        { text: '存在性问题', detail: '特殊三角形 / 平行四边形' }
      ] }
    ])
  },
  {
    item: { id: 'mkt_phys_newton', title: '高中物理 · 牛顿运动定律', author: '王同学', subject: '物理', summary: '三大定律 / 受力分析 / 连接体', downloads: 932 },
    build: () => mskeleton('牛顿运动定律', '物理', [
      { text: '牛顿第一定律', type: NodeType.PHYSICS, detail: '惯性：保持运动状态' },
      { text: '牛顿第二定律', type: NodeType.PHYSICS, detail: 'F合=ma' },
      { text: '牛顿第三定律', type: NodeType.PHYSICS, detail: '作用力与反作用力等大反向' },
      { text: '受力分析步骤', children: [
        { text: '重力', type: NodeType.PHYSICS },
        { text: '弹力', type: NodeType.PHYSICS, detail: '接触且有形变' },
        { text: '摩擦力', type: NodeType.PHYSICS, detail: '静摩擦 / 滑动摩擦' }
      ] },
      { text: '典型模型', type: NodeType.PHYSICS, children: [
        { text: '连接体', detail: '整体法 + 隔离法' },
        { text: '传送带', detail: '相对运动判断' }
      ] }
    ])
  },
  {
    item: { id: 'mkt_chem_acid', title: '中考化学 · 酸碱盐', author: '化学课代表', subject: '化学', summary: '性质 / 通性 / 复分解条件', downloads: 775 },
    build: () => mskeleton('酸碱盐', '化学', [
      { text: '酸', type: NodeType.CHEM, detail: 'H⁺ + 酸根', children: [
        { text: '通性', detail: '使石蕊变红 / 与活泼金属放H₂' },
        { text: '盐酸 HCl', type: NodeType.CHEM, detail: '除铁锈' },
        { text: '硫酸 H₂SO₄', type: NodeType.CHEM, detail: '浓硫酸吸水' }
      ] },
      { text: '碱', type: NodeType.CHEM, detail: 'OH⁻ + 金属离子', children: [
        { text: '通性', detail: '使酚酞变红 / 与非金属氧化物反应' },
        { text: 'NaOH', type: NodeType.CHEM, detail: '易潮解' },
        { text: 'Ca(OH)₂', type: NodeType.CHEM, detail: '澄清石灰水' }
      ] },
      { text: '盐', type: NodeType.CHEM, detail: '金属离子 + 酸根' },
      { text: '复分解反应', type: NodeType.CHEM, detail: '生成↓/↑/H₂O 才发生' }
    ])
  },
  {
    item: { id: 'mkt_bio_photo', title: '初中生物 · 光合作用与呼吸', author: '生物兴趣小组', subject: '生物', summary: '场所 / 原料产物 / 能量转化', downloads: 540 },
    build: () => mskeleton('光合作用与呼吸', '生物', [
      { text: '光合作用', type: NodeType.BIO, detail: 'CO₂+H₂O→(光,叶绿体)有机物+O₂', children: [
        { text: '场所：叶绿体', type: NodeType.BIO },
        { text: '原料：CO₂、水', type: NodeType.BIO },
        { text: '产物：有机物、O₂', type: NodeType.BIO }
      ] },
      { text: '呼吸作用', type: NodeType.BIO, detail: '有机物+O₂→CO₂+H₂O+能量', children: [
        { text: '场所：线粒体', type: NodeType.BIO },
        { text: '释放能量', type: NodeType.BIO, detail: '供生命活动' }
      ] },
      { text: '二者关系', type: NodeType.BIO, detail: '光合作用储能，呼吸释能' }
    ])
  }
];

/** 精品导图列表 */
export function listMarket(): MarketItem[] {
  const items: MarketItem[] = [];
  for (let i = 0; i < DEFS.length; i++) {
    items.push(DEFS[i].item);
  }
  return items;
}

/** 按 id 取得精品导图（深拷贝） */
export function getMarketMindMap(id: string): MindMap | undefined {
  for (let i = 0; i < DEFS.length; i++) {
    if (DEFS[i].item.id === id) {
      return DEFS[i].build();
    }
  }
  return undefined;
}
