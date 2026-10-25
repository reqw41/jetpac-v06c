#!/usr/bin/env python3
"""Данные Jetpac для i8080 (src/vec/gen/data.asm) из картриджной сборки (build/jetpac.bin, build/z80.sym).

- Таблицы, тексты, тайлы, шрифт — байт в байт под теми же метками, что в ZX.
- Спрайты для вывода (vs_*): заголовок как в ZX [смещение X, ширина, высота], затем данные ПО СТОЛБЦАМ:
  столбец = строки снизу вверх (строка 0 спрайта ZX — нижняя, MaskSprite идёт вверх), высота дополнена
  нулём до чётной (вывод читает по 2 байта через pop). Длина столбца в байтах — vs_h2 (= высота с запасом).
- Таблицы указателей на спрайты вывода: vs_jetman_sprite_table (Джетмен; пришельцы и предметы — буферы),
  vs_collectible_sprite_table, vs_explosion_sprite_table.
- Сырые спрайты ZX (alien_sprite_table, collectible_sprite_table) — для BufferCopy* (сдвиги в буферы).
- rnd_rom: 256 байт ПЗУ ZX 0x0000..0x00FF (генератор случайных чисел) и байт 0x0244.
"""
import re, sys, os

ROOT = os.path.join(os.path.dirname(__file__), '..')
B = 0x5CCB
img = open(os.path.join(ROOT, 'build/jetpac.bin'), 'rb').read()
rom = open(os.path.join(ROOT, 'ref/48.rom'), 'rb').read()
SYM = {}
for l in open(os.path.join(ROOT, 'build/z80.sym')):
    m = re.match(r'(\w+):\s+EQU\s+0x([0-9A-F]+)', l, re.I)
    if m: SYM[m.group(1)] = int(m.group(2), 16)

def mem(a, n=1): return img[a - B:a - B + n]
def w(a): return img[a - B] | img[a - B + 1] << 8

out = []
def db(label, data, comment=''):
    if label: out.append(f'{label}:' + (f'\t\t\t; {comment}' if comment else ''))
    for i in range(0, len(data), 16):
        out.append('\t\tDB\t' + ','.join(f'0x{x:02X}' for x in data[i:i + 16]))
def dw(label, words, comment=''):
    out.append(f'{label}:' + (f'\t\t\t; {comment}' if comment else ''))
    for i in range(0, len(words), 8):
        out.append('\t\tDW\t' + ','.join(words[i:i + 8]))

name_at = {v: k for k, v in sorted(SYM.items(), key=lambda kv: kv[0])}
def span(label):
    a = SYM[label]
    nxt = min(v for v in SYM.values() if v > a)
    return a, nxt - a

out.append('; Сгенерировано tools/mkvecdata.py — не править руками.')
# --- таблицы и тексты как есть
for lab in ['gfx_params_platforms', 'default_player_state', 'default_rocket_state', 'default_rocket_module_state',
            'default_item_state', 'menu_colour_table', 'menu_position_table', 'item_drop_positions_table',
            'explosion_sfx_defaults', 'item_level_object_types', 'default_alien_state', 'laser_beam_colours',
            'tile_life_icon', 'ScoreLabel1UP', 'ScoreLabel2UP', 'ScoreLabelHI',
            'tile_platform_left', 'tile_platfor_mmiddle']:
    a, n = span(lab)
    db(lab, mem(a, n))
db('tile_platform_right', mem(SYM['tile_platform_right'], 8))
# тексты: menu_copyright, game_over_text (байт +0x12 меняется — данные в ОЗУ), menu_text
for lab in ['menu_copyright', 'game_over_text']:
    a = SYM[lab]; n = 1
    while not (mem(a + n)[0] & 0x80) or n == 1: n += 1
    db(lab, mem(a, n + 1))
a = SYM['menu_text']; n = SYM['MenuWriteText'] - a
db('menu_text', mem(a, n))
# шрифт: с символа 0x20 до конца образа
fa = SYM['system_font']
db('system_font', img[fa - B:])

# --- спрайты вывода по столбцам
def vs_bytes(a):
    x, wd, h = mem(a, 3)
    rows = [mem(a + 3 + r * wd, wd) for r in range(h)]
    h2 = h + (h & 1)
    data = []
    for c in range(wd):
        col = [rows[r][c] for r in range(h)] + [0] * (h2 - h)
        data += col
    return bytes([x, wd, h]) + bytes(data)

