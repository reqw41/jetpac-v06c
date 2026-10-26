; Jetpac на Векторе: загрузка, прерывание (палитра, кадры, клавиатура, джойстик «П», звук), меню, игра.
; Клавиатура и джойстик — по образцу alien8-v06c (tools/a8_vec.py: vec_scan, vec_zxmap, vec_joy).

boot:
		ld	a,0x88			; ППА: порт A — скролл/ряд клавиатуры, B — бордюр/режим
		out	(0x00),a
		xor	a
		out	(0x02),a
		ld	a,0xFF
		out	(0x03),a
		ld	a,0x83			; джойстик «П»: ППИ2 83h, порт 5 = 9Fh, чтение — порт 6
		out	(0x04),a
		ld	a,0x9F
		out	(0x05),a
		in	a,(0x06)
		ld	(vj_rest+1),a		; значение покоя
		call	snd_stop
		call	timer_init
		xor	a
		ld	(lock_mode),a
		ld	(frame_ticked),a
		ei
		call	fs_calib		; тиков секундомера на кадр — на этой машине/эмуляторе
		call	fs_start
		ld	(frame_ticked),a
		; заставка: палитра заставки, картинка (zx0) прямо в экран, ждать клавишу
		ld	hl,pal_splash
		ld	(pal_ptr),hl
		ld	a,3
		ld	(pal_load),a
		ei
		call	clear_screen
		ld	hl,splash_zx0
		ld	bc,0x8000
		call	dzx0
spl_w0:		call	any_key			; дождаться нажатия
		jp	z,spl_w0
spl_w1:		call	any_key			; и отпускания (иначе огонь сразу стартует игру из меню)
		jp	nz,spl_w1
		call	clear_screen
		ld	hl,pal_vec
		ld	(pal_ptr),hl
		ld	a,3
		ld	(pal_load),a
; StartGame: обнулить рекорд и очки
start_game:
		ld	hl,hi_score
		ld	b,0x0A
sg0:		ld	(hl),0
		inc	hl
		dec	b
		jp	nz,sg0
; ResetGame
reset_game:
		ld	sp,STACK_TOP
		xor	a
		ld	(paused),a
		ei
		call	snd_stop
		call	reset_screen
		ld	a,4
		ld	(jetman_velocity_modifier),a
; MenuScreen
menu_screen:
		call	menu_draw
		ld	a,(game_options)
		ld	d,a
		ld	a,0xF7			; ряд 1..5
		call	in_row
		cpl
		ld	e,a
		ld	a,(vj_fire)		; огонь (пробел, джойстик) — «5 START GAME»
		or	a
		jp	z,ms0
		ld	a,e
		or	0x10
		ld	e,a
ms0:		ld	a,e
		and	1
		jp	z,ms1
		ld	a,d
		and	0xFE
		ld	d,a
ms1:		ld	a,e
		and	2
		jp	z,ms2
		ld	a,d
		or	1
		ld	d,a
ms2:		ld	a,e
		and	4
		jp	z,ms3
		ld	a,d
		and	0xFD
		ld	d,a
ms3:		ld	a,e
		and	8
		jp	z,ms4
		ld	a,d
		or	2
		ld	d,a
ms4:		ld	a,(vec_kbmat+1)		; F1+F3 — старт с бессмертием
		and	0x28
		cp	0x28
		jp	z,game_start_god
		ld	a,e
		and	0x10
		jp	nz,game_start
		ld	a,d
		ld	(game_options),a
		ld	hl,menu_colour_table+1	; мигают выбранные пункты
		ld	c,a
		and	1
		call	ms_flash
		ld	a,c
		and	2
		call	ms_flash
		jp	menu_screen
ms_flash:					; Z — первый пункт пары мигает, иначе второй
		jp	nz,msf2
		ld	a,(hl)
		or	0x80
		ld	(hl),a
		inc	hl
		ld	a,(hl)
		and	0x7F
		ld	(hl),a
		inc	hl
		ret
msf2:		ld	a,(hl)
		and	0x7F
		ld	(hl),a
		inc	hl
		ld	a,(hl)
		or	0x80
		ld	(hl),a
		inc	hl
		ret

menu_draw:					; MenuDrawEntries
		ld	b,6
		ld	hl,menu_colour_table
		ld	de,menu_position_table
		ld	(md_txt),hl
		ld	hl,menu_text
		ld	(md_str),hl
		ld	hl,menu_colour_table
