; Главный цикл, уровни и ходы игроков на i8080 (по src/model/logic.js: pass, mainLoop, frameUpdate, ...).

ws:		ds	8		; текущий объект (копия)
cur:		dw	0		; его адрес
ws_skip:	db	0		; 1 — объект уже записан (ws_flush), не копировать обратно
ml_lim:		dw	0		; конец списка объектов прохода
ml_nested:	db	0		; 1 — вложенный проход (по кадру)
pass_sp:	dw	0		; SP на входе в pass — выход при конце игры
game_over:	db	0
lock_mode:	db	0		; 1 — сверка с моделью (без задержек)
flash_lbl:	db	0		; мигающая надпись: 0 — нет, 0x18 — 1UP, 0xD8 — 2UP
r_idx:		db	0
snd_ptr:	dw	snd_buf
snd_buf:	ds	96

; ld a,r ZX: очередь r_buf (на Векторе её пополняет генератор)
get_r:
		push	hl
		ld	a,(r_idx)
		ld	l,a
		inc	a
		ld	(r_idx),a
		ld	h,r_buf >> 8
		ld	a,(hl)
		pop	hl
		ret

ws_load:	ld	hl,(cur)
		ld	de,ws
		jp	copy8
ws_store:	ld	hl,ws
		ex	de,hl
		ld	hl,(cur)
		ex	de,hl
		jp	copy8
ws_flush:	call	ws_store
		ld	a,1
		ld	(ws_skip),a
		ret

call_hl:	jp	(hl)

; диспетчер: объект cur -> ws, подпрограмма по типу, ws -> объект
dispatch_obj:
		ld	hl,(cur)		; пустой слот (FrameRateLimiter) — без копирования
		ld	a,(hl)
		or	a
		ret	z
		xor	a
		ld	(ws_skip),a
		call	ws_load
		ld	a,(ws)
		rlca
		and	0x7E
		ld	e,a
		ld	d,0
		ld	hl,main_table
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		call	call_hl
		ld	a,(ws_skip)
		or	a
		ret	nz
		jp	ws_store

main_table:	dw	frame_rate_limiter, player_turn_starts, jetman_walk, meteor_update
		dw	item_pickup, crossed_ship_update, sphere_update, jet_fighter_update
		dw	animate_explosion, rocket_update, rocket_takeoff, rocket_landing
		dw	sfx_enemy_death, sfx_jetman_death, item_check_collect, ufo_update
		dw	laser_animate, squidgy_update

; проход главного цикла (MainLoopResetStack .. NewActor_4)
pass:
		ld	hl,0
		add	hl,sp
		ld	(pass_sp),hl
		xor	a
		ld	(current_alien_number),a
		ld	(ml_nested),a
		ld	hl,inactive_jetman_state
		ld	(ml_lim),hl
		ld	hl,rocket_state
; MainLoop: HL = первый объект; ml_lim, ml_nested — у вызывающего
main_loop:
ml0:		ld	(cur),hl
		ld	a,(last_frame)		; во вложенном проходе кадр не сменится: прерывание его не считает
		ld	b,a
		ld	a,(FRAMES)
		cp	b
		call	nz,frame_update
ml1:		call	dispatch_obj
		ld	hl,random_number	; NewActor
		inc	(hl)
		ld	hl,(cur)
		ld	de,8
		add	hl,de
		ex	de,hl
		ld	hl,(ml_lim)
		ld	a,e
		sub	l
		ld	a,d
		sbc	a,h
		ex	de,hl
		jp	c,ml0
na_pause:	ld	a,0xFE			; SHIFT — пауза
		call	in_row
		and	1
		jp	z,na_pause
		ld	hl,(game_timer)
		inc	hl
		ld	(game_timer),hl
		call	get_r
		ld	c,a
		ld	a,(ml_nested)
		or	a
		ret	nz			; конец вложенного прохода (JP ResetModifiedInFrame)
		ld	a,(game_timer)
		ld	l,a
		ld	h,rnd_rom >> 8
		ld	a,(hl)
		add	a,RND_0244
		add	a,c
		ld	(random_number),a
		ld	b,a
		ld	a,(current_alien_number)
		cp	3
		jp	c,na1
		ld	a,b
		and	0x1F
		jp	nz,na4
		ld	a,(current_alien_number)
		cp	6
		jp	nc,na4
