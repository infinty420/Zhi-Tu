/**
 * gen_subjects_model.js —— 生成「3D 学科知识馆」场景模型 zhitu_subjects.glb（Wave 8 功能升级）。
 *
 * 场景结构（单 glb 多节点，节点名供运行时 getNodeByPath 查找/高亮）：
 *   core_gem        中心知识晶体（二十面体，蓝渐变）
 *   subj_chinese    语文 —— 书卷（双层盒）
 *   subj_math       数学 —— 八面体 + 底座
 *   subj_english    英语 —— 字母积木块（三块堆叠）
 *   subj_physics    物理 —— 单摆（杆 + 摆线 + 摆球）
 *   subj_chemistry  化学 —— 三原子分子（球 + 键）
 *   subj_biology    生物 —— DNA 双螺旋（5 层横档）
 *   subj_history    历史 —— 金字塔（四棱锥 + 底座）
 *   subj_geography  地理 —— 地球（二十面体蓝绿异色面）
 *   subj_politics   政治 —— 天平（柱 + 梁 + 双盘）
 *
 * 学科 i 摆放角 θi = i·2π/9（运行时相机 yaw 对准 θi 即聚焦该学科），环半径 4.6。
 *
 * 用法：node tools/gen_subjects_model.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'models', 'zhitu_subjects.glb');

/** 环形布局参数（与 Scene3DPage 常量保持一致） */
const RING_R = 4.6;
const SUBJECT_COUNT = 9;

/** glb 二进制写出（glTF 2.0，JSON 块 0x20 补齐、BIN 块 0x00 补齐、bufferView 4 字节对齐） */
function writeGlb(filePath, gltfJson, binBuffer) {
  const jsonBuf = Buffer.from(JSON.stringify(gltfJson), 'utf8');
  const jsonPad = (4 - (jsonBuf.length % 4)) % 4;
  const binPad = (4 - (binBuffer.length % 4)) % 4;
  const jsonLen = jsonBuf.length + jsonPad;
  const binLen = binBuffer.length + binPad;
  const total = 12 + 8 + jsonLen + 8 + binLen;
  const out = Buffer.alloc(total);
  let o = 0;
  out.writeUInt32LE(0x46546c67, o); o += 4;
  out.writeUInt32LE(2, o); o += 4;
  out.writeUInt32LE(total, o); o += 4;
  out.writeUInt32LE(jsonLen, o); o += 4;
  out.writeUInt32LE(0x4e4f534a, o); o += 4;
  jsonBuf.copy(out, o); o += jsonBuf.length;
  for (let i = 0; i < jsonPad; i++) { out[o] = 0x20; o += 1; }
  out.writeUInt32LE(binLen, o); o += 4;
  out.writeUInt32LE(0x004e4942, o); o += 4;
  binBuffer.copy(out, o); o += binBuffer.length;
  for (let i = 0; i < binPad; i++) { out[o] = 0x00; o += 1; }
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, out);
  console.log(`[gen] ${path.relative(ROOT, filePath)}  ${out.length} bytes`);
}

// ---------------- 几何组件（返回 primitive：绝对局部坐标） ----------------

