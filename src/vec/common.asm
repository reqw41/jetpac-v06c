; Общие подпрограммы логики Jetpac на i8080 (по src/model/logic.js): ввод, столкновения, лазер-попадание,
; счёт, текст, жизни, платформы. Текущий объект — копия в ws (8 байт), адрес — cur (см. loop.asm).

; адрес Вектора для координат ZX (Y, X) — на этапе сборки
VADDR		MACRO	yy, xx
		ld	hl,((0x80 + ((xx) >> 3)) << 8) | ((223 - (yy)) & 0xFF)
		ENDM

; --- ввод: матрица ZX zx_kb[8] (бит = 0 — нажата) ------------------------------------------------------
; in_row: A = старший байт порта (нули выбирают ряды) -> A = 0xE0 | биты (как in a,($fe))
in_row:
		push	hl
		push	bc
		ld	c,a
		ld	b,0x1F
		ld	hl,zx_kb
		REPT	8
		ld	a,c
		rrca
		ld	c,a
		jp	c,$+6			; ряд не выбран
		ld	a,(hl)
		and	b
		ld	b,a
		inc	hl
		ENDR
		ld	a,b
		or	0xE0
		pop	bc
		pop	hl
		ret

read_i2:	ld	a,0xEF
		jp	in_row

read_lr:
		ld	a,(game_options)
		and	2
		jp	nz,read_i2
		ld	a,0xFE
		call	in_row
		and	0x1E
		cp	0x1E
		jp	z,rlr0
		and	0x14
		cp	0x14
		ld	a,0xEF
		ret	z
		ld	a,0xF7
		ret
rlr0:		ld	a,0x7F
		call	in_row
		and	0x1E
		cp	0x1E
		jp	z,rlr_none
		and	0x14
		cp	0x14
		ld	a,0xF7
		ret	z
		ld	a,0xEF
		ret
rlr_none:	ld	a,0xFF
		ret

; ReadInputFire / ReadInputThrust: два ряда; нажатие -> hit, иначе 0xFF
read_fire:
		ld	a,(game_options)
		and	2
		jp	nz,read_i2
		ld	a,0xFD
		call	in_row
		and	0x1F
		cp	0x1F
		jp	nz,rf_hit
		ld	a,0xBF
		call	in_row
		and	0x1F
		cp	0x1F
		ld	a,0xFF
		ret	z
rf_hit:		ld	a,0xFE
		ret
read_thrust:
		ld	a,(game_options)
		and	2
		jp	nz,read_i2
		ld	a,0xFB
		call	in_row
		and	0x1F
		cp	0x1F
		jp	nz,rt_hit
		ld	a,0xDF
		call	in_row
		and	0x1F
		cp	0x1F
		ld	a,0xFF
		ret	z
rt_hit:		ld	a,0xFD
		ret

; --- актёр ----------------------------------------------------------------------------------------------
tmp_actor:					; TmpActorPosUpdate
		ld	a,(ws+1)
		ld	(actor),a
		ld	a,(ws+2)
		ld	(actor+1),a
		ld	a,(ws)
		ld	(actor+2),a
		ret
actor_update_dir:				; ActorUpdateDir
		call	tmp_actor
		ld	a,(ws)
		and	0xC0
		or	3
		ld	(actor+2),a
		ret

; --- PlatformCollisionCheckAll -> E ------------------------------------------------------------------
pcca:
		ld	hl,gfx_params_platforms
		ld	b,4
pc_loop:	ld	e,0
		inc	hl			; p+1: X платформы
		ld	a,(ws+1)
		ld	c,a
		ld	a,(hl)
		sub	c
		jp	m,pc_neg
		ld	c,a			; справа или над: у пришельцев (тип 3) -9
		ld	a,(ws)
		and	0x3F
		cp	3
		ld	a,c
		jp	nz,pc_w
		sub	9
		jp	p,pc_w
		add	a,9
		jp	pc_w
pc_neg:		cpl
		inc	a
		ld	c,a
		ld	a,e
		or	0x40
		ld	e,a
		ld	a,c
pc_w:		inc	hl
		inc	hl			; p+3: ширина
		cp	(hl)
		jp	nc,pc_next3
		add	a,0x12
		cp	(hl)
		jp	c,pc_0
		ld	a,e
		or	8
		ld	e,a
