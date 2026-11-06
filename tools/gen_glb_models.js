/**
 * gen_glb_models.js —— 生成智图 3D 演示所需的两个最小合法 glTF 2.0 二进制模型（.glb）。
 *
 * 产物：
 *   entry/src/main/resources/rawfile/models/zhitu_cube.glb  六面异色立方体（6 材质/6 图元）
 *   entry/src/main/resources/rawfile/models/zhitu_gem.glb   二十面体晶体（20 材质/20 图元，渐变色）
 *
 * 用法：node tools/gen_glb_models.js
 * 说明：纯 Node 无三方依赖；顶点法线/绕序均按 glTF 前向逆时针（CCW）计算；
 *       bufferView 按 4 字节对齐（POSITION FLOAT 访问器安全），JSON 块补 0x20，BIN 块补 0x00。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'models');

/** 组装并写出一个 .glb 文件 */
function writeGlb(filePath, gltfJson, binBuffer) {
  const jsonText = JSON.stringify(gltfJson);
  const jsonBuf = Buffer.from(jsonText, 'utf8');
  const jsonPad = (4 - (jsonBuf.length % 4)) % 4;
  const binPad = (4 - (binBuffer.length % 4)) % 4;
  const jsonLen = jsonBuf.length + jsonPad;
  const binLen = binBuffer.length + binPad;
  const total = 12 + 8 + jsonLen + 8 + binLen;

  const out = Buffer.alloc(total);
  let o = 0;
  out.writeUInt32LE(0x46546c67, o); o += 4; // magic 'glTF'
  out.writeUInt32LE(2, o); o += 4;         // version
  out.writeUInt32LE(total, o); o += 4;     // total length
  out.writeUInt32LE(jsonLen, o); o += 4;   // chunk 0 length
  out.writeUInt32LE(0x4e4f534a, o); o += 4; // chunk 0 type 'JSON'
  jsonBuf.copy(out, o); o += jsonBuf.length;
  for (let i = 0; i < jsonPad; i++) { out[o] = 0x20; o += 1; } // 空格补齐
  out.writeUInt32LE(binLen, o); o += 4;    // chunk 1 length
  out.writeUInt32LE(0x004e4942, o); o += 4; // chunk 1 type 'BIN'
  binBuffer.copy(out, o); o += binBuffer.length;
  for (let i = 0; i < binPad; i++) { out[o] = 0x00; o += 1; } // 零补齐

  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, out);
  console.log(`[gen] ${path.relative(ROOT, filePath)}  ${out.length} bytes (json ${jsonLen}B, bin ${binLen}B)`);
}

/**
 * 由图元集合构建 glTF 资源。
 * primitives: [{ positions: number[][], normals: number[][], indices: number[], color: [r,g,b], metallic, roughness }]
 */
function buildModel(nodeName, primitives) {
  const buffers = [];
  const bufferViews = [];
  const accessors = [];
  const materials = [];
  const meshesPrimitives = [];
  let byteOffset = 0;

  const pushView = (byteLength) => {
    const view = { buffer: 0, byteOffset, byteLength };
    bufferViews.push(view);
    byteOffset += byteLength;
    const pad = (4 - (byteOffset % 4)) % 4;
    byteOffset += pad; // 保证后续 view 4 字节对齐
    return view;
  };

  const pushAccessor = (view, componentType, count, type, minMax) => {
    const acc = { bufferView: bufferViews.indexOf(view), componentType, count, type };
    if (minMax) { acc.min = minMax.min; acc.max = minMax.max; }
    accessors.push(acc);
    return accessors.length - 1;
  };

  for (const p of primitives) {
    // POSITION
    const posBuf = Buffer.alloc(p.positions.length * 12);
    let mn = [Infinity, Infinity, Infinity];
    let mx = [-Infinity, -Infinity, -Infinity];
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

    // NORMAL
    const nrmBuf = Buffer.alloc(p.normals.length * 12);
    p.normals.forEach((v, i) => {
      nrmBuf.writeFloatLE(v[0], i * 12);
      nrmBuf.writeFloatLE(v[1], i * 12 + 4);
      nrmBuf.writeFloatLE(v[2], i * 12 + 8);
    });
    const nrmView = pushView(nrmBuf.length);
    buffers.push(nrmBuf);
    const nrmIdx = pushAccessor(nrmView, 5126, p.normals.length, 'VEC3');

    // INDICES（UNSIGNED_SHORT 5123）
    const idxBuf = Buffer.alloc(p.indices.length * 2);
    p.indices.forEach((v, i) => idxBuf.writeUInt16LE(v, i * 2));
    const idxView = pushView(idxBuf.length);
    buffers.push(idxBuf);
    const idxIdx = pushAccessor(idxView, 5123, p.indices.length, 'SCALAR');

    // MATERIAL
    materials.push({
      name: `mat_${materials.length}`,
      pbrMetallicRoughness: {
        baseColorFactor: [p.color[0], p.color[1], p.color[2], 1.0],
        metallicFactor: p.metallic,
        roughnessFactor: p.roughness
      }
    });

    meshesPrimitives.push({
      attributes: { POSITION: posIdx, NORMAL: nrmIdx },
      indices: idxIdx,
      material: materials.length - 1,
      mode: 4 // TRIANGLES
    });
  }

  const binBuffer = Buffer.concat(buffers);

  const gltf = {
    asset: { version: '2.0', generator: 'zhitu-gen' },
    scene: 0,
    scenes: [{ name: 'Scene', nodes: [0] }],
    nodes: [{ name: nodeName, mesh: 0 }],
    meshes: [{ name: nodeName + '_mesh', primitives: meshesPrimitives }],
    materials,
    accessors,
    bufferViews,
    buffers: [{ byteLength: binBuffer.length }]
  };
  return { gltf, binBuffer };
}

