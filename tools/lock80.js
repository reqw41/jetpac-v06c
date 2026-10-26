#!/usr/bin/env node
// Сверка i8080 (build/vec/jetpac.bin) с эталоном ZX по проходам (docs/LOGIC_PLAN.md, этап 2).
//
// Модель совпадает с эталоном на всех сценариях, поэтому i8080 сверяется прямо с эталоном: на каждом шаге
// i8080 выполняет `pass` на своём зеркале с теми же входами — чтения FRAMES подаются из очереди шага
// (перехват чтения 0x5C78), ld a,r — r_buf, клавиши шага — zx_kb (без SHIFT), — и сравниваются:
//   переменные 0x5CF0..0x5DFF, экран ZX (объединение 4 плоскостей Вектора по адресу точки), звуки (c, d).
// После шага зеркало исправляется по эталону (расхождения не копятся): переменные — как в ZX, экран —
// байт ZX в плоскость 0x80 (цвет не сверяется). Буферы спрайтов i8080 — свои (формат по столбцам):
// в начале переводятся из буферов ZX, дальше их строит сам i8080.
//   node tools/lock80.js build/golden/<имя>.json.gz [...] [--max N] [--from шаг] [--ticks N]
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const vm = require('vm');
const ZX = require('./zx48');
const { where } = require('./sym');

const ROOT = path.join(__dirname, '..');
const SYM80 = {};
for (const l of fs.readFileSync(path.join(ROOT, 'build/vec/jetpac.sym'), 'latin1').split('\n')) {
  const m = l.match(/^(\w+):\s+EQU\s+0x([0-9A-F]+)/i); if (m) SYM80[m[1]] = parseInt(m[2], 16);
}
const BIN = fs.readFileSync(path.join(ROOT, 'build/vec/jetpac.bin'));

// --- процессор i8080 (ядро vector06js, такты Вектора)
const base = process.env.V06JS || path.join(require('os').homedir(), 'projects/vector06js');
const g = { console: { log() {}, debug() {}, warn() {}, error() {}, info() {} } }; g.window = g;
const ctx = vm.createContext(g);
for (const f of ['i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js'])
  vm.runInContext(fs.readFileSync(path.join(base, f), 'utf8'), ctx, { filename: f });
const mem = new Uint8Array(0x10000);
let framesQ = [], framesLast = 0;
const written = new Set();
const memory = {
  read: (a) => {
    a &= 0xffff;
    if (a === 0x5c78) { const v = framesQ.length ? framesQ.shift() : framesLast; framesLast = v; mem[a] = v; return v; }
    return mem[a];
  },
  write: (a, v) => { a &= 0xffff; written.add(a); mem[a] = v & 0xff; },
};
const cpu = new ctx.I8080(memory, { input: () => 0xff, output: () => {}, commit: () => {}, interrupt: () => {} });
// профиль: такты по меткам i8080 (--prof)
const PROF = process.argv.includes('--prof');
const labAt = new Int32Array(0x10000).fill(-1), labNames = [], profT = [];
if (PROF) {
  const ls = Object.entries(SYM80).filter(([k, v]) => v < 0x8000 && !/^(L|\d)/.test(k)).sort((a, b) => a[1] - b[1]);
  ls.forEach(([k], i) => { labNames.push(k); profT.push(0); });
  let j = -1; for (let a = 0; a < 0x10000; a++) { while (j + 1 < ls.length && ls[j + 1][1] <= a) j++; labAt[a] = j; }
}
function call(addr, maxT) {
  const SENT = 0xfffe;
  mem[0x5afe] = SENT & 0xff; mem[0x5aff] = SENT >> 8;
  cpu.sp = 0x5afe; cpu.pc = addr;
  let t = 0; const lim = maxT || 2e8;
  while (cpu.pc !== SENT) {
    const pc0 = cpu.pc;
    cpu.instruction(); t += cpu.vcycles;
    if (PROF && labAt[pc0] >= 0) profT[labAt[pc0]] += cpu.vcycles;
    if (t > lim) throw new Error('i8080: не вернулась ' + addr.toString(16) + ' pc ' + cpu.pc.toString(16));
  }
  return t;
}