/** 盒体：中心 (cx,cy,cz)，尺寸 (w,h,d)，单色单图元（24 顶点 / 36 索引） */
function boxPrim(cx, cy, cz, w, h, d, color, metallic = 0.15, roughness = 0.55) {
  const x0 = cx - w / 2, x1 = cx + w / 2;
  const y0 = cy - h / 2, y1 = cy + h / 2;
  const z0 = cz - d / 2, z1 = cz + d / 2;
  const v = [
    [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], // +Z
    [x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], // -Z
    [x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], // +Y
    [x1, y0, z1], [x0, y0, z1], [x0, y0, z0], [x1, y0, z0], // -Y
    [x1, y0, z1], [x1, y1, z1], [x1, y1, z0], [x1, y0, z0], // +X
    [x0, y0, z0], [x0, y1, z0], [x0, y1, z1], [x0, y0, z1]  // -X
  ];
  const n = [[0, 0, 1], [0, 0, -1], [0, 1, 0], [0, -1, 0], [1, 0, 0], [-1, 0, 0]];
  const positions = [];
  const normals = [];
  for (let f = 0; f < 6; f++) {
    for (let k = 0; k < 4; k++) {
      positions.push(v[f * 4 + k]);
      normals.push(n[f]);
    }
  }
  const indices = [];
  for (let f = 0; f < 6; f++) {
    const b = f * 4;
    indices.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  return { positions, normals, indices, color, metallic, roughness };
}

/** 八面体：中心 (cx,cy,cz)，半径 r，8 个三角面 */
function octaPrims(cx, cy, cz, r, color, metallic = 0.5, roughness = 0.3) {
  const t = [
    [0, r, 0], [0, -r, 0],
    [r, 0, 0], [-r, 0, 0],
    [0, 0, r], [0, 0, -r]
  ];
  const faces = [
    [0, 4, 2], [0, 2, 5], [0, 5, 3], [0, 3, 4],
    [1, 2, 4], [1, 5, 2], [1, 3, 5], [1, 4, 3]
  ];
  return faces.map((f) => {
    const a = t[f[0]], b = t[f[1]], c = t[f[2]];
    return triPrim(a, b, c, color, metallic, roughness);
  }).map((p) => offsetPrim(p, cx, cy, cz));
}

/** 四棱锥：底面中心 (cx,cy,cz)，底边长 base，高 h（尖朝上） */
function pyramidPrims(cx, cy, cz, base, h, color, metallic = 0.4, roughness = 0.45) {
  const s = base / 2;
  const b0 = [-s, 0, s], b1 = [s, 0, s], b2 = [s, 0, -s], b3 = [-s, 0, -s];
  const apex = [0, h, 0];
  return [
    triPrim(b0, b1, apex, color, metallic, roughness),
    triPrim(b1, b2, apex, color, metallic, roughness),
    triPrim(b2, b3, apex, color, metallic, roughness),
    triPrim(b3, b0, apex, color, metallic, roughness)
  ].map((p) => offsetPrim(p, cx, cy, cz));
}

/** 二十面体：中心 (cx,cy,cz)，半径 r；colorFn(i) 决定第 i 面颜色 → 多图元 */
function icosaPrims(cx, cy, cz, r, colorFn, metallic = 0.6, roughness = 0.25) {
  const phi = (1 + Math.sqrt(5)) / 2;
  const inv = 1 / Math.sqrt(1 + phi * phi);
  const verts = [
    [-1, phi, 0], [1, phi, 0], [-1, -phi, 0], [1, -phi, 0],
    [0, -1, phi], [0, 1, phi], [0, -1, -phi], [0, 1, -phi],
    [phi, 0, -1], [phi, 0, 1], [-phi, 0, -1], [-phi, 0, 1]
  ].map((v) => [v[0] * inv * r, v[1] * inv * r, v[2] * inv * r]);
  const faceIdx = [
    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
  ];
  return faceIdx.map((f, i) => {
    const p = triPrim(verts[f[0]], verts[f[1]], verts[f[2]], colorFn(i), metallic, roughness);
    return offsetPrim(p, cx, cy, cz);
  });
}

/** 三角面图元（绕序 CCW，法线 = (b-a)×(c-a) 归一） */
function triPrim(a, b, c, color, metallic, roughness) {
  const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  const e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  let nx = e1[1] * e2[2] - e1[2] * e2[1];
  let ny = e1[2] * e2[0] - e1[0] * e2[2];
  let nz = e1[0] * e2[1] - e1[1] * e2[0];
  const nl = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1;
  nx /= nl; ny /= nl; nz /= nl;
  return {
    positions: [a, b, c],
    normals: [[nx, ny, nz], [nx, ny, nz], [nx, ny, nz]],
    indices: [0, 1, 2],
    color, metallic, roughness
  };
}

/** 图元整体平移 */
function offsetPrim(p, dx, dy, dz) {
  return {
    positions: p.positions.map((v) => [v[0] + dx, v[1] + dy, v[2] + dz]),
    normals: p.normals,
    indices: p.indices,
    color: p.color, metallic: p.metallic, roughness: p.roughness
  };
}

// ---------------- 学科标志物（局部坐标，节点平移到环上） ----------------

const C = {
  chinese: [0.85, 0.30, 0.30],
  math: [0.06, 0.44, 0.95],
  english: [0.18, 0.72, 0.38],
  physics: [0.95, 0.62, 0.20],
  chemistry: [0.10, 0.70, 0.72],
  biology: [0.16, 0.65, 0.45],
  history: [0.78, 0.58, 0.28],
  geography: [0.25, 0.55, 0.92],
  politics: [0.62, 0.38, 0.72]
};

/** 语文：书卷（封面 + 内页） */
function buildChinese() {
  return [
    boxPrim(0, 0, 0, 1.6, 0.22, 1.1, C.chinese, 0.1, 0.6),
    boxPrim(0.02, 0.18, 0, 1.4, 0.12, 0.92, [0.96, 0.94, 0.88], 0.0, 0.75)
  ];
}

/** 数学：八面体 + 方底座 */
function buildMath() {
  return [
    ...octaPrims(0, 0.75, 0, 0.72, C.math, 0.55, 0.3),
    boxPrim(0, -0.35, 0, 0.72, 0.16, 0.72, [0.55, 0.63, 0.8], 0.2, 0.55)
  ];
}

/** 英语：字母积木块（三块堆叠错位） */
function buildEnglish() {
  return [
    boxPrim(0, -0.4, 0, 1.0, 0.5, 1.0, C.english, 0.15, 0.5),
    boxPrim(-0.18, 0.1, 0.06, 0.72, 0.44, 0.72, [0.30, 0.80, 0.48], 0.15, 0.5),
    boxPrim(0.1, 0.55, -0.05, 0.46, 0.38, 0.46, [0.55, 0.88, 0.64], 0.15, 0.5)
  ];
}

/** 物理：单摆（立杆 + 横臂 + 摆线 + 摆球） */
function buildPhysics() {
  const gray = [0.62, 0.66, 0.74];
  return [
    boxPrim(0, -0.55, 0, 0.62, 0.12, 0.62, gray, 0.3, 0.5),
    boxPrim(0, 0.2, 0, 0.08, 1.6, 0.08, gray, 0.3, 0.5),
    boxPrim(0.3, 0.95, 0, 0.72, 0.07, 0.07, gray, 0.3, 0.5),
    boxPrim(0.6, 0.5, 0, 0.025, 0.9, 0.025, [0.8, 0.84, 0.9], 0.0, 0.8),
    ...icosaPrims(0.6, -0.05, 0, 0.26, () => C.physics, 0.4, 0.35)
  ];
}

/** 化学：三原子分子（一大两小 + 双键） */
function buildChemistry() {
  const bond = [0.75, 0.78, 0.84];
  return [
    ...icosaPrims(0, 0.45, 0, 0.34, () => C.chemistry, 0.5, 0.3),
    ...icosaPrims(-0.62, -0.18, 0.1, 0.22, () => [0.92, 0.94, 0.97], 0.3, 0.35),
    ...icosaPrims(0.62, -0.05, -0.15, 0.22, () => [0.94, 0.4, 0.4], 0.3, 0.35),
    boxPrim(-0.32, 0.12, 0.04, 0.34, 0.06, 0.06, bond, 0.2, 0.6),
    boxPrim(0.32, 0.2, -0.06, 0.34, 0.06, 0.06, bond, 0.2, 0.6)
  ];
}

/** 生物：DNA 双螺旋（5 层，蓝绿双链 + 横档） */
function buildBiology() {
  const prims = [];
  const layers = 5;
  const dy = 0.42;
  for (let i = 0; i < layers; i++) {
    const y = -0.8 + i * dy;
    const ph = i * 0.62;
    const r = 0.42;
    const xA = Math.sin(ph) * r;
    const zA = Math.cos(ph) * r;
    const xB = Math.sin(ph + Math.PI) * r;
    const zB = Math.cos(ph + Math.PI) * r;
    prims.push(boxPrim(xA, y, zA, 0.24, 0.18, 0.24, C.biology, 0.3, 0.4));
    prims.push(boxPrim(xB, y, zB, 0.24, 0.18, 0.24, [0.36, 0.78, 0.92], 0.3, 0.4));
    const mx = (xA + xB) / 2;
    const mz = (zA + zB) / 2;
    const len = Math.sqrt((xB - xA) ** 2 + (zB - zA) ** 2) || 0.1;
    const along = Math.abs(xB - xA) > Math.abs(zB - zA);
    prims.push(boxPrim(mx, y, mz, along ? len : 0.07, 0.07, along ? 0.07 : len, [0.92, 0.9, 0.6], 0.1, 0.6));
  }
  return prims;
}

/** 历史：金字塔（四棱锥 + 基座） */
function buildHistory() {
  return [
    boxPrim(0, -0.62, 0, 1.3, 0.14, 1.3, [0.55, 0.45, 0.3], 0.2, 0.6),
    ...pyramidPrims(0, -0.5, 0, 1.05, 1.5, C.history, 0.45, 0.4)
  ];
}

/** 地理：地球（二十面体蓝绿异色面） */
function buildGeography() {
  return icosaPrims(0, 0.15, 0, 0.82, (i) => {
    const land = i % 3 === 0 ? [0.22, 0.62, 0.35] : (i % 3 === 1 ? [0.2, 0.45, 0.78] : [0.12, 0.35, 0.68]);
    return land;
  }, 0.35, 0.45);
}

/** 政治：天平（底座 + 立柱 + 横梁 + 双托盘） */
function buildPolitics() {
  const gold = [0.85, 0.68, 0.3];
  const gray = [0.62, 0.66, 0.74];
  return [
    boxPrim(0, -0.66, 0, 0.78, 0.14, 0.58, gray, 0.3, 0.5),
    boxPrim(0, 0.0, 0, 0.09, 1.35, 0.09, gray, 0.3, 0.5),
    boxPrim(0, 0.72, 0, 1.62, 0.07, 0.07, gold, 0.5, 0.35),
    boxPrim(-0.72, 0.58, 0, 0.34, 0.06, 0.34, gold, 0.5, 0.35),
    boxPrim(0.72, 0.62, 0, 0.34, 0.06, 0.34, gold, 0.5, 0.35),
    boxPrim(-0.72, 0.5, 0, 0.02, 0.18, 0.02, gray, 0.2, 0.6),
    boxPrim(0.72, 0.54, 0, 0.02, 0.18, 0.02, gray, 0.2, 0.6)
  ];
}

/** 中心知识晶体（蓝渐变二十面体） */
function buildCoreGem() {
  const lerp = (a, b, t) => a + (b - a) * t;
  return icosaPrims(0, 1.3, 0, 1.15, (i) => {
    const t = i / 19;
    const boost = i % 2 === 0 ? 1.0 : 0.82;
    return [
      Math.min(1, lerp(0.10, 0.16, t) * boost + 0.06),
      Math.min(1, lerp(0.45, 0.74, t) * boost + 0.05),
      Math.min(1, lerp(0.95, 0.70, t) * boost + 0.06)
    ];
  }, 0.85, 0.22);
}

// ---------------- 多节点 glTF 组装 ----------------

/**
 * 组装多节点模型。
 * nodesDef: [{ name, translation: [x,y,z], primitives }]
 */
function buildMultiNode(nodesDef) {
  const buffers = [];
  const bufferViews = [];
  const accessors = [];
  const materials = [];
  const meshes = [];
  const nodes = [];
  let byteOffset = 0;

  const pushView = (byteLength) => {
    const view = { buffer: 0, byteOffset, byteLength };
    bufferViews.push(view);
    byteOffset += byteLength;
    const pad = (4 - (byteOffset % 4)) % 4;
    byteOffset += pad;
    return view;
  };

  const pushAccessor = (view, componentType, count, type, minMax) => {
    const acc = { bufferView: bufferViews.indexOf(view), componentType, count, type };
    if (minMax) { acc.min = minMax.min; acc.max = minMax.max; }
    accessors.push(acc);
    return accessors.length - 1;
  };

  const pushPrim = (p) => {
    const posBuf = Buffer.alloc(p.positions.length * 12);
    const mn = [Infinity, Infinity, Infinity];
    const mx = [-Infinity, -Infinity, -Infinity];
    p.positions.forEach((v, i) => {
      posBuf.writeFloatLE(v[0], i * 12);
      posBuf.writeFloatLE(v[1], i * 12 + 4);
      posBuf.writeFloatLE(v[2], i * 12 + 8);
      for (let k = 0; k < 3; k++) {
        mn[k] = Math.min(mn[k], v[k]);
        mx[k] = Math.max(mx[k], v[k]);
      }
    });
    const posView = pushView(posBuf.length);
    buffers.push(posBuf);
    const posIdx = pushAccessor(posView, 5126, p.positions.length, 'VEC3', { min: mn, max: mx });

    const nrmBuf = Buffer.alloc(p.normals.length * 12);
    p.normals.forEach((v, i) => {
      nrmBuf.writeFloatLE(v[0], i * 12);
      nrmBuf.writeFloatLE(v[1], i * 12 + 4);
      nrmBuf.writeFloatLE(v[2], i * 12 + 8);
    });
    const nrmView = pushView(nrmBuf.length);
    buffers.push(nrmBuf);
    const nrmIdx = pushAccessor(nrmView, 5126, p.normals.length, 'VEC3');

    const idxBuf = Buffer.alloc(p.indices.length * 2);
    p.indices.forEach((v, i) => idxBuf.writeUInt16LE(v, i * 2));
    const idxView = pushView(idxBuf.length);
    buffers.push(idxBuf);
    const idxIdx = pushAccessor(idxView, 5123, p.indices.length, 'SCALAR');

    materials.push({
      name: `mat_${materials.length}`,
      pbrMetallicRoughness: {
        baseColorFactor: [p.color[0], p.color[1], p.color[2], 1.0],
        metallicFactor: p.metallic,
        roughnessFactor: p.roughness
      }
    });

    return {
      attributes: { POSITION: posIdx, NORMAL: nrmIdx },
      indices: idxIdx,
      material: materials.length - 1,
      mode: 4
    };
  };

  for (const def of nodesDef) {
    const prims = def.primitives.map(pushPrim);
    meshes.push({ name: `${def.name}_mesh`, primitives: prims });
    const node = { name: def.name, mesh: meshes.length - 1 };
    if (def.translation) {
      node.translation = [def.translation[0], def.translation[1], def.translation[2]];
    }
    nodes.push(node);
  }

  const binBuffer = Buffer.concat(buffers);
  const gltf = {
    asset: { version: '2.0', generator: 'zhitu-gen-subjects' },
    scene: 0,
    scenes: [{ name: 'Scene', nodes: nodes.map((_, i) => i) }],
    nodes,
    meshes,
    materials,
    accessors,
    bufferViews,
    buffers: [{ byteLength: binBuffer.length }]
  };
  return { gltf, binBuffer };
}

// ---------------- 组装学科星系 ----------------

const builders = [
  buildChinese, buildMath, buildEnglish, buildPhysics, buildChemistry,
  buildBiology, buildHistory, buildGeography, buildPolitics
];
const codes = ['chinese', 'math', 'english', 'physics', 'chemistry', 'biology', 'history', 'geography', 'politics'];

const nodesDef = [];
for (let i = 0; i < SUBJECT_COUNT; i++) {
  const theta = i * 2 * Math.PI / SUBJECT_COUNT;
  const tx = RING_R * Math.sin(theta);
  const tz = RING_R * Math.cos(theta);
  nodesDef.push({ name: `subj_${codes[i]}`, translation: [tx, 0, tz], primitives: builders[i]() });
}
nodesDef.push({ name: 'core_gem', translation: [0, 0, 0], primitives: buildCoreGem() });

const result = buildMultiNode(nodesDef);
writeGlb(OUT, result.gltf, result.binBuffer);

// 自检：buffer 长度一致 + 节点数 + 图元数
if (result.gltf.buffers[0].byteLength !== result.binBuffer.length) {
  throw new Error('buffer byteLength mismatch');
}
console.log(`[gen] OK: nodes=${result.gltf.nodes.length}, meshes=${result.gltf.meshes.length}, prims=${result.gltf.meshes.reduce((s, m) => s + m.primitives.length, 0)}`);
