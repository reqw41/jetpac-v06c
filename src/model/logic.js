// Логика Jetpac в модели: объекты главного цикла (Джетмен, лазеры, ракета, предметы, пришельцы, взрывы),
// уровни и ходы игроков, счёт, ввод. Повторяет картриджный код (build/jetpac_z80.asm) по подпрограммам;
// где код опирается на регистры вывода — через общий регистровый файл M.r (см. core.js, draw.js).
'use strict';
const { S, GameOver, neg, rrc, rlc, addDaa } = require('./core');
const D = require('./draw');

const E = module.exports = {};
const JM = S.jetman_motion;
const FRAMES = 0x5c78;
const bit = (M, a, n) => (M.rd(a) >> n) & 1;
const set = (M, a, n) => M.wr(a, M.rd(a) | (1 << n));
const res = (M, a, n) => M.wr(a, M.rd(a) & ~(1 << n));
const inc = (M, a) => { const v = (M.rd(a) + 1) & 0xff; M.wr(a, v); return v; };
const dec = (M, a) => { const v = (M.rd(a) - 1) & 0xff; M.wr(a, v); return v; };
E.copy = function copy(M, src, dst, n) { for (let i = 0; i < n; i++) M.wr(dst + i, M.rd(src + i)); M.hl = src + n; M.de = dst + n; M.bc = 0; }

// --- звук (только запись входа: имя и регистры) ------------------------------------------------------
E.playSquareWave1 = function playSquareWave1(M) { M.sound('PlaySquareWave1'); const r = M.r; r.a = 0; r.b = 0; r.c = 0; }
E.playSquareWav2 = function playSquareWav2(M) { M.sound('PlaySquareWav2'); const r = M.r; r.a = 0; r.b = 0; r.c = 0; }
E.sfxPlayExplosion = function sfxPlayExplosion(M) { M.sound('SfxPlayExplosion'); const r = M.r; r.a = 0; r.b = 0; r.c = 0; }
E.sfxLaserFire = function sfxLaserFire(M) { M.sound('SfxLaserFire'); const r = M.r; r.c = 0x38; r.a = 0x38; r.b = 0; }
E.sfxThrusters = function sfxThrusters(M, ix) {
  const r = M.r;
  r.d = (rrc(rrc(rrc(rrc(M.rd(ix + 2))))) & 0x7f) | 0x40; r.c = 0x10;
  E.playSquareWav2(M);
}
E.sfxRocketBuild = function sfxRocketBuild(M) { M.r.d = 0x20; M.r.c = 0x50; E.playSquareWav2(M); }
E.sfxPickupFuel = function sfxPickupFuel(M) { M.r.d = 0x50; M.r.c = 0x28; E.playSquareWav2(M); }
E.sfxPickupItem = function sfxPickupItem(M) { M.r.d = 0x30; M.r.c = 0x40; E.playSquareWave1(M); }
E.sfxSetExplodeParams = function sfxSetExplodeParams(M, a) {
  const r = M.r;
  r.c = (a << 1) & 0xff; r.b = 0;
  M.de = S.explosion_sfx_params; M.hl = S.explosion_sfx_defaults + r.c;
  M.wr(M.de, M.rd(M.hl)); M.wr(M.de + 1, M.rd(M.hl + 1));
  r.a = M.rd(M.hl + 1); M.hl = M.hl + 1; M.de = M.de + 1;
}
E.sfxFinishReturn = function sfxFinishReturn(M, ix) { M.wr(ix, 0); }
E.sfxJetmanDeath = function sfxJetmanDeath(M, ix) {
  if (!dec(M, ix + 1)) return E.sfxFinishReturn(M, ix);
  M.r.c = 0x10; E.sfxPlayExplosion(M);
}
E.sfxEnemyDeath = function sfxEnemyDeath(M, ix) {
  if (!dec(M, ix + 1)) return E.sfxFinishReturn(M, ix);
  M.r.c = (M.rd(ix + 1) + 0x18) & 0xff; E.sfxPlayExplosion(M);
}

// --- ввод ---------------------------------------------------------------------------------------------
E.readI2 = function readI2(M) { return (M.r.a = M.inp(0xeffe)); }
E.readInputLR = function readInputLR(M) {
  if (M.rd(S.game_options) & 2) return E.readI2(M);
  let a = M.inp(0xfefe) & 0x1e;
  if (a !== 0x1e) return (M.r.a = (a & 0x14) === 0x14 ? 0xef : 0xf7);
  a = M.inp(0x7ffe) & 0x1e;
  if (a === 0x1e) return (M.r.a = 0xff);
  return (M.r.a = (a & 0x14) === 0x14 ? 0xf7 : 0xef);
}
E.readRows = function readRows(M, r1, r2, hit) {
  if (M.rd(S.game_options) & 2) return E.readI2(M);
  const r = M.r;
  r.b = 2;
  let row = r1;
  do {
    if ((M.inp(row << 8 | 0xfe) & 0x1f) !== 0x1f) return (r.a = hit);
    row = r2; r.b = (r.b - 1) & 0xff;
  } while (r.b);
  return (r.a = 0xff);
}
const readInputFire = (M) => E.readRows(M, 0xfd, 0xbf, 0xfe);
const readInputThrust = (M) => E.readRows(M, 0xfb, 0xdf, 0xfd);

// --- общие подпрограммы объектов ---------------------------------------------------------------------
E.tmpActorPosUpdate = function tmpActorPosUpdate(M, ix) {
  M.wr(S.actor, M.rd(ix + 1)); M.wr(S.actor + 1, M.rd(ix + 2));
  M.r.a = M.rd(ix); M.wr(S.actor + 2, M.r.a);
}
E.actorUpdateDir = function actorUpdateDir(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  M.r.a = (M.rd(ix) & 0xc0) | 3; M.wr(S.actor + 2, M.r.a);
}

// PlatformCollisionCheckAll -> E (бит 2 — касание, 7 — сверху, 4 — снизу, 6 — слева, 3 — край)
E.platformCollisionCheckAll = function platformCollisionCheckAll(M, ix) {
  const r = M.r;
  r.b = 4;
  let p = S.gfx_params_platforms;
  for (;;) {
    r.e = 0;
    let a = (M.rd(p + 1) - M.rd(ix + 1)) & 0xff;
    if (!(a & 0x80)) {
      const t = M.rd(ix) & 0x3f;
      M.r_.a = t;
      if (t === 3) { const a2 = (a - 9) & 0xff; if (!(a2 & 0x80)) a = a2; }
    } else { a = neg(a); r.e |= 0x40; }
    const w = M.rd(p + 3);
    if (a < w) {
      a = (a + 0x12) & 0xff;
      if (a >= w) r.e |= 8;
      a = (neg((M.rd(p + 2) - M.rd(ix + 2)) & 0xff) + 2) & 0xff;
      if (!(a & 0x80)) {
        const h = M.rd(ix + 7);
        let hit = false;
        if (a < 2) { r.e |= 0x80; hit = true; }
        else if (a < h) hit = true;
        else { a = (a - 2) & 0xff; if (a < h) { r.e |= 0x10; hit = true; } }
        if (hit) { r.e |= 4; r.a = a; M.hl = p; return r.e; }
      }
    }
    p += 4;
    r.b = (r.b - 1) & 0xff;
    if (!r.b) { r.a = a; M.hl = p; return r.e; }
  }
}

// AlienCollision -> E = 1 при столкновении с Джетменом
E.alienCollision = function alienCollision(M, ix) {
  const r = M.r;
  r.e = 0; M.hl = JM;
  let a = M.rd(JM) & 0x3f;
  if (a !== 1 && a !== 2) return 0;
  a = (M.rd(JM + 1) - M.rd(ix + 1)) & 0xff;
  if (a & 0x80) a = neg(a);
  if (a >= 0x0c) return 0;
  a = (M.rd(JM + 2) - M.rd(ix + 2)) & 0xff;
  if (!(a & 0x80)) r.d = 0x15;
  else { a = neg(a); r.d = M.rd(ix + 7); a = (a + 0x0e) & 0xff; }
  if (a >= r.d) return 0;
  return (r.e = 1);
}

