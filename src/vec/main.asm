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
		xor	a
		ld	(lock_mode),a
		ld	(frame_ticked),a
		; заставка: палитра заставки, картинка (zx0) прямо в экран, ждать клавишу
		ld	hl,pal_splash
		ld	(pal_ptr),hl
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
ms4:		ld	a,e
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
game_start:					; ZX: «5» уходит в NewGame, не записав D
		call	new_game
		call	tune_play		; мелодия BBC-версии на старте (игра её ждёт, как на BBC)
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
		ld	hl,(pal_ptr)		; палитра: все 16 записей каждый кадр (луч в обратном ходе)
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
		ld	a,(frame_ticked)	; во вложенном проходе кадр не считается (ZX: DI)
		or	a
		jp	nz,isp1
		ld	hl,(FRAMES)
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
vs0:		ld	a,b
		out	(0x03),a
		in	a,(0x02)
		cpl
		ld	(hl),a
		inc	hl
		ld	a,b
		rlca
		ld	b,a
		jp	c,vs0
		ld	a,0x88
		out	(0x00),a
		ld	a,0xFF
		out	(0x03),a
		xor	a
		out	(0x02),a
		ret
; ряды ZX: zx_kb = клавиши Вектора по vec_zxmap + стрелки/пробел/джойстик (по режиму игры)
vj_fire:	db	0
vk_prev:	db	0
paused:		db	0			; 1 — пауза (ВК); игра стоит в na_pause
zx_build:
		ld	hl,zx_kb
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

; --- звук: ВИ53 канал 2 (порт 09h, управление 08h), меандр, асинхронно (из прерывания) ----------------
; На ZX эффекты — петли бипера, игра ждала их; здесь звук идёт сам, игра не ждёт. Делитель и длительность —
; по таймингам петель ZX (3,5 МГц): период меандра PlaySquareWav2 ~ 26*D + 40 тактов -> делитель ВИ53
; (1,5 МГц) N = 0,43 * период = 11*D + D/8 + 17; длительность C периодов. Лазер — «пиу» в два шага
; (на ZX полупериод растёт c = 8..55), взрыв — короткий щелчок высотой по C.
snd_left:	db	0			; кадров звучать текущему шагу
snd_nxt:	dw	0			; делитель второго шага (0 — нет)
snd_nxf:	db	0			; его кадры
snd_stop:
		xor	a
		ld	(snd_left),a
		ld	a,0xB0
		out	(0x08),a
		xor	a
		out	(0x09),a
		out	(0x09),a
		ret
snd_tick:
		ld	a,(snd_left)
		or	a
		ret	z
		dec	a
		ld	(snd_left),a
		ret	nz
		ld	hl,(snd_nxt)
		ld	a,h
		or	l
		jp	z,snd_stop
		ld	a,(snd_nxf)
		ld	(snd_left),a
		ld	de,0
		ex	de,hl
		ld	(snd_nxt),hl
		ex	de,hl
		jp	snd_out
; A = вид (1, 2 — меандр D, C периодов; 3 — лазер; 4 — взрыв C)
snd_play:
		ld	hl,0
		ld	(snd_nxt),hl
		cp	3
		jp	z,sp_laser
		cp	4
		jp	z,sp_expl
		; N = 11*D + D/8 + 17
		ld	a,d
		ld	(sp_d),a
		ld	l,d
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl
		add	hl,hl
		add	hl,de			; 5D
		add	hl,hl			; 10D
		add	hl,de			; 11D
		ld	a,e
		rrca
		rrca
		rrca
		and	0x1F
		add	a,17
		add	a,l
		ld	l,a
		ld	a,h
		adc	a,0
		ld	h,a
		add	hl,hl			; октавой ниже: на ZX код в спорной памяти шёл медленнее, звук ниже
		ld	(sp_n),hl
		; кадров = C * (26*D + 40) / 70000 ~ (C * ((26*D + 40) >> 6)) >> 10
		ld	l,e			; E = D (сохранён выше)
		ld	h,0
		add	hl,hl			; 2D
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,hl			; 8D
		push	hl
		add	hl,hl			; 16D
		pop	de			; (8D)
		add	hl,de			; 24D
		ld	e,c			; C — периодов
		ld	a,(sp_d)
		add	a,a
		ld	c,a
		ld	b,0
		add	hl,bc			; 26D (младшая часть 2D; D < 128 у всех эффектов)
		ld	c,e
		ld	de,40
		add	hl,de
		add	hl,hl
		add	hl,hl			; H = (26D + 40) >> 6
		ld	e,h
		ld	d,0
		ld	hl,0
		ld	a,c
		or	a
		jp	z,sp_f1
sp_m:		add	hl,de
		dec	c
		jp	nz,sp_m
sp_f1:		ld	a,h
		rrca
		rrca
		and	0x3F
		jp	nz,sp_f2
		inc	a
sp_f2:		ld	(snd_left),a
		ld	hl,(sp_n)
		jp	snd_out
sp_n:		dw	0
sp_d:		db	0
sp_laser:	ld	hl,1200			; второй шаг ~1,25 кГц
		ld	(snd_nxt),hl
		ld	a,2
		ld	(snd_nxf),a
		ld	a,1
		ld	(snd_left),a
		ld	hl,600			; ~2,5 кГц
		jp	snd_out
sp_expl:	ld	a,(FRAMES)		; треск: N ~ 48*C + 300 с прыжком тона от кадра
		and	0x1F
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	de,300
		add	hl,de
		ex	de,hl
		ld	l,c
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl			; 16C
		ld	b,h
		ld	c,l
		add	hl,hl			; 32C
		add	hl,bc			; 48C
		add	hl,de
		ld	a,2
		ld	(snd_left),a
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
mt_ch:		; каналы: звучащие — делитель (с вибрато), погасшие — тишина
		ld	c,0
mt_c0:		ld	b,0
		ld	hl,mus_left
		add	hl,bc
		ld	a,(hl)
		or	a
		jp	z,mt_off
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
mt_out:		call	mus_set
		jp	mt_nx
mt_off:		ld	de,0
		call	mus_set
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
		ret
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
		cp	0x0B
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