na1:		ld	a,(begin_play_delay_counter)
		or	a
		jp	nz,na4
		ld	a,(jetman_motion)
		and	0x3F
		dec	a
		jp	z,na2
		dec	a
		jp	nz,na4
na2:		ld	hl,alien_states
		ld	de,8
		ld	b,6
na3:		ld	a,(hl)
		or	a
		jp	z,na5
		add	hl,de
		dec	b
		jp	nz,na3
na4:		call	item_new_fuel_pod
		jp	item_new_collectible
na5:		call	new_alien
		jp	na4

; FrameUpdate: вложенный проход Джетмена и лазеров
frame_update:
		ld	a,(FRAMES)
		ld	(last_frame),a
		ld	a,1
		ld	(frame_ticked),a
		ld	hl,(cur)
		push	hl
		ld	hl,(ml_lim)
		push	hl
		ld	hl,rocket_state
		ld	(ml_lim),hl
		ld	a,1
		ld	(ml_nested),a
		ld	hl,jetman_motion
		call	main_loop
		xor	a
		ld	(ml_nested),a
		ld	(frame_ticked),a
		pop	hl
		ld	(ml_lim),hl
		pop	hl
		ld	(cur),hl
		ret

; новый пришелец в слоте HL (NewActor_5)
new_alien:
		push	hl
		ex	de,hl
		ld	hl,default_alien_state
		call	copy8
		pop	hl
		push	hl
		ld	a,(game_timer)
		ld	e,a
		and	0x40
		ld	(hl),a			; +0
		inc	hl
		inc	hl
		ld	b,a
		ld	a,e
		and	0x7F
		add	a,0x28
		ld	(hl),a			; +2
		inc	hl
		pop	de
		push	de
		ld	a,e
		rrca
		rrca
		rrca
		and	3
		add	a,2
		ld	(hl),a			; +3
		inc	hl
		ld	(hl),b			; +4
		inc	hl
		inc	hl
		and	1
		ld	(hl),a			; +6
		ld	a,(player_level)
		and	7
		ld	e,a
		ld	d,0
		ld	hl,item_level_object_types
		add	hl,de
		ld	b,(hl)
		pop	hl
		ld	a,(hl)
		and	0xC0
		or	b
		ld	(hl),a
		ret

; --- уровни и ходы ------------------------------------------------------------------------------------
set_inactive:					; HL, B объектов по 8 байт
		ld	de,8
si0:		ld	(hl),0
		add	hl,de
		dec	b
		jp	nz,si0
		ret

player_init:
		ld	hl,default_player_state
		ld	de,jetman_motion
		call	copy8
		ld	a,(game_options)
		and	1
		ld	a,0x80
		jp	z,pi0
		ld	a,0xFF
pi0:		ld	(begin_play_delay_counter),a
		ld	hl,player_lives
		dec	(hl)
		jp	display_lives

rocket_reset:
		ld	hl,default_rocket_state
		ld	de,rocket_state
		call	copy8
		call	copy8
		call	copy8
		ld	a,8
		jp	buffer_copy_rocket

level_new:
		ld	a,(player_level)
		and	3
		jp	nz,level_init
		call	rocket_reset
		ld	hl,player_lives
		inc	(hl)
		call	player_init
level_init:
		call	alien_buffer_init
		call	reset_screen
		call	draw_platforms
		call	display_lives
		ld	a,(FRAMES)
		ld	(last_frame),a
		ret

players_swap:
		ld	hl,player_level
		ld	de,inactive_player_level
		ld	b,2
		call	swap_b
		ld	hl,rocket_state
		ld	de,inactive_rocket_state
		ld	b,0x18