md0:		push	bc
		ld	a,(hl)
		ld	(txt_col),a
		inc	hl
		push	hl
		ld	a,(de)
		inc	de
		push	de
		ld	h,a
		ld	l,0x30
		call	coord2scr
		push	hl
		ld	hl,(md_str)
		ex	de,hl
		pop	hl
		call	write_chars
		ex	de,hl
		ld	(md_str),hl
		pop	de
		pop	hl
		pop	bc
		dec	b
		jp	nz,md0
		ld	hl,0xB800
		ld	de,menu_copyright
		jp	display_string
md_txt:		dw	0
md_str:		dw	0
; символы DE (последний с битом 7) в HL цветом txt_col -> DE за строкой
write_chars:
		ld	a,(de)
		ld	c,a
		and	0x7F
		call	draw_char
		inc	de
		ld	a,c
		and	0x80
		jp	z,write_chars
		ret

; --- игра ---------------------------------------------------------------------------------------------
game_start_god:
		ld	a,1
		jp	gs0
game_start:					; ZX: «5» уходит в NewGame, не записав D
		xor	a
gs0:		ld	(god_mode),a
		xor	a
		ld	(game_over),a		; иначе после прошлой игры первый же проход уходит в меню
gs1:		call	any_key			; дождаться отпускания (F1+F3, огонь)
		jp	nz,gs1
		call	new_game
		call	tune_play		; мелодия BBC-версии на старте (игра её ждёт, как на BBC)
		call	timer_init		; канал 0 ВИ53 снова секундомер (звук, кадры)
		call	fs_start
game_loop:
		call	pass
		ld	a,(game_over)
		or	a
		jp	nz,reset_game
		call	flash_update
		jp	game_loop

; мигание «1UP»/«2UP» (FlashText ZX): надпись перерисовывается инверсной по фазе кадров
fl_shown:	db	0
fl_pos:		db	0
flash_update:
		ld	a,(flash_lbl)
		or	a
		jp	z,fu0
		ld	(fl_pos),a
		ld	a,(FRAMES)
		and	0x10
		jp	z,fu0
		ld	a,1
fu0:		ld	b,a			; нужно: 1 — инверсно
		ld	a,(fl_shown)
		cp	b
		ret	z
		ld	a,b
		ld	(fl_shown),a
		ld	(txt_inv),a
		ld	a,(fl_pos)
		ld	l,a
		ld	h,0
		cp	0x18
		ld	de,ScoreLabel1UP
		jp	z,fu1
		ld	de,ScoreLabel2UP
fu1:		call	display_string
		xor	a
		ld	(txt_inv),a
		ret

; --- ld a,r на Векторе: генератор (на сверке — очередь r_buf) --------------------------------------
r_seed:		db	0x5A
get_r_vec:
		ld	a,(r_seed)
		ld	b,a
		add	a,a
		add	a,a
		add	a,b
		add	a,0x1B
		ld	b,a
		ld	a,(FRAMES)
		xor	b
		ld	(r_seed),a
		and	0x7F
		ret

; --- прерывание ---------------------------------------------------------------------------------------
isr:
		push	af
		push	bc
		push	de
		push	hl
		ld	hl,(isr_cnt)		; отладка: число прерываний
		inc	hl
		ld	(isr_cnt),hl
		ld	a,(pal_load)		; палитра: только после смены (3 кадра — на случай промаха мимо обратного хода)
		or	a
		jp	z,isp_np
		dec	a
		ld	(pal_load),a
		ld	hl,(pal_ptr)
		ld	de,15
		add	hl,de
		ld	e,0x0F
isp0:		ld	a,e
		out	(0x02),a
		ld	a,(hl)
		dec	hl
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		dec	e
		jp	p,isp0
		xor	a
		out	(0x02),a
isp_np:		ld	a,(fs_on)		; отметка секундомера на кадровом прерывании (для догона потерянных)
		or	a
		jp	z,isp_fr
		ld	a,(mus_on)
		or	a
		jp	nz,isp_fr
		call	timer_now
		ld	(fs_t),hl
isp_fr:		ld	hl,(FRAMES)		; кадр — по прерыванию (синхронно с лучом)
		inc	hl
		ld	(FRAMES),hl
		ld	a,h
		or	l
		jp	nz,isp1
		ld	hl,FRAMES+2
		inc	(hl)
isp1:		call	vec_scan
		ld	a,(vec_kbmat+0)		; ВК: по нажатию пауза вкл/выкл
		and	0x04
		ld	hl,vk_prev
		ld	b,(hl)
		ld	(hl),a
		jp	z,isp2
		cp	b
		jp	z,isp2
		ld	a,(paused)
		xor	1
		ld	(paused),a
