; Объекты главного цикла Jetpac на i8080 (по src/model/logic.js). Текущий объект — копия ws (8 байт),
; адрес — cur; диспетчер копирует объект в ws и обратно (если ws_skip = 0). Подпрограммы, которые
; переписывают объекты целиком (новый уровень, конец хода), сначала сбрасывают ws (ws_flush).

; --- звук: событие A = 1 (Wave1), 2 (Wav2), 3 (лазер), 4 (взрыв); C, D — параметры -------------------
sound_ev:
		call	snd_block
		push	hl
		push	af
		ld	a,(lock_mode)		; на сверке — в журнал, в игре — в ВИ53
		or	a
		jp	nz,se_log
		pop	af
		push	bc
		push	de
		call	snd_play
		pop	de
		pop	bc
		pop	hl
		ret
se_log:		pop	af
		ld	hl,(snd_ptr)
		ld	(hl),a
		inc	hl
		ld	(hl),c
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(snd_ptr),hl
		pop	hl
		ret
; snd_block: пауза на время звука ZX (бипер блокировал игру); A = вид, C, D; регистры сохраняет.
; 1, 2: C периодов по 2 * (13 * D) тактов ZX -> ~C * D витков по 20 тактов Вектора;
; 3 (лазер): ~42000 тактов ZX; 4 (взрыв): сумма по c = C..1 (26c + 50) -> c витков + 2 на шаг.
snd_block:
		push	af
		push	bc
		push	de
		cp	3
		jp	z,sbl_laser
		cp	4
		jp	z,sbl_expl
sbl_w0:		ld	a,d			; C раз по D витков
sbl_w1:		dec	a
		jp	nz,sbl_w1
		dec	c
		jp	nz,sbl_w0
		jp	sbl_end
sbl_laser:	ld	de,1800
sbl_l0:		dec	de
		ld	a,d
		or	e
		jp	nz,sbl_l0
		jp	sbl_end
sbl_expl:	ld	a,c
		or	a
		jp	z,sbl_end
sbl_e0:		ld	a,c
		add	a,2
sbl_e1:		dec	a
		jp	nz,sbl_e1
		dec	c
		jp	nz,sbl_e0
sbl_end:	pop	de
		pop	bc
		pop	af
		ret

sfx_thrusters:
		ld	a,(ws+2)
		rrca
		rrca
		rrca
		rrca
		and	0x7F
		or	0x40
		ld	d,a
		ld	c,0x10
		ld	a,2
		jp	sound_ev
sfx_rocket_build:
		ld	d,0x20
		ld	c,0x50
		ld	a,2
		jp	sound_ev
sfx_pickup_fuel:
		ld	d,0x50
		ld	c,0x28
		ld	a,2
		jp	sound_ev
sfx_pickup_item:
		ld	d,0x30
		ld	c,0x40
		ld	a,1
		jp	sound_ev
; SfxSetExplodeParams: A = 0 / 1
sfx_set_explode:
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,explosion_sfx_defaults
		add	hl,de
		ld	a,(hl)
		ld	(explosion_sfx_params),a
		inc	hl
		ld	a,(hl)
		ld	(explosion_sfx_params+1),a
		ret
sfx_jetman_death:
		ld	a,(ws+1)
		dec	a
		ld	(ws+1),a
		jp	z,sfx_finish
		ld	c,0x10
		ld	a,4
		jp	sound_ev
sfx_enemy_death:
		ld	a,(ws+1)
		dec	a
		ld	(ws+1),a
		jp	z,sfx_finish
		add	a,0x18
		ld	c,a
		ld	a,4
		jp	sound_ev
sfx_finish:	xor	a
		ld	(ws),a
		ret

; --- анимации -------------------------------------------------------------------------------------------
anim_reset:					; AnimationStateReset (ws)
		ld	a,(ws)
		and	0xC0
		or	3
		ld	b,a
		xor	a
		ld	(ws+5),a
		ld	a,b
anim_enable:	ld	(ws+6),a
		ld	a,8
		ld	(ws),a
		xor	a
		ld	(ws+4),a
		ret
; то же для объекта HL (не текущего)
anim_reset_hl:
		ld	a,(hl)
		and	0xC0
		or	3
		ld	b,a
		push	hl
		ld	de,5
		add	hl,de
		ld	(hl),0
		inc	hl
		ld	(hl),b			; +6
		pop	hl
		ld	(hl),8
		inc	hl
		inc	hl
		inc	hl
		inc	hl
		ld	(hl),0			; +4
		ret

explosion_after_kill:
		ld	a,(jetman_pos_x)
		ld	(jetman_exploding_anim_state+1),a
		ld	a,(jetman_pos_y)
		ld	(jetman_exploding_anim_state+2),a
		ld	a,(jetman_motion)
		ld	(jetman_exploding_anim_state+6),a
		ld	a,1
		ld	(jetman_exploding_anim_state+5),a
		ld	a,8
		ld	(jetman_exploding_anim_state),a
		xor	a
		ld	(jetman_exploding_anim_state+4),a
		ld	(jetman_motion),a
		ret
alien_coll_anim_sfx:
		call	anim_reset
		ld	a,1
		call	sfx_set_explode
		jp	explosion_after_kill
alien_kill1:
		call	anim_reset
		xor	a
		jp	sfx_set_explode
