/**
 * 构建脚本：直接用 DevEco Studio 自带的 node + hvigor 包装器编译 entry HAP。
 * 通过 spawnSync 设置 cwd，绕开被污染的 bash shell（无法 cd）。
 * 编码鲁棒解码：优先按 BOM 判断，否则尝试 UTF-8 / UTF-16LE / GBK。
 * 关键判定（BUILD SUCCESSFUL / COMPILE RESULT / ERROR）均为 ASCII，即使中文乱码也能正确检索。
 */
const { spawnSync } = require('child_process');
const fs = require('fs');

const DEV_NODE = 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe';
const WRAPPER = 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js';
const PROJECT = 'C:/Users/infinty/DevEcoStudioProjects/ZhiTu';
const LOG = 'C:/Users/infinty/DevEcoStudioProjects/ZhiTu/build_v20.log';
const args = ['assembleHap', '--mode', 'module', '-p', 'product=default', '--no-daemon'];

const r = spawnSync(DEV_NODE, [WRAPPER, ...args], {
  cwd: PROJECT,
  encoding: 'buffer',
  maxBuffer: 256 * 1024 * 1024,
  env: process.env
});

const out = Buffer.concat([r.stdout || Buffer.alloc(0), r.stderr || Buffer.alloc(0)]);
fs.writeFileSync(LOG, out);

function tryDecode(buf) {
  if (buf.length >= 2 && buf[0] === 0xFF && buf[1] === 0xFE) {
    return buf.toString('utf16le');
  }
  if (buf.length >= 2 && buf[0] === 0xFE && buf[1] === 0xFF) {
    return buf.swap16().toString('utf16le');
  }
  const utf8 = buf.toString('utf8');
  const repl = (utf8.match(/�/g) || []).length;
  if (repl < utf8.length * 0.03) {
    return utf8;
  }
  try {
    const utf16 = buf.toString('utf16le');
    if (/BUILD|ERROR|COMPILE/.test(utf16)) {
      return utf16;
    }
  } catch (e) {}
  try {
    const td = new TextDecoder('gbk');
    const gbk = td.decode(buf);
    if (/BUILD|ERROR|COMPILE/.test(gbk)) {
      return gbk;
    }
  } catch (e) {}
  return utf8;
}

const text = tryDecode(out);
const hasSuccess = /BUILD SUCCESSFUL/.test(text);
const hasFail = /BUILD FAILED/.test(text);
const compileMatch = text.match(/COMPILE RESULT:\S+ \{ERROR:(\d+) WARN:(\d+)\}/);
const lines = text.split('\n');
const errorLines = lines.filter((l) => /ERROR/.test(l));

console.log('EXIT_CODE:', r.status);
console.log('BUILD_SUCCESSFUL:', hasSuccess, 'BUILD_FAILED:', hasFail);
console.log('COMPILE:', compileMatch ? compileMatch[0] : 'n/a');
console.log('ERROR_LINE_COUNT:', errorLines.length);
console.log('--- ERROR LINES (first 60) ---');
errorLines.slice(0, 60).forEach((l) => console.log(l.trim()));
console.log('--- TAIL (last 25) ---');
console.log(lines.slice(-25).join('\n').trim());
