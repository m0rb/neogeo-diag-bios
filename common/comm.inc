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

; sm1 crc32, sent as 8 seq-tagged nibbles (hi=seq 1..8, lo=data)
COMM_SM1_CRC_REPORT		equ $b5		; z80 -> 68k
COMM_SM1_CRC_ACK		equ $b6		; 68k -> z80

; first raw sm1 bytes (no-sm1 boards read open bus/garbage); seq wraps $1..$f
COMM_SM1_SIG_REPORT		equ $b7		; z80 -> 68k
COMM_SM1_SIG_ACK		equ $b8		; 68k -> z80
SM1_SIG_LEN			equ 8

; no sm1: pre/post bank-switch read identical (reading our own m1), benign
COMM_SM1_NONE			equ $b9		; z80 -> 68k
COMM_SM1_NONE_ACK		equ $ba		; 68k -> z80