pc_0:		dec	hl			; p+2: Y платформы
		ld	a,(ws+2)
		ld	c,a
		ld	a,(hl)
		sub	c
		cpl
		inc	a
		inc	a
		inc	a
		jp	m,pc_next2
		cp	2
		jp	c,pc_land
		ld	c,a
		ld	a,(ws+7)
		ld	d,a
		ld	a,c
		cp	d
		jp	c,pc_hit
		sub	2
		cp	d
		jp	nc,pc_next2
		ld	a,e
		or	0x10
		ld	e,a
pc_hit:		ld	a,e
		or	4
		ld	e,a
		ret
pc_land:	ld	a,e
		or	0x84
		ld	e,a
		ret
pc_next3:	dec	hl
pc_next2:	dec	hl
		dec	hl
		inc	hl
		inc	hl
		inc	hl
		inc	hl
		dec	b
		jp	nz,pc_loop
		ret

; --- AlienCollision -> E = 1 при столкновении с Джетменом ---------------------------------------------
alien_coll:
		ld	e,0
		ld	a,(jetman_motion)
		and	0x3F
		dec	a
		jp	z,ac0
		dec	a
		ret	nz
ac0:		ld	a,(ws+1)
		ld	c,a
		ld	a,(jetman_pos_x)
		sub	c
		jp	p,ac1
		cpl
		inc	a
ac1:		cp	0x0C
		ret	nc
		ld	a,(ws+2)
		ld	c,a
		ld	a,(jetman_pos_y)
		sub	c
		jp	p,ac2
		cpl
		inc	a
		add	a,0x0E
		ld	c,a
		ld	a,(ws+7)
		ld	d,a
		ld	a,c
		jp	ac3
ac2:		ld	d,0x15
ac3:		cp	d
		ret	nc
		ld	e,1
		ret

; --- LaserBeamFire -> C = 1, если пришельца задел лазер ---------------------------------------------
laser_fire:
		ld	hl,laser_beam_params
		ld	b,4
lf_loop:	ld	a,(hl)
		or	a
		jp	z,lf_next
		push	hl
		inc	hl
		inc	hl
		inc	hl
		ld	a,(hl)			; импульс 2
		ld	c,a
		and	4
		jp	z,lf_pop
		ld	a,(ws+1)
		ld	d,a
		ld	a,c
		and	0xF8
		sub	d
		jp	p,lf1
		cpl
		inc	a
		ld	c,8
		jp	lf2
lf1:		ld	c,0x20
lf2:		cp	c
		jp	nc,lf_pop
		pop	hl
		push	hl
		inc	hl			; Y лазера
		ld	a,(ws+2)
		ld	d,a
		ld	a,(hl)
		sub	d
		cpl
		inc	a
		jp	m,lf_pop
		add	a,0x0C
		ld	c,a
		ld	a,(ws+7)
		ld	d,a
		ld	a,c
		cp	d
		jp	nc,lf_pop
		inc	hl			; импульс 1
		ld	a,(hl)
		and	0xF8
		ld	(hl),a
		pop	hl
		ld	c,1
		ret
lf_pop:		pop	hl
lf_next:	ld	de,8
		add	hl,de
		dec	b
		jp	nz,lf_loop
		ld	c,0
		ret

; --- счёт ---------------------------------------------------------------------------------------------
; AddPointsToScore: BC = очки (BCD)
add_points:
		ld	a,(current_player_number)
		or	a
		ld	hl,p1_score+2
		jp	z,ap1
		ld	hl,p2_score+2
ap1:		ld	a,(hl)
		add	a,c
		daa
		ld	(hl),a
		dec	hl
		ld	a,(hl)
		adc	a,b
		daa
		ld	(hl),a
		dec	hl
		ld	a,(hl)
		adc	a,0
		daa
		ld	(hl),a
		ld	a,(current_player_number)
		or	a
		jp	nz,show_score_p2
show_score_p1:
		VADDR	8, 0x08
		ld	de,p1_score
		jp	display_score
show_score_p2:
		VADDR	8, 0xC8
		ld	de,p2_score
		jp	display_score
show_score_hi:
		VADDR	8, 0x68
		ld	de,hi_score
; DisplayScore: HL = адрес, DE -> 3 байта BCD; цифры жёлтые (атрибуты строки 1 — 0x46)
display_score:
		ld	a,0x46
		ld	(txt_col),a
		ld	b,3
ds0:		ld	a,(de)
		rrca
		rrca
		rrca
		rrca
		and	0x0F
		add	a,0x30
		call	draw_char
		ld	a,(de)
		and	0x0F
		add	a,0x30
		call	draw_char
		inc	de
		dec	b
		jp	nz,ds0
		ret

