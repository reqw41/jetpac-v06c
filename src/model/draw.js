// Вывод Jetpac в модели — буквально, в раскладке экрана ZX (экран — состояние: лазер его читает).
// Регистры — общий файл M.r / M.r_ (см. core.js): процедуры вывода передают друг другу оба набора (exx).
'use strict';
const { S, rrc } = require('./core');

// Coord2Scr: HL = Y,X -> адрес экрана ZX
function coord2Scr(M) {
  const r = M.r, x = r.l, y = r.h;
  r.l = ((x >> 3) & 0x1f) | ((y << 2) & 0xe0);
  r.h = 0x40 | ((y >> 3) & 0x18) | (y & 7);
  r.a = r.h;
}

// Coord2AttrFile: HL = Y,X -> адрес атрибута; C = Y rlc 2
function coord2Attr(M) {
  const r = M.r, x = r.l, y = r.h;
  const c = ((y << 2) | (y >> 6)) & 0xff;
  r.c = c;
  r.l = ((x >> 3) & 0x1f) | (c & 0xe0);
  r.h = (c & 3) | 0x58;
  r.a = r.h;
}

function screenUp(M) {
  const r = M.r;
  r.h = (r.h - 1) & 0xff;
  r.a = r.h & 7;
  if (r.a !== 7) return;
  r.l = (r.l - 0x20) & 0xff;
  r.a = r.l & 0xe0;
  if (r.a === 0xe0) return;
  r.h = (r.h + 8) & 0xff; r.a = r.h;
}

// одна строка спрайта: стирание (AND NOT) или рисование (OR); DE идёт дальше, HL — строкой выше
function line(M, draw) {
  const r = M.r, b = r.b, c = r.c, h = r.h, l = r.l;
  let n = b;
  do {
    const s = M.rd(r.d << 8 | r.e), a = r.h << 8 | r.l;
    M.wr(a, draw ? s | M.rd(a) : ~s & M.rd(a));
    M.de = (M.de + 1) & 0xffff;
    r.l = (r.l + 1) & 0xff;
    if ((r.l & 0x1f) === 0) r.l = (r.l - 0x20) & 0xff;
    n = (n - 1) & 0xff;
  } while (n);
  r.h = h; r.l = l;
  screenUp(M);
  r.b = b; r.c = c;
}

// MaskSprite и хвосты ActorUpdateSize*: построчно стирает старый кадр (набор, где C — строк стереть) и рисует
// новый (другой набор). entry: 'mask' | 'size' | 'sizeFlip' | 'heightMask' (a — высота для actor+6)
function maskLoop(M, entry, a) {
  const r = M.r;
  let st = entry;
  for (;;) {
    switch (st) {
      case 'mask':
        if (r.c) {
          r.c = (r.c - 1) & 0xff; line(M, false);
          M.exx();
          if (!r.c) { M.exx(); continue; }
          st = 'draw'; continue;
        }
        M.exx();
        if (r.c) { st = 'draw'; continue; }
        st = 'sizeFlip'; continue;
      case 'draw':
        r.c = (r.c - 1) & 0xff; line(M, true);
        M.exx(); st = 'mask'; continue;
      case 'sizeFlip':
        M.exx(); st = 'size'; continue;
      case 'size':
        r.c = M.rd(S.actor + 5);
        if (!(M.rd(S.actor + 6) | r.c)) { r.a = 0; return; }
        M.wr(S.actor + 5, 0);
        M.exx();
        r.c = M.rd(S.actor + 6);
        a = 0; st = 'heightMask'; continue;
      case 'heightMask':
        M.wr(S.actor + 6, a); r.a = a;
        M.exx(); st = 'mask'; continue;
    }
  }
}

// ActorGetSpriteAddress: A = направление, C = X&6 -> DE = спрайт из jetman_sprite_table
function actorGetSpriteAddress(M, a) {
  const r = M.r;
  if (a & 0x40) r.c |= 8;
  a = ((a - 1) << 4) & 0xf0;
  r.c = a | r.c; r.b = 0;
  const p = S.jetman_sprite_table + r.c;
  r.e = M.rd(p); r.d = M.rd(p + 1);
  M.hl = p + 1; r.a = a | (r.c & 0x0f);
}
function actorFindPosDir(M) { M.r.c = M.rd(S.actor) & 6; actorGetSpriteAddress(M, M.rd(S.actor + 2)); }
function actorMoveSprite(M, ix) { M.r.c = M.rd(ix + 1) & 6; actorGetSpriteAddress(M, M.rd(ix)); }

