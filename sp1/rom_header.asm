; Cartridge header for the diagnostics-as-a-cartridge build.
;
; This replaces vector_table.asm when building the diag to run from a
; cartridge slot (e.g. off a flash cart) instead of the bios socket.  It
; provides the 68k exception vectors, the standard "NEO-GEO" program header
; the host bios looks for, a minimal soft-dip block, the security code and
; the USER entry point the bios jumps to.
;
; Boot flow: on power up the host bios initializes, swaps in our cartridge
; vector table, then calls our USER routine (header offset $122).  We grab
; control there and jump straight into the diag's _start, which fully
; re-initializes the hardware and never returns to the bios.  This means
; the diag runs immediately on both AES and MVS (during the bios' first
; USER request) without needing to insert credits.

	include "neogeo.inc"
	include "sp1.inc"

	global _start
	global vblank_interrupt
	global timer_interrupt

; bios exception handler entry points (jump table at the start of the system
; rom).  A valid cartridge points its exception vectors at these so any
; exception the bios takes while the cart vector table is mapped is handled
; sanely - a table full of $ffffffff (as we had) reads as a "bad" program rom.
BIOS_INIT_HARDWARE	equ $00c00402
BIOS_EXC_BUS_ERROR	equ $00c00408
BIOS_EXC_ADDR_ERROR	equ $00c0040e
BIOS_EXC_ILLEGAL_OP	equ $00c00414
BIOS_EXC_INVALID_OP	equ $00c0041a
BIOS_EXC_TRACE		equ $00c00420
BIOS_EXC_FPU_EMU	equ $00c00426
BIOS_UNINIT_INT		equ $00c0042c
BIOS_SPURIOUS_INT	equ $00c00432

; bios vblank/timer handlers and the flag that says the bios has finished
; booting (and is therefore handing control to the cartridge).
SYSTEM_INT1		equ $00c00438		; bios vblank handler
SYSTEM_INT2		equ $00c0043e		; bios timer handler
BIOS_SYSTEM_MODE	equ $0010fd80		; bit 7 set once bios init is done

	section	vectors,data

;------------------------------------------------------------------------------
; 68k exception vector table ($000 - $0ff) - mirrors the standard neogeo layout
; (ngdevkit / commercial carts): reset + exceptions point into the bios, the
; vblank/timer autovectors point at our handlers.
;------------------------------------------------------------------------------
	dc.l	SP_INIT_ADDR			; $000 initial supervisor stack
	dc.l	BIOS_INIT_HARDWARE		; $004 reset pc
	dc.l	BIOS_EXC_BUS_ERROR		; $008 bus error
	dc.l	BIOS_EXC_ADDR_ERROR		; $00c address error
	dc.l	BIOS_EXC_ILLEGAL_OP		; $010 illegal instruction
	dc.l	BIOS_EXC_INVALID_OP		; $014 divide by zero
	dc.l	BIOS_EXC_INVALID_OP		; $018 chk
	dc.l	BIOS_EXC_INVALID_OP		; $01c trapv
	dc.l	BIOS_EXC_INVALID_OP		; $020 privilege violation
	dc.l	BIOS_EXC_TRACE			; $024 trace
	dc.l	BIOS_EXC_FPU_EMU		; $028 line 1010
	dc.l	BIOS_EXC_FPU_EMU		; $02c line 1111
	dcb.l	3, $ffffffff			; $030 reserved
	dc.l	BIOS_UNINIT_INT			; $03c uninitialized interrupt
	dcb.l	8, $ffffffff			; $040 reserved
	dc.l	BIOS_SPURIOUS_INT		; $060 spurious interrupt
	dc.l	rom_vblank			; $064 level 1 autovector (vblank)
	dc.l	rom_timer			; $068 level 2 autovector (timer)
	dc.l	$00000000			; $06c level 3 autovector
	dcb.l	4, $00000000			; $070 level 4..7 autovectors
	dcb.l	16, $ffffffff			; $080 trap #0..15
	dcb.l	8, $ffffffff			; $0c0 fpu
	dcb.l	3, $ffffffff			; $0e0 mmu
	dcb.l	5, $ffffffff			; $0ec reserved