isp2:		call	zx_build
		call	snd_tick
		call	mus_tick
		pop	hl
		pop	de
		pop	bc
		pop	af
		ei
		ret

; палитра: индекс = p80<<3 | pA0<<2 | pC0<<1 | pE0 (чёрная плоскость не видна); сочетания плоскостей —
; ink_planes (render.asm); цвета — «холодная» (вариант 4, 26.10) + Джетмен и салатный из заставки; %BBGGGRRR
pal_ptr:	dw	pal_vec
pal_load:	db	3			; кадров грузить палитру (ставить при смене pal_ptr)
; догон потерянного кадра: прерывание при DI на Векторе теряется (блиттер держит DI на плоскость).
; Если с последнего прерывания по секундомеру прошло больше 1,5 кадра (44928 тиков 1,5 МГц) — кадр
; потерян: FRAMES += 1, отметка -= кадр (29952). Зовёт главный цикл перед проверкой кадра.
fs_t:		dw	0
fs_cnt:		dw	0
isr_cnt:	dw	0
fs_tpf:		dw	29952			; тиков на кадр (калибруется)
fs_thr:		dw	0xFFFF			; порог догона = 1,5 кадра; 0xFFFF — догон выключен
; калибровка: два кадра подряд при включённых прерываниях, без вывода
fs_calib:
		call	fsc_wait
		call	timer_now
		push	hl
		call	fsc_wait
		call	timer_now
		ex	de,hl
		pop	hl
		ld	a,l			; тиков = первый - второй
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
		ld	(fs_tpf),hl
		ld	d,h
		ld	e,l
		ld	a,h			; порог = 1,5 * tpf, если помещается в период секундомера
		and	a
		rra
		ld	h,a
		ld	a,l
		rra
		ld	l,a
		add	hl,de
		jp	c,fsc_off
		ld	a,h
		cp	0xF8
		jp	nc,fsc_off
		ld	(fs_thr),hl
		ret
fsc_off:	ld	hl,0xFFFF
		ld	(fs_thr),hl
		ret
fsc_wait:	ld	a,(FRAMES)
		ld	b,a
fsw0:		ld	a,(FRAMES)
		cp	b
		jp	z,fsw0
		ret
frames_sync:
		ld	a,(lock_mode)
		or	a
		ret	nz
		ld	a,(fs_on)
		or	a
		ret	z
		ld	a,(mus_on)
		or	a
		ret	nz
		di
		call	fsync_core
		ei
		ret
; под DI: прерывание потерялось (с отметки прошло > 1,5 кадра) — FRAMES += 1, отметка -= кадр
fsync_core:
		push	bc
		push	de
		push	hl
		call	timer_now
		ex	de,hl			; DE = сейчас
fsc0:		ld	hl,(fs_t)
		ld	a,l			; прошло = отметка - сейчас (счётчик идёт вниз)
		sub	e
		ld	c,a
		ld	a,h
		sbc	a,d
		ld	b,a
		ld	a,(fs_thr)
		ld	l,a
		ld	a,c
		sub	l
		ld	a,(fs_thr+1)
		ld	l,a
		ld	a,b
		sbc	a,l
		jp	c,fsc_done
		ld	hl,(fs_t)		; отметка -= кадр
		ld	a,(fs_tpf)
		ld	c,a
		ld	a,l
		sub	c
		ld	l,a
		ld	a,(fs_tpf+1)
		ld	c,a
		ld	a,h
		sbc	a,c
		ld	h,a
		ld	(fs_t),hl
		ld	hl,(FRAMES)
		inc	hl
		ld	(FRAMES),hl
		ld	hl,(fs_cnt)
		inc	hl
		ld	(fs_cnt),hl
		jp	fsc0
fsc_done:	pop	hl
		pop	de
		pop	bc
		ret
fs_on:		db	0
; отметка = сейчас, счёт по секундомеру включить
fs_start:
		di
		call	timer_now
		ld	(fs_t),hl
		ld	a,1
		ld	(fs_on),a
		ei
		ret
; NZ — нажата любая клавиша Вектора или огонь джойстика
any_key:
		ld	hl,vec_kbmat
		ld	b,8
		xor	a
ak0:		or	(hl)
		inc	hl
		dec	b
		jp	nz,ak0
		ld	b,a
		ld	a,(vj_fire)
		or	b
		ret
