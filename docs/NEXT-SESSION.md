# Jetpac → Вектор-06Ц: старт следующей сессии

Создано 25.10.2026. Сделано только: папка, git, подмодуль `upstream/`
(mrcook/jetpac-disassembly, 69dcde1), SkoolKit в `.venv`, `tools/sjasmplus` (из alien8-v06c).

## Что за исходник

- `upstream/jetpac.skool` — полный дизассемблер картриджной версии (SkoolKit), всё размечено:
  265 меток, 3732 инструкции. `skool2asm.py -H -crs` даёт `build/jetpac_z80.asm` (6159 строк),
  `skool2bin.py` — `build/jetpac.bin` (0x5CCB–0x9C66, 16284 Б).
- Кассетная версия отличается только адресом загрузки и Kempston вместо Interface 2.
- ROM картриджа в репозитории нет — для сверки с оригиналом нужен снимок или .rom (кладёт пользователь).

## Карта памяти ZX

    0x4000-0x57FF  экран ZX, 0x5800-0x5AFF атрибуты (игра рисует прямо в экран, XOR, без теневого буфера)
    0x5CCB-0x5FFF  стек (37 Б, ld sp,stack_memory+$25) и переменные
    0x6000-0x7FB2  код и данные игры (~8 КБ); 0x6000 jp 0x61BF (EntryPoint)
    0x7FB3-0x9AB2  loading_screen (6912 Б, экран ZX целиком — для заставки)
    0x9AB3-0x9C66  system_font (кусок шрифта ZX ROM; код берёт system_font-0x100)

Сама игра ~9 КБ — на ванильном Векторе (экран 0x8000–0xFFFF) помещается в 0x0100–0x7FFF
с большим запасом. Заставку и шрифт переложить ниже 0x8000 (ссылки на них — по меткам).

## Точки соприкосновения с железом ZX (по `build/jetpac_z80.asm`)

- Экран: `Coord2Scr` (стр. ~4205), `ScreenPosOnePixelAbove`, `ClearScreen`, `DrawFontChar`,
  `DrawPlatformTile`, `MaskSprite`, буферные `BufferCopy*`/`BufferFlipSprite`.
- Цвет: `ColourizeSprite`, `Coord2AttrFile`, `ClearAttrFile`, `UpdateRocketColour`, прямой `$5820`.
- Время: `SYSVAR_FRAMES` (0x5C78, тикает ПЗУ ZX по IM1), `FrameRateLimiter`, `ei` в стр. ~2189.
- Ввод: `in a,($fe)` ×8, `out ($fd),a` ×7 (картриджная особенность, на Векторе выбросить),
  `ReadInterface2Joystick` → джойстик «П» как в прошлых портах.
- Звук: бипер `out ($fe)` (`PlaySquareWave*`, `SfxPlayExplosion`) → порт 0 / ВИ53.
- `jp (hl)` в MainLoop (диспетчер актёров), `ld sp` ×2.

## Z80-специфика (сколько переводить)

ix 305 (iy нет), jr 240, bit/set/res 173, djnz 38, exx 33, ex af 18, neg 15, rl/rr/sla/srl 19,
adc/sbc hl 8, ldir 6. Переводчик Z80→i8080 есть: `~/projects/alien8-v06c/tools/a8_z80_to_8080.py`
(+ `check_i8080.py`, `check_djnz.py`, `check_ixflags.py`) — начать с его адаптации.

## Предлагаемый план

1. **Оракул.** Снимок/ROM оригинала → стенд ZX (MAME, как `knightlore-research/zx-stand`).
   Проверить, что `skool2bin` побайтно совпадает с образом.
2. **Перевод Z80→i8080** всего кода; ix-структуры актёров — на HL/DE или фиксированные адреса.
3. **Экран.** Вывод в плоскость Вектора вместо раскладки ZX: `Coord2Scr` → столбцовая адресация
   Вектора (адрес = 0x8000+плоскость + x/8·256 + (255−y)), XOR-спрайты сохраняются.
4. **Цвет.** Атрибутов на Векторе нет. Вариант, который и проще, и лучше оригинала: 3 плоскости
   = INK ZX (8 цветов), спрайт пишется в плоскости по своему цвету → без «клэша» атрибутов.
   Цена — три XOR-прохода на спрайт; замерить, если тесно — 1 плоскость + цвет по зонам.
5. **Время, ввод, звук**: прерывание Вектора 50 Гц тикает свой FRAMES; клавиатура + джойстик «П»;
   бипер → порт 0 (или ВИ53).
6. **Сверка**: локстеп логики против ZX (рецепт `~/projects/knightlore-v06c/docs/PORT_RECIPE.md`),
   гейты headless на V06JS (`~/projects/vector06js`), образы `rom/*.rom` (+ .c00 для MiSTer).

Решить на старте: цвет (п. 4) — 3 плоскости по INK или зональная палитра.