// GetSpritePosition: DE = заголовок спрайта, HL = Y,X -> HL экран, B ширина, C = 0, DE данные, actor+5 высота
function getSpritePosition(M) {
  const r = M.r;
  r.a = M.rd(M.de); M.de = (M.de + 1) & 0xffff;
  r.l = (r.a + r.l) & 0xff;
  coord2Scr(M);
  r.b = M.rd(M.de); M.de = (M.de + 1) & 0xffff;
  r.a = M.rd(M.de); M.wr(S.actor + 5, r.a);
  r.c = 0; M.de = (M.de + 1) & 0xffff;
}
function getActorLocation(M) { M.hl = M.rd16(S.actor); getSpritePosition(M); }
function jumpActorFindPosDir(M) { actorFindPosDir(M); getActorLocation(M); }

// ActorUpdate: новый кадр по (ix): HL экран, B ширина, C = 0, DE данные; actor_coords, actor+3/4/6
function actorUpdate(M, ix) {
  const r = M.r;
  r.l = M.rd(ix + 1); r.h = M.rd(ix + 2);
  r.a = M.rd(M.de); M.de = (M.de + 1) & 0xffff;
  r.l = (r.a + r.l) & 0xff;
  M.wr16(S.actor_coords, M.hl);
  coord2Scr(M);
  r.a = M.rd(M.de); r.b = r.a; M.wr(S.actor + 4, r.a);
  M.de = (M.de + 1) & 0xffff;
  r.a = M.rd(M.de); M.wr(S.actor + 6, r.a); M.wr(S.actor + 3, r.a);
  r.c = 0; M.de = (M.de + 1) & 0xffff;
}
function findActorSpriteAndUpdate(M, ix) { actorMoveSprite(M, ix); actorUpdate(M, ix); }

function actorEraseMovedSprite(M, ix) {
  const r = M.r;
  const a = (M.rd(S.actor + 1) - M.rd(ix + 2)) & 0xff;
  if (a === 0) return maskLoop(M, 'size');
  if (!(a & 0x80)) {
    r.c = a;
    const h = M.rd(S.actor + 5);
    if (h < r.c) return maskLoop(M, 'size');
    M.wr(S.actor + 5, h - r.c);
    return maskLoop(M, 'mask');
  }
  M.exx();
  r.c = (-a) & 0xff;
  const h = M.rd(S.actor + 6);
  if (h < r.c) return maskLoop(M, 'sizeFlip');
  return maskLoop(M, 'heightMask', h - r.c);
}

function updateAndEraseActor(M, ix) {
  findActorSpriteAndUpdate(M, ix);
  M.exx();
  jumpActorFindPosDir(M);
  actorEraseMovedSprite(M, ix);
}
// ActorUpdatePosition: DE = спрайт; старый и новый кадр — один и тот же спрайт
function actorUpdatePosition(M, ix) {
  const de = M.de;
  getActorLocation(M);
  M.exx();
  M.de = de;
  actorUpdate(M, ix);
  M.exx();
  actorEraseMovedSprite(M, ix);
}
function eraseAnimationSprite(M) { M.exx(); M.wr(S.actor + 5, 0); M.r.c = 0; M.r.a = 0; maskLoop(M, 'mask'); }
function actorEraseAnimSprite(M, ix) { actorUpdate(M, ix); eraseAnimationSprite(M); }
function actorEraseDestroyed(M) {
  M.exx(); M.r.a = 0; M.r.c = 0;
  M.wr(S.actor + 6, 0); M.wr(S.actor + 3, 0);
  M.exx(); maskLoop(M, 'mask');
}
function actorDestroy(M) { getActorLocation(M); actorEraseDestroyed(M); }
function actorFindDestroy(M) { jumpActorFindPosDir(M); actorEraseDestroyed(M); }