alien_kill2:					; BC = очки
		call	add_points
		call	anim_reset
		ld	a,1
		jp	sfx_set_explode

; --- буферы спрайтов (сдвиги, зеркало) в формате вывода ------------------------------------------------
; buffer_copy: HL -> таблица сырых спрайтов, DE = буфер, B = сдвиг, C = число; bc_skip2 = 1 — пропустить
; [X, ширина] у спрайта (модули ракеты/предметы)
bc_skip2:	db	0
bc_tbl:		dw	0
bc_buf:		dw	0
bc_cnt:		db	0
bc_shift:	db	0
bc_h2:		db	0
bc_rows:	db	0
bc_colp:	dw	0
buffer_copy:
		ld	(bc_tbl),hl
		ex	de,hl
		ld	(bc_buf),hl
		ld	a,b
		ld	(bc_shift),a
		ld	a,c
		ld	(bc_cnt),a
bcp0:		ld	hl,(bc_tbl)
		ld	e,(hl)
		inc	hl
		ld	d,(hl)			; DE -> сырой спрайт
		ld	a,(bc_skip2)
		or	a
		jp	z,bcp1
		inc	de
		inc	de
bcp1:		ld	a,(de)			; высота
		inc	de
		cp	0x11
		jp	c,bcp2
		ld	a,0x10
bcp2:		ld	hl,(bc_buf)
		ld	(hl),0
		inc	hl
		ld	(hl),3
		inc	hl
		ld	(hl),a
		inc	hl
		ld	(bc_rows),a
		inc	a
		and	0xFE
		ld	(bc_h2),a
		ld	(bc_colp),hl
		ld	b,a			; обнулить 3 столбца (дополнение до чётной)
		add	a,b
		add	a,b
		ld	b,a
		xor	a
bcz:		ld	(hl),a
		inc	hl
		dec	b
		jp	nz,bcz
bcr:		ld	a,(jetman_rocket_mod_connected)
		or	a
		jp	nz,bcr_flip
		ld	a,(de)			; SpriteReadTwoBytes: C:D:E = b0:b1:0 >> сдвиг
		ld	c,a
		inc	de
		ld	a,(de)
		inc	de
		push	de
		ld	d,a
		ld	e,0
		ld	a,(bc_shift)
		or	a
		jp	z,bcr_put
		ld	b,a
bcr_r:		ld	a,c
		and	a
		rra
		ld	c,a
		ld	a,d
		rra
		ld	d,a
		ld	a,e
		rra
		ld	e,a
		dec	b
		jp	nz,bcr_r
		jp	bcr_put
bcr_flip:	ld	a,(de)			; BufferFlipSprite: C:D:E = 0:rev(b1):rev(b0) << сдвиг
		call	rev_bits
		ld	c,a
		inc	de
		ld	a,(de)
		inc	de
		push	de
		call	rev_bits
		ld	d,a
		ld	e,c
		ld	c,0
		ld	a,(bc_shift)
		or	a
		jp	z,bcr_put
		ld	b,a
bcr_l:		ld	a,e
		add	a,a
		ld	e,a
		ld	a,d
		rla
		ld	d,a
		ld	a,c
		rla
		ld	c,a
		dec	b
		jp	nz,bcr_l
bcr_put:	ld	hl,(bc_colp)		; столбцы 0, 1, 2 этой строки
		ld	(hl),c
		inc	hl
		ld	(bc_colp),hl
		dec	hl
		ld	a,(bc_h2)
		ld	c,a
		ld	b,0
		add	hl,bc
		ld	(hl),d
		add	hl,bc
		ld	(hl),e
		pop	de			; сырой — следующая строка
		ld	a,(bc_rows)
		dec	a
		ld	(bc_rows),a
		jp	nz,bcr
		; следующий буфер: +0x33, следующая запись таблицы: +2, сдвиг += rocket_mod_attached
		ld	hl,(bc_buf)
		ld	de,0x33
		add	hl,de
		ld	(bc_buf),hl
		ld	hl,(bc_tbl)
		inc	hl
		inc	hl
		ld	(bc_tbl),hl
		ld	a,(rocket_mod_attached)
		ld	b,a
		ld	a,(bc_shift)
		add	a,b
		ld	(bc_shift),a
		ld	a,(bc_cnt)
		dec	a
		ld	(bc_cnt),a
		jp	nz,bcp0
		ret

rev_bits:					; A -> биты в обратном порядке; портит B
		push	bc
		ld	c,a
		ld	b,8
rv0:		ld	a,c
		rrca
		ld	c,a
		ld	a,b			; собрать в B? — сдвигаем в E через A
		ld	a,(rv_acc)
		rla
		ld	(rv_acc),a
		dec	b
		jp	nz,rv0
		ld	a,(rv_acc)
		pop	bc
		ret
rv_acc:		db	0

; BufferCopyRocket: A = смещение спрайта (8 — модули)
buffer_copy_rocket:
		ld	c,a
		ld	a,(player_level)
		rrca
		and	6
		or	c
		ld	e,a
		ld	d,0
		ld	hl,raw_collectible_sprite_table
		add	hl,de
		ld	a,2
		ld	(rocket_mod_attached),a
		xor	a
		ld	(jetman_rocket_mod_connected),a
		ld	a,1
		ld	(bc_skip2),a
		ld	de,buffers_item_1
		ld	b,0			; сдвиг 0, 2, 4, 6 — один и тот же спрайт в 4 буфера
		ld	c,4