// LaserBeamFire -> C = 1, если пришельца задел лазер
E.laserBeamFire = function laserBeamFire(M, ix) {
  const r = M.r;
  r.b = 4; M.de = 8;
  for (let p = S.laser_beam_params; ; p += 8) {
    if (M.rd(p)) {
      let a = M.rd(p + 3);
      if (a & 4) {
        a = ((a & 0xf8) - M.rd(ix + 1)) & 0xff;
        if (a & 0x80) { a = neg(a); r.c = 8; } else r.c = 0x20;
        if (a < r.c) {
          a = neg((M.rd(p + 1) - M.rd(ix + 2)) & 0xff);
          if (!(a & 0x80)) {
            a = (a + 0x0c) & 0xff;
            if (a < M.rd(ix + 7)) {
              r.c = 1;
              M.wr(p + 2, M.rd(p + 2) & 0xf8);
              M.hl = p; return 1;
            }
          }
        }
      }
    }
    r.b = (r.b - 1) & 0xff;
    if (!r.b) { M.hl = p + 8; r.c = 0; return 0; }
  }
}

E.addPointsToScore = function addPointsToScore(M, bc) {
  const r = M.r;
  M.bc = bc;
  const p = M.rd(S.current_player_number) ? S.p2_score : S.p1_score;
  let [a, c] = addDaa(M.rd(p + 2), r.c, false); M.wr(p + 2, a);
  [a, c] = addDaa(M.rd(p + 1), r.b, c); M.wr(p + 1, a);
  [a, c] = addDaa(M.rd(p), 0, c); M.wr(p, a);
  if (M.rd(S.current_player_number)) D.showScoreP2(M); else D.showScoreP1(M);
}

E.setObjectInactive = function setObjectInactive(M, p, n) { do { M.wr(p, 0); p += 8; n = (n - 1) & 0xff; } while (n); M.r.b = 0; M.de = 8; M.hl = p; }

E.animationEnable = function animationEnable(M, ix, a) { M.wr(ix + 6, a); M.wr(ix, 8); M.wr(ix + 4, 0); }
E.animationStateReset = function animationStateReset(M, ix) {
  M.r.a = (M.rd(ix) & 0xc0) | 3;
  M.wr(ix + 5, 0); E.animationEnable(M, ix, M.r.a);
}
E.animationStateSet = function animationStateSet(M, ix, a) { M.wr(ix + 5, 1); E.animationEnable(M, ix, a); }

E.explosionAfterKill = function explosionAfterKill(M) {
  const ex = S.jetman_exploding_anim_state;
  M.r.c = M.rd(JM);
  M.wr(ex + 1, M.rd(JM + 1)); M.wr(ex + 2, M.rd(JM + 2));
  M.hl = JM + 2;
  E.animationStateSet(M, ex, M.r.c);
  M.r.a = 0; M.wr(JM, 0);
}
E.alienCollisionAnimSfx = function alienCollisionAnimSfx(M, ix) {
  E.animationStateReset(M, ix);
  E.sfxSetExplodeParams(M, 1);
  E.explosionAfterKill(M);
}
E.alienKillAnimSfx1 = function alienKillAnimSfx1(M, ix) { E.animationStateReset(M, ix); E.sfxSetExplodeParams(M, 0); }
E.alienKillAnimSfx2 = function alienKillAnimSfx2(M, ix, bc) { E.addPointsToScore(M, bc); E.animationStateReset(M, ix); E.sfxSetExplodeParams(M, 1); }

// --- спрайты в буферы (сдвиги и зеркало) ------------------------------------------------------------
E.reverseBits = function reverseBits(a) { let c = 0; for (let i = 0; i < 8; i++) { c = (c << 1) | (a & 1); a >>= 1; } return c & 0xff; }
E.spriteReadTwoBytes = function spriteReadTwoBytes(M) {
  const r = M.r;
  r.a = r.b; M.exaf();
  r.e = 0; r.c = M.rd(M.hl); M.hl = (M.hl + 1) & 0xffff; r.d = M.rd(M.hl); M.hl = (M.hl + 1) & 0xffff;
  r.a = r.b;
  if (!r.a) return;
  do {
    const c0 = r.c & 1; r.c >>= 1;
    const d0 = r.d & 1; r.d = (r.d >> 1) | (c0 << 7);
    r.e = (r.e >> 1) | (d0 << 7);
    r.b = (r.b - 1) & 0xff;
  } while (r.b);
  M.exaf(); r.b = r.a;
}
E.bufferFlipSprite = function bufferFlipSprite(M) {
  const r = M.r;
  r.a = r.b; M.exaf();
  r.c = 0;
  r.e = E.reverseBits(M.rd(M.hl)); M.hl = (M.hl + 1) & 0xffff;
  r.d = E.reverseBits(M.rd(M.hl)); M.hl = (M.hl + 1) & 0xffff;
  r.a = r.b;
  if (!r.a) return;
  do {
    const e7 = r.e >> 7; r.e = (r.e << 1) & 0xff;
    const d7 = r.d >> 7; r.d = ((r.d << 1) | e7) & 0xff;
    r.c = ((r.c << 1) | d7) & 0xff;
    r.b = (r.b - 1) & 0xff;
  } while (r.b);
  M.exaf(); r.b = r.a;
}
E.bufferWritePixel = function bufferWritePixel(M) {
  const r = M.r;
  do {
    M.exx();
    r.a = M.rd(S.jetman_rocket_mod_connected);
    if (r.a) E.bufferFlipSprite(M); else E.spriteReadTwoBytes(M);
    const de = M.de, bc = M.bc;
    M.exx();
    M.wr(M.hl, bc & 0xff); M.hl = (M.hl + 1) & 0xffff;
    M.wr(M.hl, de >> 8); M.hl = (M.hl + 1) & 0xffff;
    M.wr(M.hl, de & 0xff); M.hl = (M.hl + 1) & 0xffff;
    M.de = de;
    r.b = (r.b - 1) & 0xff;
  } while (r.b);
}
// BufferCopySprite / BufferCopyRocketSpriteData: HL = указатель в таблице спрайтов, DE = буфер, B = сдвиг, C = число
E.bufferCopySprite = function bufferCopySprite(M, rocket) {
  const r = M.r;
  for (;;) {
    const sHL = M.hl, sDE = M.de, sBC = M.bc;
    let p = M.rd16(M.hl);
    if (rocket) p = (p + 2) & 0xffff;
    M.hl = p;
    const spr = M.hl; M.hl = M.de; M.de = spr;
    M.exx();
    M.hl = spr; M.bc = sBC;
    r.a = M.rd(M.hl); M.exaf();
    M.hl = (M.hl + 1) & 0xffff;
    M.exx();
    M.wr(M.hl, 0); M.hl = (M.hl + 1) & 0xffff;
    M.wr(M.hl, 3); M.hl = (M.hl + 1) & 0xffff;
    M.exaf();
    if (r.a >= 0x11) r.a = 0x10;
    M.wr(M.hl, r.a); M.hl = (M.hl + 1) & 0xffff;
    r.b = r.a;
    E.bufferWritePixel(M);
    M.bc = sBC;
    M.hl = (sDE + 0x33) & 0xffff;
    M.de = (sHL + 2) & 0xffff;
    { const t = M.hl; M.hl = M.de; M.de = t; }
    r.a = (M.rd(S.rocket_mod_attached) + r.b) & 0xff; r.b = r.a;
    r.c = (r.c - 1) & 0xff;
    if (!r.c) return;
    rocket = false;
  }
}
E.bufferCopyRocket = function bufferCopyRocket(M, a) {
  const r = M.r;
  r.c = a;
  r.a = (rrc(M.rd(S.player_level)) & 6) | r.c; r.c = r.a; r.b = 0;
  M.hl = S.collectible_sprite_table + r.c;
  M.de = S.buffers_item_1;
  M.wr(S.rocket_mod_attached, 2);
  M.wr(S.jetman_rocket_mod_connected, 0);
  r.c = 4; r.a = 0;
  do {
    const bc = M.bc;
    r.b = r.a; r.c = 1;
    E.bufferCopySprite(M, true);
    r.a = r.b;
    M.bc = bc;
    M.hl = (M.hl - 2) & 0xffff;
    r.c = (r.c - 1) & 0xff;
  } while (r.c);
}
E.alienBufferInit = function alienBufferInit(M) {
  const tbl = S.alien_sprite_table + (rlc(rlc(M.rd(S.player_level))) & 0x1c);
  M.hl = tbl; M.de = S.buffers_aliens_R1;
  M.bc = 2; M.wr(S.rocket_mod_attached, 4); M.wr(S.jetman_rocket_mod_connected, 0);
  E.bufferCopySprite(M, false);
  M.hl = tbl; M.de = S.buffers_aliens_L1;
  M.bc = 2; M.r.a = M.rd(S.rocket_mod_attached); M.wr(S.jetman_rocket_mod_connected, 1);
  E.bufferCopySprite(M, false);
}