pal_vec:	db	0x00,0x00, 0xD5,0xD5, 0x4E,0x4E, 0xF2,0xF2	; -, пурпурный, красный, голубой
		db	0xEC,0xEC, 0x3D,0x3D, 0xFE,0xFE, 0x2E,0x2E	; Джетмен (голубой заставки), салатный, белый, жёлтый (золото заставки)

; --- клавиатура -----------------------------------------------------------------------------------------
		ALIGN	8
vec_kbmat:	ds	8			; матрица Вектора (1 = нажата)
vec_scan:
		ld	a,0x8A			; порт B на вход
		out	(0x00),a
		ld	hl,vec_kbmat
		ld	b,0xFE
		ld	c,0			; накопитель отличий от прошлого кадра
vs0:		ld	a,b
		out	(0x03),a
		in	a,(0x02)
		cpl
		ld	d,a
		xor	(hl)
		or	c
		ld	c,a
		ld	(hl),d
		inc	hl
		ld	a,b
		rlca
		ld	b,a
		jp	c,vs0
		ld	a,c
		ld	(kb_chg),a
		ld	a,0x88
		out	(0x00),a
		ld	a,0xFF
		out	(0x03),a
		xor	a
		out	(0x02),a
		ret
kb_chg:		db	0xFF
; ряды ZX: zx_kb = клавиши Вектора по vec_zxmap + стрелки/пробел/джойстик (по режиму игры)
vj_fire:	db	0
vk_prev:	db	0
paused:		db	0			; 1 — пауза (ВК); игра стоит в na_pause
zx_build:
		in	a,(0x06)		; джойстик и режим ввода — тоже повод пересобрать
		ld	b,a
		ld	a,(game_options)
		and	2
		or	b
		ld	b,a
		ld	a,(zb_prev)
		cp	b
		ld	a,b
		ld	(zb_prev),a
		jp	nz,zb_go
		ld	a,(kb_chg)
		or	a
		ret	z
zb_go:		ld	hl,zx_kb
		ld	de,vec_zxmap
		ld	c,8
zb0:		ld	b,0x1F			; ряд ZX
		push	hl
		ld	a,1
		ld	(zb_bit),a
zb1:		ld	a,(de)			; ячейка матрицы (младший байт)
		inc	de
		ld	l,a
		ld	h,vec_kbmat >> 8
		ld	a,(de)			; маска
		inc	de
		and	(hl)
		jp	z,zb2
		ld	a,(zb_bit)
		cpl
		and	b
		ld	b,a
zb2:		ld	a,(zb_bit)
		add	a,a
		ld	(zb_bit),a
		cp	0x20
		jp	nz,zb1
		pop	hl
		ld	(hl),b
		inc	hl
		dec	c
		jp	nz,zb0
		; направления: стрелки Вектора + джойстик «П» -> биты 0 R, 1 L, 2 U, 3 D, 6 огонь
		ld	a,(vec_kbmat+0)		; стрелки: 0x10 влево, 0x40 вправо, 0x20 вверх, 0x80 вниз
		ld	b,0
		rlca
		jp	nc,zb3
		ld	b,8			; вниз
zb3:		rlca
		jp	nc,zb4
		inc	b			; вправо
zb4:		rlca
		jp	nc,zb5
		ld	c,a
		ld	a,b
		or	4			; вверх
		ld	b,a
		ld	a,c
zb5:		rlca
		jp	nc,zb6
		ld	a,b
		or	2			; влево
		ld	b,a
zb6:		ld	a,(vec_kbmat+7)		; пробел
		and	0x80
		jp	z,zb7
		ld	a,b
		or	0x40
		ld	b,a
zb7:		in	a,(0x06)		; джойстик «П»
vj_rest:	xor	0xFF			; значение покоя -> 1 = нажато
		ld	c,a
		and	0x30			; биты 4, 5 в покое единица: иначе порта нет — не считать
		jp	nz,zb8
		ld	a,c
		and	0xCF
		ld	c,a
		and	0xC0
		jp	z,zb7a
		ld	a,c
		or	0x40
		ld	c,a
zb7a:		ld	a,c
		and	0x4F
		or	b
		ld	b,a
zb8:		ld	a,b
		and	0x40
		ld	(vj_fire),a
		ld	a,(game_options)
		and	2
		ld	hl,dir_kbd
		jp	z,zb9
		ld	hl,dir_joy
zb9:		ld	c,5			; R L U D огонь
zb10:		ld	a,b
		rrca
		ld	b,a
		jp	nc,zb11
		push	bc
		ld	e,(hl)			; ряд ZX
		inc	hl
		ld	c,(hl)			; маска (0 = нажата)
		dec	hl
		push	hl
		ld	hl,zx_kb
		ld	d,0
		add	hl,de
		ld	a,(hl)
		and	c
		ld	(hl),a
		pop	hl
		pop	bc