bcr4:		push	bc
		push	hl
		push	de
		ld	c,1
		call	buffer_copy
		pop	de
		ld	hl,0x33
		add	hl,de
		ex	de,hl
		pop	hl
		pop	bc
		ld	a,(rocket_mod_attached)
		add	a,b
		ld	b,a
		dec	c
		jp	nz,bcr4
		xor	a
		ld	(bc_skip2),a
		ret

; AlienBufferInit
alien_buffer_init:
		ld	a,(player_level)
		rlca
		rlca
		and	0x1C
		ld	e,a
		ld	d,0
		ld	hl,raw_alien_sprite_table
		add	hl,de
		push	hl
		ld	a,4
		ld	(rocket_mod_attached),a
		xor	a
		ld	(jetman_rocket_mod_connected),a
		ld	(bc_skip2),a
		ld	de,buffers_aliens_R1
		ld	bc,0x0002
		call	buffer_copy
		pop	hl
		ld	a,1
		ld	(jetman_rocket_mod_connected),a
		ld	de,buffers_aliens_L1
		ld	bc,0x0002
		jp	buffer_copy

; --- предметы -------------------------------------------------------------------------------------------
item_get_sprite_ofs:				; A += ws+6 -> ItemGetSpriteAddress
		ld	b,a
		ld	a,(ws+6)
		add	a,b
item_get_sprite:				; A = смещение -> DE = спрайт вывода
		ld	e,a
		ld	d,0
		ld	hl,vs_collectible_sprite_table
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ret
item_display_sprite:
		xor	a
		call	item_get_sprite_ofs
		call	actor_update_position
		jp	colourize_sprite
item_drop_gold:
		ld	a,0x46
		ld	(ws+3),a
		jp	item_display_sprite
item_drop_plutonium:
		ld	a,0x44
		ld	(ws+3),a
		jp	item_display_sprite
item_drop_chemical:
		ld	a,(game_timer)
		and	0x1F
		cp	0x18
		ld	a,0x45
		jp	nc,idc0
		xor	a
idc0:		ld	(ws+3),a
		jp	item_display_sprite
item_drop_random:
		ld	a,(game_timer)
		rrca
		rrca
		and	7
		jp	nz,idr0
		inc	a
idr0:		or	0x40
		ld	(ws+3),a
		jp	item_display_sprite
item_drop_table:
		dw	item_drop_gold, item_drop_chemical, item_drop_chemical, item_drop_plutonium, item_drop_random

item_check_collect:
		call	tmp_actor
		call	pcca
		ld	a,e
		and	4
		jp	nz,icc0
		ld	a,(ws+2)
		add	a,2
		ld	(ws+2),a
icc0:		call	alien_coll
		dec	e
		jp	nz,item_drop_new
		xor	a
		call	item_get_sprite_ofs
		call	actor_destroy
		xor	a
		ld	(ws),a
		ld	bc,0x0250
		call	add_points
		jp	sfx_pickup_item
item_drop_new:
		ld	a,(ws+6)
		and	0x0F
		ld	e,a
		ld	d,0
		ld	hl,item_drop_table
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		jp	(hl)

redraw_sprite:
		call	update_and_erase_actor
		jp	colourize_sprite
inc_y_redraw:
		ld	a,(ws+2)
		add	a,2
		ld	(ws+2),a
		jp	redraw_sprite
item_pickup:
		call	tmp_actor
		ld	a,(ws+4)
		ld	b,a
		and	4
		jp	nz,pickup_rocket_item
		ld	a,b
		and	2
		jp	nz,carry_rocket_item
		ld	a,b
		and	1
		jp	nz,ip1
		ld	a,(player_level)		; GetCollectibleID
		rrca
		and	6
		call	item_get_sprite_ofs
		call	actor_erase_anim_sprite
		jp	colourize_sprite
ip1:		call	alien_coll
		dec	e
		jp	z,collect_rocket_item
		call	pcca
		ld	a,e
		and	4
		jp	nz,redraw_sprite
		jp	inc_y_redraw
attach_jetman:
		ld	a,(jetman_pos_x)
		ld	(ws+1),a
		ld	a,(jetman_pos_y)
		ld	(ws+2),a
		ret
collect_rocket_item:
		ld	a,(ws+4)
		or	2
		ld	(ws+4),a
		call	actor_find_destroy
		ld	bc,0x0100
		call	add_points
		call	sfx_pickup_fuel
		call	attach_jetman
		call	tmp_actor
		jp	redraw_sprite
carry_rocket_item:
		call	attach_jetman
		ld	a,(ws+1)
		ld	b,a
		ld	a,(rocket_state+1)
		sub	b
		jp	p,cri0
		cpl
		inc	a
cri0:		cp	6
		jp	nc,redraw_sprite
		ld	a,(ws+4)
		or	4
		ld	(ws+4),a
		ld	a,(rocket_state+1)
		ld	(ws+1),a
		jp	redraw_sprite