// --- экран: ZX адрес <-> Вектор
const zxXY = (a) => { const o = a - 0x4000; return [((o >> 8) & 7) | ((o >> 2) & 0x38) | ((o >> 5) & 0xc0), o & 0x1f]; };
const vecOf = (a) => { const [y, c] = zxXY(a); return ((0x80 + c) << 8) | ((223 - y) & 0xff); };
const zxOfVec = new Map();
for (let a = 0x4000; a < 0x5800; a++) zxOfVec.set(vecOf(a), a);
const union = (v) => mem[v] | mem[v + 0x2000] | mem[v + 0x4000] | mem[v + 0x6000];
function putScreen(a, v) { const p = vecOf(a); mem[p] = v; mem[p + 0x2000] = 0; mem[p + 0x4000] = 0; mem[p + 0x6000] = 0; }

// буфер ZX (3 + h*3 по строкам) -> формат i8080 (3 + 3 столбца по h2)
function convBuffer(ram, a) {
  const h = ram[a + 2], h2 = h + (h & 1);
  mem[a] = ram[a]; mem[a + 1] = ram[a + 1]; mem[a + 2] = h;
  for (let c = 0; c < 3; c++) for (let r = 0; r < h2; r++) mem[a + 3 + c * h2 + r] = r < h ? ram[a + 3 + r * 3 + c] : 0;
}

const SND_ID = { PlaySquareWave1: 1, PlaySquareWav2: 2, SfxLaserFire: 3, SfxPlayExplosion: 4 };
const sndZX = (l) => l.map((s) => s[0] === 'SfxPlayExplosion' ? `4(${s[3]})` : s[0] === 'SfxLaserFire' ? '3' : `${SND_ID[s[0]]}(${s[3]},${s[4]})`).join(' ');
function snd80() {
  const out = [];
  for (let p = SYM80.snd_buf; p < (mem[SYM80.snd_ptr] | mem[SYM80.snd_ptr + 1] << 8); p += 3) {
    const id = mem[p], c = mem[p + 1], d = mem[p + 2];
    out.push(id === 4 ? `4(${c})` : id === 3 ? '3' : `${id}(${c},${d})`);
  }
  return out.join(' ');
}

const args = process.argv.slice(2);
let maxShow = 5, from = 0, maxTicks = 1e9;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max') maxShow = +args[++i];
  else if (args[i] === '--from') from = +args[++i];
  else if (args[i] === '--ticks') maxTicks = +args[++i];
  else if (args[i] === '--prof') {}
  else files.push(args[i]);
}