zb11:		inc	hl
		inc	hl
		dec	c
		jp	z,zb12
		ld	a,c
		cp	1			; после D (бит 3) — пропустить биты 4, 5 до огня (бит 6)
		jp	nz,zb10
		ld	a,b
		rrca
		rrca
		ld	b,a
		jp	zb10
zb12:		ret
zb_bit:		db	0
zb_prev:	db	0
; клавиши ZX для R, L, U, D, огонь: (ряд, маска)
dir_kbd:	db	0,0xFB, 0,0xFD, 2,0xFE, 7,0xFF, 1,0xFE	; X Z Q - A
dir_joy:	db	4,0xF7, 4,0xEF, 4,0xFD, 4,0xFB, 4,0xFE		; 7 6 9 8 0
; ZX ряд -> клавиши Вектора: 8 рядов x 5 (ячейка vec_kbmat, маска); из alien8-v06c
vec_zxmap:	db	low vec_kbmat+7,0x00, low vec_kbmat+7,0x04, low vec_kbmat+7,0x01, low vec_kbmat+4,0x08, low vec_kbmat+6,0x40	; SHIFT(нет) Z X C V
		db	low vec_kbmat+4,0x02, low vec_kbmat+6,0x08, low vec_kbmat+4,0x10, low vec_kbmat+4,0x40, low vec_kbmat+4,0x80	; A S D F G
		db	low vec_kbmat+6,0x02, low vec_kbmat+6,0x80, low vec_kbmat+4,0x20, low vec_kbmat+6,0x04, low vec_kbmat+6,0x10	; Q W E R T
		db	low vec_kbmat+2,0x02, low vec_kbmat+2,0x04, low vec_kbmat+2,0x08, low vec_kbmat+2,0x10, low vec_kbmat+2,0x20	; 1 2 3 4 5
		db	low vec_kbmat+2,0x01, low vec_kbmat+3,0x02, low vec_kbmat+3,0x01, low vec_kbmat+2,0x80, low vec_kbmat+2,0x40	; 0 9 8 7 6
		db	low vec_kbmat+6,0x01, low vec_kbmat+5,0x80, low vec_kbmat+5,0x02, low vec_kbmat+6,0x20, low vec_kbmat+7,0x02	; P O I U Y
		db	low vec_kbmat+0,0x00, low vec_kbmat+5,0x10, low vec_kbmat+5,0x08, low vec_kbmat+5,0x04, low vec_kbmat+5,0x01	; ENTER(нет: ВК — пауза) L K J H
		db	low vec_kbmat+7,0x80, low vec_kbmat+7,0x10, low vec_kbmat+5,0x20, low vec_kbmat+5,0x40, low vec_kbmat+4,0x04	; SPACE SYM(\) M N B

; --- звук: ВИ53 канал 2 (тон), канал 0 — секундомер (1,5 МГц, вниз) ----------------------------------
; На ZX эффекты — короткие петли бипера (1..25 мс) со сменой тона. Здесь эффект — шаги «делитель + длительность»
; (единица длительности — 8 тиков секундомера, 5,3 мкс); шаги переключает snd_poll из главного цикла (при
; каждом объекте) и из прерывания. Тон и длительность — по тактам петель ZX с поправкой на спорную память
; (код ZX на 0x6000 шёл ~ на 20 % медленнее): тики = такты ZX * 1,5/3,5 * 1,2 ~ такты * (1/2 + 1/64).
; Игра звук не ждёт (на ZX ждала).
timer_init:					; канал 0: режим 2, делитель 0xFFFF (0 на MiSTer не стартует)
		ld	a,0x34
		out	(0x08),a
		ld	a,0xFF
		out	(0x0B),a
		out	(0x0B),a
		ret
timer_now:					; HL = счётчик канала 0
		xor	a
		out	(0x08),a		; защёлка канала 0
		in	a,(0x0B)
		ld	l,a
		in	a,(0x0B)
		ld	h,a
		ret
snd_steps:	ds	4*8			; шаги: делитель, длительность (в 8 тиках)
snd_n:		db	0			; шагов осталось
snd_p:		dw	snd_steps		; текущий шаг
snd_t0:		dw	0			; секундомер на начале шага
snd_f0:		db	0			; FRAMES на начале эффекта (страховка: не дольше 3 кадров)
snd_stop:
		xor	a
		ld	(snd_n),a
		ld	a,0xB0
		out	(0x08),a
		xor	a
		out	(0x09),a
		out	(0x09),a
		ret