pickup_rocket_item:
		ld	a,(ws+6)
		cp	0x18
		jp	z,pri_fuel
		add	a,a
		ld	b,a
		ld	a,(ws+2)
		add	a,b
		cp	0xB7
		jp	c,inc_y_redraw
		; модуль на месте: rocket_module_state+4 |= 1 (это может быть текущий объект)
		ld	hl,(cur)
		ld	a,l
		cp	rocket_module_state & 0xFF
		jp	nz,pri_m1
		ld	a,(ws+4)
		or	1
		ld	(ws+4),a
		jp	pri_m2
pri_m1:		ld	a,(rocket_module_state+4)
		or	1
		ld	(rocket_module_state+4),a
pri_m2:		ld	hl,rocket_state+4
		inc	(hl)
		ld	a,(ws+6)
		add	a,8
		call	buffer_copy_rocket
		jp	pri_done
pri_fuel:	ld	a,(ws+2)
		cp	0xB0
		jp	c,inc_y_redraw
		ld	hl,rocket_state+5
		inc	(hl)
pri_done:	call	actor_find_destroy
		xor	a
		ld	(ws),a
		jp	sfx_rocket_build

item_calc_drop_column:				; -> A
		ld	a,(random_number)
		and	0x0F
		ld	e,a
		ld	d,0
		ld	hl,item_drop_positions_table
		add	hl,de
		ld	a,(hl)
		ret
jetman_slow:					; Z = нет (направление 0 или >= 3)
		ld	a,(jetman_motion)
		and	0x3F
		ret	z
		cp	3
		jp	nc,js_no
		or	a			; NZ
		ret
js_no:		xor	a
		ret
copy8:						; HL -> DE, 8 байт
		REPT	8
		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		ENDR
		ret
item_new_collectible:
		call	jetman_slow
		ret	z
		ld	a,(item_state)
		or	a
		ret	nz
		ld	a,(game_timer)
		and	0x7F
		ret	nz
		ld	hl,default_item_state
		ld	de,item_state
		call	copy8
		call	item_calc_drop_column
		ld	(item_state+1),a
		call	get_r
		and	0x0E
		ld	b,a
		and	8
		jp	z,inc0
		ld	b,8
inc0:		ld	a,b
		or	0x20
		ld	(item_state+6),a
		ret
item_new_fuel_pod:
		call	jetman_slow
		ret	z
		ld	a,(rocket_module_state)
		or	a
		ret	nz
		ld	a,(rocket_state+5)
		cp	6
		ret	nc
		ld	a,(game_timer)
		cpl
		and	0x0F
		ret	nz
		ld	hl,default_rocket_module_state
		ld	de,rocket_module_state
		call	copy8
		call	item_calc_drop_column
		ld	(rocket_module_state+1),a
		ret

; --- ракета ---------------------------------------------------------------------------------------------
rocket_animate_flames:
		ld	a,(ws+2)
		add	a,0x15
		ld	(ws+2),a
		ld	a,(actor+1)
		add	a,0x15
		ld	(actor+1),a
		ld	a,(ws+2)
		cp	0xB8
		jp	z,raf3
		jp	nc,raf1
		ld	a,(game_timer)
		and	4
		ld	de,vs_rocket_flames1
		jp	nz,raf0
		ld	de,vs_rocket_flames2
raf0:		push	de
		ld	de,vs_rocket_flames1
		call	actor_destroy
		ld	de,vs_rocket_flames2
		call	actor_destroy
		pop	de
		call	actor_erase_anim_sprite
		ld	a,0x42
		ld	(ws+3),a
		call	colourize_sprite
raf1:		ld	a,(ws+2)
		sub	0x15
		ld	(ws+2),a
		ld	a,(actor+1)
		sub	0x15
		ld	(actor+1),a
		ret
raf3:		ld	de,vs_rocket_flames1
		call	actor_destroy
		ld	de,vs_rocket_flames2
		call	actor_destroy
		jp	raf1

rocket_takeoff:
		call	tmp_actor
		ld	hl,ws+2
		dec	(hl)
		call	sfx_thrusters
		call	rocket_animate_flames
		ld	a,(ws+2)
		cp	0x28
		jp	nc,update_rocket_colour
		ld	hl,player_level
		inc	(hl)
		ld	hl,ws
		inc	(hl)
		xor	a
		ld	(ws+5),a
		call	ws_flush			; дальше объекты переписываются
		ld	hl,rocket_module_state		; RocketModulesReset
		ld	b,0x0C
		call	set_inactive
		jp	level_new
rocket_landing:
		call	tmp_actor
		ld	hl,ws+2
		inc	(hl)
		call	sfx_thrusters
		call	rocket_animate_flames
		ld	a,(ws+2)
		cp	0xB7
		jp	c,update_rocket_colour
		ld	a,9
		ld	(ws),a
		call	player_init
		jp	update_rocket_colour
rocket_update:
		call	tmp_actor
		call	alien_coll
		dec	e
		jp	nz,update_rocket_colour
		ld	a,(ws+5)
		cp	6
		jp	c,update_rocket_colour
		ld	hl,ws
		inc	(hl)
		ld	a,(jetman_pos_x)		; TmpActorPosUpdate для Джетмена
		ld	(actor),a
		ld	a,(jetman_pos_y)
		ld	(actor+1),a
		ld	a,(jetman_motion)
		ld	(actor+2),a
		call	actor_find_destroy
		xor	a
		ld	(jetman_motion),a
		ld	hl,player_lives
		inc	(hl)
		jp	display_lives

