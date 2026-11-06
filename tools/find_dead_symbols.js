/**
 * find_dead_symbols.js —— 符号级死代码扫描（只读不写，结果供人工复核）。
 *
 * 三类候选：
 * A) 未使用的 import：import { X } 中 X 在文件其余部分零出现。
 * B) 顶层非导出符号：仅在声明处出现（函数/常量从未被调用）。
 * C) 导出符号：全工程（含本文件）除声明外零出现 → 真死代码。
 *
 * 注意：正则统计会误报注释/字符串中的同名文本，删除前必须人工确认。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ETS_ROOT = path.join(ROOT, 'entry', 'src', 'main', 'ets');

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

const etsFiles = walk(ETS_ROOT, []).filter((p) => p.endsWith('.ets'));
const corpus = etsFiles.map((p) => ({ path: p, text: fs.readFileSync(p, 'utf8') }));

const unusedImports = [];
const deadTopLevel = [];
const deadExports = [];

for (const c of corpus) {
  const rel = path.relative(ROOT, c.path);
  const lines = c.text.split('\n');

  // A) 未使用 import
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^import\s+\{([^}]+)\}\s+from\s+['"][^'"]+['"]\s*;?\s*$/);
    if (!m) continue;
    const names = m[1].split(',').map((s) => s.trim().split(/\s+as\s+/).pop()).filter((s) => s.length > 0);
    const rest = lines.slice(i + 1).join('\n');
    for (const n of names) {
      const re = new RegExp('\\b' + n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b');
      if (!re.test(rest)) {
        unusedImports.push(`${rel}:${i + 1}  import { ${n} } 未使用`);
      }
    }
  }

  // 提取本文件顶层声明（非 struct 内部）：以无缩进行判定
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const decl = line.match(/^(?:export\s+)?(?:async\s+)?(?:function|const|let|class|enum|interface)\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (!decl) continue;
    const name = decl[1];
    const isExport = /^export\b/.test(line);
    const textWithoutDeclLine = lines.filter((_, idx) => idx !== i).join('\n');
    const re = new RegExp('\\b' + name + '\\b');
    const selfUsed = re.test(textWithoutDeclLine);
    // 全工程其余文件引用
    let extRefs = 0;
    for (const c2 of corpus) {
      if (c2.path === c.path) continue;
      if (re.test(c2.text)) extRefs++;
    }
    if (isExport) {
      if (!selfUsed && extRefs === 0) deadExports.push(`${rel}:${i + 1}  export ${name}（全工程零引用）`);
    } else {
      if (!selfUsed) deadTopLevel.push(`${rel}:${i + 1}  ${name}（本文件内未使用）`);
    }
  }
}

console.log('=== A) 未使用的 import ===');
unusedImports.forEach((s) => console.log('  ' + s));
console.log(`共 ${unusedImports.length} 处`);

console.log('\n=== B) 顶层非导出符号本文件未使用 ===');
deadTopLevel.forEach((s) => console.log('  ' + s));
console.log(`共 ${deadTopLevel.length} 处`);

console.log('\n=== C) 导出符号全工程零引用 ===');
deadExports.forEach((s) => console.log('  ' + s));
console.log(`共 ${deadExports.length} 处`);
