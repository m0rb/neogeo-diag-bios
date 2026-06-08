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
You can grab the lastest build from the master branch at

https://www.mvs-scans.com/neogeo-diag-bios/19a02-master.zip

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
| **D**     | full z80 test including the SM1 OE/CRC test |
| **C+D**   | z80 test, SM1 OE/CRC skipped |
| **B+D**   | z80 test, SM1 OE/CRC skipped (for MV-1B/1C and other boards without an SM1) |

If/When the SM1 CRC test fails, the actual computed CRC is shown on the error screen
so it can be checked against the expected value. (Please report an issue with screenshot)

### Notes

- Soft reset is **P1 START + COIN** (BIOS build uses START + SELECT).
- See [docs/rom.md](docs/rom.md) for the boot flow, build internals and
  board-variant details.