; UpdateRocketColour: модули ракеты перерисовываются; цвета полос по 8 строк считаются заранее
urc_last:	ds	16			; цвета полос на экране
urc_cols:	ds	16			; цвет полос снизу вверх (модулей может быть больше 3 — запись в память)
urc_x:		db	0
urc_y:		db	0
update_rocket_colour:
		ld	a,(ws+1)
		ld	(urc_x),a
		ld	a,(ws+2)
		ld	(urc_y),a
		; цвета полос и итоговый ws+3 (как в ZX)
		ld	a,(ws+4)
		add	a,a
		ld	b,a			; полос = модулей * 2
		ld	(urc_nb),a
		ld	c,0x47
		cp	6
		jp	c,urc_fill
		ld	a,(ws+5)
		or	a
		jp	z,urc_fill
		cp	6
		jp	c,urc_fuel
		ld	a,(game_timer)
		rrca
		rrca
		and	4
		or	0x43
		ld	c,a			; заправлена: мигание
		jp	urc_fill
urc_fuel:	ld	b,a
		ld	a,6
		ld	(urc_nb),a
		ld	a,b
		ld	hl,urc_cols		; первые fuel полос — пурпурные, остальные белые
		ld	c,6
urf0:		ld	(hl),0x43
		inc	hl
		dec	c
		dec	b
		jp	nz,urf0
urf1:		ld	(hl),0x47
		inc	hl
		dec	c
		jp	nz,urf1
		ld	a,0x47
		ld	(ws+3),a
		jp	urc_draw
urc_fill:	ld	a,c
		ld	(ws+3),a
		ld	hl,urc_cols
		ld	b,16
urf2:		ld	(hl),c
		inc	hl
		dec	b
		jp	nz,urf2
urc_draw:	ld	a,(ws+4)
		ld	b,a
		ld	c,0
		ld	hl,urc_cols
urd0:		push	bc
		push	hl
		ld	a,(player_level)
		rrca
		rrca
		and	3
		or	c
		add	a,a
		call	item_get_sprite
		call	actor_update_position		; стереть старый, кадр нового — в nf_*
		xor	a
		ld	(nf_pend),a
		pop	hl
		push	hl
		ld	a,(nf_same)		; кадр на месте: если цвет полос сменился — стереть
		or	a
		jp	z,urd1
		ld	de,urc_last-urc_cols
		ex	de,hl
		add	hl,de			; HL -> urc_last[полоса], DE -> urc_cols[полоса]
		ld	a,(de)
		cp	(hl)
		jp	nz,urd_er
		inc	hl
		inc	de
		ld	a,(de)
		cp	(hl)
		jp	z,urd1
urd_er:		call	load_nf
		call	blit_erase
urd1:		pop	hl
		push	hl
		ld	de,urc_last-urc_cols	; запомнить цвета полос
		ex	de,hl
		add	hl,de
		ld	a,(de)
		ld	(hl),a
		inc	hl
		inc	de
		ld	a,(de)
		ld	(hl),a
		pop	hl
		push	hl
		ld	a,(hl)			; нижняя полоса модуля
		ld	c,0
		call	urc_half
		pop	hl
		inc	hl
		push	hl
		ld	a,(hl)			; верхняя полоса
		ld	c,8
		call	urc_half
		pop	hl
		inc	hl
		ld	a,(ws+2)
		sub	0x10
		ld	(ws+2),a
		ld	a,(actor+1)
		sub	0x10
		ld	(actor+1),a
		pop	bc
		ld	a,c
		add	a,4
		ld	c,a
		dec	b
		jp	nz,urd0
		ld	a,2
		ld	(actor+4),a
		xor	a
		ld	(actor+3),a
		ld	a,(urc_x)
		ld	(actor_coords),a
		ld	a,(urc_nb)		; ColourizeSprite по полосам: Y -= 8 за полосу
		add	a,a
		add	a,a
		add	a,a
		ld	b,a
		ld	a,(urc_y)
		ld	(ws+2),a
		sub	b
		ld	(actor_coords+1),a
		ret
urc_nb:		db	0
; полоса модуля: A = цвет, C = первая строка (0 / 8); 8 строк по каждому столбцу кадра nf_*
urc_half:
		ld	(urh_col),a
		ld	a,(nf_h2)		; строк в полосе: min(8, h2 - C)
		sub	c
		ret	c
		ret	z
		cp	8
		jp	c,urh_n
		ld	a,8
urh_n:		ld	(urh_cnt),a
		ld	a,(nf_w)
		ld	b,a
		ld	hl,(nf_scr)
		ld	a,l
		add	a,c
		ld	l,a
		ld	(bl_scr),hl
		ld	hl,(nf_dat)
		ld	e,c
		ld	d,0
		add	hl,de
urh0:		ld	(bl_dat),hl
		push	hl
		push	bc
		ld	a,1
		ld	(bl_w),a
		ld	a,(urh_cnt)
		ld	(bl_h2),a
		ld	a,(urh_col)
		call	blit_draw
		pop	bc
		ld	hl,(bl_scr)
		inc	h
		ld	(bl_scr),hl
		ld	a,(nf_h2)
		ld	e,a
		ld	d,0
		pop	hl
		add	hl,de
		dec	b
		jp	nz,urh0
		ret
