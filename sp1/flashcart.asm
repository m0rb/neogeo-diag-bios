	include "neogeo.inc"
	include "macros.inc"
	include "sp1.inc"

	global manual_return_to_flashcart
	global STR_RETURN_TO_FLASHCART

	section text

; ============================================================================
; Return to flash-cart loader menu.  Flash carts patch a normal game's vblank to
; forward the controller to an on-cart register; the diag runs its own vblank so
; it never gets patched - so it does the forward itself. BackBit: while START 
; held, move.w (BIOS_P1CURRENT ^ $6b17), $2bacb0.
; ============================================================================
PLATNEO_CART_REG	equ $002bacb0
PLATNEO_XOR		equ $6b17

manual_return_to_flashcart:
		lea	XY_STR_RTF_1, a0
		RSUB	print_xy_string_struct_clear
		lea	XY_STR_RTF_2, a0
		RSUB	print_xy_string_struct_clear
		lea	XY_STR_RTF_3, a0
		tst.b	REG_STATUS_B			; AES: start+select combo
		bmi	.mvs_reset_str
		lea	XY_STR_RTF_3_AES, a0
	.mvs_reset_str:
		RSUB	print_xy_string_struct_clear

	.loop:
		WATCHDOG
		bsr	check_reset_request		; START+COIN = reset
		bsr	p1p2_input_update

		move.b	#1, $0010fd82			; heartbeat
		move.b	#2, $0010fd83

		btst	#0, p1_input_aux		; START held: forward buttons ^ xor
		beq	.frame
		moveq	#0, d0
		move.b	p1_input, d0
		lsl.w	#8, d0
		move.b	p1_input_edge, d0
		eori.w	#PLATNEO_XOR, d0
		move.w	d0, PLATNEO_CART_REG

	.frame:
		bsr	wait_frame
		bra	.loop

STR_RETURN_TO_FLASHCART:	STRING "RETURN TO FLASHCART MENU"

XY_STR_RTF_1:	XY_STRING  4,  7, "PRESS THE FLASH CART RETURN COMBO"
XY_STR_RTF_2:	XY_STRING  4,  8, "TO RETURN TO ITS MENU."
XY_STR_RTF_3:	XY_STRING  4, 26, "START+COIN: SOFT RESET"
XY_STR_RTF_3_AES:	XY_STRING  4, 26, "START+SELECT: SOFT RESET"