;------------------------------------------------------------------------------
; NEO-GEO program header ($100)
;------------------------------------------------------------------------------
	rorg	$100, $ff
	dc.b	"NEO-GEO", $00			; $100 magic
	dc.w	$0202				; $108 NGH (cartridge id, non-zero)
	dc.l	$00080000			; $10a program rom size (512k)
	dc.l	$00000000			; $10e backup ram data address
	dc.w	$0000				; $112 backup ram data size
	dc.b	$01				; $114 eyecatch: $01 = game-drawn eyecatcher.
						;      This makes the bios call our USER entry for
						;      the eyecatcher request, which our hook grabs
						;      (matches what working homebrew like 240p uses).
						;      $00 = bios draws its own and never hands off;
						;      $02 = no eyecatcher, bios crosshatches.
	dc.b	$00				; $115 logo first tile (hi byte)
	dc.l	dip_info			; $116 jp soft-dip / cart info
	dc.l	dip_info			; $11a us soft-dip / cart info
	dc.l	dip_info			; $11e eu soft-dip / cart info

	; entry jump table.  each slot is an explicit 6 byte "jmp abs.l"
	; ($4ef9 + 32bit target) so the fixed header offsets are exact.
	rorg	$122, $ff
	dc.w	$4ef9				; $122 USER
	dc.l	rom_user
	dc.w	$4ef9				; $128 PLAYER START
	dc.l	rom_return
	dc.w	$4ef9				; $12e DEMO END
	dc.l	rom_return
	dc.w	$4ef9				; $134 COIN SOUND
	dc.l	rom_return

	; pointer to the security code (61 word sequence the bios checks)
	rorg	$182, $ff
	dc.l	SCODE

SCODE:
	dc.w	$7600,$4a6d,$0a14,$6600,$003c,$206d,$0a04,$3e2d
	dc.w	$0a08,$13c0,$0030,$0001,$3210,$0c01,$00ff,$671a
	dc.w	$3028,$0002,$b02d,$0ace,$6610,$3028,$0004,$b02d
	dc.w	$0acf,$6606,$b22d,$0ad0,$6708,$5088,$51cf,$ffd4
	dc.w	$3607,$4e75,$206d,$0a04,$3e2d,$0a08,$3210,$e049
	dc.w	$0c01,$00ff,$671a,$3010,$b02d,$0ace,$6612,$3028
	dc.w	$0002,$e048,$b02d,$0acf,$6606,$b22d,$0ad0,$6708
	dc.w	$5888,$51cf,$ffd8,$3607,$4e75

;------------------------------------------------------------------------------
; minimal soft-dip / cartridge info block
;  16 byte rom name, 2 unused time dips, 2 unused int dips, 10 unused enum dips
;------------------------------------------------------------------------------
dip_info:
	dc.b	"NEO DIAGNOSTICS "		; 16 byte name
	dc.b	$ff,$ff,$ff,$ff			; time dips (unused)
	dc.b	$00,$00				; int dips (unused)
	dcb.b	10, $00				; enum dips (unused)

;------------------------------------------------------------------------------
; cartridge entry points (live in the normal code rom)
;------------------------------------------------------------------------------
	section	text

; While the bios is still booting it runs with OUR cartridge vector table
; mapped, so vblank/timer interrupts land here.  The bios' boot code waits on
; flags that only its own vblank handler clears, so until it has finished init
; (BIOS_SYSTEM_MODE bit 7) we forward interrupts to the bios handlers, or it
; hangs.  Once our diag has taken over it sets bit 7 (in _start) and we route to
; the diag's own handlers.  jmp keeps the interrupt stack frame intact.
;
; (The work ram test can clobber bit 7 mid-session, after which interrupts fall
; back to the bios handler - harmless in practice, and we must NOT try to be
; clever with the stack pointer here: different bioses boot on different stacks
; - unibios boots high - so an sp-based check breaks their boot.)
rom_vblank:
	btst	#7, BIOS_SYSTEM_MODE
	bne	.diag_running
	jmp	SYSTEM_INT1
.diag_running:
	jmp	vblank_interrupt

rom_timer:
	btst	#7, BIOS_SYSTEM_MODE
	bne	.diag_running
	jmp	SYSTEM_INT2
.diag_running:
	jmp	timer_interrupt

; The bios calls our USER entry during boot.  We grab control on the first call
; and never return - the diag fully re-initializes the hardware itself.  (We
; tried only taking over on the Game/Title request, but with eyecatch=0 that
; lets the bios run its own eyecatcher on our blank graphics and it crosshatches,
; and eyecatch=2 stops the bios calling USER at all - so hijacking the first
; call is what actually works.)
rom_user:
	move	#$2700, sr			; supervisor, all interrupts masked
	movea.l	#SP_INIT_ADDR, a7		; our stack
	jmp	_start				; run the diag, never returns

rom_return:
	rts					; player start / demo end / coin sound