urh_col:	db	0
urh_cnt:	db	0

; --- взрывы и пустые места ------------------------------------------------------------------------------
animate_explosion:
		ld	hl,current_alien_number
		inc	(hl)
		ld	a,(ws+4)
		ld	c,a			; кадр
		ld	a,(ws+5)
		ld	b,a
		ld	a,(game_timer)
		and	b
		jp	nz,ae0
		ld	hl,ws+4
		inc	(hl)
ae0:		ld	a,c
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,vs_explosion_sprite_table
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	a,c
		cp	6
		jp	nc,ae1
		cp	3
		jp	nc,ae2
		call	actor_erase_anim_sprite
		ld	a,(random_number)
		and	7
		or	0x42
		ld	(ws+3),a
		jp	colourize_sprite
ae2:		ld	hl,(ws+1)		; GetSpritePosition с Y,X объекта
		call	old_frame_hl
		jp	actor_erase_destroyed
ae1:		ld	a,(ws+6)
		ld	(ws),a
		call	tmp_actor
		call	actor_find_destroy
		xor	a
		ld	(ws),a
		ld	a,(ws+6)
		and	0x3F
		cp	3
		ret	nc
		call	ws_flush
		jp	player_turn_ends
; FrameRateLimiter: пустой слот, кадр не сменился — пауза как на ZX (192 витка ~ 5000 тактов ZX
; = 4290 тактов Вектора). Этим оригинал и держит темп.
frame_rate_limiter:
		ld	a,(frame_ticked)
		or	a
		ret	nz
		ld	b,120			; подобрано: средний проход как у ZX (lock80, «темп»)
frl0:		dec	b
		jp	nz,frl0
		ret

; --- пришельцы ------------------------------------------------------------------------------------------
draw_alien:
		ld	a,(ws)
		push	af
		and	0xC0
		or	3
		ld	(ws),a
		call	update_and_erase_actor
		call	colourize_sprite
		pop	af
		ld	(ws),a
		ret

jet_fighter_update:
		ld	hl,current_alien_number
		inc	(hl)
		call	actor_update_dir
		ld	hl,0
		ld	(jf_hl),hl
		ld	a,(ws+4)
		and	2
		jp	nz,jf4
		ld	a,(random_number)
		and	0x1F
		call	z,jf_speed
		ld	a,(ws+2)
		ld	b,a
		ld	a,(jetman_pos_y)
		sub	0x0C
		cp	b
		call	z,jf_speed
		ld	a,(game_timer)
		and	0x40
		jp	nz,jf_down
		jp	jf_up
jf4:		ld	a,(ws+5)
		dec	a
		ld	(ws+5),a
		jp	z,jf_die
		ld	a,(ws)
		and	0x40
		ld	a,4
		jp	z,jf5
		ld	a,0xFC
jf5:		ld	(jf_hl),a
		ld	a,(ws+2)
		ld	b,a
		ld	a,(jetman_pos_y)
		cp	b
		jp	c,jf_up
jf_down:	ld	a,2
		jp	jf6
jf_up:		ld	a,0xFE
jf6:		ld	(jf_hl+1),a
		ld	a,(ws)
		and	0xC0
		or	3
		ld	(ws),a
		ld	a,(jf_hl)
		ld	b,a
		ld	a,(ws+1)
		add	a,b
		ld	(ws+1),a
		ld	a,(jf_hl+1)
		ld	b,a
		ld	a,(ws+2)
		add	a,b
		ld	(ws+2),a
		call	update_and_erase_actor
		call	colourize_sprite
		ld	a,(ws+2)
		cp	0x28
		jp	c,jf_die
		call	laser_fire
		ld	a,c
		and	1
		jp	nz,jf_die
		call	pcca
		ld	a,e
		and	4
		jp	nz,jf_die
		call	alien_coll
		dec	e
		jp	z,alien_coll_anim_sfx
		ld	a,(ws)
		and	0xC0
		or	7
		ld	(ws),a
		ret
jf_speed:					; JetFighterUpdate_3: A = C
		ld	c,a
		ld	a,(ws+4)
		or	2
		ld	(ws+4),a
		ld	a,(game_timer)
		add	a,c
		and	0x7F
		or	0x20
		ld	(ws+5),a
		ld	a,0x47
		ld	(ws+3),a
		ret
jf_die:		ld	bc,0x0055
		call	add_points
		call	sfx_thrusters
		jp	anim_reset
jf_hl:		dw	0

; касание платформы у пришельцев: E -> бит 7 / 6 (ws+4); flip = 0x40 для UFO и корабля
; выход: A = 0x80 (сверху), 0x10 (снизу), иначе 0
alien_bounce:
		ld	(ab_flip),a
		call	pcca
		ld	a,e
		and	4
		ret	z
		ld	a,e
		and	0x80
		jp	nz,ab_top
		ld	a,e
		and	0x10
		jp	nz,ab_bot
		ld	a,e
		and	0x40
		ld	b,a
		ld	a,(ab_flip)
		xor	b
		ld	b,a
		ld	a,(ws+4)
		and	0xBF
		or	b
		ld	(ws+4),a
		xor	a
		ret
