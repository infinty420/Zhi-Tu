/**
 * find_dead_code.js —— 死代码扫描：找出全工程零外部引用的 .ets 文件。
 *
 * 规则：
 * 1. 收集 entry/src/main/ets 下全部 .ets 文件，取 basename（不含扩展名）。
 * 2. 在其余 ets + module.json5 + resources/profile/*.json + main_pages.json 中
 *    按 \b<basename>\b 词级匹配统计引用（import 路径 / 类型名 / 路由名字符串均覆盖）。
 * 3. 白名单：框架/构建入口（Index、EntryAbility、EntryBackupAbility、FormAbility 等）。
 * 输出候选清单，人工二次确认后再删除（本脚本只读不写）。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ETS_ROOT = path.join(ROOT, 'entry', 'src', 'main', 'ets');

// 框架/配置入口（module.json5、main_pages.json、form_config 引用或 hypium 测试框架）
const WHITELIST = new Set([
  'Index',              // main_pages.json
  'EntryAbility',       // module.json5 mainElement
  'EntryBackupAbility', // module.json5 extensionAbilities
  'FormAbility',        // module.json5 extensionAbilities
  'LocalUnit.test',     // 单元测试入口（构建模板固定引用）
  'Ability.test'        // 仪器测试入口（构建模板固定引用）
]);

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) {
      walk(p, out);
    } else {
      out.push(p);
    }
  }
  return out;
}

const etsFiles = walk(ETS_ROOT, []).filter((p) => p.endsWith('.ets'));
const extraFiles = [
  path.join(ROOT, 'entry', 'src', 'main', 'module.json5')
];
// profile json
const profileDir = path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'profile');
if (fs.existsSync(profileDir)) {
  for (const f of fs.readdirSync(profileDir)) {
    extraFiles.push(path.join(profileDir, f));
  }
}

const corpus = [];
for (const f of etsFiles) {
  corpus.push({ path: f, text: fs.readFileSync(f, 'utf8') });
}
for (const f of extraFiles) {
  if (fs.existsSync(f)) {
    corpus.push({ path: f, text: fs.readFileSync(f, 'utf8') });
  }
}

const dead = [];
const lowRef = [];
for (const f of etsFiles) {
  const base = path.basename(f, '.ets');
  if (WHITELIST.has(base)) {
    continue;
  }
  const re = new RegExp('\\b' + base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b');
  let refs = 0;
  const refFrom = [];
  for (const c of corpus) {
    if (path.resolve(c.path) === path.resolve(f)) {
      continue;
    }
    if (re.test(c.text)) {
      refs++;
      refFrom.push(path.relative(ROOT, c.path));
    }
  }
  if (refs === 0) {
    dead.push(path.relative(ROOT, f));
  } else if (refs <= 2) {
    lowRef.push({ file: path.relative(ROOT, f), refs, refFrom });
  }
}

console.log('=== 零引用候选（需人工确认后删除） ===');
dead.forEach((d) => console.log('  ' + d));
console.log(`共 ${dead.length} 个`);

console.log('\n=== 低引用（<=2 处，供复核） ===');
lowRef.forEach((l) => {
  console.log(`  ${l.file}  refs=${l.refs}`);
  l.refFrom.forEach((r) => console.log(`      <- ${r}`));
});
console.log(`共 ${lowRef.length} 个`);