/** 立方体：六面异色，每面独立图元与材质 */
function buildCube() {
  const s = 1.15;
  const faces = [
    { n: [1, 0, 0], v: [[1, -1, -1], [1, 1, -1], [1, 1, 1], [1, -1, 1]], color: [0.05, 0.44, 0.98], name: 'px' },   // +X 智图蓝
    { n: [-1, 0, 0], v: [[-1, -1, 1], [-1, 1, 1], [-1, 1, -1], [-1, -1, -1]], color: [0.04, 0.72, 0.67], name: 'nx' }, // -X 青
    { n: [0, 1, 0], v: [[-1, 1, -1], [-1, 1, 1], [1, 1, 1], [1, 1, -1]], color: [0.96, 0.66, 0.14], name: 'py' },   // +Y 琥珀
    { n: [0, -1, 0], v: [[1, -1, -1], [1, -1, 1], [-1, -1, 1], [-1, -1, -1]], color: [0.93, 0.33, 0.33], name: 'ny' }, // -Y 红
    { n: [0, 0, 1], v: [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]], color: [0.48, 0.36, 0.96], name: 'pz' },   // +Z 紫
    { n: [0, 0, -1], v: [[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]], color: [0.18, 0.80, 0.44], name: 'nz' } // -Z 绿
  ];
  const primitives = faces.map((f) => ({
    positions: f.v.map((p) => [p[0] * s, p[1] * s, p[2] * s]),
    normals: [f.n, f.n, f.n, f.n],
    indices: [0, 1, 2, 0, 2, 3],
    color: f.color,
    metallic: 0.15,
    roughness: 0.55
  }));
  return buildModel('CubeRoot', primitives);
}

/** 二十面体晶体：20 面，蓝→青渐变，高金属度低粗糙度 */
function buildGem() {
  const phi = (1 + Math.sqrt(5)) / 2;
  const invLen = 1 / Math.sqrt(1 + phi * phi); // 顶点半径归一
  const scale = 1.35;
  const verts = [
    [-1, phi, 0], [1, phi, 0], [-1, -phi, 0], [1, -phi, 0],
    [0, -1, phi], [0, 1, phi], [0, -1, -phi], [0, 1, -phi],
    [phi, 0, -1], [phi, 0, 1], [-phi, 0, -1], [-phi, 0, 1]
  ].map((v) => [v[0] * invLen * scale, v[1] * invLen * scale, v[2] * invLen * scale]);

  const faceIdx = [
    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
  ];

  const lerp = (a, b, t) => a + (b - a) * t;
  const primitives = faceIdx.map((f, i) => {
    const a = verts[f[0]];
    const b = verts[f[1]];
    const c = verts[f[2]];
    // 面法线 = (b-a)×(c-a) 归一化
    const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    const e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let nx = e1[1] * e2[2] - e1[2] * e2[1];
    let ny = e1[2] * e2[0] - e1[0] * e2[2];
    let nz = e1[0] * e2[1] - e1[1] * e2[0];
    const nl = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1;
    nx /= nl; ny /= nl; nz /= nl;
    const t = i / (faceIdx.length - 1);
    // 蓝 → 青 → 亮蓝渐变，交替亮度制造晶体切面感
    const boost = i % 2 === 0 ? 1.0 : 0.82;
    return {
      positions: [a, b, c],
      normals: [[nx, ny, nz], [nx, ny, nz], [nx, ny, nz]],
      indices: [0, 1, 2],
      color: [
        Math.min(1, lerp(0.07, 0.10, t) * boost + 0.05),
        Math.min(1, lerp(0.45, 0.76, t) * boost + 0.04),
        Math.min(1, lerp(0.95, 0.72, t) * boost + 0.05)
      ],
      metallic: 0.85,
      roughness: 0.22
    };
  });
  return buildModel('GemRoot', primitives);
}

const cube = buildCube();
writeGlb(path.join(OUT_DIR, 'zhitu_cube.glb'), cube.gltf, cube.binBuffer);

const gem = buildGem();
writeGlb(path.join(OUT_DIR, 'zhitu_gem.glb'), gem.gltf, gem.binBuffer);

// 自检：JSON 可回读、buffer 长度一致
[cube, gem].forEach((m, i) => {
  const j = JSON.parse(JSON.stringify(m.gltf));
  const declared = j.buffers[0].byteLength;
  if (declared !== m.binBuffer.length) {
    throw new Error(`model ${i}: buffer byteLength mismatch declared=${declared} actual=${m.binBuffer.length}`);
  }
});
console.log('[gen] OK: both models self-check passed.');
