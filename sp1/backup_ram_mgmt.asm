	include "neogeo.inc"
	include "macros.inc"
	include "sp1.inc"

	global manual_backup_ram_mgmt
	global STR_BACKUP_RAM_MGMT

	section text

; backup ram table/hex viewer + init ($d00000-$d0ffff, mvs only)
; table offsets per https://wiki.neogeodev.org/index.php?title=Backup_RAM

; scratch (free work ram, above the bios info scratch)
BRAM_VIEW_OFFS		equ $103030	; word
BRAM_REPEAT		equ $103032	; word
BRAM_VIEW_MODE		equ $103034	; byte, 0 = table, 1 = hex
BRAM_CURSOR		equ $103035	; byte, table entry 0-7
BRAM_COPY_SRC		equ $103036	; byte, copy source entry, $ff = inactive

BRAM_SIG		equ BACKUP_RAM_START+$10	; "BACKUP RAM OK!" 16 bytes
BRAM_CREDITS		equ BACKUP_RAM_START+$34	; 2 bcd bytes, p1/p2
BRAM_SLOT_TABLE		equ BACKUP_RAM_START+$124	; 8 x (ngh word, block id word)
BRAM_SLOT_DATES		equ BACKUP_RAM_START+$144	; 8 x YYMMDDdd
BRAM_RING_BYTES		equ BACKUP_RAM_START+$11a	; 8 day ring bytes, block id indexed
BRAM_DAY_COUNTS		equ BACKUP_RAM_START+$200	; 8 longs, block id indexed
BRAM_DIP_TABLE		equ BACKUP_RAM_START+$220	; 8 x 16 byte soft dips
BRAM_NAME_TABLE		equ BACKUP_RAM_START+$2a0	; 8 x 16 byte name
BRAM_SAVE_BLOCKS	equ BACKUP_RAM_START+$320	; 8 x $1000 byte save data
BRAM_PLAY_DAILY		equ BACKUP_RAM_START+$8320	; 8 x $240, block id indexed
BRAM_PLAY_MONTHLY	equ BACKUP_RAM_START+$9520	; 8 x $c0, block id indexed
BRAM_PLAY_TOTAL		equ BACKUP_RAM_START+$9b20	; 8 x $10, block id indexed
BRAM_EXTRA_BLOCKS	equ BACKUP_RAM_START+$a1a0	; 8 x $60, block id indexed
BRAM_BOOK_START		equ BACKUP_RAM_START+$8320	; all bookkeeping records
BRAM_BOOK_LONGS		equ $7a0			; through $a19f

BRAM_ROW_FIRST		equ 7
BRAM_ROW_COUNT		equ 16
BRAM_PAGE_SIZE		equ BRAM_ROW_COUNT*8
BRAM_REPEAT_DELAY	equ 15		; frames held before auto-repeat
BRAM_REPEAT_RATE	equ 2