// ColourizeSprite (exx в начале — наборы остаются переставленными)
function colourizeSprite(M, ix) {
  M.exx();
  const r = M.r;
  M.hl = M.rd16(S.actor_coords);
  coord2Attr(M);
  r.b = M.rd(S.actor + 4);
  let a = M.rd(S.actor + 3);
  a = rrc(rrc(a)); a = (a + 1) & 0xff; a = rrc(a); a &= 0x1f; a = (a + 1) & 0xff;
  r.c = a; r.d = M.rd(ix + 3); r.e = r.b;
  do {
    const hl = M.hl;
    for (;;) {
      r.a = r.h;
      if (r.a >= 0x5b || r.a < 0x58) break;
      M.wr(M.hl, r.d);
      r.l = (r.l + 1) & 0xff;
      if ((r.l & 0x1f) === 0) r.l = (r.l - 0x20) & 0xff;
      r.b = (r.b - 1) & 0xff;
      if (!r.b) break;
    }
    M.hl = (hl - 0x20) & 0xffff;
    r.b = r.e;
    r.c = (r.c - 1) & 0xff;
  } while (r.c);
}

// --- текст -------------------------------------------------------------------------------------------
// DrawCharPixels: B строк из DE в экран HL; восстанавливает DE, BC из «стека» (de0, bc0)
function drawCharPixels(M, de0, bc0) {
  const r = M.r;
  do {
    r.a = M.rd(M.de); M.wr(M.hl, r.a);
    M.de = (M.de + 1) & 0xffff;
    r.h = (r.h + 1) & 0xff;
    r.b = (r.b - 1) & 0xff;
  } while (r.b);
  M.de = de0; M.bc = bc0;
  r.h = (r.h - 8) & 0xff; r.a = r.h;
  r.l = (r.l + 1) & 0xff;
}
function drawFontChar(M, a) {
  const bc0 = M.bc, de0 = M.de, hl0 = M.hl;
  const base = M.rd16(S.DrawFontChar + 10);       // ld de,system_font-$0100 (оригинал: $3A00 — ПЗУ картриджа)
  M.de = ((a << 3) + base) & 0xffff;
  M.hl = hl0;
  M.r.b = 8;
  drawCharPixels(M, de0, bc0);
}
function drawPlatformTile(M) { const bc0 = M.bc, de0 = M.de; M.r.b = 8; drawCharPixels(M, de0, bc0); }

function writeAsciiChars(M) {
  const r = M.r;
  for (;;) {
    M.exx();
    r.a = M.rd(M.de);
    if (r.a & 0x80) {
      r.a &= 0x7f; drawFontChar(M, r.a);
      M.exx(); M.exaf(); M.wr(M.hl, r.a);
      return;
    }
    drawFontChar(M, r.a);
    M.de = (M.de + 1) & 0xffff;
    M.exx(); M.exaf();
    M.wr(M.hl, r.a);
    r.l = (r.l + 1) & 0xff;
    M.exaf();
  }
}
// DisplayString: HL = Y,X, DE = строка (первый байт — цвет)
function displayString(M) {
  const hl = M.hl;
  coord2Scr(M);
  M.r.a = M.rd(M.de); M.exaf();
  M.de = (M.de + 1) & 0xffff;
  M.exx();
  M.hl = hl;
  coord2Attr(M);
  writeAsciiChars(M);
}
function menuWriteText(M) {
  const hl = M.hl;
  coord2Scr(M);
  M.r.a = M.rd(S.current_colour_attr); M.exaf();
  M.exx();
  M.hl = hl;
  coord2Attr(M);
  writeAsciiChars(M);
}

function displayScore(M, hl, de) {
  const r = M.r;
  M.hl = hl; M.de = de; r.b = 3;
  do {
    r.a = M.rd(M.de);
    drawFontChar(M, ((rrc(rrc(rrc(rrc(r.a)))) & 0x0f) + 0x30) & 0xff);
    r.a = M.rd(M.de);
    drawFontChar(M, ((r.a & 0x0f) + 0x30) & 0xff);
    M.de = (M.de + 1) & 0xffff;
    r.b = (r.b - 1) & 0xff;
  } while (r.b);
}
const showScoreP1 = (M) => displayScore(M, 0x4021, S.p1_score);
const showScoreP2 = (M) => displayScore(M, 0x4039, S.p2_score);
const showScoreHI = (M) => displayScore(M, 0x402d, S.hi_score);

