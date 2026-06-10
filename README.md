# neogeo-diag-bios
Disassembly of smkdan's Neo Geo Diagnostics BIOS with new features.

http://smkdan.eludevisibility.org/neo/diag/

This is a disassembly of smkdan's diag bios, both sp1 and m1 are included.  I
originally did this as a personal project to learn 68k/z80 assembly and neo geo
hardware.  However with smkdan having disappeared in late 2014 I thought others
might find this useful.  I've started adding new features which you can see in
the [CHANGELOG](CHANGELOG.md)

Please use the [v0.19](https://github.com/jwestfall69/neogeo-diag-bios/tree/v0.19)
branch of the disassembly if you want compiled rom files to match up with the
original smkdan roms.

## Pre-Built
You can grab the lastest build from the master branch [here](https://github.com/m0rb/neogeo-diag-bios/releases/latest/)

## Building
Building requires vasm and vlink, which are available here

http://sun.hasenbraten.de/vasm/<br>
http://sun.hasenbraten.de/vlink/

For vasm you will need vasmm68k_mot and vasmz80_mot binaries.  If you are
building vasm from source, like I did, you can build them with the following
commands

```
$ make CPU=m68k SYNTAX=mot
$ make CPU=z80 SYNTAX=mot
```

Copy the resulting vasmm68k_mot and vasmz80_mot binaries so they are within
your $PATH

Then its just a matter of going into the sp1 and m1 directories and running
make.  The resulting rom file for each will be placed in the output/ directory.

## Running from a cartridge slot (ROM build)

For systems where you can't easily replace the bios, the diag can also be built
as a **program rom** and run from a cartridge (flash cart, emulator) instead of 
the BIOS socket.  Works on stock SNK and Universe BIOS.

From the repo root:

```
$ make -f Makefile.rom           # romset -> dist/NGDIAG.{p1,m1,s1,v1,c1}
$ make -f Makefile.rom neo       # also pack a Terraonion .neo (needs the neosd tool)
$ make -f Makefile.rom validate  # romset with a forced SM1 CRC fail (see below)
```

The romset is the bare minimum a flash cart needs: PROM, MROM, and 1KB zero-filled 
S/V/C roms.

### z80 / m1 testing

z80 testing is opt-in via the buttons held at boot:

| hold at boot | result |
|---|---|
| (nothing) | z80 testing skipped (clean boot) |
| **D**     | full z80 test; the SM1 OE/CRC test runs unless the board is detected as having no SM1 |
| **C+D**   | z80 test, SM1 OE/CRC force-skipped |
| **B+D**   | z80 test, SM1 OE/CRC force-skipped (skips the slot switch; for MV-1B/1C) |
| **A+D**   | z80 test, SM1 OE/CRC **forced** even if the board is detected as having no SM1 |

**No false SM1 errors on no-SM1 boards.** There are two layers:

1. **Boot-time auto-skip (host-bios detection):** the cart inspects the host
   bios at boot and skips the SM1 test on boards it can identify as having no
   SM1 (AES, **unibios in AES mode**, and stock MV-1B/MV-1C). You'll see
   `SM1 AUTO-SKIPPED`; press **B** on the results screen to retest live, or hold
   **A+D** at boot to force it.
2. **In-test detection (bios-independent):** if a no-SM1 board *isn't* caught at
   boot (e.g. MV-1B/MV-1C running under unibios in MVS mode), the m1 catches it
   during the test — it snapshots its own bytes before the bank switch and, if
   the post-switch read is byte-for-byte identical (the switch had no SM1 to map,
   so it's reading itself), it reports **`SM1: NONE`** and passes instead of
   throwing a CRC error. This works under any bios on any board, so **a no-SM1
   board never produces a false SM1 error.**

If/When the SM1 CRC test fails, the actual computed CRC is shown on the error screen
so it can be checked against the expected value. (Please report an issue with screenshot)

The new **BIOS INFO** menu item reports the host bios in detail: header HW
(AES/MVS), region, runtime mode, Universe Bios detection, the bios CRC32 and the
identified bios/board name, plus whether the SM1 test will run on this board.

The **RETURN TO FLASHCART MENU** item lets you drop straight back to your flash
cart's loader from the diag. Flash carts implement their in-game return combo by
patching a normal game's vblank handler to forward the controller state to an
on-cart register; the diag hijacks the bios so it never gets patched, so instead
it performs that same forward itself. Currently wired for **PlatNeo / BackBit**
(hold your configured return combo, or hold **A** to force it); the writes are
harmless on other carts. See [docs/rom.md](docs/rom.md) for the mechanism.

### Notes

- Soft reset is **P1 START + COIN** (BIOS build uses START + SELECT).
- See [docs/rom.md](docs/rom.md) for the boot flow, build internals and
  board-variant details.