ab_top:		call	res7
		ld	a,0x80
		ret
ab_bot:		call	set7
		ld	a,0x10
		ret
ab_flip:	db	0
set7:		ld	a,(ws+4)
		or	0x80
		ld	(ws+4),a
		ret
res7:		ld	a,(ws+4)
		and	0x7F
		ld	(ws+4),a
		ret

squidgy_update:
		ld	hl,current_alien_number
		inc	(hl)
		call	actor_update_dir
		call	laser_fire
		dec	c
		jp	z,sq_kill
		call	alien_coll
		dec	e
		jp	z,alien_coll_anim_sfx
		xor	a
		ld	(alien_new_dir_flag),a
sq0:		xor	a
		call	alien_bounce
		ld	a,(ws+4)
		and	0x40
		ld	a,(ws+1)
		jp	z,sq_l
		add	a,2
		jp	sq1
sq_l:		sub	2
sq1:		ld	(ws+1),a
		ld	a,(ws+4)
		and	0x80
		ld	a,(ws+2)
		jp	z,sq_u
		add	a,2
		jp	sq2
sq_u:		sub	2
		cp	0x24
		jp	nc,sq2
		ld	b,a
		call	set7
		ld	a,b
sq2:		ld	(ws+2),a
		ld	a,(alien_new_dir_flag)
		or	a
		jp	nz,draw_alien
		inc	a
		ld	(alien_new_dir_flag),a
		jp	sq0
sq_kill:	ld	bc,0x0080
		call	add_points
		jp	alien_kill1

; UFOUpdate_17: L = B, DE = (C << 4) << 1
ufo_off:
		ld	l,b
		ld	a,c
		add	a,a
		add	a,a
		add	a,a
		add	a,a
		ld	e,a
		ld	d,0
		ex	de,hl
		add	hl,hl
		ex	de,hl
		ret
ufo_update:
		ld	hl,current_alien_number
		inc	(hl)
		call	actor_update_dir
		call	laser_fire
		dec	c
		jp	z,ufo_kill
		call	alien_coll
		dec	e
		jp	z,alien_coll_anim_sfx
		xor	a
		ld	(alien_new_dir_flag),a
uf0:		ld	a,0x40
		call	alien_bounce
		; по X
		ld	a,(ws+5)
		ld	b,a
		and	0x0F
		ld	c,a
		ld	a,b
		and	0xF0
		ld	b,a
		ld	a,(ws+1)
		ld	d,a
		ld	a,(jetman_pos_x)
		sub	d
		jp	p,ufx_pos
		ld	a,(ws+4)
		and	0x40
		jp	z,ufx_10
		ld	a,c			; _1inc
		cp	0x0F
		jp	nc,ufx_2
		inc	a
		jp	ufx_2
ufx_10:		ld	a,c
		dec	a
		jp	nz,ufx_8
		ld	a,(ws+4)
		or	0x40
		ld	(ws+4),a
		xor	a
		jp	ufx_2
ufx_pos:	ld	a,(ws+4)
		and	0x40
		jp	z,ufx_9
		ld	a,c			; _7dec
		dec	a
		jp	nz,ufx_2
		ld	a,(ws+4)
		and	0xBF
		ld	(ws+4),a
		xor	a
		jp	ufx_8
ufx_9:		ld	a,c
		cp	0x0F
		jp	nc,ufx_8
		inc	a
ufx_8:		ld	c,a
		ld	a,(ws+1)
		ld	h,a
		push	hl
		call	ufo_off
		pop	af			; H из стека в A — вернуть H
		ld	h,a
		add	hl,de
		jp	ufx_3
ufx_2:		ld	c,a
		ld	a,(ws+1)
		ld	h,a
		push	hl
		call	ufo_off
		pop	af
		ld	h,a
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
ufx_3:		ld	a,h
		ld	(ws+1),a
		ld	a,l
		and	0xF0
		or	c
		ld	(ws+5),a
		; по Y
		ld	a,(ws+6)
		ld	b,a
		and	0x0F
		ld	c,a
		ld	a,b
		and	0xF0
		ld	b,a
		ld	a,(ws+2)
		ld	d,a
		ld	a,(jetman_pos_y)
		sub	d
		jp	p,ufy_pos
		ld	a,(ws+4)
		and	0x80
		jp	z,ufy_14
		ld	a,c			; dec
		dec	a
		jp	nz,ufy_12
		call	res7
		xor	a
		jp	ufy_4
ufy_14:		ld	a,c
		cp	0x0F
		jp	nc,ufy_4
		inc	a
		jp	ufy_4
ufy_pos:	ld	a,(ws+4)
		and	0x80
		jp	z,ufy_13
		ld	a,c			; _11inc
		cp	0x0F
		jp	nc,ufy_12
		inc	a
		jp	ufy_12
ufy_13:		ld	a,c
		dec	a
		jp	nz,ufy_4
		call	set7
		xor	a
ufy_12:		ld	c,a
		ld	a,(ws+2)
		ld	h,a
		push	hl
		call	ufo_off
		pop	af
		ld	h,a
		add	hl,de
		jp	ufy_5
ufy_4:		ld	c,a
		ld	a,(ws+2)
		ld	h,a
		push	hl
		call	ufo_off
		pop	af
		ld	h,a
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
ufy_5:		ld	a,h
		cp	0x28
		jp	nc,ufy_6
		call	set7
		ld	a,h