let allOk = true;
for (const file of files) {
  const gd = JSON.parse(zlib.gunzipSync(fs.readFileSync(file)));
  const real = new Uint8Array(0x10000);
  real.set(fs.readFileSync(path.join(ROOT, 'build/jetpac.bin')), 0x5ccb);
  real.set(Buffer.from(gd.first, 'base64'), gd.lo);
  mem.fill(0); mem.set(BIN, 0);
  for (let a = 0x5c78; a < 0x5c7b; a++) mem[a] = real[a];
  for (let a = 0x5cf0; a < 0x5e00; a++) mem[a] = real[a];
  for (let a = 0x4000; a < 0x5800; a++) putScreen(a, real[a]);
  for (let k = 0; k < 8; k++) convBuffer(real, 0x5e00 + k * 0x33);
  mem[SYM80.lock_mode] = 1;
  let bad = 0, run = 0, shown = 0, tsum = 0, tmax = 0, frsum = 0;
  const pairs = []; let kUsed = 0;
  for (let t = 0; t < gd.ticks.length && run < maxTicks; t++) {
    const tk = gd.ticks[t];
    for (const [a, v] of tk.pk || []) { real[a] = v; if (a >= 0x4000 && a < 0x5800) putScreen(a, v); else if (a >= 0x5cf0 && a < 0x5e00) mem[a] = v; }
    for (const [a, v] of tk.d) real[a] = v;
    if (t < from || tk.menu) { syncAll(tk); continue; }
    // входы шага
    framesQ = tk.rd.filter(([a]) => a === 0x5c78).map(([, v]) => v);
    framesLast = mem[0x5c78];
    for (let k = 0; k < 256; k++) mem[0x5b00 + k] = tk.r[k] || 0;
    mem[SYM80.r_idx] = 0;
    const zx = new ZX(); zx.keysOnly(tk.keys.filter((k) => k !== 'SHIFT'));
    for (let r = 0; r < 8; r++) mem[SYM80.zx_kb + r] = zx.kb[r];
    mem[SYM80.snd_ptr] = SYM80.snd_buf & 0xff; mem[SYM80.snd_ptr + 1] = SYM80.snd_buf >> 8;
    mem[SYM80.game_over] = 0;
    written.clear();
    let err = null, tt = 0;
    try { tt = call(SYM80.pass); } catch (e) { err = e; }
    if (mem[SYM80.k_used]) kUsed++;
    run++; tsum += tt; if (tt > tmax) tmax = tt; frsum += tk.fr;
    if (tk.t !== undefined) pairs.push([tt / 59904, (tk.t - tk.ts) / 69888, tk.ts / 69888]);
    const diffs = [];
    if (err) diffs.push(['исключение', '', err.message]);
    // переменные
    for (let a = 0x5cf0; a < 0x5e00; a++) if (mem[a] !== real[a]) diffs.push([a, real[a], mem[a]]);
    // экран: всё, что писали ZX (d) и i8080
    const scr = new Set();
    for (const [a] of tk.d) if (a >= 0x4000 && a < 0x5800) scr.add(a);
    for (const v of written) { const z = zxOfVec.get(((v & 0x9fff) | 0x8000) & 0xffff); if (v >= 0x8000 && z !== undefined) scr.add(z); }
    for (const a of scr) if (union(vecOf(a)) !== real[a]) diffs.push(['экр:' + a.toString(16), real[a], union(vecOf(a))]);
    const s80 = snd80(), szx = sndZX(tk.snd);
    if (s80 !== szx) diffs.push(['звук', szx, s80]);
    if (mem[SYM80.game_over] && !tk.menu) diffs.push(['конец игры у i8080', '', '']);
    if (framesQ.length) diffs.push(['FRAMES', `осталось ${framesQ.length}`, '']);
    if (mem[SYM80.r_idx] !== tk.r.length) diffs.push(['ld a,r', tk.r.length, mem[SYM80.r_idx]]);
    if (diffs.length) {
      bad++;
      if (shown++ < maxShow) {
        const nm = (a) => typeof a === 'number' ? where(a) + ':' + a.toString(16) : a;
        console.log(`  шаг ${t}: ${diffs.length} расхождений: ` + diffs.slice(0, 10).map(([a, r, m]) => `${nm(a)} ZX ${r} i8080 ${m}`).join('; '));
      }
    }
    syncAll(tk);
  }
  function syncAll(tk) {
    for (let a = 0x5cf0; a < 0x5e00; a++) mem[a] = real[a];
    const fix = (z) => { if (union(vecOf(z)) !== real[z]) putScreen(z, real[z]); };
    for (const a of written) if (a >= 0x8000) { const z = zxOfVec.get(((a & 0x9fff) | 0x8000) & 0xffff); if (z !== undefined) fix(z); }
    for (const [a] of tk.d) if (a >= 0x4000 && a < 0x5800) fix(a);
    written.clear();
  }
  console.log(`${gd.name}: шагов ${gd.ticks.length}, i8080 ${run}, расхождений ${bad}; тактов на проход сред ${(tsum / Math.max(run, 1)).toFixed(0)} ` +
    `макс ${tmax} (${(tsum / Math.max(run, 1) / 59904).toFixed(2)} кадра Вектора; ZX ${(frsum / Math.max(run, 1)).toFixed(2)} кадра)`);
  console.log(`  чёрная плоскость в работе: ${(100 * kUsed / Math.max(run, 1)).toFixed(1)} % проходов`);
  if (pairs.length) {                       // темп: кадры ZX без звука ~ k * кадры i8080
    let sx = 0, sy = 0, sxx = 0, sxy = 0, ss = 0; for (const [x, y, z] of pairs) { sx += x; sy += y; sxx += x * x; sxy += x * y; ss += z; }
    const n = pairs.length, k = (n * sxy - sx * sy) / (n * sxx - sx * sx), b = (sy - k * sx) / n;
    let e = 0; for (const [x, y] of pairs) e += Math.abs(y - (k * x + b));
    console.log(`  темп: ZX без звука = ${k.toFixed(3)} * i8080 + ${b.toFixed(3)} кадра (ср. ошибка ${(e / n).toFixed(3)}), ZX звук ${(ss / n).toFixed(3)} кадра на проход, отношение средних ${(sy / sx).toFixed(3)}`);
  }
  if (bad) allOk = false;
}
if (PROF) {
  const tot = profT.reduce((a, b) => a + b, 0);
  profT.map((v, i) => [v, labNames[i]]).sort((a, b) => b[0] - a[0]).slice(0, 30)
    .forEach(([v, n]) => console.log(`  ${(100 * v / tot).toFixed(1).padStart(5)} %  ${n}`));
}
process.exit(allOk ? 0 : 1);