; --- текст --------------------------------------------------------------------------------------------
txt_col:	db	0x47
; draw_char: A = символ, HL = адрес; цвет txt_col; HL -> следующее знакоместо; BC, DE сохраняются
draw_char:
		push	de
		push	hl
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	de,system_font-0x100
		add	hl,de
		ex	de,hl
		pop	hl
		ld	a,(txt_col)
		call	draw_cell
		pop	de
		ret
; DisplayString: HL = Y,X; DE -> цвет, символы (последний с битом 7)
display_string:
		call	coord2scr
		ld	a,(de)
		ld	(txt_col),a
		inc	de
dstr0:		ld	a,(de)
		ld	c,a
		and	0x7F
		call	draw_char
		inc	de
		ld	a,c
		and	0x80
		jp	z,dstr0
		ret

draw_status_labels:			; DrawStatusBarLabels
		ld	hl,0x0018
		ld	de,ScoreLabel1UP
		call	display_string
		ld	hl,0x0078
		ld	de,ScoreLabelHI
		call	display_string
		ld	hl,0x00D8
		ld	de,ScoreLabel2UP
		jp	display_string

; --- жизни --------------------------------------------------------------------------------------------
p1_lives:	ld	a,(current_player_number)
		or	a
		ld	a,(player_lives)
		ret	z
		ld	a,(inactive_player_lives)
		ret
p2_lives:	ld	a,(current_player_number)
		or	a
		ld	a,(player_lives)
		ret	nz
		ld	a,(inactive_player_lives)
		ret
display_lives:					; DisplayPlayerLives
		ld	a,0x47
		ld	(txt_col),a
		call	p1_lives
		VADDR	0, 0x40
		call	dl_one
		call	p2_lives
		VADDR	0, 0xB0
dl_one:		or	a
		jp	z,dl_sp
		add	a,0x30
		call	draw_char
		ld	de,tile_life_icon
		ld	a,0x47
		jp	draw_cell
dl_sp:		ld	a,0x20
		call	draw_char
		ld	a,0x20
		jp	draw_char

; --- платформы ----------------------------------------------------------------------------------------
draw_platforms:
		ld	hl,gfx_params_platforms
		ld	b,4
dp0:		push	bc
		push	hl
		ld	a,(hl)			; цвет
		or	a
		jp	z,dp_next
		ld	(txt_col),a
		inc	hl
		ld	c,(hl)			; X
		inc	hl
		ld	d,(hl)			; Y
		inc	hl
		ld	a,(hl)			; ширина
		ld	e,a
		and	0xFC
		cpl
		inc	a
		add	a,c
		add	a,0x10
		ld	l,a
		ld	h,d
		call	coord2scr
		ld	a,e
		rrca
		rrca
		and	0x3F
		sub	4
		ld	b,a			; средних плиток
		ld	de,tile_platform_left
		ld	a,(txt_col)
		call	draw_cell
dp1:		ld	de,tile_platfor_mmiddle
		ld	a,(txt_col)
		call	draw_cell
		dec	b
		jp	nz,dp1
		ld	de,tile_platform_right
		ld	a,(txt_col)
		call	draw_cell
dp_next:	pop	hl
		ld	de,4
		add	hl,de
		pop	bc
		dec	b
		jp	nz,dp0
		ret

; --- экран --------------------------------------------------------------------------------------------
; очистка 4 плоскостей (0x8000..0xFFFF) через push, прерывания — между блоками по 512 байт
clear_screen:
		xor	a
		ld	(k_used),a
		ld	hl,0
		add	hl,sp
		ld	(cs_sp),hl
		ld	hl,0			; SP = 0x0000 -> пишет вниз от 0xFFFF
		ld	(cs_pos),hl
		ld	b,64			; 64 блока по 512 байт
cs0:		ld	de,0
		ld	hl,(cs_pos)
		di
		ld	sp,hl
		REPT	256
		push	de
		ENDR
		ld	hl,0
		add	hl,sp
		ld	(cs_pos),hl
		ld	hl,(cs_sp)
		ld	sp,hl
		ei
		dec	b
		jp	nz,cs0
		ret
cs_sp:		dw	0
cs_pos:		dw	0

; ResetScreen
reset_screen:
		call	clear_screen
		call	draw_status_labels
		call	show_score_p1
		call	show_score_p2
		jp	show_score_hi