ufy_6:		ld	(ws+2),a
		ld	a,l
		and	0xF0
		or	c
		ld	(ws+6),a
		ld	a,(alien_new_dir_flag)
		or	a
		jp	nz,draw_alien
		inc	a
		ld	(alien_new_dir_flag),a
		jp	uf0
ufo_kill:	ld	bc,0x0050
		call	add_points
		jp	alien_kill1

sphere_update:
		ld	hl,current_alien_number
		inc	(hl)
		call	actor_update_dir
		xor	a
		ld	(alien_new_dir_flag),a
		call	laser_fire
		dec	c
		ld	bc,0x0040
		jp	z,alien_kill2
		call	alien_coll
		dec	e
		jp	z,alien_coll_anim_sfx
sp0:		xor	a
		call	alien_bounce
		ld	a,(ws+4)
		and	1
		jp	nz,sp2
		ld	a,(random_number)
		ld	e,a
		and	0x0F
		jp	nz,sp2
		ld	a,(ws+4)
		or	1
		ld	(ws+4),a
		ld	a,(game_timer)
		and	0x1F
		add	a,0x10
		ld	(ws+6),a
		ld	a,e
		and	0x80
		ld	e,a
		ld	a,(ws+4)
		and	0x7F
		or	e
		ld	(ws+4),a
		jp	sp0
sp2:		ld	a,(ws+4)
		and	1
		jp	z,sp4
		ld	a,(ws+4)
		and	0x80
		ld	a,(ws+2)
		jp	z,sp_u
		add	a,2
		jp	sp3
sp_u:		sub	2
		cp	0x28
		jp	nc,sp3
		ld	b,a
		call	set7
		ld	a,b
sp3:		ld	(ws+2),a
		ld	a,(ws+6)
		dec	a
		ld	(ws+6),a
		jp	nz,sp4
		ld	a,(ws+4)
		and	0xFE
		ld	(ws+4),a
sp4:		ld	a,(ws+4)
		and	0x40
		ld	a,(ws+1)
		jp	z,sp_l
		add	a,2
		jp	sp5
sp_l:		sub	2
sp5:		ld	(ws+1),a
		ld	a,(alien_new_dir_flag)
		or	a
		jp	nz,draw_alien
		inc	a
		ld	(alien_new_dir_flag),a
		jp	sp0

crossed_ship_update:
		call	actor_update_dir
		ld	hl,current_alien_number
		inc	(hl)
		call	laser_fire
		dec	c
		ld	bc,0x0060
		jp	z,alien_kill2
		call	alien_coll
		dec	e
		jp	z,alien_coll_anim_sfx
		xor	a
		ld	(alien_new_dir_flag),a
cs_0:		ld	a,0x40
		call	alien_bounce
		cp	0x80
		jp	nz,cs_1
		ld	a,(random_number)
		add	a,8
		ld	(ws+6),a
cs_1:		ld	a,(ws+4)
		and	0x40
		ld	a,(ws+1)
		jp	nz,cs_l
		add	a,2
		jp	cs_2
cs_l:		sub	2
cs_2:		ld	(ws+1),a
		ld	a,(ws+6)
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	a,(ws+2)
		ld	d,a
		ld	a,(ws+5)
		ld	e,a
		ld	a,(ws+4)
		and	0x80
		jp	z,cs_sub
		add	hl,de
		jp	cs_3
cs_sub:		ld	a,e
		sub	l
		ld	l,a
		ld	a,d
		sbc	a,h
		ld	h,a
cs_3:		ld	a,l
		ld	(ws+5),a
		ld	a,h
		ld	(ws+2),a
		cp	0x28
		call	c,set7
		ld	a,(ws+4)
		and	0x80
		jp	nz,cs_inc
		ld	a,(ws+6)
		dec	a
		ld	(ws+6),a
		call	z,set7
		jp	cs_4
cs_inc:		ld	a,(ws+6)
		inc	a
		ld	(ws+6),a
		jp	nz,cs_4
		ld	a,0xFF
		ld	(ws+6),a
cs_4:		ld	a,(alien_new_dir_flag)
		or	a
		jp	nz,draw_alien
		inc	a
		ld	(alien_new_dir_flag),a
		jp	cs_0

meteor_update:
		call	tmp_actor
		ld	hl,current_alien_number
		inc	(hl)
		ld	a,(ws+5)
		ld	b,a
		ld	a,(ws+4)
		and	0x40
		ld	a,(ws+1)
		jp	nz,mu_l
		add	a,b
		jp	mu0
mu_l:		sub	b
mu0:		ld	(ws+1),a
		ld	a,(ws+6)
		ld	b,a
		ld	a,(ws+2)
		add	a,b
		ld	(ws+2),a
		call	update_and_erase_actor
		call	colourize_sprite
		call	pcca
		ld	a,e
		and	4
		jp	nz,mu2
		call	laser_fire
		ld	a,c
		or	a
		jp	nz,mu1
		call	alien_coll
		dec	e
		jp	z,alien_coll_anim_sfx
		ret
mu1:		ld	bc,0x0025
		call	add_points
mu2:		call	anim_reset
		xor	a
		jp	sfx_set_explode
