; 68k <-> z80 comm defines

; comm test
COMM_TEST_HELLO			equ $c3		; z80 -> 68k
COMM_TEST_HANDSHAKE		equ $5a		; 68k -> z80
COMM_TEST_ACK			equ $3c		; z80 -> 68k

; z80 -> 68k indicating all tests are complete
COMM_Z80_TESTS_COMPLETE		equ $e7

; sm1 tests
COMM_SM1_TEST_SWITCH_SM1	equ $b0		; z80 -> 68k
COMM_SM1_TEST_SWITCH_SM1_DENY	equ $b1		; z80 -> 68k
COMM_SM1_TEST_SWITCH_SM1_DONE	equ $b2		; 68k -> z80
COMM_SM1_TEST_SWITCH_M1		equ $b3		; z80 -> 68k
COMM_SM1_TEST_SWITCH_M1_DONE	equ $b4		; 68k -> z80

; z80 reports the computed sm1 crc32 to the 68k so it can be shown on screen.
; it is sent as 8 sequence-tagged nibbles (high nibble = sequence 1..8, low
; nibble = data) so every transferred byte is distinct and non-zero, which
; keeps the single-latch handshake robust against repeated/zero crc bytes.
COMM_SM1_CRC_REPORT		equ $b5		; z80 -> 68k ("crc follows")
COMM_SM1_CRC_ACK		equ $b6		; 68k -> z80 ("ready, send it")