manual_backup_ram_mgmt:
		clr.w	BRAM_VIEW_OFFS
		clr.b	BRAM_VIEW_MODE
		clr.b	BRAM_CURSOR
		move.b	d0, REG_SRAMUNLOCK	; locked sram doesn't drive reads on real hw
		bsr	bram_show_screen

	.loop:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		bsr	wait_frame

		tst.b	BRAM_VIEW_MODE
		bne	.hex_input

		move.b	BRAM_COPY_SRC, d0		; picking a copy destination?
		cmp.b	#$ff, d0
		bne	.copy_input

		btst	#D_BUTTON, p1_input_edge
		bne	.exit

		btst	#C_BUTTON, p1_input_edge
		beq	.t_no_init
		bsr	bram_init_screen
		bsr	bram_show_screen
		bra	.loop

	.t_no_init:
		btst	#B_BUTTON, p1_input_edge
		beq	.t_no_toggle
		eori.b	#1, BRAM_VIEW_MODE
		bsr	bram_show_screen
		bra	.loop

	.t_no_toggle:
		btst	#A_BUTTON, p1_input_edge	; a = wipe entry
		beq	.t_no_wipe
		bsr	bram_wipe_screen
		bsr	bram_show_screen
		bra	.loop

	.t_no_wipe:
		btst	#RIGHT, p1_input_edge		; right = copy entry
		beq	.t_no_copy
		moveq	#0, d0
		move.b	BRAM_CURSOR, d0
		lsl.w	#2, d0
		lea	BRAM_SLOT_TABLE, a0
		cmpi.l	#$0000ffff, (0,a0,d0.w)
		beq	.loop				; empty source
		move.b	BRAM_CURSOR, BRAM_COPY_SRC
		lea	XY_STR_BRAMT_COPY, a0
		RSUB	print_xy_string_struct_clear
		moveq	#26, d0
		SSA3	fix_clear_line
		bra	.loop

	.t_no_copy:
		bsr	.cursor_move
		bra	.loop

	.copy_input:
		btst	#D_BUTTON, p1_input_edge	; cancel
		beq	.c_no_cancel
		move.b	#$ff, BRAM_COPY_SRC
		lea	XY_STR_BRAMT_KEYS1, a0
		RSUB	print_xy_string_struct_clear
		lea	XY_STR_BRAMT_KEYS2, a0
		RSUB	print_xy_string_struct_clear
		bra	.loop
	.c_no_cancel:
		btst	#A_BUTTON, p1_input_edge	; commit
		beq	.c_no_commit
		bsr	bram_copy_entry
		move.w	d0, -(a7)
		bsr	bram_show_screen		; leaves copy mode
		move.w	(a7)+, d0
		tst.w	d0
		beq	.loop
		lea	XY_STR_BRAM_NOFREE, a0
		RSUB	print_xy_string_struct
		bra	.loop
	.c_no_commit:
		bsr	.cursor_move
		bra	.loop

	.cursor_move:
		move.b	p1_input_edge, d0
		and.b	#$3, d0
		beq	.cm_done
		move.b	BRAM_CURSOR, d3
		btst	#UP, d0
		beq	.cursor_down
		subq.b	#1, d3
		bpl	.cursor_update
		moveq	#7, d3
		bra	.cursor_update
	.cursor_down:
		addq.b	#1, d3
		cmp.b	#8, d3
		bne	.cursor_update
		moveq	#0, d3
	.cursor_update:
		moveq	#$20, d2
		bsr	bram_cursor_char
		move.b	d3, BRAM_CURSOR
		moveq	#$11, d2
		bsr	bram_cursor_char
	.cm_done:
		rts

	.hex_input:
		btst	#D_BUTTON, p1_input_edge
		bne	.exit
		btst	#C_BUTTON, p1_input_edge
		beq	.h_no_init
		bsr	bram_init_screen
		bsr	bram_show_screen
		bra	.loop
	.h_no_init:
		btst	#B_BUTTON, p1_input_edge
		beq	.check_nav
		eori.b	#1, BRAM_VIEW_MODE
		bsr	bram_show_screen
		bra	.loop

	.check_nav:
		move.b	p1_input, d1
		and.b	#$f, d1
		bne	.dir_held
		move.w	#BRAM_REPEAT_DELAY, BRAM_REPEAT
		bra	.loop

	.dir_held:
		move.b	p1_input_edge, d0
		and.b	#$f, d0
		beq	.no_edge
		move.w	#BRAM_REPEAT_DELAY, BRAM_REPEAT
		move.b	d0, d1
		bra	.act

	.no_edge:
		subq.w	#1, BRAM_REPEAT
		bpl	.loop
		move.w	#BRAM_REPEAT_RATE, BRAM_REPEAT

	.act:
		move.w	BRAM_VIEW_OFFS, d0
		btst	#UP, d1
		beq	.up_not_pressed
		sub.w	#BRAM_PAGE_SIZE, d0
	.up_not_pressed:
		btst	#DOWN, d1
		beq	.down_not_pressed
		add.w	#BRAM_PAGE_SIZE, d0
	.down_not_pressed:
		btst	#LEFT, d1
		beq	.left_not_pressed
		sub.w	#$1000, d0
	.left_not_pressed:
		btst	#RIGHT, d1
		beq	.right_not_pressed
		add.w	#$1000, d0
	.right_not_pressed:
		move.w	d0, BRAM_VIEW_OFFS
		bsr	bram_draw_page
		bra	.loop

	.exit:
		move.b	d0, REG_SRAMLOCK
		rts