// --- предметы ---------------------------------------------------------------------------------------
E.itemGetSpriteAddress = function itemGetSpriteAddress(M, a) {
  const r = M.r;
  r.c = a; r.b = 0; M.hl = S.collectible_sprite_table + a;
  r.e = M.rd(M.hl); M.hl = M.hl + 1; r.d = M.rd(M.hl);
}
const itemGetSpriteAddressAttrOffset = (M, ix, a) => E.itemGetSpriteAddress(M, (a + M.rd(ix + 6)) & 0xff);
E.itemDisplaySprite = function itemDisplaySprite(M, ix) {
  itemGetSpriteAddressAttrOffset(M, ix, 0);
  D.actorUpdatePosition(M, ix);
  D.colourizeSprite(M, ix);
}
E.itemDropGoldBar = function itemDropGoldBar(M, ix) { M.wr(ix + 3, 0x46); E.itemDisplaySprite(M, ix); }
E.itemDropPlutonium = function itemDropPlutonium(M, ix) { M.wr(ix + 3, 0x44); E.itemDisplaySprite(M, ix); }
E.itemDropChemical = function itemDropChemical(M, ix) { M.wr(ix + 3, (M.rd(S.game_timer) & 0x1f) >= 0x18 ? 0x45 : 0); E.itemDisplaySprite(M, ix); }
E.itemDropRandomColour = function itemDropRandomColour(M, ix) {
  let a = rrc(rrc(M.rd(S.game_timer))) & 7;
  if (!a) a = 1;
  M.wr(ix + 3, a | 0x40); E.itemDisplaySprite(M, ix);
}
E.itemCheckCollect = function itemCheckCollect(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  if (!(E.platformCollisionCheckAll(M, ix) & 4)) { inc(M, ix + 2); inc(M, ix + 2); }
  if (E.alienCollision(M, ix) !== 1) return E.dispatch(M, ix, S.item_drop_jump_table, M.rd(ix + 6) & 0x0f);
  itemGetSpriteAddressAttrOffset(M, ix, 0);
  D.actorDestroy(M);
  M.wr(ix, 0);
  E.addPointsToScore(M, 0x0250);
  E.sfxPickupItem(M);
}
E.redrawSprite = function redrawSprite(M, ix) { D.updateAndEraseActor(M, ix); D.colourizeSprite(M, ix); }
E.incYRedrawSprite = function incYRedrawSprite(M, ix) { inc(M, ix + 2); inc(M, ix + 2); E.redrawSprite(M, ix); }
E.itemPickup = function itemPickup(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  const a = M.rd(ix + 4);
  if (a & 4) return E.pickupRocketItem(M, ix);
  if (a & 2) return E.carryRocketItem(M, ix);
  if (!(a & 1)) {
    itemGetSpriteAddressAttrOffset(M, ix, rrc(M.rd(S.player_level)) & 6);
    D.actorEraseAnimSprite(M, ix);
    return D.colourizeSprite(M, ix);
  }
  if (E.alienCollision(M, ix) === 1) return E.collectRocketItem(M, ix);
  if (E.platformCollisionCheckAll(M, ix) & 4) return E.redrawSprite(M, ix);
  E.incYRedrawSprite(M, ix);
}
E.attachToJetman = function attachToJetman(M, ix) { M.hl = M.rd16(S.jetman_pos_x); M.wr(ix + 1, M.r.l); M.wr(ix + 2, M.r.h); }
E.collectRocketItem = function collectRocketItem(M, ix) {
  set(M, ix + 4, 1);
  D.actorFindDestroy(M);
  E.addPointsToScore(M, 0x0100);
  E.sfxPickupFuel(M);
  E.attachToJetman(M, ix);
  E.tmpActorPosUpdate(M, ix);
  E.redrawSprite(M, ix);
}
E.carryRocketItem = function carryRocketItem(M, ix) {
  E.attachToJetman(M, ix);
  let a = (M.rd(S.rocket_state + 1) - M.rd(ix + 1)) & 0xff;
  if (a & 0x80) a = neg(a);
  if (a >= 6) return E.redrawSprite(M, ix);
  set(M, ix + 4, 2);
  M.wr(ix + 1, M.rd(S.rocket_state + 1));
  E.redrawSprite(M, ix);
}
E.pickupRocketItem = function pickupRocketItem(M, ix) {
  let a = M.rd(ix + 6);
  if (a === 0x18) {
    if (M.rd(ix + 2) < 0xb0) return E.incYRedrawSprite(M, ix);
    inc(M, S.rocket_state + 5);
  } else {
    a = (((a << 1) & 0xff) + M.rd(ix + 2)) & 0xff;
    if (a < 0xb7) return E.incYRedrawSprite(M, ix);
    M.wr(S.rocket_module_state + 4, M.rd(S.rocket_module_state + 4) | 1);
    inc(M, S.rocket_state + 4);
    E.bufferCopyRocket(M, (M.rd(ix + 6) + 8) & 0xff);
  }
  D.actorFindDestroy(M);
  M.wr(ix, 0);
  E.sfxRocketBuild(M);
}
E.itemCalcDropColumn = function itemCalcDropColumn(M) {
  const r = M.r;
  r.c = M.rd(S.random_number) & 0x0f; r.b = 0;
  M.hl = S.item_drop_positions_table + r.c;
  return (r.a = M.rd(M.hl));
}
E.jetmanFlyingSlow = function jetmanFlyingSlow(M) { const a = M.rd(JM) & 0x3f; return a !== 0 && a < 3; }
E.itemNewCollectible = function itemNewCollectible(M) {
  if (!E.jetmanFlyingSlow(M)) return;
  if (M.rd(S.item_state)) return;
  if (M.rd(S.game_timer) & 0x7f) return;
  E.copy(M, S.default_item_state, S.item_state, 8);
  M.wr(S.item_state + 1, E.itemCalcDropColumn(M));
  let a = M.ldar() & 0x0e;
  if (a & 8) a &= 8;
  M.wr(S.item_state + 6, a | 0x20);
}
E.itemNewFuelPod = function itemNewFuelPod(M) {
  if (!E.jetmanFlyingSlow(M)) return;
  if (M.rd(S.rocket_module_state)) return;
  if (M.rd(S.rocket_state + 5) >= 6) return;
  if ((~M.rd(S.game_timer)) & 0x0f) return;
  E.copy(M, S.default_rocket_module_state, S.rocket_module_state, 8);
  M.wr(S.rocket_module_state + 1, E.itemCalcDropColumn(M));
}

