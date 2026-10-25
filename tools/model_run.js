#!/usr/bin/env node
// Прогон JS-модели по эталону без процессора (docs/LOGIC_PLAN.md): начальное состояние — снимок эталона
// (first, 0x4000..0x7FB2) + ПЗУ 48K, регистры — regs; на каждом шаге — очереди эталона: чтения FRAMES (rd),
// порты (in), ld a,r (r). Модель выполняет проход главного цикла (logic.pass) и сравнивает изменённую память
// с эталоном (d) и входы в звук. После шага состояние берётся из эталона (расхождения не копятся).
//   node tools/model_run.js build/golden/<имя>.json.gz [...] [--max N] [--from шаг]
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { Mem } = require('../src/model/core');
const logic = require('../src/model/logic');
const { where } = require('./sym');

// значимые регистры входа в звук
const SND_KEYS = { PlaySquareWave1: [3, 4], PlaySquareWav2: [2, 3, 4], SfxLaserFire: [], SfxPlayExplosion: [3] };
const sndStr = (l) => l.map((s) => s[0] + '(' + SND_KEYS[s[0]].map((i) => s[i]).join(',') + ')').join(' ');

const args = process.argv.slice(2);
let maxShow = 5, from = 0;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max') maxShow = +args[++i];
  else if (args[i] === '--from') from = +args[++i];
  else files.push(args[i]);
}

function runOne(file) {
  const g = JSON.parse(zlib.gunzipSync(fs.readFileSync(file)));
  const ram = new Uint8Array(0x10000);
  ram.set(fs.readFileSync(path.join(__dirname, '../ref/48.rom')));
  ram.set(fs.readFileSync(path.join(__dirname, '../build/jetpac.bin')), 0x5ccb);   // шрифт и данные выше снимка
  ram.set(Buffer.from(g.first, 'base64'), g.lo);
  const real = new Uint8Array(ram);
  const owned = new Set(g.owned);
  const skip = (a) => a < g.lo || a >= g.hi || (a >= 0x5b00 && a < 0x5cf0) || owned.has(a);
  let bad = 0, run = 0, skipped = 0, shown = 0;
  const M = new Mem(ram);
  M.owned = owned;
  const R = g.regs;
  Object.assign(M.r, { a: R.a, b: R.b, c: R.c, d: R.d, e: R.e, h: R.h, l: R.l });
  Object.assign(M.r_, { a: R.a_, b: R.b_, c: R.c_, d: R.d_, e: R.e_, h: R.h_, l: R.l_ });
  for (let t = 0; t < g.ticks.length; t++) {
    const tk = g.ticks[t];
    for (const [a, v] of tk.pk || []) { real[a] = v; ram[a] = v; }
    if (t < from || tk.menu) { for (const [a, v] of tk.d) real[a] = v; ram.set(real); skipped++; continue; }
    M.q = new Map();
    for (const [a, v] of tk.rd) { let q = M.q.get(a); if (!q) M.q.set(a, q = []); q.push(v); }
    M.inq = tk.in.slice(); M.rq = tk.r.slice(); M.snd = []; M.writes = new Set();
    let err = null;
    try { logic.pass(M); } catch (e) { if (e.notModeled || e.gameOver) err = e; else { console.log(`  шаг ${t}: ${e.stack}`); err = e; } }
    for (const [a, v] of tk.d) real[a] = v;
    if (err && err.notModeled) { ram.set(real); skipped++; continue; }
    run++;
    const diffs = [];
    const check = new Set([...M.writes, ...tk.d.map((x) => x[0])]);
    for (const a of check) if (!skip(a) && ram[a] !== real[a]) diffs.push([a, real[a], ram[a]]);
    diffs.sort((x, y) => x[0] - y[0]);
    const ms = sndStr(M.snd), rs = sndStr(tk.snd);
    if (ms !== rs) diffs.push(['звук', rs, ms]);
    if (M.inq.length) diffs.push(['порты', `осталось ${M.inq.length}`, '']);
    if (M.rq.length) diffs.push(['ld a,r', `осталось ${M.rq.length}`, '']);
    if (err && !err.gameOver) diffs.push(['исключение', '', err.message]);
    if (diffs.length) {
      bad++;
      if (shown++ < maxShow) {
        const nm = (a) => typeof a === 'number' ? (a < 0x5800 ? 'экр' : a < 0x5b00 ? 'атр' : where(a)) + ':' + a.toString(16) : a;
        console.log(`  шаг ${t}: ${diffs.length} расхождений: ` + diffs.slice(0, 8).map(([a, r, m]) => `${nm(a)} ZX ${r} модель ${m}`).join('; '));
      }
    }
    ram.set(real);
  }
  console.log(`${g.name}: шагов ${g.ticks.length}, модель ${run}, расхождений ${bad}, без модели ${skipped}`);
  return bad === 0;
}

let ok = true;
for (const f of files) ok = runOne(f) && ok;
process.exit(ok ? 0 : 1);