swap_b:		ld	a,(de)
		ld	c,(hl)
		ld	(hl),a
		ld	a,c
		ld	(de),a
		inc	hl
		inc	de
		dec	b
		jp	nz,swap_b
		ret

player_turn_ends:
		ld	hl,jetman_thruster_anim_state
		ld	b,0x0A
		call	set_inactive
		ld	hl,rocket_module_state+4
		ld	a,(hl)
		and	0xFD
		ld	(hl),a
		ld	hl,item_state+4
		ld	a,(hl)
		and	0xFD
		ld	(hl),a
		ld	a,(game_options)
		and	1
		jp	z,pte0
		ld	a,(inactive_player_lives)
		or	a
		jp	z,pte0
		ld	a,(player_lives)
		or	a
		call	z,show_game_over
		call	players_swap
		ld	a,(current_player_number)
		cpl
		ld	(current_player_number),a
		ld	a,(rocket_state+4)
		rlca
		rlca
		rlca
		and	0x38
		call	buffer_copy_rocket
		call	level_init
		jp	player_init
pte0:		ld	a,(player_lives)
		or	a
		jp	z,pte_over
		call	level_init
		jp	player_init
pte_over:	call	update_hiscore
		call	show_game_over
		ld	a,1
		ld	(game_over),a
		ld	hl,(pass_sp)
		ld	sp,hl
		ret

show_game_over:
		ld	a,(current_player_number)
		or	a
		ld	a,0xB1
		jp	z,got0
		ld	a,0xB2
got0:		ld	(game_over_text+0x12),a
		call	reset_screen
		ld	de,game_over_text
		ld	hl,0x7038
		call	display_string
		ld	a,(lock_mode)
		or	a
		ret	nz
		ld	b,90			; ~1,8 с (ZX: 4 x 65536 витков)
		jp	wait_frames

; ждать B кадров
wait_frames:
		ld	a,(FRAMES)
		ld	c,a
wf0:		ld	a,(FRAMES)
		cp	c
		jp	z,wf0
		dec	b
		jp	nz,wait_frames
		ret

update_hiscore:
		ld	a,(p2_score)
		ld	b,a
		ld	a,(p1_score)
		cp	b
		jp	c,uh_p2
		jp	nz,uh_p1
		ld	a,(p2_score+1)
		ld	b,a
		ld	a,(p1_score+1)
		cp	b
		jp	c,uh_p2
		jp	nz,uh_p1
		ld	a,(p1_score+2)
		ld	b,a
		ld	a,(p2_score+2)
		cp	b
		jp	c,uh_p1
uh_p2:		ld	hl,p2_score
		jp	uh0
uh_p1:		ld	hl,p1_score
uh0:		ld	de,hi_score
		ld	b,3
		push	hl
uh1:		ld	a,(de)
		cp	(hl)
		jp	c,uh_copy
		jp	nz,uh_ret
		inc	hl
		inc	de
		dec	b
		jp	nz,uh1
uh_ret:		pop	hl
		ret
uh_copy:	pop	hl
		ld	de,hi_score
		ld	b,3
uh2:		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		dec	b
		jp	nz,uh2
		ret

score_label_flash:
		ld	a,(current_player_number)
		or	a
		ld	a,0x18
		jp	z,slf0
		ld	a,0xD8
slf0:		ld	(flash_lbl),a
		ret
score_label_unflash:
		xor	a
		ld	(flash_lbl),a
		ret

; NewGame: очистка очков и состояния, данные игроков, новый уровень
new_game:
		ld	hl,p1_score
ng0:		ld	(hl),0
		inc	hl
		ld	a,h
		cp	0x60
		jp	c,ng0
		ld	b,2
ng1:		push	bc
		xor	a
		ld	(player_level),a
		ld	a,4
		ld	(player_lives),a
		call	rocket_reset
		call	players_swap
		pop	bc
		dec	b
		jp	nz,ng1
		ld	a,5
		ld	(inactive_player_lives),a
		ld	a,(game_options)
		and	1
		jp	nz,ng2
		ld	(inactive_player_lives),a
ng2:		jp	level_new
