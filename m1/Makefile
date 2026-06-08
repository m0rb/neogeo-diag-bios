HOST_CC = cc
VASM = vasmz80_mot
VASM_FLAGS = -Fbin -spaces -L debug/m1.asm.txt -chklabels
ODIR = output
MKDIR = mkdir

${ODIR}/m1.bin: gen-crc-mirror-bank m1.asm m1.inc macros.inc neogeo.inc ${ODIR}
	${VASM} ${VASM_FLAGS} -o ${ODIR}/m1.bin m1.asm
	./gen-crc-mirror-bank ${ODIR}/m1.bin

# Cartridge variant of the m1: the comm test waits silently instead of beeping
# a NO_HANDSHAKE timeout (the cart m1 auto-boots without a 68k partner unless
# the user runs the z80 test).  Deploy this one as the cart's m1 rom.
rom: ${ODIR}/m1_rom.bin

${ODIR}/m1_rom.bin: gen-crc-mirror-bank m1.asm m1.inc macros.inc neogeo.inc ${ODIR}
	${VASM} -Fbin -spaces -L debug/m1_rom.asm.txt -chklabels -DROM=1 -o ${ODIR}/m1_rom.bin m1.asm
	./gen-crc-mirror-bank ${ODIR}/m1_rom.bin

# Same as cart, but forces the SM1 CRC test to fail (after computing the real
# value) so the error screen + reported CRC show even when the CRC matches -
# for validating the CRC display against a known-good board.
rom-validate: ${ODIR}/m1_rom_validate.bin

${ODIR}/m1_rom_validate.bin: gen-crc-mirror-bank m1.asm m1.inc macros.inc neogeo.inc ${ODIR}
	${VASM} -Fbin -spaces -L debug/m1_rom_validate.asm.txt -chklabels -DROM=1 -DFORCE_SM1_CRC_FAIL=1 -o ${ODIR}/m1_rom_validate.bin m1.asm
	./gen-crc-mirror-bank ${ODIR}/m1_rom_validate.bin

gen-crc-mirror-bank: gen-crc-mirror-bank.c
	${HOST_CC} gen-crc-mirror-bank.c -o gen-crc-mirror-bank

${ODIR}:
	${MKDIR} ${ODIR} debug

clean:
	rm -f gen-crc-mirror-bank ${ODIR}/m1.bin ${ODIR}/m1_rom.bin ${ODIR}/m1_rom_validate.bin debug/m1.asm.txt debug/m1_rom.asm.txt debug/m1_rom_validate.asm.txt