// --- ракета -----------------------------------------------------------------------------------------
E.rocketAnimateFlames = function rocketAnimateFlames(M, ix) {
  M.wr(ix + 2, (M.rd(ix + 2) + 0x15) & 0xff);
  M.wr(S.actor + 1, (M.rd(S.actor + 1) + 0x15) & 0xff);
  const y = M.rd(ix + 2);
  if (y === 0xb8) {
    M.de = S.gfx_rocket_flames1; D.actorDestroy(M);
    M.de = S.gfx_rocket_flames2; D.actorDestroy(M);
  } else if (y < 0xb8) {
    const de = (M.rd(S.game_timer) & 4) ? S.gfx_rocket_flames1 : S.gfx_rocket_flames2;
    M.de = S.gfx_rocket_flames1; D.actorDestroy(M);
    M.de = S.gfx_rocket_flames2; D.actorDestroy(M);
    M.de = de;
    D.actorEraseAnimSprite(M, ix);
    M.wr(ix + 3, 0x42);
    D.colourizeSprite(M, ix);
  }
  M.wr(ix + 2, (M.rd(ix + 2) - 0x15) & 0xff);
  M.wr(S.actor + 1, (M.rd(S.actor + 1) - 0x15) & 0xff);
}
E.rocketTakeoff = function rocketTakeoff(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  dec(M, ix + 2);
  E.sfxThrusters(M, ix);
  E.rocketAnimateFlames(M, ix);
  if (M.rd(ix + 2) >= 0x28) return E.updateRocketColour(M, ix);
  inc(M, S.player_level);
  E.setObjectInactive(M, S.rocket_module_state, 0x0c);
  inc(M, ix);
  M.wr(ix + 5, 0);
  E.levelNew(M);
}
E.rocketLanding = function rocketLanding(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  inc(M, ix + 2);
  E.sfxThrusters(M, ix);
  E.rocketAnimateFlames(M, ix);
  if (M.rd(ix + 2) >= 0xb7) { M.wr(ix, 9); E.playerInit(M); }
  E.updateRocketColour(M, ix);
}
E.rocketUpdate = function rocketUpdate(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  if (E.alienCollision(M, ix) !== 1 || M.rd(ix + 5) < 6) return E.updateRocketColour(M, ix);
  inc(M, ix);
  E.tmpActorPosUpdate(M, JM);
  D.actorFindDestroy(M);
  M.wr(JM, 0);
  inc(M, S.player_lives);
  E.displayPlayerLives(M);
}
E.updateRocketColour = function updateRocketColour(M, ix) {
  const r = M.r;
  r.l = M.rd(ix + 1); r.h = M.rd(ix + 2);
  const hl0 = M.hl;
  r.b = M.rd(ix + 4); r.c = 0;
  do {
    const bc = M.bc;
    E.itemGetSpriteAddress(M, (((rrc(rrc(M.rd(S.player_level))) & 3) | r.c) << 1) & 0xff);
    D.actorUpdatePosition(M, ix);
    M.bc = bc;
    M.wr(ix + 2, (M.rd(ix + 2) - 0x10) & 0xff);
    M.wr(S.actor + 1, (M.rd(S.actor + 1) - 0x10) & 0xff);
    r.c = (r.c + 4) & 0xff;
    r.b = (r.b - 1) & 0xff;
  } while (r.b);
  M.wr(S.actor + 4, 2); M.wr(S.actor + 3, 0);
  M.hl = hl0;
  M.wr(ix + 2, r.h);
  M.wr16(S.actor_coords, hl0);
  r.b = (M.rd(ix + 4) << 1) & 0xff;
  let colour = 0x47;
  const colourize = () => {
    do {
      const bc = M.bc;
      D.colourizeSprite(M, ix);
      M.bc = bc;
      M.hl = M.rd16(S.actor_coords);
      r.h = (r.h - 8) & 0xff;
      M.wr16(S.actor_coords, M.hl);
      r.b = (r.b - 1) & 0xff;
    } while (r.b);
  };
  if (r.b >= 6 && M.rd(ix + 5)) {
    const fuel = M.rd(ix + 5);
    const c = (rrc(rrc(M.rd(S.game_timer))) & 4) | 0x43;
    r.c = c;
    if (fuel >= 6) colour = c;
    else {
      r.b = fuel;
      M.wr(ix + 3, 0x43);
      colourize();
      r.b = (6 - M.rd(ix + 5)) & 0xff;
    }
  }
  M.wr(ix + 3, colour);
  colourize();
}

// --- взрывы и пустые места ---------------------------------------------------------------------------
E.animateExplosion = function animateExplosion(M, ix) {
  const r = M.r;
  inc(M, S.current_alien_number);
  const c = M.rd(ix + 4);
  r.b = M.rd(ix + 5);
  if (!(M.rd(S.game_timer) & r.b)) inc(M, ix + 4);
  r.c = (c << 1) & 0xff; r.b = 0;
  M.hl = S.explosion_sprite_table + r.c;
  r.e = M.rd(M.hl); M.hl = M.hl + 1; r.d = M.rd(M.hl);
  r.l = M.rd(ix + 1); r.h = M.rd(ix + 2);
  if (c >= 6) {
    M.wr(ix, M.rd(ix + 6));
    E.tmpActorPosUpdate(M, ix);
    D.actorFindDestroy(M);
    M.wr(ix, 0);
    if ((M.rd(ix + 6) & 0x3f) < 3) E.playerTurnEnds(M);
    return;
  }
  if (c >= 3) { D.getSpritePosition(M); return D.actorEraseDestroyed(M); }
  D.actorEraseAnimSprite(M, ix);
  M.wr(ix + 3, (M.rd(S.random_number) & 7) | 0x42);
  D.colourizeSprite(M, ix);
}
E.frameRateLimiter = function frameRateLimiter(M) {
  if (M.rd(S.frame_ticked)) { M.r.a = 1; return; }
  M.hl = 0; M.r.a = 0;
}

// --- пришельцы ---------------------------------------------------------------------------------------
E.drawAlien = function drawAlien(M, ix) {
  const a = M.rd(ix);
  M.wr(ix, (a & 0xc0) | 3);
  D.updateAndEraseActor(M, ix);
  D.colourizeSprite(M, ix);
  M.wr(ix, a);
}
E.jetFighterUpdate = function jetFighterUpdate(M, ix) {
  const r = M.r;
  inc(M, S.current_alien_number);
  E.actorUpdateDir(M, ix);
  r.h = 0; r.l = 0;
  const speed = (a) => {           // JetFighterUpdate_3
    set(M, ix + 4, 1); r.c = a;
    M.wr(ix + 5, (((M.rd(S.game_timer) + r.c) & 0x7f) | 0x20));
    M.wr(ix + 3, 0x47);
  };
  let down;
  if (!(M.rd(ix + 4) & 2)) {
    if (!(M.rd(S.random_number) & 0x1f)) speed(0);
    const a = (M.rd(S.jetman_pos_y) - 0x0c) & 0xff;
    if (a === M.rd(ix + 2)) speed(a);
    down = !!(M.rd(S.game_timer) & 0x40);
  } else {
    if (!dec(M, ix + 5)) return E.jetFighterDie(M, ix);
    r.l = (M.rd(ix) & 0x40) ? 0xfc : 4;
    down = !(M.rd(S.jetman_pos_y) < M.rd(ix + 2));
  }
  r.h = down ? 2 : 0xfe;
  M.wr(ix, (M.rd(ix) & 0xc0) | 3);
  M.wr(ix + 1, (M.rd(ix + 1) + r.l) & 0xff);
  M.wr(ix + 2, (M.rd(ix + 2) + r.h) & 0xff);
  D.updateAndEraseActor(M, ix);
  D.colourizeSprite(M, ix);
  if (M.rd(ix + 2) < 0x28) return E.jetFighterDie(M, ix);
  if (E.laserBeamFire(M, ix) & 1) return E.jetFighterDie(M, ix);
  if (E.platformCollisionCheckAll(M, ix) & 4) return E.jetFighterDie(M, ix);
  if (E.alienCollision(M, ix) === 1) return E.alienCollisionAnimSfx(M, ix);
  M.wr(ix, (M.rd(ix) & 0xc0) | 7);
}
E.jetFighterDie = function jetFighterDie(M, ix) {
  E.addPointsToScore(M, 0x0055);
  E.sfxThrusters(M, ix);
  E.animationStateReset(M, ix);
}