static = [k for k in SYM if k.startswith('gfx_') and k not in ('gfx_params_platforms',)]
static = [k for k in static if not re.match(r'gfx_(squidgy|jet_fighter|ufo|sphere|cross|space|frog)', k)]
static.sort(key=lambda k: SYM[k])
for k in static:
    db('vs_' + k[4:], vs_bytes(SYM[k]))
vs_name = {SYM[k]: 'vs_' + k[4:] for k in static}
raw_name = {}

# сырые спрайты ZX — источники буферов (пришельцы; предметы и модули ракеты — через collectible_sprite_table)
for k in ['gfx_squidgy_alien1', 'gfx_squidgy_alien2', 'gfx_jet_fighter', 'gfx_ufo', 'gfx_sphere_alien1',
          'gfx_sphere_alien2', 'gfx_cross_ship', 'gfx_space_craft', 'gfx_frog_alien', 'gfx_meteor1', 'gfx_meteor2']:
    a, n = span(k)
    db('raw_' + k[4:], mem(a, n)); raw_name[a] = 'raw_' + k[4:]
for k in ['gfx_rocket_u3_bottom', 'gfx_rocket_u3_middle', 'gfx_rocket_u3_top', 'gfx_rocket_u1_bottom',
          'gfx_rocket_u1_middle', 'gfx_rocket_u1_top', 'gfx_rocket_u5_bottom', 'gfx_rocket_u5_middle',
          'gfx_rocket_u5_top', 'gfx_rocket_u4_bottom', 'gfx_rocket_u4_middle', 'gfx_rocket_u4_top', 'gfx_gold_bar',
          'gfx_fuel_pod', 'gfx_radiation', 'gfx_chemical_weapon', 'gfx_plutonium', 'gfx_diamond']:
    a, n = span(k)
    hgt = mem(a + 2)[0]
    db('raw_' + k[4:], mem(a, 3 + 2 * hgt)); raw_name[a] = 'raw_' + k[4:]

def table(label, src, n, names, prefix_ok=True):
    words = []
    for i in range(n):
        p = w(src + 2 * i)
        if p in names: words.append(names[p])
        elif 0x5E00 <= p < 0x6000: words.append(f'0x{p:04X}')
        else: raise SystemExit(f'{label}[{i}]: нет спрайта для {p:04X}')
    dw(label, words)

# jetman_sprite_table: 4 направления по 8 указателей (Джетмен летит/идёт — спрайты, пришельцы/предметы — буферы)
table('vs_jetman_sprite_table', SYM['jetman_sprite_table'], 32, vs_name)
ct = SYM['collectible_sprite_table']
n_ct = (SYM['SfxThrusters'] - ct) // 2
table('vs_collectible_sprite_table', ct, n_ct, vs_name)
table('raw_collectible_sprite_table', ct, n_ct, raw_name)
et = SYM['explosion_sprite_table']
table('vs_explosion_sprite_table', et, (SYM['FrameRateLimiter'] - et) // 2, vs_name)
at = SYM['alien_sprite_table']
table('raw_alien_sprite_table', at, (SYM['FrameUpdate'] - at) // 2, raw_name)

# случайные числа: ПЗУ 0x0000..0x00FF выровнено на страницу (ld h,0 -> h = старший байт rnd_rom)
out.append('\t\tALIGN\t256')
db('rnd_rom', rom[0:256], 'ПЗУ ZX 0x0000..0x00FF')
out.append(f'RND_0244\tequ\t0x{rom[0x244]:02X}\t\t; ld a,($0244)')

os.makedirs(os.path.join(ROOT, 'src/vec/gen'), exist_ok=True)
open(os.path.join(ROOT, 'src/vec/gen/data.asm'), 'w').write('\n'.join(out) + '\n')

# переменные ZX: адреса как в ZX (0x5C78 FRAMES, 0x5CCB..0x5DFF)
vs = ['; Сгенерировано tools/mkvecdata.py: переменные игры по адресам ZX.', 'FRAMES\t\tequ\t0x5C78']
for k, v in sorted(SYM.items(), key=lambda kv: kv[1]):
    if 0x5CCB <= v < 0x6000 and not k.startswith('L5'):
        vs.append(f'{k}\tequ\t0x{v:04X}')
open(os.path.join(ROOT, 'src/vec/gen/vars.asm'), 'w').write('\n'.join(vs) + '\n')
print('data.asm:', len(out), 'строк; vars.asm:', len(vs))
