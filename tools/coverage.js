#!/usr/bin/env node
// Покрытие кода игры эталонами: какие команды (по меткам) ни разу не выполнялись.
//   node tools/coverage.js build/golden/*.json.gz
'use strict';
const fs = require('fs'), zlib = require('zlib');
const { SYM } = require('./sym');
const hit = new Set();
for (const f of process.argv.slice(2)) for (const a of JSON.parse(zlib.gunzipSync(fs.readFileSync(f))).cov || []) hit.add(a);
// границы команд — по листингу skool (адрес в начале строки кода)
const instr = [];
for (const l of fs.readFileSync(require('path').join(__dirname, '../upstream/jetpac.skool'), 'utf8').split('\n')) {
  const m = l.match(/^[c* ]\$([0-9a-f]{4}) ([a-z]+)/);
  if (m && (l[0] === 'c' || instr.length && instr[instr.length - 1].code)) instr.push({ a: parseInt(m[1], 16), code: true, txt: l.slice(7, 40).trim() });
  else if (/^[bstuwi]\$/.test(l)) instr.push({ a: -1, code: false });
}
const code = instr.filter((i) => i.code && i.a >= 0x6000);
const labels = Object.entries(SYM).filter(([, v]) => v >= 0x6000 && v < 0x8000).sort((a, b) => a[1] - b[1]);
const lab = (a) => { let b = null; for (const [k, v] of labels) { if (v > a) break; b = [k, v]; } return b ? b[0] + (a - b[1] ? '+' + (a - b[1]) : '') : a.toString(16); };
const miss = code.filter((i) => !hit.has(i.a));
console.log(`команд ${code.length}, выполнено ${code.length - miss.length} (${(100 * (code.length - miss.length) / code.length).toFixed(1)} %)`);
let prevLab = null;
for (const i of miss) { const L = lab(i.a).split('+')[0]; if (L !== prevLab) { console.log(' ' + L + ':'); prevLab = L; } console.log(`   ${i.a.toString(16)} ${i.txt}`); }