// обработка касания платформы у пришельцев: E -> бит 7 (ix+4), бит 6 (ix+4); flip — UFO/корабль (xor $40)
E.alienPlatformBounce = function alienPlatformBounce(M, ix, flip) {
  const e = E.platformCollisionCheckAll(M, ix);
  if (!(e & 4)) return 0;
  if (e & 0x80) return 0x80;
  if (e & 0x10) return 0x10;
  let v = e & 0x40;
  if (flip) v ^= 0x40;
  M.r.e = v;
  M.wr(ix + 4, (M.rd(ix + 4) & 0xbf) | v);
  return 4;
}

E.squidgyAlienUpdate = function squidgyAlienUpdate(M, ix) {
  inc(M, S.current_alien_number);
  E.actorUpdateDir(M, ix);
  if (E.laserBeamFire(M, ix) === 1) { E.addPointsToScore(M, 0x0080); return E.alienKillAnimSfx1(M, ix); }
  if (E.alienCollision(M, ix) === 1) return E.alienCollisionAnimSfx(M, ix);
  M.wr(S.alien_new_dir_flag, 0);
  for (;;) {
    const b = E.alienPlatformBounce(M, ix, false);
    if (b === 0x80) res(M, ix + 4, 7); else if (b === 0x10) set(M, ix + 4, 7);
    let a = M.rd(ix + 1);
    a = bit(M, ix + 4, 6) ? (a + 2) & 0xff : (a - 2) & 0xff;
    M.wr(ix + 1, a);
    a = M.rd(ix + 2);
    if (bit(M, ix + 4, 7)) a = (a + 2) & 0xff;
    else { a = (a - 2) & 0xff; if (a < 0x24) set(M, ix + 4, 7); }
    M.wr(ix + 2, a);
    if (M.rd(S.alien_new_dir_flag)) return E.drawAlien(M, ix);
    M.wr(S.alien_new_dir_flag, 1);
  }
}

E.ufoUpdate = function ufoUpdate(M, ix) {
  const r = M.r;
  inc(M, S.current_alien_number);
  E.actorUpdateDir(M, ix);
  if (E.laserBeamFire(M, ix) === 1) { E.addPointsToScore(M, 0x0050); return E.alienKillAnimSfx1(M, ix); }
  if (E.alienCollision(M, ix) === 1) return E.alienCollisionAnimSfx(M, ix);
  M.wr(S.alien_new_dir_flag, 0);
  const off = () => {                 // UFOUpdate_17: L = B, DE = (C << 4) << 1
    r.l = r.b;
    const a = (r.c << 4) & 0xf0;
    M.de = a << 1;
    r.a = a;
  };
  const sub16 = () => { M.hl = (M.hl - M.de) & 0xffff; };
  const add16 = () => { M.hl = (M.hl + M.de) & 0xffff; };
  for (;;) {
    const bb = E.alienPlatformBounce(M, ix, true);
    if (bb === 0x80) res(M, ix + 4, 7); else if (bb === 0x10) set(M, ix + 4, 7);
    // по X
    let v = M.rd(ix + 5);
    r.b = v & 0xf0; r.c = v & 0x0f;
    let a = (M.rd(S.jetman_pos_x) - M.rd(ix + 1)) & 0xff;
    let st;
    if (!(a & 0x80)) st = bit(M, ix + 4, 6) ? '7dec' : '9';
    else st = bit(M, ix + 4, 6) ? '1inc' : '10';
    for (;;) {
      if (st === '1inc') { a = r.c; if (a < 0x0f) a++; st = '2'; }
      else if (st === '10') { a = (r.c - 1) & 0xff; if (a) st = '8'; else { set(M, ix + 4, 6); st = '2'; } }
      else if (st === '7dec') { a = (r.c - 1) & 0xff; if (a) st = '2'; else { res(M, ix + 4, 6); st = '8'; } }
      else if (st === '9') { a = r.c; if (a < 0x0f) a++; st = '8'; }
      if (st === '2') { r.c = a; r.h = M.rd(ix + 1); off(); sub16(); break; }
      if (st === '8') { r.c = a; r.h = M.rd(ix + 1); off(); add16(); break; }
    }
    M.wr(ix + 1, r.h);
    M.wr(ix + 5, (r.l & 0xf0) | r.c);
    // по Y
    v = M.rd(ix + 6);
    r.b = v & 0xf0; r.c = v & 0x0f;
    a = (M.rd(S.jetman_pos_y) - M.rd(ix + 2)) & 0xff;
    if (!(a & 0x80)) st = bit(M, ix + 4, 7) ? '11inc' : '13';
    else st = bit(M, ix + 4, 7) ? 'dec' : '14';
    for (;;) {
      if (st === 'dec') { a = (r.c - 1) & 0xff; if (a) st = '12'; else { res(M, ix + 4, 7); st = '4'; } }
      else if (st === '14') { a = r.c; if (a < 0x0f) a++; st = '4'; }
      else if (st === '11inc') { a = r.c; if (a < 0x0f) a++; st = '12'; }
      else if (st === '13') { a = (r.c - 1) & 0xff; if (a) st = '4'; else { set(M, ix + 4, 7); st = '12'; } }
      if (st === '4') { r.c = a; r.h = M.rd(ix + 2); off(); sub16(); break; }
      if (st === '12') { r.c = a; r.h = M.rd(ix + 2); off(); add16(); break; }
    }
    a = r.h;
    if (a < 0x28) set(M, ix + 4, 7);
    M.wr(ix + 2, a);
    M.wr(ix + 6, (r.l & 0xf0) | r.c);
    if (M.rd(S.alien_new_dir_flag)) return E.drawAlien(M, ix);
    M.wr(S.alien_new_dir_flag, 1);
  }
}

E.sphereAlienUpdate = function sphereAlienUpdate(M, ix) {
  inc(M, S.current_alien_number);
  E.actorUpdateDir(M, ix);
  M.wr(S.alien_new_dir_flag, 0);
  if (E.laserBeamFire(M, ix) === 1) return E.alienKillAnimSfx2(M, ix, 0x0040);
  if (E.alienCollision(M, ix) === 1) return E.alienCollisionAnimSfx(M, ix);
  for (;;) {
    const b = E.alienPlatformBounce(M, ix, false);
    if (b === 0x80) res(M, ix + 4, 7); else if (b === 0x10) set(M, ix + 4, 7);
    if (!bit(M, ix + 4, 0)) {
      const e = M.rd(S.random_number);
      if (!(e & 0x0f)) {
        set(M, ix + 4, 0);
        M.wr(ix + 6, ((M.rd(S.game_timer) & 0x1f) + 0x10) & 0xff);
        M.wr(ix + 4, (M.rd(ix + 4) & 0x7f) | (e & 0x80));
        continue;
      }
    }
    if (bit(M, ix + 4, 0)) {
      let a = M.rd(ix + 2);
      if (bit(M, ix + 4, 7)) a = (a + 2) & 0xff;
      else { a = (a - 2) & 0xff; if (a < 0x28) set(M, ix + 4, 7); }
      M.wr(ix + 2, a);
      if (!dec(M, ix + 6)) res(M, ix + 4, 0);
    }
    let a = M.rd(ix + 1);
    a = bit(M, ix + 4, 6) ? (a + 2) & 0xff : (a - 2) & 0xff;
    M.wr(ix + 1, a);
    if (M.rd(S.alien_new_dir_flag)) return E.drawAlien(M, ix);
    M.wr(S.alien_new_dir_flag, 1);
  }
}

