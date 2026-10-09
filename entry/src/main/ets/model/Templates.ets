/**
 * 考点 / 教材模板库（v1.2）。
 * 内置中考高频考点与教材章节大纲模板，首页「选模板一键建图」复用 MindMapStore.importAsNew。
 * 模板以 MindMap 实体返回，保证结构合法、向后兼容。
 */

import { Layout, NodeType } from './Constants';
import { MindMap } from './MindMap';
import { MindNode } from './MindNode';
import { GenUid } from '../utils/GenUid';

/** 模板元信息（列表展示用，不含全量结构） */
export interface TemplateItem {
  id: string;
  title: string;
  subject: string;
  summary: string;
}

interface TemplateDef {
  item: TemplateItem;
  build: () => MindMap;
}

interface TemplateChild {
  text: string;
  detail?: string;
  type?: NodeType;
}

interface TemplateBranch {
  text: string;
  detail?: string;
  type?: NodeType;
  children?: TemplateChild[];
}

function node(text: string, parentId: string | null, type: NodeType = NodeType.GENERAL, detail: string = ''): MindNode {
  const n = MindNode.create(GenUid.nextNodeId(), text, parentId, type);
  n.detail = detail;
  return n;
}

function skeleton(title: string, subject: string, branches: TemplateBranch[]): MindMap {
  const map = MindMap.create(GenUid.nextMapId(), title, subject, '教材章节大纲模板');
  const root = node(title, null, NodeType.GENERAL, '中心主题');
  map.nodes.push(root);
  for (let i = 0; i < branches.length; i++) {
    const b = branches[i];
    const bn = node(b.text, root.id, b.type || NodeType.GENERAL, b.detail || '');
    map.nodes.push(bn);
    if (b.children) {
      for (let j = 0; j < b.children.length; j++) {
        const c = b.children[j];
        map.nodes.push(node(c.text, bn.id, c.type || NodeType.GENERAL, c.detail || ''));
      }
    }
  }
  return map;
}

