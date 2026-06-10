	include "neogeo.inc"
	include "macros.inc"
	include "sp1.inc"
	include "../common/error_codes.inc"

	global manual_bios_info_tests
	global board_no_sm1
	global STR_BIOS_INFO

	section text

; ============================================================================
; bios inspection / board detection
; ============================================================================

; ---------------------------------------------------------------------------
; board_no_sm1 - decide if the board lacks an SM1 (so SM1 test is skipped)
;   returns d0.b = 1 (no SM1: AES / unibios-AES / MV-1B / MV-1C), else 0
; ---------------------------------------------------------------------------
board_no_sm1:
		tst.w	RUNTIME_AES_LATCH		; real AES or unibios AES mode
		bne	.no_sm1
		move.w	HOST_BIOS_UNIBIOS_SIG, d0	; unibios: can't id board, latch only
		cmp.w	#$4e55, d0
		beq	.has_sm1
		tst.b	HOST_BIOS_HW_BYTE		; stock: $00 = AES
		beq	.no_sm1
		; stock MVS: MV-1B/1C bios'es flag no_sm1
		movem.l	d1-d5/a0-a1, -(a7)
		bsr	bios_crc_and_name		; d1 = table no_sm1 flag
		moveq	#0, d0
		move.b	d1, d0
		movem.l	(a7)+, d1-d5/a0-a1
		rts
	.has_sm1:
		moveq	#0, d0
		rts
	.no_sm1:
		moveq	#1, d0
		rts

; ---------------------------------------------------------------------------
; bios_crc_and_name - crc the bios and look it up in the id table
;   returns d0.l = crc32, a0 = name string ptr, d1.b = table no_sm1 flag
; ---------------------------------------------------------------------------
bios_crc_and_name:
		move.l	#HOST_BIOS_SIZE, d0
		lea	HOST_BIOS_BASE, a0
		bsr	bi_calc_crc32			; d0 = crc32
		; fall through to lookup (d0 preserved)

; given d0.l = crc, return a0 = name ptr, d1.b = no_sm1 flag
get_bios_by_crc:
		lea	BIOS_ID_TABLE, a0
	.loop:
		move.l	(a0), d1			; table crc, 0 = end of table
		beq	.unknown
		cmp.l	d0, d1
		beq	.found
		lea	(BIOS_ID_ENTRY_SIZE,a0), a0
		bra	.loop
	.found:
		moveq	#0, d1
		move.b	(8,a0), d1			; no_sm1 flag
		movea.l	(4,a0), a0			; name ptr
		rts
	.unknown:
		moveq	#0, d1
		lea	STR_BIOS_UNKNOWN, a0
		rts

; ---------------------------------------------------------------------------
; bi_calc_crc32 - zlib crc32 (self-contained; no dep on bios_crc32.o)
;   d0.l = length, a0 = start -> d0.l = crc32
; ---------------------------------------------------------------------------
bi_calc_crc32:
		movem.l	d1-d5/a1, -(a7)
		subq.l	#1, d0
		move.w	d0, d3
		swap	d0
		move.w	d0, d4
		lea	REG_WATCHDOG, a1
		move.l	#$edb88320, d5
		moveq	#-1, d0
	.loop_outer:
		move.b	d0, (a1)			; pet watchdog (~0.3s over 128KiB)
		moveq	#7, d2
		move.b	(a0)+, d1
		eor.b	d1, d0
	.loop_inner:
		lsr.l	#1, d0
		bcc	.no_carry
		eor.l	d5, d0
	.no_carry:
		dbra	d2, .loop_inner
		dbra	d3, .loop_outer
		dbra	d4, .loop_outer
		not.l	d0
		movem.l	(a7)+, d1-d5/a1
		rts