E.crossedShipUpdate = function crossedShipUpdate(M, ix) {
  E.actorUpdateDir(M, ix);
  inc(M, S.current_alien_number);
  if (E.laserBeamFire(M, ix) === 1) return E.alienKillAnimSfx2(M, ix, 0x0060);
  if (E.alienCollision(M, ix) === 1) return E.alienCollisionAnimSfx(M, ix);
  M.wr(S.alien_new_dir_flag, 0);
  for (;;) {
    const b = E.alienPlatformBounce(M, ix, true);
    if (b === 0x80) { res(M, ix + 4, 7); M.wr(ix + 6, (M.rd(S.random_number) + 8) & 0xff); }
    else if (b === 0x10) set(M, ix + 4, 7);
    let a = M.rd(ix + 1);
    a = bit(M, ix + 4, 6) ? (a - 2) & 0xff : (a + 2) & 0xff;
    M.wr(ix + 1, a);
    M.hl = (M.rd(ix + 6) << 1) & 0xffff;
    M.r.d = M.rd(ix + 2); M.r.e = M.rd(ix + 5);
    if (bit(M, ix + 4, 7)) M.hl = (M.hl + M.de) & 0xffff;
    else { const hl = M.hl; M.hl = (M.de - hl) & 0xffff; M.de = hl; }
    M.wr(ix + 5, M.r.l); M.wr(ix + 2, M.r.h);
    if (M.r.h < 0x28) set(M, ix + 4, 7);
    if (!bit(M, ix + 4, 7)) { if (!dec(M, ix + 6)) set(M, ix + 4, 7); }
    else if (!inc(M, ix + 6)) M.wr(ix + 6, 0xff);
    if (M.rd(S.alien_new_dir_flag)) return E.drawAlien(M, ix);
    M.wr(S.alien_new_dir_flag, 1);
  }
}

E.meteorUpdate = function meteorUpdate(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  inc(M, S.current_alien_number);
  let a = M.rd(ix + 1);
  a = bit(M, ix + 4, 6) ? (a - M.rd(ix + 5)) & 0xff : (a + M.rd(ix + 5)) & 0xff;
  M.wr(ix + 1, a);
  M.wr(ix + 2, (M.rd(ix + 2) + M.rd(ix + 6)) & 0xff);
  D.updateAndEraseActor(M, ix);
  D.colourizeSprite(M, ix);
  if (!(E.platformCollisionCheckAll(M, ix) & 4)) {
    if (!E.laserBeamFire(M, ix)) {
      if (E.alienCollision(M, ix) === 1) E.alienCollisionAnimSfx(M, ix);
      return;
    }
    E.addPointsToScore(M, 0x0025);
  }
  E.animationStateReset(M, ix);
  E.sfxSetExplodeParams(M, 0);
}

// --- лазер ------------------------------------------------------------------------------------------
E.laserNewIfFreeSlot = function laserNewIfFreeSlot(M) {
  if (M.rd(FRAMES) & 3) return;
  for (let p = S.laser_beam_params, n = 4; n; n--, p += 8) if (!M.rd(p)) return E.laserBeamInit(M, p);
}
E.laserBeamInit = function laserBeamInit(M, p) {
  const r = M.r;
  M.wr(p, 0x10);
  const b = M.rd(JM);
  let c = (M.rd(JM + 1) & 0xf8) | 5;
  if (b & 0x40) c = (c - 8) & 0xff;
  else { let a = c; if (M.rd(JM + 1) & 7) a = (a + 8) & 0xff; c = ((a + 0x10) & 0xff) & 0xfe; }
  M.wr(p + 1, (M.rd(JM + 2) - 0x0d) & 0xff);
  M.wr(p + 2, c);
  const a = c & 0xfb;
  M.wr(p + 3, a); M.wr(p + 4, a); M.wr(p + 5, a);
  M.wr(p + 6, (M.rd(S.random_number) & 0x38) | 0x84);
  r.c = M.rd(S.random_number) & 3; r.b = 0;
  M.wr(p + 7, M.rd(S.laser_beam_colours + r.c));
  E.sfxLaserFire(M);
}
E.laserBeamAnimate = function laserBeamAnimate(M, ix) {
  const r = M.r;
  r.d = M.rd(ix + 1);
  let a = M.rd(ix + 2);
  if (a & 4) {
    r.l = a;
    a = (r.l & 1) ? 0xf8 : 8;
    r.e = (a + r.l) & 0xff;
    r.h = r.d;
    const hl = M.hl;
    D.coord2Scr(M);
    let blocked = false;
    if (M.rd(ix + 1) < 0x80 && M.rd(M.hl)) blocked = true;
    if (!blocked) {
      M.wr(ix + 2, r.e);
      M.wr(M.hl, 0xff);
      M.hl = hl;
      D.coord2Attr(M);
      M.wr(M.hl, M.rd(ix + 7));
      a = (M.rd(ix + 6) - 8) & 0xff;
      M.wr(ix + 6, a);
      if (!(a & 0xf8)) res(M, ix + 2, 2);
    } else {
      M.hl = hl;
      res(M, ix + 2, 2);
    }
  }
  M.exx(); M.bc = 0x031c; r.e = 0xe0; M.exx();
  r.e = 3;
  let bc = ix + 3;
  for (;;) {
    if ((M.rd(bc) ^ M.rd(ix + 2)) & 0xf8) {
      a = M.rd(bc);
      if (!(a & 4)) {
        const v = dec(M, ix + 6);
        if (v & 7) { M.bc = bc; return; }
        M.wr(ix + 6, (M.rd(S.random_number) & 3) | 4 | v);
        M.wr(bc, M.rd(bc) | 4);
        M.bc = bc; return;
      }
      r.l = a;
      a = ((r.l & 1) ? 0xf8 : 8) + r.l;
      M.wr(bc, a & 0xff);
      r.h = r.d;
      D.coord2Scr(M);
      M.exx(); r.a = r.b; r.b = r.c; r.c = r.e; M.exx();
      M.wr(M.hl, (~r.a) & M.rd(M.hl));
      bc = (bc + 1) & 0xffff;
      r.e = (r.e - 1) & 0xff;
      if (r.e) continue;
      M.bc = bc; return;
    }
    M.exx(); r.a = r.b; r.b = r.c; r.c = r.e; M.exx();
    bc = (bc + 1) & 0xffff;
    r.e = (r.e - 1) & 0xff;
    if (!r.e) { M.wr(ix, 0); M.bc = bc; return; }
  }
}