; переключение шагов: snd_poll — из главного цикла (под di), snd_tick — из прерывания
snd_poll:
		ld	a,(snd_n)
		or	a
		ret	z
		di
		call	snd_tick
		ei
		ret
snd_tick:
		ld	a,(snd_n)
		or	a
		ret	z
		push	bc
		push	de
		push	hl
		ld	a,(FRAMES)		; страховка: длинные паузы (новый уровень) — сразу тишина
		ld	b,a
		ld	a,(snd_f0)
		sub	b
		cpl
		inc	a
		cp	3
		jp	nc,spo_end
		call	timer_now
		ex	de,hl
		ld	hl,(snd_t0)
		ld	a,l			; прошло = t0 - сейчас (счётчик идёт вниз)
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
		ld	b,3			; в единицах по 8 тиков
spo_sh:		ld	a,h
		and	a
		rra
		ld	h,a
		ld	a,l
		rra
		ld	l,a
		dec	b
		jp	nz,spo_sh
		ex	de,hl			; DE = прошло
		ld	hl,(snd_p)
		inc	hl
		inc	hl
		ld	a,e			; прошло >= длительность?
		sub	(hl)
		inc	hl
		ld	a,d
		sbc	a,(hl)
		jp	c,spo_ret
		; следующий шаг: t0 -= длительность*8
		dec	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl			; HL -> следующий шаг
		ld	(snd_p),hl
		ex	de,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ex	de,hl
		ld	hl,(snd_t0)
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
		ld	(snd_t0),hl
		ld	hl,snd_n
		dec	(hl)
		jp	z,spo_end
		ld	hl,(snd_p)
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	a,e			; следующий шаг — только делитель (без разрыва фазы)
		out	(0x09),a
		ld	a,d
		out	(0x09),a
		jp	spo_ret
spo_end:	call	snd_stop
spo_ret:	pop	hl
		pop	de
		pop	bc
		ret
; шаг в буфер: HL = делитель, DE = длительность (в 8 тиках); BC -> буфер (растёт)
snd_put:
		ld	a,l
		ld	(bc),a
		inc	bc
		ld	a,h
		ld	(bc),a
		inc	bc
		ld	a,e
		ld	(bc),a
		inc	bc
		ld	a,d
		ld	(bc),a
		inc	bc
		ld	hl,snd_n
		inc	(hl)
		ret
; x * 0,514 ~ x/2 + x/64 (HL -> HL)
snd_k:
		push	de
		ld	d,h
		ld	e,l
		ld	a,6
sk0:		push	af
		ld	a,d
		and	a
		rra
		ld	d,a
		ld	a,e
		rra
		ld	e,a
		pop	af
		dec	a
		jp	nz,sk0			; DE = x/64
		ld	a,h
		and	a
		rra
		ld	h,a
		ld	a,l
		rra
		ld	l,a			; HL = x/2
		add	hl,de
		pop	de
		ret
; A = вид (1, 2 — меандр D, C периодов; 3 — лазер; 4 — взрыв C)
snd_play:
		ld	(sp_k),a
		ld	a,c
		ld	(sp_c),a
		ld	a,d
		ld	(sp_d),a
		di
		xor	a
		ld	(snd_n),a
		ld	a,(sp_k)
		cp	3
		jp	z,sp_laser
		cp	4
		jp	z,sp_expl
		; меандр: период ZX ~ 26*D + 47 тактов, C периодов
		ld	a,(sp_d)
		ld	l,a
		ld	h,0
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,de			; 3D
		add	hl,hl
		add	hl,hl			; 12D
		add	hl,de			; 13D
		add	hl,hl			; 26D
		ld	de,47
		add	hl,de
		call	snd_k			; HL = делитель
		push	hl
		ex	de,hl			; длительность = C * делитель / 8
		ld	hl,0
		ld	a,(sp_c)
		or	a
		jp	z,spw1
spw0:		add	hl,de
		jp	c,spw_big
		dec	a
		jp	nz,spw0
		jp	spw1
spw_big:	ld	hl,0xFFFF
spw1:		ld	b,3
spw2:		ld	a,h
		and	a
		rra
		ld	h,a
		ld	a,l
		rra
		ld	l,a
		dec	b
		jp	nz,spw2
		ex	de,hl			; DE = длительность
		pop	hl			; делитель
		ld	bc,snd_steps
		call	snd_put
		jp	sp_go
