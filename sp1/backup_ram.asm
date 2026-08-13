	include "neogeo.inc"
	include "macros.inc"
	include "sp1.inc"
	include "../common/error_codes.inc"

	global auto_backup_ram_tests
	global manual_backup_ram_tests
	global STR_BACKUP_RAM_TEST_LOOP

	section text

; bounce buffer (free work ram, above the fixmap backup + screen scratch)
BRAM_KEEP_BUF	equ $104000

; The automatic tests save/restore backup ram contents so the mvs bios'
; bookkeeping table survives booting the diag.  Only failures leave it
; partially clobbered (contents were suspect anyway).
auto_backup_ram_tests:
		tst.b	REG_STATUS_B			; do test if MVS
		bmi	.do_tests
		moveq	#0, d0
		rts

	.do_tests:
		move.b	d0, REG_SRAMUNLOCK		; unlock
		RSUB	backup_ram_oe_tests		; read-only
		tst.b	d0
		bne	.done

		move.w	BACKUP_RAM_START, BRAM_KEEP_BUF	; we test clobbers first word only
		RSUB	backup_ram_we_tests
		tst.b	d0
		bne	.done
		move.w	BRAM_KEEP_BUF, BACKUP_RAM_START

		moveq	#0, d5				; data tests, 16k chunks
	.loop_data_chunk:
		WATCHDOG
		bsr	.chunk_addr
		lea	BRAM_KEEP_BUF, a1
		move.w	#$4000, d0
		bsr	copy_memory
		bsr	.chunk_addr
		move.w	#$2000, d0			; words
		RSUB	check_ram_data
		tst.b	d0
		bne	.data_failed
		bsr	.chunk_addr
		movea.l	a0, a1
		lea	BRAM_KEEP_BUF, a0
		move.w	#$4000, d0
		bsr	copy_memory
		addq.w	#1, d5
		cmp.w	#4, d5
		bne	.loop_data_chunk

		; address tests clobber first $200 bytes + one word every $200
		lea	BACKUP_RAM_START, a0
		lea	BRAM_KEEP_BUF, a1
		move.w	#$200, d0
		bsr	copy_memory
		lea	BACKUP_RAM_START, a0
		lea	BRAM_KEEP_BUF+$200, a1
		move.w	#$80-1, d1
	.loop_save_sparse:
		WATCHDOG
		move.w	(a0), (a1)+
		lea	($200,a0), a0
		dbra	d1, .loop_save_sparse

		RSUB	backup_ram_address_tests
		tst.b	d0
		bne	.done

		lea	BRAM_KEEP_BUF, a0
		lea	BACKUP_RAM_START, a1
		move.w	#$200, d0
		bsr	copy_memory
		lea	BRAM_KEEP_BUF+$200, a0
		lea	BACKUP_RAM_START, a1
		move.w	#$80-1, d1
	.loop_restore_sparse:
		WATCHDOG
		move.w	(a0)+, (a1)
		lea	($200,a1), a1
		dbra	d1, .loop_restore_sparse
		moveq	#0, d0

	.done:
		move.b	d0, REG_SRAMLOCK		; lock
		rts

	.data_failed:
		subq.b	#1, d0
		add.b	#EC_BRAM_DATA_LOWER, d0
		bra	.done

	.chunk_addr:					; a0 = start of chunk d5
		moveq	#0, d0
		move.w	d5, d0
		swap	d0
		lsr.l	#2, d0				; * $4000
		lea	BACKUP_RAM_START, a0
		adda.l	d0, a0
		rts