// --- Джетмен ----------------------------------------------------------------------------------------
const vmod = (M) => M.rd(S.jetman_velocity_modifier);
E.playerTurnStarts = function playerTurnStarts(M, ix) {
  const v = M.rd(S.begin_play_delay_counter);
  if (v) {
    if (dec(M, S.begin_play_delay_counter)) return E.scoreLabelFlash(M);
    E.sfxPickupItem(M);
    M.hl = M.rd(S.current_player_number) ? 0x00d8 : 0x0018;
    E.scoreLabelUnflash(M);
  }
  E.jetmanFly(M, ix);
}
E.jetmanFly = function jetmanFly(M, ix) {
  const r = M.r;
  E.tmpActorPosUpdate(M, ix);
  const lr = E.readInputLR(M);
  let st;
  if (!(lr & 8)) { res(M, ix, 6); st = bit(M, ix + 4, 6) ? 'flipX' : 'incX'; }
  else if (!(lr & 0x10)) { set(M, ix, 6); st = bit(M, ix + 4, 6) ? 'incX' : 'flipX'; }
  else st = (M.rd(S.game_timer) & 1) ? 'calcX' : 'horiz';
  // скорость по X
  if (st === 'incX') {
    const a = (neg(vmod(M)) + 8 + M.rd(ix + 5)) & 0xff;
    M.wr(ix + 5, a >= 0x40 ? 0x40 : a);
  } else if (st === 'flipX') {
    const a = (vmod(M) - 8 + M.rd(ix + 5)) & 0xff;
    if (!(a & 0x80)) M.wr(ix + 5, a);
    else { M.wr(ix + 5, 0); M.wr(ix + 4, M.rd(ix + 4) ^ 0x40); }
  } else if (st === 'calcX') {
    const a = (vmod(M) - 8 + M.rd(ix + 5)) & 0xff;
    M.wr(ix + 5, (a & 0x80) ? 0 : a);
  }
  // JetmanFlyHorizontal
  M.hl = M.rd(ix + 5) << 3;
  r.d = M.rd(ix + 1); r.e = M.rd(S.actor + 7);
  if (bit(M, ix + 4, 6)) { const hl = M.hl; M.hl = (M.de - hl) & 0xffff; M.de = hl; }
  else M.hl = (M.hl + M.de) & 0xffff;
  M.wr(S.actor + 7, r.l);
  M.wr(ix + 1, r.h);
  // JetmanApplyGravity: цифры 1–0 — висеть
  let vy;
  if (M.rd(S.game_options) & 2) vy = (E.readI2(M) & 4) ? 'fall' : 'min';
  else {
    vy = 'fall';
    r.b = 2;
    let row = 0xef;
    do {
      if ((M.inp(row << 8 | 0xfe) & 0x1f) !== 0x1f) { vy = 'min'; break; }
      row = 0xf7; r.b = (r.b - 1) & 0xff;
    } while (r.b);
  }
  if (vy === 'min') M.wr(ix + 6, 0);
  else {
    // JetmanFalling
    let s2;
    if (readInputThrust(M) & 2) { set(M, ix, 7); s2 = bit(M, ix + 4, 7) ? 'incY' : 'flipY'; }
    else { res(M, ix, 7); s2 = bit(M, ix + 4, 7) ? 'flipY' : 'incY'; }
    if (s2 === 'incY') {
      const a = (neg(vmod(M)) + 8 + M.rd(ix + 6)) & 0xff;
      M.wr(ix + 6, a >= 0x3f ? 0x3f : a);
    } else {
      const a = (vmod(M) - 8 + M.rd(ix + 6)) & 0xff;
      if (!(a & 0x80)) M.wr(ix + 6, a);
      else { M.wr(ix + 6, 0); M.wr(ix + 4, M.rd(ix + 4) ^ 0x80); }
    }
  }
  // JetmanFlyVertical
  M.hl = M.rd(ix + 6) << 3;
  r.d = M.rd(ix + 2); r.e = M.rd(S.jetman_fly_counter);
  if (!bit(M, ix + 4, 7)) { const hl = M.hl; M.hl = (M.de - hl) & 0xffff; M.de = hl; }
  else M.hl = (M.hl + M.de) & 0xffff;
  M.wr(S.jetman_fly_counter, r.l);
  M.wr(ix + 2, r.h);
  if (r.h >= 0xc0) res(M, ix + 4, 7);
  else if (r.h < 0x2a) {
    set(M, ix + 4, 7);
    const a = M.rd(ix + 6) >> 1;
    if (a) M.wr(ix + 6, a);
  }
  // JetmanPlatformCollision
  const e = E.platformCollisionCheckAll(M, ix);
  if (e & 4) {
    if (e & 0x80) {
      res(M, ix + 4, 7);
      M.wr(ix, (M.rd(ix) & 0xc0) | 2);
      M.wr(ix + 5, 0); M.wr(ix + 6, 0);
    } else if (e & 0x10) set(M, ix + 4, 7);
    else {
      const v = (e ^ 0x40) & 0x40;
      r.e = v;
      M.wr(ix + 4, (M.rd(ix + 4) & 0xbf) | v);
    }
  }
  E.jetmanRedraw(M, ix);
}
E.jetmanRedraw = function jetmanRedraw(M, ix) {
  D.updateAndEraseActor(M, ix);
  D.colourizeSprite(M, ix);
  if (!(readInputFire(M) & 1)) E.laserNewIfFreeSlot(M);
}
E.jetmanWalk = function jetmanWalk(M, ix) {
  E.tmpActorPosUpdate(M, ix);
  const lr = E.readInputLR(M);
  if (!(lr & 8)) { inc(M, ix + 1); res(M, ix, 6); res(M, ix + 4, 6); M.wr(ix + 5, 0x20); }
  else if (!(lr & 0x10)) { dec(M, ix + 1); set(M, ix, 6); set(M, ix + 4, 6); M.wr(ix + 5, 0x20); }
  else M.wr(ix + 5, 0);
  let leave = !(readInputThrust(M) & 2);
  if (!leave) {
    const e = E.platformCollisionCheckAll(M, ix);
    if (!(e & 4)) leave = true;
    else if ((e & 8) && !M.rd(ix + 5)) {
      if (bit(M, ix, 6)) dec(M, ix + 1);
      else { inc(M, ix + 1); M.wr(ix + 5, 0x20); }
    }
  }
  if (leave) {
    M.wr(ix, (M.rd(ix) & 0xc0) | 1);
    M.hl = M.rd16(S.jetman_pos_x);
    const th = S.jetman_thruster_anim_state;
    if (!M.rd(th)) {
      M.wr(th, 3);
      M.wr16(th + 1, M.hl);
      E.animationStateReset(M, th);
    }
    dec(M, ix + 2); dec(M, ix + 2);
  }
  E.jetmanRedraw(M, ix);
}

// --- счёт, жизни, ходы ------------------------------------------------------------------------------
const p1Lives = (M) => M.rd(M.rd(S.current_player_number) ? S.inactive_player_lives : S.player_lives);
const p2Lives = (M) => M.rd(M.rd(S.current_player_number) ? S.player_lives : S.inactive_player_lives);
E.displayPlayerLives = function displayPlayerLives(M) { D.displayPlayerLives(M, p1Lives, p2Lives); }

E.flashText = function flashText(M, on) {
  D.coord2Attr(M);
  M.r.b = 3;
  do {
    const v = M.rd(M.hl);
    M.wr(M.hl, on ? v | 0x80 : v & 0x7f);
    M.hl = (M.hl + 1) & 0xffff;
    M.r.b = (M.r.b - 1) & 0xff;
  } while (M.r.b);
}
E.scoreLabelFlash = function scoreLabelFlash(M) { M.hl = M.rd(S.current_player_number) ? 0x00d8 : 0x0018; E.flashText(M, true); }
E.scoreLabelUnflash = function scoreLabelUnflash(M) { E.flashText(M, false); }

E.updateHiScore = function updateHiScore(M) {
  const p1 = M.rd(S.p1_score) << 8 | M.rd(S.p1_score + 1);
  const p2 = M.rd(S.p2_score) << 8 | M.rd(S.p2_score + 1);
  let best;
  if (p1 < p2) best = S.p2_score;
  else if (p1 !== p2) best = S.p1_score;
  else best = M.rd(S.p2_score + 2) < M.rd(S.p1_score + 2) ? S.p1_score : S.p2_score;
  for (let i = 0; i < 3; i++) {
    const h = M.rd(S.hi_score + i), p = M.rd(best + i);
    if (h < p) { E.copy(M, best, S.hi_score, 3); return; }
    if (h !== p) return;
  }
}

