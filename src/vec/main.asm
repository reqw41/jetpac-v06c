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
		pop	hl
		pop	de
		pop	bc
		pop	af
		ei
		ret

; палитра: индекс = p80<<3 | pA0<<2 | pC0<<1 | pE0 (чёрная плоскость не видна);
; сочетания плоскостей -> цвета ZX как в ink_planes (render.asm); цвет Вектора %BBGGGRRR
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
pal_vec:	db	0x00,0x00, 0x71,0x71, 0x4E,0x4E, 0xF2,0xF2	; -, зелёный, красный, голубой (палитра «холодная», выбор владельца 26.10)
		db	0xFE,0xFE, 0x76,0x76, 0xD5,0xD5, 0xD9,0xD9	; белый, жёлтый, пурпурный, синий

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

; --- звук: ВИ53 канал 2 (порт 09h, управление 08h), меандр; эффекты ZX пересчитаны в делитель и кадры --
snd_left:	db	0			; кадров звучать
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
		jp	snd_stop
; A = вид (1, 2 — меандр D/C; 3 — лазер; 4 — взрыв C), C, D
snd_play:
		cp	3
		jp	z,sp_laser
		cp	4
		jp	z,sp_expl
		; полупериод ZX ~ 13*D + 26 тактов; делитель ВИ53 (1,5 МГц) ~ 0,43*(26*D + 52) = 11*D + D/8 + 22
		ld	l,d
		ld	h,0
		push	hl
		add	hl,hl
		add	hl,hl
		push	hl
		add	hl,hl			; 8D
		pop	de
		add	hl,de			; 12D
		pop	de
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a			; 11D
		ld	de,22
		add	hl,de
		; длительность: кадров = C * N / 30000 ~ (N/16) * (C/16 + 1) / 128
		push	hl
		ld	a,l
		rrca
		rrca
		rrca
		rrca
		and	0x0F
		ld	e,a
		ld	a,h
		add	a,a
		add	a,a
		add	a,a
		add	a,a
		or	e
		ld	e,a
		ld	d,0
		ld	a,c
		rrca
		rrca
		rrca
		rrca
		and	0x0F
		inc	a
		ld	b,a
		ld	hl,0
sp_m:		add	hl,de
		dec	b
		jp	nz,sp_m
		add	hl,hl
		ld	a,h
		inc	a
		ld	(snd_left),a
		pop	hl
		jp	snd_out
sp_c:		db	0
sp_laser:	ld	hl,374
		ld	a,2
		ld	(snd_left),a
		jp	snd_out
sp_expl:	ld	l,c			; низкий шум: делитель ~ 11*C + 22
		ld	h,0
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,de
		add	hl,de
		add	hl,de
		ld	de,22
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
