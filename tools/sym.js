// Метки картриджной сборки (build/z80.sym, tools/mkbin.sh): имя -> адрес, адрес -> имя.
'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const SYM = {}, NAME = new Map();
for (const l of fs.readFileSync(path.join(ROOT, 'build/z80.sym'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+):\s+EQU\s+0x([0-9A-F]+)/i);
  if (m) { SYM[m[1]] = parseInt(m[2], 16); if (!NAME.has(SYM[m[1]])) NAME.set(SYM[m[1]], m[1]); }
}
// ближайшая метка не выше адреса: "Имя+N"
function where(a) {
  let best = null, bv = -1;
  for (const [k, v] of Object.entries(SYM)) if (v <= a && v > bv && !/^SYSVAR/.test(k)) { best = k; bv = v; }
  return best ? best + (a - bv ? '+' + (a - bv) : '') : a.toString(16);
}
module.exports = { SYM, NAME, where, ROOT };