sp_k:		db	0
sp_c:		db	0
sp_d:		db	0
sp_laser:	ld	hl,laser_steps
		ld	de,snd_steps
		ld	b,6*4
spl0:		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		dec	b
		jp	nz,spl0
		ld	a,6
		ld	(snd_n),a
		jp	sp_go
; лазер: c = 8..55, период ZX 26c + 58, по 8 значений c на шаг (tools: см. docs/LOGIC_PLAN.md)
laser_steps:	dw	184,184, 291,291, 398,398, 505,505, 611,611, 718,718
; взрыв: c = C..1, период ZX 26c + 47; 4 шага по четверти C
sp_expl:	ld	a,(sp_c)
		or	a
		jp	z,sp_go
		ld	bc,snd_steps
		ld	e,4
spx0:		push	de
		; c середины четверти: C - (2s+1)*C/8, s = 4 - E
		ld	a,(sp_c)
		rrca
		rrca
		rrca
		and	0x1F			; C/8
		ld	d,a
		ld	a,4
		sub	e			; s
		add	a,a
		inc	a			; 2s+1
		ld	l,a
		xor	a
spx1:		add	a,d
		dec	l
		jp	nz,spx1
		ld	l,a
		ld	a,(sp_c)
		sub	l
		jp	nc,spx2
		ld	a,1
spx2:		jp	nz,spx3
		inc	a
spx3:		ld	l,a			; c
		ld	h,0
		push	bc
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,de
		add	hl,hl
		add	hl,hl
		add	hl,de
		add	hl,hl			; 26c
		ld	de,47
		add	hl,de
		call	snd_k			; делитель
		ld	a,(sp_c)		; длительность = (C/4) * делитель / 8
		rrca
		rrca
		and	0x3F
		jp	nz,spx4
		inc	a
spx4:		push	hl
		ex	de,hl
		ld	hl,0
spx5:		add	hl,de
		dec	a
		jp	nz,spx5
		ld	a,3
spx6:		push	af
		ld	a,h
		and	a
		rra
		ld	h,a
		ld	a,l
		rra
		ld	l,a
		pop	af
		dec	a
		jp	nz,spx6
		ex	de,hl
		pop	hl
		pop	bc
		call	snd_put
		pop	de
		dec	e
		jp	nz,spx0
sp_go:		ld	a,(snd_n)
		or	a
		jp	nz,sp_g1
		call	snd_stop
		ei
		ret
sp_g1:		ld	a,(FRAMES)
		ld	(snd_f0),a
		call	timer_now
		ld	(snd_t0),hl
		ld	hl,snd_steps
		ld	(snd_p),hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
		call	snd_out
		ei
		ret
snd_out:	ld	a,0xB6			; канал 2, младший/старший, режим 3, двоичный
		out	(0x08),a
		ld	a,l
		out	(0x09),a
		ld	a,h
		out	(0x09),a
		ret

; --- мелодия старта игры (BBC Micro, Дэвид Рис Джонс, 1983): 38 нот по 150 мс, каналы 1->2->3 по кругу,
; огибающая 4 (звон с вибрато 1/4 полутона). Здесь: три канала ВИ53 по кругу, нота звенит 11 кадров
; (~1,5 ноты — соседние накладываются), вибрато — каждые 4 кадра делитель меньше на 1/64.
; Строй выровнен по нотам (в оригинале всё ниже на ~1/4 полутона). Разбор — docs/BBC_TUNE.md.
mus_notes:	dw	6074, 6074, 3037, 6074, 6074, 3037, 6074, 4054, 4295, 4551
		dw	6074, 6074, 3037, 6074, 6074, 3037, 6074, 4054, 4295, 4551
		dw	4821, 4821, 2411, 4821, 4821, 2411, 4821, 4551, 4295, 4054
		dw	6074, 6074, 3037, 6074, 6074, 3037, 6074, 3037
MUS_N		equ	38
mus_on:		db	0
mus_idx:	db	0			; следующая нота
mus_wait:	db	0			; кадров до неё
mus_rot:	db	0			; канал следующей ноты 0..2
mus_ph:		db	0			; фаза вибрато
mus_left:	ds	3			; кадров звучать каналу
mus_div:	ds	6			; делители каналов
; каналы ВИ53: управляющее слово и порт данных
mus_ctl:	db	0x36, 0x76, 0xB6
mus_port:	db	0x0B, 0x0A, 0x09

