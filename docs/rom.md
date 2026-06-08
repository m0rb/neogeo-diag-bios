# Diagnostics as a PROM (ROM build)

The diag is normally burned into the BIOS socket (the `sp1` build at `$c00000`).
For systems where you can't easily replace the BIOS, there is also a **ROM**
build that runs the diag from a normal cartridge slot &mdash; off a flash cart
(BackBit, NeoSD, Darksoft, etc.) or in an emulator &mdash; on top of whatever
host BIOS is installed (stock SNK, Universe BIOS, ...).

## Building

Requires the same `vasmm68k_mot` / `vasmz80_mot` / `vlink` tools as the bios
build (see the main [README](../README.md)).  From the repo root:

```
$ make -f Makefile.rom           # romset  -> dist/NGDIAG.{p1,m1,s1,v1,c1}
$ make -f Makefile.rom neo       # + Terraonion .neo (needs the neosd tool on PATH)
$ make -f Makefile.rom validate  # romset with a forced SM1 CRC fail (see below)
$ make -f Makefile.rom clean
```

Under the hood:

* `sp1/Makefile.rom` assembles the 68k side with `-DROM`, links it at `$000000`
  with `rom.ld` (instead of `$c00000` with `sp1.ld`), uses `rom_header.asm` for
  the NEO-GEO header + boot hook, and byteswaps the image (`dd conv=swab`) the
  same way the bios p rom is stored.
* `m1/Makefile`'s `rom` target builds a `-DROM` variant of the m1
  (`output/m1_rom.bin`); `rom-validate` adds `-DFORCE_SM1_CRC_FAIL`.
* `Makefile.rom` ties them together and drops the romset in `dist/`, named
  `NGDIAG.<type>` with 1KB zero-filled `s1`/`v1`/`c1` stubs.

The diag draws all of its text from the **on-board sfix font**, so the
cartridge's own S rom is never used and the C/V roms aren't needed for normal
operation &mdash; blank stubs are fine.

## How it boots

The ROM build is linked at `$000000` and carries a standard NEO-GEO program
header ([rom_header.asm](../sp1/rom_header.asm)): the 68k vector table (reset +
exceptions point into the host bios, the vblank/timer autovectors point at our
own `rom_vblank`/`rom_timer` wrappers), the `"NEO-GEO"` magic + NGH + sizes, the
security code, and the `USER` entry point.

On power up the host bios initializes, swaps in our cartridge vector table, then
calls our `USER` routine; we grab control on that first call and jump straight
into the diag's `_start`, which fully re-initializes the hardware and never
returns to the bios.  The diag therefore runs immediately on both AES and MVS
without inserting credits.

While the host bios is still booting it runs with our vector table mapped, so
vblank/timer interrupts land in `rom_vblank`/`rom_timer`.  Until the diag has
taken over (`BIOS_SYSTEM_MODE` bit 7) those forward to the host bios' handlers
(its boot waits on flags only its own vblank clears); afterwards they route to
the diag's handlers.

## z80 / m1 testing

Because the diag is a guest of a working host bios, the z80 doesn't run *our* m1
by default &mdash; with the board audio bank selected it runs whatever sound
program the board provides.  So z80 testing on a cart **forces a slot switch**:
`REG_CRTFIX` flips the z80's m1 bank to the cartridge and a `#$3` reset reboots
the z80 into our m1's `_start`.  That's the only way our diag m1 actually runs,
and it's why the bios build's HELLO auto-detect is *not* used on a cart.

Testing is opt-in via the buttons held at boot (latched at takeover, so a brief
press is enough):

| hold at boot | result |
|---|---|
| (nothing) | z80 testing skipped &mdash; clean boot |
| **D**     | full z80 test including the SM1 OE/CRC test |
| **C+D**   | z80 test, SM1 OE/CRC skipped (`SKIP_SM1` flag) |
| **B+D**   | z80 test, SM1 OE/CRC skipped (for MV-1B/1C and other boards without an SM1)  |

The cart m1's comm test waits *silently* instead of beeping a `NO_HANDSHAKE`
timeout, so a powered-but-untested z80 (no D held) doesn't cry a false comm
error after ~20s of idling.

### SM1 OE/CRC test &mdash; board dependent

The SM1 OE/CRC test reads the board's SM1 rom, so its result depends on whether
the board actually has one:

* **Boards with an SM1** &mdash; the test reads the rom. (MV-1F/2F/4F/6F...)
  
  * **Boards without an SM1** &mdash; MV-1B, MV-1C, and AES have no SM1 rom, so
  the test reads a fixed wrong region and throws an error. (Error Code 001100) 
  On these boards, use **B+D** or **C+D** to skip the SM1 test.

When the SM1 CRC test fails, the actual computed CRC is shown on the error screen
(`SM1 CRC READ: xxxxxxxx`) so you can see what your particular board hashes to
and compare it against the expected value in [m1.inc](../m1/m1.inc)
(`SM1_CRC32_UPPER`/`SM1_CRC32_LOWER`).  The `make -f Makefile.rom validate` build
forces this path even when the CRC matches, for confirming the readout against a
known-good board.

## Other differences from the bios build

* Soft reset is **P1 START + COIN** (the bios build uses START + SELECT) &mdash;
  handier on a cab / flash-cart setup.
* The controller test shows a **COIN** row (the bios build's redundant `DEC`
  column is dropped to make room).
* The **BIOS MIRROR** and **BIOS CRC32** automatic tests are removed &mdash; as a
  cartridge they would be testing the host's bios, not the diag.
* This is **not** a substitute for the bios build when diagnosing a dead board.
  To even reach the cartridge, the host bios, work ram and the cartridge bus all
  have to be working.  If those are suspect, use the real bios build.

Everything else &mdash; color bars, video dac, controller, work/backup/palette/
video ram loops, calendar, memory card, misc input, and the automatic ram tests
&mdash; works the same as the bios build.