; ---------------------------------------------------------------------------
; manual_bios_info_tests - "BIOS INFO" menu item: show all the bios detail
; ---------------------------------------------------------------------------
manual_bios_info_tests:
		lea	XY_STR_BI_WAIT, a0
		RSUB	print_xy_string_struct_clear

		bsr	bios_crc_and_name		; d0=crc, a0=name, d1=no_sm1
		move.l	d0, BI_CRC
		move.l	a0, BI_NAME
		move.b	d1, BI_NOSM1

		; --- header HW ($c00400): AES / MVS ---
		lea	XY_STR_BI_HW, a0
		RSUB	print_xy_string_struct_clear
		tst.b	HOST_BIOS_HW_BYTE
		bne	.hw_mvs
		lea	STR_BI_AES, a0
		bra	.hw_put
	.hw_mvs:
		lea	STR_BI_MVS, a0
	.hw_put:
		moveq	#BI_VAL_X, d0
		moveq	#7, d1
		RSUB	print_xy_string

		; --- region ($c00401): JP / US / EU ---
		lea	XY_STR_BI_REGION, a0
		RSUB	print_xy_string_struct_clear
		moveq	#0, d0
		move.b	HOST_BIOS_REGION_BYTE, d0
		cmp.b	#2, d0
		bhi	.region_unk
		add.w	d0, d0
		add.w	d0, d0
		lea	BI_REGION_TBL, a0
		movea.l	(0,a0,d0.w), a0
		bra	.region_put
	.region_unk:
		lea	STR_BI_UNK, a0
	.region_put:
		moveq	#BI_VAL_X, d0
		moveq	#8, d1
		RSUB	print_xy_string

		; --- runtime mode (latched $10fd82): AES / MVS ---
		lea	XY_STR_BI_RUNTIME, a0
		RSUB	print_xy_string_struct_clear
		tst.w	RUNTIME_AES_LATCH
		beq	.rt_mvs
		lea	STR_BI_AES, a0
		bra	.rt_put
	.rt_mvs:
		lea	STR_BI_MVS, a0
	.rt_put:
		moveq	#BI_VAL_X, d0
		moveq	#9, d1
		RSUB	print_xy_string

		; --- universe bios? (word at $c000b0 == "NU") ---
		lea	XY_STR_BI_UNIBIOS, a0
		RSUB	print_xy_string_struct_clear
		move.w	HOST_BIOS_UNIBIOS_SIG, d0
		cmp.w	#$4e55, d0
		bne	.uni_no
		lea	STR_BI_YES, a0
		bra	.uni_put
	.uni_no:
		lea	STR_BI_NO, a0
	.uni_put:
		moveq	#BI_VAL_X, d0
		moveq	#10, d1
		RSUB	print_xy_string

		; --- bios crc32 ---
		lea	XY_STR_BI_CRC, a0
		RSUB	print_xy_string_struct_clear
		lea	BI_CRC, a1
		moveq	#BI_VAL_X, d0
		moveq	#11, d1
		moveq	#3, d3
	.crc_loop:
		move.b	(a1)+, d2
		movem.l	d0/d1/d3/a1, -(a7)
		RSUB	print_hex_byte
		movem.l	(a7)+, d0/d1/d3/a1
		addq.b	#2, d0
		dbra	d3, .crc_loop

		; --- identified name ---
		lea	XY_STR_BI_NAME, a0
		RSUB	print_xy_string_struct_clear
		movea.l	BI_NAME, a0
		moveq	#BI_VAL_X, d0
		moveq	#12, d1
		RSUB	print_xy_string

		; --- SM1 verdict ---
		lea	XY_STR_BI_SM1, a0
		RSUB	print_xy_string_struct_clear
		bsr	bi_sm1_verdict			; d0 = 0 supported, 1 none, 2 unknown
		add.w	d0, d0
		add.w	d0, d0
		lea	BI_SM1_STR_TBL, a1
		movea.l	(0,a1,d0.w), a0
		moveq	#BI_VAL_X, d0
		moveq	#14, d1
		RSUB	print_xy_string

		lea	XY_STR_BI_BACK, a0
		RSUB	print_xy_string_struct_clear

	.loop_wait_exit:
		WATCHDOG
		bsr	check_reset_request
		bsr	p1p2_input_update
		btst	#D_BUTTON, p1_input_edge
		beq	.loop_wait_exit
		rts