tune_play:
		call	snd_stop
		xor	a
		ld	(mus_idx),a
		ld	(mus_rot),a
		ld	(mus_left),a
		ld	(mus_left+1),a
		ld	(mus_left+2),a
		inc	a
		ld	(mus_wait),a
		ld	(mus_on),a
tp0:		ld	a,(mus_on)		; ждать конца (клавиатура, как на BBC, не прерывает)
		or	a
		jp	nz,tp0
		ret

; из прерывания: каждые 7/8 кадров новая нота, каналы гаснут по счётчикам, вибрато
mus_tick:
		ld	a,(mus_on)
		or	a
		ret	z
		ld	hl,mus_ph
		inc	(hl)
		; новая нота?
		ld	hl,mus_wait
		dec	(hl)
		jp	nz,mt_ch
		ld	a,(mus_idx)
		cp	MUS_N
		jp	nc,mt_ch		; ноты кончились — дозвучать
		ld	b,a
		inc	a
		ld	(mus_idx),a
		and	1			; 150 мс = 7,5 кадра: попеременно 8 и 7
		add	a,7
		ld	(mus_wait),a
		ld	a,b
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,mus_notes
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)			; DE = делитель
		ld	a,(mus_rot)
		ld	c,a
		inc	a
		cp	3
		jp	c,mt_r
		xor	a
mt_r:		ld	(mus_rot),a
		ld	b,0
		ld	hl,mus_left
		add	hl,bc
		ld	(hl),11
		ld	hl,mus_div
		add	hl,bc
		add	hl,bc
		ld	(hl),e
		inc	hl
		ld	(hl),d
		call	mus_set			; новая нота: режим 3 и делитель
mt_ch:		; каналы: делитель (с вибрато) пишется без управляющего слова — без разрыва фазы
		ld	c,0
mt_c0:		ld	b,0
		ld	hl,mus_left
		add	hl,bc
		ld	a,(hl)
		or	a
		jp	z,mt_nx			; давно молчит
		dec	(hl)
		jp	z,mt_off
		ld	hl,mus_div
		add	hl,bc
		add	hl,bc
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	a,(mus_ph)		; вибрато: кадры 4..7 из 12 — выше на 1/4 полутона
		and	0x0C
		cp	4
		jp	nz,mt_out
		ld	h,d
		ld	l,e
		ld	a,6			; DE -= DE >> 6
mt_sh:		ld	b,a
		ld	a,h
		and	a
		rra
		ld	h,a
		ld	a,l
		rra
		ld	l,a
		ld	a,b
		dec	a
		jp	nz,mt_sh
		ld	a,e
		sub	l
		ld	e,a
		ld	a,d
		sbc	a,h
		ld	d,a
mt_out:		call	mus_cnt
		jp	mt_nx
mt_off:		ld	de,8			; конец ноты: неслышимо высокий тон (без щелчка режима 0)
		call	mus_cnt
mt_nx:		inc	c
		ld	a,c
		cp	3
		jp	c,mt_c0
		; всё отзвучало?
		ld	a,(mus_idx)
		cp	MUS_N
		ret	c
		ld	a,(mus_left)
		ld	b,a
		ld	a,(mus_left+1)
		or	b
		ld	b,a
		ld	a,(mus_left+2)
		or	b
		ret	nz
		xor	a
		ld	(mus_on),a
		ld	c,0			; тишина: режим 0 всем каналам (один раз)
mt_q:		ld	de,0
		call	mus_set
		inc	c
		ld	a,c
		cp	3
		jp	c,mt_q
		ret
; канал C: только делитель (канал уже в режиме 3)
mus_cnt:
		ld	b,0
		ld	hl,mus_port
		add	hl,bc
		ld	a,(hl)
		jp	ms_port
; канал C: DE = делитель (0 — тишина: режим 0 с нулём на выходе)
mus_set:
		ld	b,0
		ld	hl,mus_ctl
		add	hl,bc
		ld	a,d
		or	e
		ld	a,(hl)
		jp	nz,ms_on
		and	0xF0			; режим 0 — выход в 0
ms_on:		out	(0x08),a
		ld	hl,mus_port
		add	hl,bc
		ld	a,(hl)
ms_port:	cp	0x0B
		jp	z,ms_p0
		cp	0x0A
		jp	z,ms_p1
		ld	a,e
		out	(0x09),a
		ld	a,d
		out	(0x09),a
		ret
ms_p1:		ld	a,e
		out	(0x0A),a
		ld	a,d
		out	(0x0A),a
		ret
ms_p0:		ld	a,e
		out	(0x0B),a
		ld	a,d
		out	(0x0B),a
		ret
