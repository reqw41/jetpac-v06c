#!/usr/bin/env python3
"""Заставка Jetpac для Вектора: экран картриджа ZX (ref/splash/cart.scr) -> 16 цветов, 4 плоскости, zx0.

    python3 tools/mksplash.py            # src/vec/gen/splash.zx0, src/vec/gen/splash_pal.asm, превью

Раскраска по областям картинки (решение владельца: ярче и разнообразнее, с учётом Вектора): пиксель ZX
(чернила/бумага + цвет атрибута) -> индекс своей палитры по правилам ниже, с градиентами по строкам и
расстоянию. Палитра — 16 цветов сетки Вектора (BBGGGRRR), индекс 0 — чёрный (поля экрана).
Плоскости как у экрана игры: столбец x/8, строка 223 - y; аппаратный индекс = p80<<3|pA0<<2|pC0<<1|pE0.
Превью build/splash_preview.png собирается обратно из плоскостей и палитры.
"""
import os, subprocess, sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
scr = open(os.path.join(ROOT, 'ref/splash/cart.scr'), 'rb').read()

def v(r, g, b): return b << 6 | g << 3 | r          # уровни Вектора: R, G 0..7, B 0..3
def rgb(c): return ((c & 7) * 255 // 7, ((c >> 3) & 7) * 255 // 7, ((c >> 6) & 3) * 255 // 3)

# палитра заставки (индекс -> цвет Вектора)
PAL = {
    'black': v(0, 0, 0), 'white': v(7, 7, 3), 'frost': v(4, 5, 3), 'ice': v(5, 7, 3), 'cyan': v(1, 6, 3),
    'blue': v(1, 2, 3), 'pink': v(7, 3, 3), 'purple': v(4, 1, 2), 'red': v(7, 1, 0), 'orange': v(7, 4, 0),
    'yellow': v(7, 7, 1), 'darkred': v(4, 0, 0), 'green': v(1, 6, 0), 'lime': v(5, 7, 0), 'gold': v(6, 5, 0),
    'violet': v(3, 2, 3),
}
NAMES = list(PAL)
assert len(NAMES) == 16 and NAMES[0] == 'black'

def zx_pixel(x, y):
    a = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3)
    at = scr[6144 + (y >> 3) * 32 + (x >> 3)]
    on = (scr[a] >> (7 - (x & 7))) & 1
    return on, (at & 7) if on else (at >> 3) & 7, at

def colour(x, y):
    on, c, at = zx_pixel(x, y)
    if c == 0: return 'black'
    # верхняя и нижняя плашки (бумага жёлтая): золото с отливом по строкам
    if c == 6 and (y < 56 or y >= 176):
        yy = y if y < 56 else y - 176
        return 'yellow' if yy % 8 < 2 else 'gold'
    # логотип JETPAC (y 4..48): голубой верх — лёд->голубой, красный низ — оранжевый->красный->тёмно-красный
    if y < 56:
        if c == 5: return 'ice' if y < 16 else 'cyan'
        if c == 2: return 'orange' if y < 32 else ('red' if y < 40 else 'darkred')
        return 'white'
    # плашка ULTIMATE (x < 144, y 128..176)
    if x < 144 and 128 <= y < 176:
        if c == 7: return 'frost'                      # рамка
        if c == 5: return 'ice' if y < 142 else 'cyan'
        if c == 4: return 'green' if y < 156 else 'lime'
        return NAMES[min(c, 15)] if False else 'white'
    # луч: радуга по атрибутам (y 96..112)
    if 92 <= y < 112 and x < 128:
        return {2: 'red', 3: 'pink', 1: 'blue', 5: 'cyan', 4: 'green', 6: 'yellow', 7: 'white'}.get(c, 'white')
    # знак © у плашки ULTIMATE — золотой
    if c == 3 and 140 <= x < 156 and 144 <= y < 168: return 'gold'
    # горы (пурпурные): розовые вершины -> фиолетовый низ
    if c == 3:
        return 'pink' if y < 90 else ('violet' if y < 110 else 'purple')
    # пламя ранца: от сопла (~x 205, y 118) жёлтое -> оранжевое -> красное -> тёмно-красное
    if c in (2, 6) and x >= 180:
        d = ((x - 205) ** 2 + (y - 118) ** 2) ** 0.5
        return 'yellow' if d < 14 else 'orange' if d < 26 else 'red' if d < 42 else 'darkred'
    # звёзды и значки
    if c == 7 and y < 90 and not (130 <= x < 210):
        return 'ice' if (x + y) % 3 else 'white'
    if c == 6: return 'gold'
    # скафандр: белый с холодной тенью справа-снизу
    if c == 7:
        return 'frost'                                 # скафандр целиком — цвет Джетмена в игре
    return {1: 'blue', 2: 'red', 4: 'green', 5: 'cyan'}.get(c, 'white')

img = [[NAMES.index(colour(x, y)) for x in range(256)] for y in range(192)]

# индекс палитры -> аппаратный индекс Вектора (биты плоскостей): берём тот же номер
planes = bytearray(4 * 8192)
for y in range(192):
    for x in range(256):
        i = img[y][x]
        for p in range(4):                                   # p: 0 -> 0x80 (бит 3), 1 -> 0xA0 (бит 2), ...
            if (i >> (3 - p)) & 1:
                planes[p * 8192 + (x >> 3) * 256 + (223 - y)] |= 0x80 >> (x & 7)
os.makedirs(os.path.join(ROOT, 'src/vec/gen'), exist_ok=True)
os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
raw = os.path.join(ROOT, 'build/splash.bin')
open(raw, 'wb').write(planes)
out = os.path.join(ROOT, 'src/vec/gen/splash.zx0')
r = subprocess.run([os.path.join(ROOT, 'tools/zx0/zx0'), '-f', '-c', raw, out], capture_output=True, text=True)
if r.returncode: sys.exit(r.stdout + r.stderr)
pal = [PAL[n] for n in NAMES]
open(os.path.join(ROOT, 'src/vec/gen/splash_pal.asm'), 'w').write(
    '; Сгенерировано tools/mksplash.py: палитра заставки (аппаратный индекс 0..15)\n'
    'pal_splash:\tdb\t' + ','.join(f'0x{c:02X}' for c in pal) + '\n')
# превью из плоскостей
pv = Image.new('RGB', (256, 256))
for y in range(256):
    for x in range(256):
        a = (x >> 3) * 256 + (255 - y)
        i = sum(((planes[p * 8192 + a] >> (7 - (x & 7))) & 1) << (3 - p) for p in range(4))
        pv.putpixel((x, y), rgb(pal[i]))
pv.resize((768, 768), Image.NEAREST).save(os.path.join(ROOT, 'build/splash_preview.png'))
print(f'splash.zx0: {os.path.getsize(out)} Б (из {len(planes)})')
