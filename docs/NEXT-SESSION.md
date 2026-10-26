# Jetpac → Вектор-06Ц: старт следующей сессии

Состояние на 26.10.2026: игра работает на Векторе (эмулятор vector06js без окна): меню, полёт, стрельба,
пришельцы, сбор ракеты, конец игры. Логика на i8080 совпадает с ZX байт в байт по 8 сценариям.
Подробно — **docs/JOURNAL.md** (что сделано, грабли, открытое) и **docs/LOGIC_PLAN.md** (устройство i8080).
Запуск: `tools/emu80_run.sh` (Emu80 с окном, MCP 19787).

Решения владельца: цвет — 3 плоскости без клэша; логика — через JS-модель с оптимизацией под i8080;
вывод графики — по максимуму процедурами на SP.

## Команды
    tools/mkbin.sh                               # картриджная сборка ZX из skool -> build/jetpac.bin, z80.sym
    node tools/zx_trace.js research/scenarios/X.json   # эталон ZX -> build/golden/X.json.gz
    node tools/model_run.js build/golden/*.json.gz      # JS-модель против эталона
    tools/build_vec.sh                           # i8080 -> build/vec/jetpac.bin, rom/jetpac.r0m, .c00
    node tools/lock80.js build/golden/X.json.gz [--prof] # i8080 против эталона (+ профиль, темп)
    node tools/vecshot.js rom/jetpac.r0m 700 "100:5+ 104:5- 300:up+" out.png   # снимок Вектора
    node tools/coverage.js build/golden/*.json.gz       # покрытие кода ZX сценариями (95 %)

## Управление на Векторе
Клавиши как на ZX (Z/X — влево/вправо, Q.. — газ, A.. — огонь, цифры 1–0 — висеть), плюс стрелки
(вверх — газ) и пробел (огонь); джойстик «П». В режиме «4 JOYSTICK» стрелки/джойстик идут как Interface 2.
В меню огонь = «5 START GAME»; F1+F3 — старт с бессмертием. ВК — пауза.

## Оригиналы
orig/ (не в git): кассета .tzx и снимок .sp — другая сборка, не картридж; эталон — картридж из skool.