function drawStatusBarLabels(M) {
  M.hl = 0x0018; M.de = S.ScoreLabel1UP; displayString(M);
  M.hl = 0x0078; M.de = S.ScoreLabelHI; displayString(M);
  M.hl = 0x00d8; M.de = S.ScoreLabel2UP; displayString(M);
}

// MemoryFill: от HL до старшего байта B байтом C
function memoryFill(M) {
  const r = M.r;
  do {
    M.wr(M.hl, r.c);
    M.hl = (M.hl + 1) & 0xffff;
    r.a = r.h;
  } while (r.a < r.b);
}
function clearScreen(M) { M.hl = 0x4000; M.r.b = 0x58; M.r.c = 0; memoryFill(M); }
function clearAttrFile(M) { M.hl = 0x5800; M.r.b = 0x5b; M.r.c = 0x47; memoryFill(M); }

function resetScreen(M) {
  const r = M.r;
  clearScreen(M); clearAttrFile(M);
  drawStatusBarLabels(M);
  M.hl = 0x5820; r.b = 0x20; r.c = 0x46;
  do { M.wr(M.hl, r.c); r.l = (r.l + 1) & 0xff; r.b = (r.b - 1) & 0xff; } while (r.b);
  showScoreP1(M); showScoreP2(M); showScoreHI(M);
}

function drawPlatforms(M) {
  const r = M.r;
  let p = S.gfx_params_platforms;
  for (let k = 0; k < 4; k++, p += 4) {
    const col = M.rd(p);
    if (!col) continue;
    const x = M.rd(p + 1), y = M.rd(p + 2);
    const xs = ((-(M.rd(p + 3) & 0xfc)) + x + 0x10) & 0xff;
    r.c = x;
    r.h = y; r.l = xs;
    coord2Scr(M);
    M.de = S.tile_platform_left; drawPlatformTile(M);
    r.b = ((M.rd(p + 3) >> 2) - 4) & 0xff;
    M.de = S.tile_platfor_mmiddle;
    do { drawPlatformTile(M); r.b = (r.b - 1) & 0xff; } while (r.b);
    M.de = S.tile_platform_right; drawPlatformTile(M);
    r.h = y; r.l = xs;
    coord2Attr(M);
    r.b = ((M.rd(p + 3) >> 2) - 2) & 0xff;
    r.c = col; r.a = col;
    do { M.wr(M.hl, col); M.hl = (M.hl + 1) & 0xffff; r.b = (r.b - 1) & 0xff; } while (r.b);
  }
}

// DisplayPlayerLives
function displayPlayerLives(M, P1, P2) {
  const r = M.r;
  const one = (cnt) => {
    if (!cnt) { drawFontChar(M, 0x20); drawFontChar(M, 0x20); return; }
    drawFontChar(M, (cnt + 0x30) & 0xff);
    const bc0 = M.bc; M.de = S.tile_life_icon;
    r.b = 8; drawCharPixels(M, S.tile_life_icon, bc0);
  };
  M.hl = 0x0040; coord2Scr(M); one(P1(M));
  M.hl = 0x00b0; coord2Scr(M); one(P2(M));
}

module.exports = {
  coord2Scr, coord2Attr, screenUp, maskLoop, actorGetSpriteAddress, actorFindPosDir, actorMoveSprite,
  getSpritePosition, getActorLocation, jumpActorFindPosDir, actorUpdate, findActorSpriteAndUpdate,
  actorEraseMovedSprite, updateAndEraseActor, actorUpdatePosition, eraseAnimationSprite, actorEraseAnimSprite,
  actorEraseDestroyed, actorDestroy, actorFindDestroy, colourizeSprite, drawCharPixels, drawFontChar,
  drawPlatformTile, writeAsciiChars, displayString, menuWriteText, displayScore, showScoreP1, showScoreP2,
  showScoreHI, drawStatusBarLabels, memoryFill, clearScreen, clearAttrFile, resetScreen, drawPlatforms,
  displayPlayerLives,
};
