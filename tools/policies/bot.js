// Политика «бот» для сценариев: собирает модули ракеты и топливо, несёт к ракете, улетает; стреляет.
// Цель: модуль/топливо (5D38) или предмет (5D40), которые лежат или падают; если несёт — к ракете; ракета
// заправлена — к ракете. Застрял — случайные клавиши. opts: { seed, fire: 0..1, jitter: 0..1 }
'use strict';
const { rng } = require('../scenario');
module.exports = (opts, S) => {
  const rnd = rng(opts.seed || 1);
  let lastX = -1, lastY = -1, still = 0, wander = 0, wkeys = [];
  return (m, t) => {
    const x = m.peek(S.jetman_pos_x), y = m.peek(S.jetman_pos_y);
    if (x === lastX && y === lastY) still++; else still = 0;
    lastX = x; lastY = y;
    if (wander > 0) { wander--; return wkeys; }
    if (still > 40) {
      still = 0; wander = 20 + Math.floor(rnd() * 40);
      wkeys = ['Z', 'X', 'Q', 'A'].filter(() => rnd() < 0.5);
      return wkeys;
    }
    const R = S.rocket_state;
    let tx = m.peek(R + 1), ty = 0xb0;
    const carrying = [S.rocket_module_state, S.item_state].some((o) => m.peek(o) === 4 && (m.peek(o + 4) & 2));
    if (!carrying && m.peek(R + 5) < 6) {
      for (const o of [S.rocket_module_state, S.item_state]) {
        const typ = m.peek(o);
        if ((typ === 4 && !(m.peek(o + 4) & 6)) || typ === 0x0e) { tx = m.peek(o + 1); ty = m.peek(o + 2); break; }
      }
    }
    const keys = [];
    const dx = (tx - x) << 24 >> 24;
    if (dx > 3) keys.push('X'); else if (dx < -3) keys.push('Z');
    if (ty < y - 2 || (Math.abs(dx) > 24 && y > 0x60)) keys.push('Q');
    if (rnd() < (opts.fire === undefined ? 0.5 : opts.fire)) keys.push('A');
    if (opts.jitter && rnd() < opts.jitter) return ['Z', 'X', 'Q', 'A', '3', 'P', 'M', 'N'].filter(() => rnd() < 0.4);
    return keys;
  };
};