; SM1 verdict for BIOS INFO: probe result if tested, else bios guess
; (unknown under unibios, which it can't see through).
;   returns d0.w = 0 supported, 1 not present, 2 unknown
bi_sm1_verdict:
		btst	#Z80_TEST_FLAG_SM1_NONE, z80_test_flags
		bne	.none
		btst	#Z80_TEST_FLAG_SM1_PRESENT, z80_test_flags
		bne	.supported
		; not probed this session - guess from the bios
		tst.w	RUNTIME_AES_LATCH
		bne	.none
		move.w	HOST_BIOS_UNIBIOS_SIG, d0
		cmp.w	#$4e55, d0
		beq	.unknown			; unibios - can't tell without probing
		tst.b	HOST_BIOS_HW_BYTE
		beq	.none				; stock AES header
		tst.b	BI_NOSM1
		bne	.none				; stock MV-1B/1C
	.supported:
		moveq	#0, d0
		rts
	.none:
		moveq	#1, d0
		rts
	.unknown:
		moveq	#2, d0
		rts

BI_SM1_STR_TBL:
		dc.l	STR_BI_SM1_OK			; 0
		dc.l	STR_BI_SM1_NONE			; 1
		dc.l	STR_BI_SM1_UNKNOWN		; 2

; transient display scratch (free work ram, above the fixmap backup)
BI_CRC		equ $103024	; long
BI_NAME		equ $103028	; long
BI_NOSM1	equ $10302c	; byte

BI_VAL_X	equ 19

BI_REGION_TBL:
		dc.l	STR_BI_JAPAN			; $00
		dc.l	STR_BI_USA			; $01
		dc.l	STR_BI_EUROPE			; $02

; ---------------------------------------------------------------------------
; bios id table - crc32 (68k order), name, no_sm1 (MV-1B/1C only)
; ---------------------------------------------------------------------------
BIOS_ID_ENTRY_SIZE	equ 10

	macro BIOS_ID
		dc.l	\1
		dc.l	\2
		dc.b	\3, 0
	endm

BIOS_ID_TABLE:
	; --- Universe Bios (hack) ---
	BIOS_ID	$465f5764, STR_BIOS_UNI40,  0
	BIOS_ID	$2bb7b46a, STR_BIOS_UNI33,  0
	BIOS_ID	$ead2effe, STR_BIOS_UNI32,  0
	BIOS_ID	$ba8f4b1e, STR_BIOS_UNI31,  0
	BIOS_ID	$cb54aad7, STR_BIOS_UNI30,  0
	BIOS_ID	$e5224ebd, STR_BIOS_UNI23,  0
	BIOS_ID	$3775739e, STR_BIOS_UNI23O, 0
	BIOS_ID	$c6f8ac92, STR_BIOS_UNI22,  0
	BIOS_ID	$f341e486, STR_BIOS_UNI21,  0
	BIOS_ID	$406f79b2, STR_BIOS_UNI20,  0
	BIOS_ID	$d8a97133, STR_BIOS_UNI13,  0
	BIOS_ID	$6c4bacd6, STR_BIOS_UNI12,  0
	BIOS_ID	$ed81e4eb, STR_BIOS_UNI12O, 0
	BIOS_ID	$afbc316a, STR_BIOS_UNI11,  0
	BIOS_ID	$9de9d5f1, STR_BIOS_UNI10,  0
	BIOS_ID	$ea57d3ad, STR_BIOS_NEOPEN, 0
	; --- SNK MVS ---
	BIOS_ID	$ee4e56ef, STR_BIOS_JP_V3,  0
	BIOS_ID	$66bc1d26, STR_BIOS_JP_V2,  0
	BIOS_ID	$c00a0476, STR_BIOS_JP_V1,  0
	BIOS_ID	$6893a277, STR_BIOS_JP_MV1B, 1
	BIOS_ID	$f1e44b08, STR_BIOS_JP_J3A, 0
	BIOS_ID	$4c747a4d, STR_BIOS_JP_MV1C, 1
	BIOS_ID	$15192f9f, STR_BIOS_USE_V2, 0
	BIOS_ID	$7e65ea24, STR_BIOS_USE_V1, 0
	BIOS_ID	$efd21cd4, STR_BIOS_AS_MV1C, 1
	BIOS_ID	$cd0f00e7, STR_BIOS_AS_MV1B, 1
	BIOS_ID	$cab95de9, STR_BIOS_US_V2,  0
	BIOS_ID	$b907061c, STR_BIOS_US_V1,  0
	BIOS_ID	$e86773d2, STR_BIOS_US_4SLOT, 0
	BIOS_ID	$cb2e44a4, STR_BIOS_US_U4,  0
	BIOS_ID	$8f5eba5e, STR_BIOS_US_U3,  0
	BIOS_ID	$f7c94873, STR_BIOS_JP_HOTEL, 0
	; --- SNK AES ---
	BIOS_ID	$0f481e11, STR_BIOS_AES_JP, 0
	BIOS_ID	$2c50cbca, STR_BIOS_AES_EXP, 0
	BIOS_ID	$7a0d4410, STR_BIOS_DEVKIT, 0
	dc.l	0				; end of table

STR_BIOS_INFO:		STRING "BIOS INFO"

XY_STR_BI_WAIT:		XY_STRING  4,  7, "READING HOST BIOS, PLEASE WAIT..."
XY_STR_BI_HW:		XY_STRING  4,  7, "BIOS HEADER:"
XY_STR_BI_REGION:	XY_STRING  4,  8, "REGION:"
XY_STR_BI_RUNTIME:	XY_STRING  4,  9, "RUNTIME MODE:"
XY_STR_BI_UNIBIOS:	XY_STRING  4, 10, "UNIVERSE BIOS:"
XY_STR_BI_CRC:		XY_STRING  4, 11, "BIOS CRC32:"
XY_STR_BI_NAME:		XY_STRING  4, 12, "IDENTIFIED:"
XY_STR_BI_SM1:		XY_STRING  4, 14, "SM1 TEST:"
XY_STR_BI_BACK:		XY_STRING  4, 26, "D: RETURN TO MENU"

STR_BI_AES:		STRING "AES"
STR_BI_MVS:		STRING "MVS"
STR_BI_YES:		STRING "YES"
STR_BI_NO:		STRING "NO"
STR_BI_UNK:		STRING "UNKNOWN"
STR_BI_JAPAN:		STRING "JAPAN"
STR_BI_USA:		STRING "USA"
STR_BI_EUROPE:		STRING "EUROPE/WORLD"
STR_BI_SM1_OK:		STRING "SUPPORTED"
STR_BI_SM1_NONE:	STRING "NO SM1 ON BOARD"
STR_BI_SM1_UNKNOWN:	STRING "REBOOT HOLDING D"	; z80/sm1 test only runs at boot,
							; so you can't probe from the menu

STR_BIOS_UNKNOWN:	STRING "UNKNOWN - PLEASE REPORT"

STR_BIOS_UNI40:		STRING "UNIVERSE BIOS 4.0"
STR_BIOS_UNI33:		STRING "UNIVERSE BIOS 3.3"
STR_BIOS_UNI32:		STRING "UNIVERSE BIOS 3.2"
STR_BIOS_UNI31:		STRING "UNIVERSE BIOS 3.1"
STR_BIOS_UNI30:		STRING "UNIVERSE BIOS 3.0"
STR_BIOS_UNI23:		STRING "UNIVERSE BIOS 2.3"
STR_BIOS_UNI23O:	STRING "UNIVERSE BIOS 2.3 ALT"
STR_BIOS_UNI22:		STRING "UNIVERSE BIOS 2.2"
STR_BIOS_UNI21:		STRING "UNIVERSE BIOS 2.1"
STR_BIOS_UNI20:		STRING "UNIVERSE BIOS 2.0"
STR_BIOS_UNI13:		STRING "UNIVERSE BIOS 1.3"
STR_BIOS_UNI12:		STRING "UNIVERSE BIOS 1.2"
STR_BIOS_UNI12O:	STRING "UNIVERSE BIOS 1.2 ALT"
STR_BIOS_UNI11:		STRING "UNIVERSE BIOS 1.1"
STR_BIOS_UNI10:		STRING "UNIVERSE BIOS 1.0"
STR_BIOS_NEOPEN:	STRING "NEOPEN BIOS V0.1"

STR_BIOS_JP_V3:		STRING "JAPAN MVS (VER 3)"
STR_BIOS_JP_V2:		STRING "JAPAN MVS (VER 2)"
STR_BIOS_JP_V1:		STRING "JAPAN MVS (VER 1)"
STR_BIOS_JP_MV1B:	STRING "JAPAN MV-1B"
STR_BIOS_JP_J3A:	STRING "JAPAN MVS (J3 ALT)"
STR_BIOS_JP_MV1C:	STRING "JAPAN NEO-MVH MV-1C"
STR_BIOS_USE_V2:	STRING "US/EUROPE MVS (VER 2)"
STR_BIOS_USE_V1:	STRING "US/EUROPE MVS (VER 1)"
STR_BIOS_AS_MV1C:	STRING "ASIA NEO-MVH MV-1C"
STR_BIOS_AS_MV1B:	STRING "ASIA MV-1B"
STR_BIOS_US_V2:		STRING "US MVS (VER 2?)"
STR_BIOS_US_V1:		STRING "US MVS (VER 1)"
STR_BIOS_US_4SLOT:	STRING "US MVS (4 SLOT, V2)"
STR_BIOS_US_U4:		STRING "US MVS (U4)"
STR_BIOS_US_U3:		STRING "US MVS (U3)"
STR_BIOS_JP_HOTEL:	STRING "JAPANESE HOTEL"
STR_BIOS_AES_JP:	STRING "JAPAN AES"
STR_BIOS_AES_EXP:	STRING "EXPORT AES"
STR_BIOS_DEVKIT:	STRING "DEVELOPMENT SYSTEM ROM"
