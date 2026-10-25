#!/usr/bin/env node
// Эталонный прогон Jetpac на модели ZX 48K (tools/zx48.js) по шагам (docs/LOGIC_PLAN.md, этап 0).
//
// Шаг = проход главного цикла: от MainLoopResetStack до следующего MainLoopResetStack (ракета, модуль,
// предмет, пламя, 6 пришельцев, взрыв; по тику кадра внутри — вложенный проход Джетмена и лазеров).
// На каждом шаге пишется:
//   d   — изменения состояния к концу шага: [адрес, байт] в 0x4000..0x7FB2 — экран и атрибуты (логика читает
//         экран: лазер упирается в непустой байт), переменные, буферы спрайтов, код с самомодификацией;
//         без системной области и стека 0x5B00..0x5CEF;
//   rd  — чтения игрой адресов, которые пишет обработчик ПЗУ (FRAMES и пр.), по порядку: [адрес, байт];
//   in  — чтения портов игрой по порядку: [порт, байт] (клавиатура, Interface 2);
//   r   — значения `ld a,r`;
//   snd — входы в звуковые подпрограммы: [имя, a, b, c, d, e, h, l];
//   fr  — сколько кадров прошло за шаг; keys — клавиши шага; pk — записи сценария в память перед шагом.
// В начале — снимок `first` (0x4000..0x7FB2) и регистры `regs` на входе в первый шаг.
//
//   node tools/zx_trace.js <сценарий.json> [выход.json.gz]
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const ZX = require('./zx48');
const scenario = require('./scenario');
const { SYM, ROOT } = require('./sym');

const LO = 0x4000, HI = 0x7fb3, SYS_LO = 0x5b00, STACK_HI = 0x5cf0;
// звуковые подпрограммы: [имя, начало тела, конец тела) — вход считается, если прошлая команда была вне тела
// (PlaySquareWav2 — сама цель djnz, по ней PC проходит на каждом витке)
const SND = [['PlaySquareWave1', 'PlaySquareWave1', 'SfxLaserFire'], ['PlaySquareWav2', 'PlaySquareWave1', 'SfxLaserFire'],
  ['SfxLaserFire', 'SfxLaserFire', 'SfxSetExplodeParams'], ['SfxPlayExplosion', 'SfxPlayExplosion', 'SfxFinishReturn']];

function regsOf(m) {
  const s = m.cpu.getState();
  return { a: s.a, b: s.b, c: s.c, d: s.d, e: s.e, h: s.h, l: s.l, ix: s.ix, iy: s.iy,
    a_: s.a_prime, b_: s.b_prime, c_: s.c_prime, d_: s.d_prime, e_: s.e_prime, h_: s.h_prime, l_: s.l_prime };
}

function run(sc, owned, learn) {
  const { m, keysFor, applied } = scenario.start(sc);
  let cur = null;
  m.onWrite = (a, v, isr) => { if (isr && learn) learn.add(a); };
  m.onRead = (a, v, isr) => { if (!isr && cur && owned && owned.has(a)) cur.rd.push([a, v]); };
  m.onIn = (p, v, isr) => { if (!isr && cur) cur.in.push([p, v]); };
  const sndAt = new Map(SND.map(([n, a, b]) => [SYM[n], [n, SYM[a], SYM[b]]]));
  let prevPc = -1;
  const ticks = [];
  let prev = m.mem.slice(LO, HI);
  const first = Buffer.from(prev).toString('base64');
  const regs = regsOf(m);
  const END = SYM.MainLoopResetStack;
  for (let t = 0; ; t++) {
    const keys = keysFor(t);
    if (!keys) break;
    for (const [a, v] of applied) if (a >= LO && a < HI) prev[a - LO] = v;
    m.keysOnly(keys);
    cur = { rd: [], in: [], r: [], snd: [], keys };
    if (applied.length) cur.pk = applied.slice();
    const f0 = m.frames;
    let menu = false, moved = false;              // moved: выполнена хоть одна команда игры (не прерывание)
    for (;;) {
      const pc = m.pc;
      if (pc === END && !m.inIsr && moved) break;
      if (m.intLine && m.intReady()) { m.step(); continue; }
      if (!m.inIsr) moved = true;
      if (!m.inIsr) {
        if (pc === SYM.MenuScreen) menu = true;
        const sn = sndAt.get(pc);
        if (sn && !(prevPc >= sn[1] && prevPc < sn[2])) { const s = m.cpu.getState(); cur.snd.push([sn[0], s.a, s.b, s.c, s.d, s.e, s.h, s.l]); }
        prevPc = pc;
      }
      const isLdAR = !m.inIsr && m.peek(pc) === 0xed && m.peek(pc + 1) === 0x5f;
      m.step();
      if (isLdAR) cur.r.push(m.cpu.get_a());
      if (menu && m.frames - f0 > 5) break;                 // конец игры: меню — эталон кончается
      if (m.frames - f0 > 3000) throw new Error('шаг не кончается, pc ' + pc.toString(16));
    }
    cur.fr = m.frames - f0;
    if (menu) { cur.menu = 1; }
    const now = m.mem.slice(LO, HI);
    const d = [];
    for (let i = 0; i < now.length; i++) {
      const a = LO + i;
      if ((a >= SYS_LO && a < STACK_HI) || now[i] === prev[i] || (owned && owned.has(a))) continue;
      d.push([a, now[i]]);
    }
    cur.d = d;
    ticks.push(cur);
    prev = now;
    if (menu) break;
  }
  return { m, ticks, first, regs };
}

if (require.main === module) {
  const scFile = process.argv[2];
  const sc = JSON.parse(fs.readFileSync(scFile, 'utf8'));
  const out = process.argv[3] || path.join(ROOT, 'build/golden', sc.name + '.json.gz');
  const learn = new Set();
  run(sc, null, learn);
  const owned = new Set([...learn].filter((a) => !(a >= 0x5ccb && a < STACK_HI)));
  const t0 = Date.now();
  const { ticks, first, regs } = run(sc, owned, null);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const doc = { name: sc.name, scenario: sc, owned: [...owned].sort((a, b) => a - b), lo: LO, hi: HI, first, regs, ticks };
  fs.writeFileSync(out, zlib.gzipSync(JSON.stringify(doc)));
  const fr = ticks.reduce((s, t) => s + t.fr, 0);
  const cnt = (k) => ticks.reduce((s, t) => s + t[k].length, 0);
  console.log(`${sc.name}: шагов ${ticks.length}, кадров ${fr} (${(fr / ticks.length).toFixed(2)} на шаг), ` +
    `адресов ПЗУ ${owned.size} [${[...owned].map((a) => a.toString(16)).join(' ')}], ldar ${cnt('r')}, in ${cnt('in')}, ` +
    `звуков ${cnt('snd')}${ticks.length && ticks[ticks.length - 1].menu ? ', конец — меню' : ''}, ${Date.now() - t0} мс -> ${path.relative(ROOT, out)}`);
}
module.exports = { run, LO, HI, SYS_LO, STACK_HI };
