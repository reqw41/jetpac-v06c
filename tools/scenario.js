// Проигрыватель сценария для стендов ZX (zx_trace.js, shadow.js): меню по кадрам, потом клавиши на каждый
// шаг игры (steps, затем random или политика). Шаг = проход главного цикла (MainLoopResetStack).
//
// Сценарий: { "name", "menu": [{"frames": n, "keys": [...]}], "ticks": N,
//   "steps": [{"ticks": n, "keys": [...]}], "random": {"seed", "keys": [...], "p": 0.3, "hold": [a, b]},
//   "policy": {"name": ...}, "pokes": [{"tick": t, "set": {"метка или hex": значение | "@метка"}}] }
// По умолчанию меню: 60 кадров, «5» 3 кадра (1 игрок, клавиатура).
'use strict';
const path = require('path');
const ZX = require('./zx48');
const { SYM } = require('./sym');

function rng(seed) { let s = seed >>> 0 || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }

function start(sc, opts) {
  opts = opts || {};
  const m = new ZX().loadGame();
  if (opts.onCreate) opts.onCreate(m);
  const step = opts.step || ((mm) => mm.step());
  const frames = (n) => { const f = m.frames + n; while (m.frames < f) step(m); };
  const menu = sc.menu || [{ frames: 60, keys: [] }, { frames: 3, keys: ['5'] }];
  for (const st of menu) { m.keysOnly(st.keys || []); frames(st.frames); }
  m.keysOnly([]);
  const lim = m.total + ZX.T_FRAME * 3000;
  while (!(m.pc === SYM.MainLoopResetStack && !m.inIsr)) { if (m.total > lim) throw new Error('игра не началась'); step(m); }
  const plan = [];
  for (const st of sc.steps || []) for (let i = 0; i < st.ticks; i++) plan.push(st.keys || []);
  const rnd = sc.random ? rng(sc.random.seed) : null;
  let hold = 0, rkeys = [];
  const policy = sc.policy ? require(path.join(__dirname, 'policies', sc.policy.name + '.js'))(sc.policy, SYM) : null;
  const N = sc.ticks || plan.length;
  const pokes = new Map();
  for (const p of sc.pokes || []) pokes.set(p.tick, p.set);
  const applied = [];
  function keysFor(t) {
    if (t >= N) return null;
    applied.length = 0;
    const pk = pokes.get(t);
    if (pk) for (const [k, v] of Object.entries(pk)) {
      const a = k in SYM ? SYM[k] : parseInt(k, 16);
      const val = typeof v === 'string' && v[0] === '@' ? m.peek(SYM[v.slice(1)]) : v;
      m.poke(a, val); applied.push([a, val & 0xff]);
    }
    if (t < plan.length) return plan[t];
    if (policy) return policy(m, t);
    if (!rnd) return null;
    if (hold <= 0) {
      rkeys = sc.random.keys.filter(() => rnd() < (sc.random.p || 0.3));
      hold = sc.random.hold[0] + Math.floor(rnd() * (sc.random.hold[1] - sc.random.hold[0] + 1));
    }
    hold--; return rkeys;
  }
  return { m, keysFor, N, applied };
}

module.exports = { start, rng };