; clear + full redraw of the current mode
bram_show_screen:
		SSA3	fix_clear
		move.b	#$ff, BRAM_COPY_SRC
		move.w	#BRAM_REPEAT_DELAY, BRAM_REPEAT
		moveq	#4, d0
		moveq	#5, d1
		lea	STR_BACKUP_RAM_MGMT, a0
		RSUB	print_xy_string
		tst.b	BRAM_VIEW_MODE
		bne	.hex
		lea	XY_STR_BRAMT_SIG, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAMT_HDR, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAMT_KEYS1, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAMT_KEYS2, a0
		RSUB	print_xy_string_struct
		bsr	bram_draw_table_values
		moveq	#$11, d2
		bra	bram_cursor_char
	.hex:
		lea	XY_STR_BRAM_NAV, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_KEYS, a0
		RSUB	print_xy_string_struct
		bra	bram_draw_page

; table view: signature, credits, 8 game entries (# ngh id date name)
bram_draw_table_values:
		WATCHDOG
		lea	BRAM_SIG, a0
		moveq	#15, d0
		moveq	#7, d1
		moveq	#15, d3
		bsr	bram_draw_ascii

		move.b	BRAM_CREDITS, d2
		moveq	#19, d0
		moveq	#8, d1
		RSUB	print_hex_byte
		move.b	BRAM_CREDITS+1, d2
		moveq	#22, d0
		moveq	#8, d1
		RSUB	print_hex_byte

		moveq	#0, d5			; entry
	.loop_entry:
		WATCHDOG
		moveq	#11, d6
		add.w	d5, d6			; row

		moveq	#2, d0
		move.w	d6, d1
		moveq	#$31, d2
		add.w	d5, d2			; '1' + entry
		RSUB	print_xy_char

		lea	BRAM_SLOT_TABLE, a0
		move.w	d5, d0
		lsl.w	#2, d0
		adda.w	d0, a0
		move.w	(a0), d2		; ngh
		moveq	#4, d0
		move.w	d6, d1
		RSUB	print_hex_word

		move.w	(2,a0), d2		; block id
		moveq	#9, d0
		move.w	d6, d1
		RSUB	print_hex_word

		lea	BRAM_SLOT_DATES, a1
		move.w	d5, d0
		lsl.w	#2, d0
		move.l	(0,a1,d0.w), d2
		lsr.l	#8, d2			; YYMMDD
		moveq	#14, d0
		move.w	d6, d1
		RSUB	print_hex_3_bytes

		move.w	(2,a0), d0		; name = name table[block id]
		cmp.w	#8, d0
		bcc	.no_name
		lsl.w	#4, d0
		lea	BRAM_NAME_TABLE, a0
		adda.w	d0, a0
		moveq	#21, d0
		move.w	d6, d1
		moveq	#15, d3
		bsr	bram_draw_ascii
		bra	.next_entry

	.no_name:
		moveq	#21, d0
		move.w	d6, d1
		moveq	#0, d2
		moveq	#$20, d3
		moveq	#16, d4
		RSUB	print_char_repeat

	.next_entry:
		addq.w	#1, d5
		cmp.w	#8, d5
		bne	.loop_entry
		rts

; d2 = char to draw at x=1 on the cursor row
bram_cursor_char:
		moveq	#0, d1
		move.b	BRAM_CURSOR, d1
		add.w	#11, d1
		moveq	#1, d0
		RSUB	print_xy_char
		rts

; print d3+1 ascii chars from a0 at x=d0 y=d1, non-printable as '.'
bram_draw_ascii:
		lsl.w	#5, d0
		add.w	d1, d0
		add.w	#FIXMAP, d0
		move.w	d0, (-2,a6)
		move.w	#$20, (2,a6)
	.loop_char:
		moveq	#0, d2
		move.b	(a0)+, d2
		cmp.b	#$20, d2
		bcs	.not_printable
		cmp.b	#$7f, d2
		bcs	.put_char
	.not_printable:
		moveq	#$2e, d2		; '.'
	.put_char:
		move.w	d2, (a6)
		dbra	d3, .loop_char
		rts

bram_draw_page:
		move.w	BRAM_VIEW_OFFS, d5
		moveq	#BRAM_ROW_FIRST, d6
	.loop_next_row:
		WATCHDOG
		bsr	bram_draw_row
		addq.w	#8, d5
		addq.w	#1, d6
		cmp.w	#BRAM_ROW_FIRST+BRAM_ROW_COUNT, d6
		bne	.loop_next_row
		rts

; d5 = bram offset, d6 = fix row
; OOOO 00 11 22 33 44 55 66 77 AAAAAAAA
bram_draw_row:
		move.w	#FIXMAP+(2<<5), d0	; x = 2
		add.w	d6, d0
		move.w	d0, (-2,a6)
		move.w	#$20, (2,a6)

		lea	BRAM_HEX, a2

		move.w	d5, d2			; offset, 4 digits
		moveq	#3, d3
	.loop_offset:
		rol.w	#4, d2
		moveq	#$f, d0
		and.w	d2, d0
		move.b	(0,a2,d0.w), d0
		move.w	d0, (a6)
		dbra	d3, .loop_offset
		move.w	#$20, (a6)

		lea	BACKUP_RAM_START, a0
		moveq	#0, d0
		move.w	d5, d0
		adda.l	d0, a0
		movea.l	a0, a1

		moveq	#7, d3			; 8 bytes hex
	.loop_hex:
		moveq	#0, d0
		move.b	(a0)+, d0
		move.b	d0, d2
		lsr.b	#4, d0
		move.b	(0,a2,d0.w), d0
		move.w	d0, (a6)
		moveq	#$f, d0
		and.b	d2, d0
		move.b	(0,a2,d0.w), d0
		move.w	d0, (a6)
		move.w	#$20, (a6)
		dbra	d3, .loop_hex

		movea.l	a1, a0			; same 8 bytes ascii
		moveq	#7, d3
	.loop_ascii:
		moveq	#0, d2
		move.b	(a0)+, d2
		cmp.b	#$20, d2
		bcs	.not_printable
		cmp.b	#$7f, d2
		bcs	.put_char
	.not_printable:
		moveq	#$2e, d2		; '.'
	.put_char:
		move.w	d2, (a6)
		dbra	d3, .loop_ascii
		rts

BRAM_HEX:
	dc.b	"0123456789ABCDEF"
	align 1

; confirm + wipe the cursor's game entry, straight back to the table
bram_wipe_screen:
		SSA3	fix_clear
		lea	XY_STR_BRAM_WIPE1, a0
		RSUB	print_xy_string_struct
		moveq	#20, d0
		moveq	#7, d1
		moveq	#$31, d2
		add.b	BRAM_CURSOR, d2
		RSUB	print_xy_char
		lea	XY_STR_BRAM_WIPE2, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_WIPE3, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_WIPE_OK, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_CANCEL, a0
		RSUB	print_xy_string_struct

	.loop_wait_release:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		bsr	wait_frame
		btst	#D_BUTTON, p1_input_edge
		bne	.done
		move.b	p1_input, d0
		and.b	#$50, d0
		bne	.loop_wait_release

	.loop_confirm:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		bsr	wait_frame
		btst	#D_BUTTON, p1_input_edge
		bne	.done
		move.b	p1_input, d0
		and.b	#$50, d0		; a+c
		cmp.b	#$50, d0
		bne	.loop_confirm
		bsr	bram_wipe_entry
	.done:
		rts

; wipe entry BRAM_CURSOR: table pair + date; everything else is keyed on the
; freed block id (bios indexes all per-game data by block id, not entry).
; the bios rebuilds/compacts the table at boot; no checksum/counter exists.
bram_wipe_entry:
		moveq	#0, d0
		move.b	BRAM_CURSOR, d0
		lsl.w	#2, d0
		lea	BRAM_SLOT_TABLE, a0
		move.w	(2,a0,d0.w), d4		; block id
		move.l	#$0000ffff, (0,a0,d0.w)	; absent = ngh 0, id $ffff
		lea	BRAM_SLOT_DATES, a0
		clr.l	(0,a0,d0.w)

		cmp.w	#8, d4
		bcc	.done			; never saved, no block to free

		move.w	d4, d0
		lsl.w	#4, d0
		lea	BRAM_DIP_TABLE, a0
		adda.w	d0, a0
		moveq	#3, d1
		bsr	bram_zero
		move.w	d4, d0
		lsl.w	#4, d0
		lea	BRAM_NAME_TABLE, a0
		adda.w	d0, a0
		moveq	#3, d1
		bsr	bram_zero
		move.w	d4, d0
		lsl.w	#8, d0
		lsl.w	#4, d0			; * $1000
		lea	BRAM_SAVE_BLOCKS, a0
		adda.w	d0, a0
		move.w	#$400-1, d1
		bsr	bram_zero

		move.w	d4, d0
		mulu.w	#$240, d0
		lea	BRAM_PLAY_DAILY, a0
		adda.l	d0, a0
		move.w	#$90-1, d1
		bsr	bram_zero
		move.w	d4, d0
		mulu.w	#$c0, d0
		lea	BRAM_PLAY_MONTHLY, a0
		adda.l	d0, a0
		move.w	#$30-1, d1
		bsr	bram_zero
		move.w	d4, d0
		lsl.w	#4, d0
		lea	BRAM_PLAY_TOTAL, a0
		adda.w	d0, a0
		moveq	#3, d1
		bsr	bram_zero

		lea	BRAM_RING_BYTES, a0
		clr.b	(0,a0,d4.w)
		move.w	d4, d0
		lsl.w	#2, d0
		lea	BRAM_DAY_COUNTS, a0
		clr.l	(0,a0,d0.w)
		move.w	d4, d0
		mulu.w	#$60, d0
		lea	BRAM_EXTRA_BLOCKS, a0
		adda.l	d0, a0
		move.w	#$18-1, d1
		bsr	bram_zero

	.done:
		rts

; deep copy entry BRAM_COPY_SRC -> entry BRAM_CURSOR.  dest reuses its block
; id, else gets the first free one (reference scan, same as the bios).
; returns d0 = 0 ok / -1 no free block
bram_copy_entry:
		move.b	BRAM_COPY_SRC, d0
		cmp.b	BRAM_CURSOR, d0
		beq	.done_ok

		moveq	#0, d0
		move.b	BRAM_COPY_SRC, d0
		lsl.w	#2, d0
		lea	BRAM_SLOT_TABLE, a0
		move.w	(0,a0,d0.w), d3		; src ngh
		move.w	(2,a0,d0.w), d4		; src block id
		lea	BRAM_SLOT_DATES, a1
		move.l	(0,a1,d0.w), d5		; src date

		moveq	#0, d0
		move.b	BRAM_CURSOR, d0
		lsl.w	#2, d0
		move.w	(2,a0,d0.w), d6		; dest block id
		cmp.w	#8, d4
		bcc	.no_block		; src never saved
		cmp.w	#8, d6
		bcs	.write_entry
		bsr	bram_free_block
		move.w	d0, d6
		cmp.w	#8, d6
		bcs	.write_entry
		moveq	#-1, d0
		rts

	.no_block:
		move.w	#$ffff, d6

	.write_entry:
		moveq	#0, d0
		move.b	BRAM_CURSOR, d0
		lsl.w	#2, d0
		lea	BRAM_SLOT_TABLE, a0
		move.w	d3, (0,a0,d0.w)
		move.w	d6, (2,a0,d0.w)
		lea	BRAM_SLOT_DATES, a0
		move.l	d5, (0,a0,d0.w)
		cmp.w	#8, d4
		bcc	.done_ok
		bsr	bram_copy_block

	.done_ok:
		moveq	#0, d0
		rts

; returns d0.w = first block id 0-7 not referenced by the table, $ffff if none
bram_free_block:
		moveq	#0, d0
	.next_candidate:
		lea	BRAM_SLOT_TABLE, a0
		moveq	#7, d1
	.scan:
		move.w	(2,a0), d2
		cmp.w	d0, d2
		beq	.in_use
		lea	(4,a0), a0
		dbra	d1, .scan
		rts
	.in_use:
		addq.w	#1, d0
		cmp.w	#8, d0
		bne	.next_candidate
		move.w	#$ffff, d0
		rts

; copy all per-block data d4 -> d6
bram_copy_block:
		lea	BRAM_BLOCK_REGIONS, a2
		moveq	#7-1, d5
	.next_region:
		movea.l	(a2)+, a1		; base
		move.w	(a2)+, d0		; stride
		move.w	(a2)+, d3		; longs - 1
		move.w	d0, d2
		mulu.w	d4, d0
		mulu.w	d6, d2
		movea.l	a1, a0
		adda.l	d0, a0
		adda.l	d2, a1
		move.w	d3, d1
		bsr	bram_copy
		dbra	d5, .next_region

		lea	BRAM_RING_BYTES, a0
		move.b	(0,a0,d4.w), (0,a0,d6.w)
		move.w	d4, d0
		lsl.w	#2, d0
		move.w	d6, d1
		lsl.w	#2, d1
		lea	BRAM_DAY_COUNTS, a0
		move.l	(0,a0,d0.w), (0,a0,d1.w)
		rts

; a0 = src, a1 = dst, d1 = longs - 1
bram_copy:
	.loop_copy:
		WATCHDOG
		move.l	(a0)+, (a1)+
		dbra	d1, .loop_copy
		rts

BRAM_BLOCK_REGIONS:
	dc.l	BRAM_DIP_TABLE
	dc.w	$10, 4-1
	dc.l	BRAM_NAME_TABLE
	dc.w	$10, 4-1
	dc.l	BRAM_SAVE_BLOCKS
	dc.w	$1000, $400-1
	dc.l	BRAM_PLAY_DAILY
	dc.w	$240, $90-1
	dc.l	BRAM_PLAY_MONTHLY
	dc.w	$c0, $30-1
	dc.l	BRAM_PLAY_TOTAL
	dc.w	$10, 4-1
	dc.l	BRAM_EXTRA_BLOCKS
	dc.w	$60, $18-1

; a0 = start, d1 = longs - 1 (sram must be unlocked)
bram_zero:
		moveq	#0, d2
	.loop_fill:
		WATCHDOG
		move.l	d2, (a0)+
		dbra	d1, .loop_fill
		rts

bram_init_screen:
		SSA3	fix_clear
		lea	XY_STR_BRAM_WARN1, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_WARN2, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_WARN3, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_BOOK, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_CONFIRM, a0
		RSUB	print_xy_string_struct
		lea	XY_STR_BRAM_CANCEL, a0
		RSUB	print_xy_string_struct

		; require a+b+c released before arming confirm
	.loop_wait_release:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		bsr	wait_frame
		btst	#D_BUTTON, p1_input_edge
		bne	.done
		move.b	p1_input, d0
		and.b	#$70, d0
		bne	.loop_wait_release

	.loop_confirm:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		bsr	wait_frame

		btst	#D_BUTTON, p1_input_edge
		bne	.done

		move.b	p1_input, d0
		and.b	#$70, d0
		cmp.b	#$60, d0		; b+c = bookkeeping only
		beq	.wipe_bookkeeping
		cmp.b	#$50, d0		; a+c = full init
		bne	.loop_confirm

		lea	XY_STR_BRAM_RUNNING, a0
		RSUB	print_xy_string_struct_clear
		bsr	bram_do_init
		tst.b	d0
		bne	.init_failed

		lea	XY_STR_BRAM_DONE, a0
		RSUB	print_xy_string_struct_clear
		bra	.wait_exit

	.init_failed:
		lea	XY_STR_BRAM_FAIL, a0
		RSUB	print_xy_string_struct_clear
		move.l	a1, d2
		moveq	#24, d0
		moveq	#12, d1
		RSUB	print_hex_long
		lea	XY_STR_BRAM_FAIL2, a0
		RSUB	print_xy_string_struct
		bra	.wait_exit

	.wipe_bookkeeping:
		lea	BRAM_BOOK_START, a0
		move.w	#BRAM_BOOK_LONGS-1, d1
		bsr	bram_zero
		lea	XY_STR_BRAM_BOOKDONE, a0
		RSUB	print_xy_string_struct_clear

	.wait_exit:
		moveq	#24, d0
		SSA3	fix_clear_line
		moveq	#25, d0
		SSA3	fix_clear_line
		lea	XY_STR_BRAM_RETURN, a0
		RSUB	print_xy_string_struct_clear

	.loop_exit:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		bsr	wait_frame
		btst	#D_BUTTON, p1_input_edge
		beq	.loop_exit

	.done:
		rts

; zero fill + verify (sram held unlocked by the screen)
; returns d0 = 0 pass / -1 fail, a1 = failed address
bram_do_init:
		lea	BACKUP_RAM_START, a0
		move.w	#$4000-1, d1		; longs
		moveq	#0, d2
	.loop_fill:
		WATCHDOG
		move.l	d2, (a0)+
		dbra	d1, .loop_fill

		lea	BACKUP_RAM_START, a0
		move.w	#$4000-1, d1
	.loop_verify:
		WATCHDOG
		movea.l	a0, a1
		tst.l	(a0)+
		bne	.verify_failed
		dbra	d1, .loop_verify

		moveq	#0, d0
		rts

	.verify_failed:
		moveq	#-1, d0
		rts

STR_BACKUP_RAM_MGMT:	STRING "BACKUP RAM MANAGEMENT"

XY_STR_BRAMT_SIG:	XY_STRING  4,  7, "SIGNATURE:"
XY_STR_BRAMT_HDR:	XY_STRING  2, 10, "# NGH  ID   DATE   NAME"
XY_STR_BRAMT_KEYS1:	XY_STRING  2, 25, "A: DELETE  RIGHT: COPY  UP/DOWN: SELECT"
XY_STR_BRAMT_KEYS2:	XY_STRING  2, 26, "B: HEX DUMP  C: INIT  D: MAIN MENU"
XY_STR_BRAMT_COPY:	XY_STRING  2, 25, "A: PASTE  UP/DOWN: DEST  D: CANCEL"
XY_STR_BRAM_NOFREE:	XY_STRING  2, 23, "NO FREE BLOCK FOR COPY"

XY_STR_BRAM_NAV:	XY_STRING  2, 24, "UP/DOWN: PAGE  LEFT/RIGHT: JUMP 4K"
XY_STR_BRAM_KEYS:	XY_STRING  2, 26, "B: TABLE  C: INIT  D: MAIN MENU"

XY_STR_BRAM_WARN1:	XY_STRING  4,  7, "WARNING: ALL BACKUP RAM DATA AND"
XY_STR_BRAM_WARN2:	XY_STRING  4,  8, "BOOKKEEPING WILL BE ERASED!"
XY_STR_BRAM_WARN3:	XY_STRING  4, 10, "THE BIOS WILL REBUILD ON NEXT BOOT."
XY_STR_BRAM_RUNNING:	XY_STRING  4, 12, "INITIALIZING BACKUP RAM..."
XY_STR_BRAM_DONE:	XY_STRING  4, 12, "BACKUP RAM INITIALIZED"
XY_STR_BRAM_FAIL:	XY_STRING  4, 12, "READBACK FAILED AT:"
XY_STR_BRAM_FAIL2:	XY_STRING  4, 13, "RUN THE BACKUP RAM TEST LOOP"
XY_STR_BRAM_BOOK:	XY_STRING  4, 24, "B+C: WIPE BOOKKEEPING RECORDS"
XY_STR_BRAM_CONFIRM:	XY_STRING  4, 25, "A+C: INITIALIZE ALL BACKUP RAM"
XY_STR_BRAM_CANCEL:	XY_STRING  4, 26, "D: CANCEL"
XY_STR_BRAM_RETURN:	XY_STRING  4, 26, "D: RETURN"
XY_STR_BRAM_BOOKDONE:	XY_STRING  4, 12, "BOOKKEEPING RECORDS WIPED"

XY_STR_BRAM_WIPE1:	XY_STRING  4,  7, "DELETE GAME ENTRY  ?"
XY_STR_BRAM_WIPE2:	XY_STRING  4,  9, "ENTRY, DIPS, AND BOOKKEEPING"
XY_STR_BRAM_WIPE3:	XY_STRING  4, 10, "RECORDS WILL BE ERASED!"
XY_STR_BRAM_WIPE_OK:	XY_STRING  4, 25, "A+C: DELETE ENTRY"