const DEFS: TemplateDef[] = [
  {
    item: { id: 'tpl_chinese', title: '中考语文 · 古诗文默写', subject: '语文', summary: '课标必背古诗词曲 + 名句赏析' },
    build: () => skeleton('中考语文 · 古诗文', '语文', [
      { text: '古诗词曲', detail: '课标必背 40 首', children: [
        { text: '《观沧海》曹操', detail: '名句：日月之行，若出其中' },
        { text: '《次北固山下》王湾', detail: '名句：海日生残夜，江春入旧年' },
        { text: '《天净沙·秋思》马致远', detail: '断肠人在天涯' }
      ] },
      { text: '文言文', detail: '常考实词 120 个', children: [
        { text: '《陋室铭》', detail: '斯是陋室，惟吾德馨' },
        { text: '《爱莲说》', detail: '出淤泥而不染' }
      ] },
      { text: '默写策略', detail: '易错字归类 + 理解性默写' }
    ])
  },
  {
    item: { id: 'tpl_math_func', title: '初中数学 · 函数专题', subject: '数学', summary: '一次函数 / 反比例 / 二次函数图像与性质' },
    build: () => skeleton('初中数学 · 函数', '数学', [
      { text: '一次函数 y=kx+b', type: NodeType.MATH, detail: 'y=kx+b', children: [
        { text: '图像：直线', type: NodeType.MATH },
        { text: 'k 的正负与增减性', detail: 'k>0 递增' }
      ] },
      { text: '反比例函数 y=k/x', type: NodeType.MATH, detail: 'y=k/x', children: [
        { text: '图像：双曲线', type: NodeType.MATH }
      ] },
      { text: '二次函数 y=ax²+bx+c', type: NodeType.MATH, detail: 'y=a(x-h)²+k', children: [
        { text: '顶点式', type: NodeType.MATH, detail: 'y=a(x-h)²+k' },
        { text: '对称轴 x=-b/2a', detail: '对称轴' }
      ] }
    ])
  },
  {
    item: { id: 'tpl_english', title: '中考英语 · 高频句型', subject: '英语', summary: '时态 + 从句 + 写作金句' },
    build: () => skeleton('中考英语 · 高频', '英语', [
      { text: '时态', children: [
        { text: '现在完成时', detail: 'have/has + done' },
        { text: '被动语态', type: NodeType.ENGLISH, detail: 'be + done' }
      ] },
      { text: '从句', children: [
        { text: '宾语从句', type: NodeType.ENGLISH },
        { text: '定语从句', type: NodeType.ENGLISH }
      ] },
      { text: '写作金句', type: NodeType.ENGLISH, detail: '收藏后可回填节点' }
    ])
  },
  {
    item: { id: 'tpl_physics', title: '初中物理 · 力学', subject: '物理', summary: '牛顿定律 / 压强 / 浮力' },
    build: () => skeleton('初中物理 · 力学', '物理', [
      { text: '牛顿第一定律', type: NodeType.PHYSICS, detail: '惯性' },
      { text: '二力平衡', type: NodeType.PHYSICS },
      { text: '压强 p=F/S', type: NodeType.PHYSICS, detail: 'p=F/S', children: [
        { text: '液体压强', type: NodeType.PHYSICS, detail: 'p=ρgh' }
      ] },
      { text: '浮力', type: NodeType.PHYSICS, detail: '阿基米德原理 F浮=ρ液gV排' }
    ])
  },
  {
    item: { id: 'tpl_chem', title: '初中化学 · 方程式', subject: '化学', summary: '制氧 / 制二氧化碳 / 金属' },
    build: () => skeleton('初中化学 · 方程式', '化学', [
      { text: '实验室制氧气', type: NodeType.CHEM, detail: '2H2O2 = 2H2O + O2↑' },
      { text: '制二氧化碳', type: NodeType.CHEM, detail: 'CaCO3 + 2HCl = CaCl2 + H2O + CO2↑' },
      { text: '金属活动性', type: NodeType.CHEM, detail: 'Fe + CuSO4 = FeSO4 + Cu' },
      { text: '质量守恒定律', detail: '反应物总质量=生成物总质量' }
    ])
  },
  {
    item: { id: 'tpl_bio', title: '初中生物 · 细胞与结构', subject: '生物', summary: '细胞结构 / 光合作用 / 人体系统' },
    build: () => skeleton('初中生物 · 结构', '生物', [
      { text: '细胞', type: NodeType.BIO, detail: '细胞膜\n细胞质\n细胞核', children: [
        { text: '植物细胞', type: NodeType.BIO, detail: '细胞壁\n叶绿体\n液泡' },
        { text: '动物细胞', type: NodeType.BIO }
      ] },
      { text: '光合作用', type: NodeType.BIO, detail: '二氧化碳+水→有机物+氧气' },
      { text: '人体系统', type: NodeType.BIO, children: [
        { text: '消化系统', type: NodeType.BIO },
        { text: '循环系统', type: NodeType.BIO }
      ] }
    ])
  },
  {
    item: { id: 'tpl_history', title: '初中历史 · 时间轴', subject: '历史', summary: '朝代更替 + 大事件年表' },
    build: () => skeleton('初中历史 · 时间轴', '历史', [
      { text: '秦汉', type: NodeType.HISTORY, detail: '前221: 秦统一\n前202: 西汉建立' },
      { text: '隋唐', type: NodeType.HISTORY, detail: '581: 隋统一\n618: 唐建立' },
      { text: '明清', type: NodeType.HISTORY, detail: '1368: 明朝建立\n1636: 清朝建立' }
    ])
  },
  {
    item: { id: 'tpl_geo', title: '初中地理 · 区位', subject: '地理', summary: '地形区 / 气候带 / 河流' },
    build: () => skeleton('初中地理 · 区位', '地理', [
      { text: '地形区', type: NodeType.GEO, detail: '青藏高原: 世界屋脊\n东北平原: 最大平原' },
      { text: '气候', type: NodeType.GEO, detail: '季风气候: 东部\n温带大陆性: 西北' },
      { text: '河流', type: NodeType.GEO, detail: '长江: 黄金水道\n黄河: 母亲河' }
    ])
  }
];

/** 模板列表（含 v1.1 之外的全学科覆盖） */
export function listTemplates(): TemplateItem[] {
  const items: TemplateItem[] = [];
  for (let i = 0; i < DEFS.length; i++) {
    items.push(DEFS[i].item);
  }
  return items;
}

/** 按 id 取得模板导图（深拷贝，避免污染模板定义） */
export function getTemplateMindMap(id: string): MindMap | undefined {
  for (let i = 0; i < DEFS.length; i++) {
    if (DEFS[i].item.id === id) {
      return DEFS[i].build();
    }
  }
  return undefined;
}