manual_backup_ram_tests:
		lea	XY_STR_PASSES,a0
		RSUB	print_xy_string_struct_clear
		lea	XY_STR_D_MAIN_MENU, a0
		RSUB	print_xy_string_struct_clear

		moveq	#0, d6				; passes
		move.b	d0, REG_SRAMUNLOCK
		bra	.loop_start_run_test

	.loop_run_test:
		WATCHDOG

		PSUB	backup_ram_data_tests
		tst.b	d0
		bne	.test_failed_abort

		PSUB	backup_ram_address_tests
		tst.b	d0
		bne	.test_failed_abort

		addq.l	#1, d6

	.loop_start_run_test:

		moveq	#$e, d0
		moveq	#$e, d1
		move.l	d6, d2
		bclr	#$1f, d2
		PSUB	print_hex_3_bytes

		btst	#D_BUTTON, REG_P1CNT
		bne	.loop_run_test

		move.b	d0, REG_SRAMLOCK
		rts

	.test_failed_abort:
		move.b	d0, REG_SRAMLOCK

		PSUB	print_error
		bra	loop_d_pressed


backup_ram_oe_tests_dsub:
		tst.b	REG_STATUS_B			; skip test on AES unless C is pressed
		bmi	.do_test
		btst	#6, REG_P1CNT
		bne	.test_passed

	.do_test:
		lea	BACKUP_RAM_START, a0
		moveq	#0, d0
		DSUB	check_ram_oe
		tst.b	d0
		bne	.test_failed_backup_ram_upper

		moveq	#1, d0
		DSUB	check_ram_oe
		tst.b	d0
		bne	.test_failed_backup_ram_lower

	.test_passed:
		moveq	#0, d0
		DSUB_RETURN

	.test_failed_backup_ram_upper:
		moveq	#EC_BRAM_DEAD_OUTPUT_UPPER, d0
		DSUB_RETURN

	.test_failed_backup_ram_lower:
		moveq	#EC_BRAM_DEAD_OUTPUT_LOWER, d0
		DSUB_RETURN

backup_ram_we_tests_dsub:
		tst.b	REG_STATUS_B
		bmi	.do_test				; if MVS jump to bram test
		btst	#6, REG_P1CNT
		beq	.do_test
		moveq	#0, d0
		DSUB_RETURN

	.do_test:
		lea	BACKUP_RAM_START, a0
		move.w	#$ff, d0
		DSUB	check_ram_we
		tst.b	d0
		beq	.test_passed_lower

		moveq	#EC_BRAM_UNWRITABLE_LOWER, d0
		DSUB_RETURN

	.test_passed_lower:
		lea	BACKUP_RAM_START, a0
		move.w	#$ff00, d0
		DSUB	check_ram_we
		tst.b	d0
		beq	.test_passed_upper

		moveq	#EC_BRAM_UNWRITABLE_UPPER, d0
		DSUB_RETURN

	.test_passed_upper:
		moveq	#0, d0
		DSUB_RETURN

backup_ram_data_tests_dsub:
		lea	BACKUP_RAM_START, a0
		move.w	#$8000, d0
		DSUB	check_ram_data
		tst.b	d0
		bne	.test_failed
		DSUB_RETURN

	.test_failed:
		subq.b	#1, d0
		add.b	#EC_BRAM_DATA_LOWER, d0
		DSUB_RETURN


backup_ram_address_tests_dsub:
		lea	BACKUP_RAM_START, a0
		moveq	#$2, d0
		move.w	#$100, d1
		DSUB	check_ram_address

		tst.b	d0
		beq	.test_passed_a0_a7
		moveq	#EC_BRAM_ADDRESS_A0_A7, d0
		DSUB_RETURN

	.test_passed_a0_a7:
		lea	BACKUP_RAM_START, a0
		move.w	#$200, d0
		move.w	#$80, d1
		DSUB	check_ram_address

		tst.b	d0
		beq	.test_passed_a8_a14
		moveq	#EC_BRAM_ADDRESS_A8_A14, d0
		DSUB_RETURN

	.test_passed_a8_a14:
		moveq	#0, d0
		DSUB_RETURN

STR_BACKUP_RAM_TEST_LOOP:	STRING "BACKUP RAM TEST LOOP (MVS ONLY)"