E.playersSwap = function playersSwap(M) {
  const sw = (a, b, n) => { for (let i = 0; i < n; i++) { const t = M.rd(b + i), u = M.rd(a + i); M.wr(a + i, t); M.wr(b + i, u); } };
  sw(S.player_level, S.inactive_player_level, 2);
  sw(S.rocket_state, S.inactive_rocket_state, 0x18);
  M.r.b = 0;
}
E.playerInit = function playerInit(M) {
  E.copy(M, S.default_player_state, JM, 8);
  M.wr(S.begin_play_delay_counter, (M.rd(S.game_options) & 1) ? 0xff : 0x80);
  dec(M, S.player_lives);
  E.displayPlayerLives(M);
}
E.rocketReset = function rocketReset(M) {
  E.copy(M, S.default_rocket_state, S.rocket_state, 0x18);
  E.bufferCopyRocket(M, 8);
}
E.levelInit = function levelInit(M) {
  E.alienBufferInit(M);
  D.resetScreen(M);
  D.drawPlatforms(M);
  E.displayPlayerLives(M);
  M.wr(S.last_frame, M.rd(FRAMES));
}
E.levelNew = function levelNew(M) {
  if (!(M.rd(S.player_level) & 3)) {
    E.rocketReset(M);
    inc(M, S.player_lives);
    E.playerInit(M);
  }
  E.levelInit(M);
}
E.gameOverText = function gameOverText(M) {
  M.wr(S.game_over_text + 0x12, M.rd(S.current_player_number) ? 0xb2 : 0xb1);
  D.resetScreen(M);
  M.de = S.game_over_text; M.hl = 0x7038;
  D.displayString(M);
  M.hl = 0; M.r.b = 0;
}
E.playerTurnEnds = function playerTurnEnds(M) {
  E.setObjectInactive(M, S.jetman_thruster_anim_state, 0x0a);
  res(M, S.rocket_module_state + 4, 1);
  res(M, S.item_state + 4, 1);
  let two = M.rd(S.game_options) & 1;
  if (two && !M.rd(S.inactive_player_lives)) two = 0;
  if (!two) {
    if (!M.rd(S.player_lives)) {
      E.updateHiScore(M);
      E.gameOverText(M);
      throw new GameOver();
    }
    E.levelInit(M);
    return E.playerInit(M);
  }
  if (!M.rd(S.player_lives)) E.gameOverText(M);
  E.playersSwap(M);
  M.wr(S.current_player_number, (~M.rd(S.current_player_number)) & 0xff);
  E.bufferCopyRocket(M, (M.rd(S.rocket_state + 4) << 3) & 0x38);
  E.levelInit(M);
  E.playerInit(M);
}

// --- главный цикл -----------------------------------------------------------------------------------
const ROUT = new Map();
E.dispatch = function dispatch(M, ix, table, idx) {
  const r = M.r;
  r.c = idx; r.b = 0;
  const t = M.rd16(table + idx);
  M.hl = t; r.a = t & 0xff;
  const f = ROUT.get(t);
  if (!f) throw Object.assign(new Error('модель: нет подпрограммы ' + t.toString(16)), { notModeled: true });
  f(M, ix);
}

E.resetModifiedCode = function resetModifiedCode(M) {
  M.wr16(S.NewActor + 0x0d, S.inactive_jetman_state);
  M.wr(S.NewActor + 0x2b, 0x3a);
  M.wr16(S.NewActor + 0x2c, 0x0244);
}
E.frameUpdate = function frameUpdate(M) {
  M.wr(S.last_frame, M.rd(FRAMES));
  M.wr(S.frame_ticked, 1);
  M.wr16(S.NewActor + 0x0d, S.rocket_state);
  M.wr(S.NewActor + 0x2b, 0xc3);
  M.wr16(S.NewActor + 0x2c, S.ResetModifiedInFrame);
  if (E.mainLoop(M, JM) !== 'frame') throw new Error('модель: вложенный проход кончился не по кадру');
  E.resetModifiedCode(M);
  M.wr(S.frame_ticked, 0);
}

// MainLoop .. NewActor: 'frame' — конец вложенного прохода (ResetModifiedInFrame), 'end' — MainLoopResetStack
E.mainLoop = function mainLoop(M, ix) {
  const r = M.r;
  for (;;) {
    r.c = M.rd(FRAMES);
    r.a = M.rd(S.last_frame);
    if (r.a !== r.c) E.frameUpdate(M);
    E.dispatch(M, ix, S.main_jump_table, (rlc(M.rd(ix))) & 0x7e);
    // NewActor
    inc(M, S.random_number);
    ix = (ix + 8) & 0xffff;
    if (ix < M.rd16(S.NewActor + 0x0d)) continue;
    while (!(M.inp(0xfefe) & 1));                      // SHIFT — пауза
    const t = (M.rd16(S.game_timer) + 1) & 0xffff;
    M.wr16(S.game_timer, t);
    r.h = 0; r.l = t & 0xff;
    r.c = M.ldar();
    if (M.rd(S.NewActor + 0x2b) === 0xc3) return 'frame';
    let a = M.rd(M.rd16(S.NewActor + 0x2c));
    a = (a + M.rd(r.l) + r.c) & 0xff;
    M.wr(S.random_number, a);
    r.a = a; M.exaf();
    let spawn = false;
    const n = M.rd(S.current_alien_number);
    let gate = n < 3;
    if (!gate) { M.exaf(); gate = !(r.a & 0x1f) && M.rd(S.current_alien_number) < 6; }
    if (gate && !M.rd(S.begin_play_delay_counter)) {
      const d = M.rd(JM) & 0x3f;
      if (d === 1 || d === 2) {
        for (let p = S.alien_states, k = 0; k < 6; k++, p += 8) if (!M.rd(p)) { E.newAlien(M, p); spawn = true; break; }
      }
    }
    E.itemNewFuelPod(M);
    E.itemNewCollectible(M);
    return 'end';
  }
}
E.newAlien = function newAlien(M, ix) {
  E.copy(M, S.default_alien_state, ix, 8);
  const t = M.rd(S.game_timer);
  M.wr(ix + 4, t & 0x40); M.wr(ix, t & 0x40);
  M.wr(ix + 2, ((t & 0x7f) + 0x28) & 0xff);
  const a = (((ix & 0xff) >> 3) & 3) + 2;
  M.wr(ix + 3, a);
  M.wr(ix + 6, a & 1);
  M.wr(ix, (M.rd(ix) & 0xc0) | M.rd(S.item_level_object_types + (M.rd(S.player_level) & 7)));
}

// шаг: MainLoopResetStack .. MainLoopResetStack
E.pass = function pass(M) {
  M.wr(S.current_alien_number, 0);
  return E.mainLoop(M, S.rocket_state);
}

for (const [n, f] of Object.entries({
  FrameRateLimiter: 'frameRateLimiter', PlayerTurnStarts: 'playerTurnStarts', JetmanWalk: 'jetmanWalk',
  MeteorUpdate: 'meteorUpdate', ItemPickup: 'itemPickup', CrossedShipUpdate: 'crossedShipUpdate',
  SphereAlienUpdate: 'sphereAlienUpdate', JetFighterUpdate: 'jetFighterUpdate', AnimateExplosion: 'animateExplosion',
  RocketUpdate: 'rocketUpdate', RocketTakeoff: 'rocketTakeoff', RocketLanding: 'rocketLanding',
  SfxEnemyDeath: 'sfxEnemyDeath', SfxJetmanDeath: 'sfxJetmanDeath', ItemCheckCollect: 'itemCheckCollect',
  UFOUpdate: 'ufoUpdate', LaserBeamAnimate: 'laserBeamAnimate', SquidgyAlienUpdate: 'squidgyAlienUpdate',
  ItemDropGoldBar: 'itemDropGoldBar', ItemDisplaySprite: 'itemDisplaySprite', ItemDropPlutonium: 'itemDropPlutonium',
  ItemDropChemical: 'itemDropChemical', ItemDropRandomColour: 'itemDropRandomColour',
})) { if (S[n] === undefined) throw new Error('нет метки ' + n); ROUT.set(S[n], (M, ix) => E[f](M, ix)); }

