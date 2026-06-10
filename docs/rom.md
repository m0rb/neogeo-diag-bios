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

* **Boards with an SM1** &mdash; the test reads the rom and crc-checks it.
  (MV-1F/2F/4F/6F, MV-1, MV-1A...)
* **Boards without an SM1** &mdash; MV-1B, MV-1C and AES have no SM1 rom.  The
  diag detects this (see *In-test SM1 detection* below) and reports
  **`SM1: NONE`** as a pass &mdash; it no longer throws a false CRC error, and you
  no longer need **B+D**/**C+D** to dodge one (those still work as manual skips).

When the SM1 test *fails on a board that does have an SM1* (a genuine fault), the
error screen shows the actual computed CRC (`SM1 CRC READ: xxxxxxxx`) **and the
first 8 raw bytes the z80 read** (`SM1 RAW: xx xx ...`), so you can
compare the CRC against the expected value in [m1.inc](../m1/m1.inc)
(`SM1_CRC32_UPPER`/`SM1_CRC32_LOWER`).  The `make -f Makefile.rom validate` build
forces this path even when the CRC matches, for confirming the readout against a
known-good board.

### Board detection &amp; SM1 auto-skip

To avoid that false error without making the user remember a button combo, the
cart inspects the host bios at boot (the same approach as the 240p Test Suite)
and auto-skips the SM1 test on boards with no SM1.  The signals, in order:

* **Runtime mode latch** &mdash; `$10fd82` (the bios AES/MVS work-ram flag) is
  latched at takeover, before the work-ram tests wipe it, into an unused palette
  entry.  `$00` = AES.  This is what unibios sets for its AES/MVS *mode*, so it
  catches **unibios running in AES mode** even though the hardware id still reads
  MVS.
* **Bios header byte** &mdash; `$c00400` (`$00` AES / `$80` MVS) on a *stock*
  bios.  Skipped for unibios, whose header byte is not a reliable indicator.
* **Bios CRC32** &mdash; crc of the 128KiB host bios at `$c00000`, matched
  against a table of known bios ids.  The MV-1B/MV-1C board bios'es are flagged
  as no-SM1.  (Plain crc32 in 68k memory order, so the values line up with the
  240p Test Suite's table.)

When SM1 is auto-skipped you get `SM1 AUTO-SKIPPED` on the z80 screen and the
results screen.  Overrides:

* **A+D at boot** &mdash; force the SM1 test even on a detected no-SM1 board.
* **B on the results screen** &mdash; live-retest SM1 (re-runs the slot switch +
  z80 tests, no reboot) for a suspected false positive.

The host-bios detection can't see through unibios (the crc reads as unibios, not
the board), so an MV-1B/1C running under unibios in MVS mode won't be caught at
boot.  That case is handled by a second, bios-independent layer:

### In-test SM1 detection (the real catch-all)

On a board with **no SM1**, flipping `REG_BRDFIX` to "board audio" has nothing to
map, so the z80 just keeps reading the **cart m1** (confirmed on an MV-1C: the
SM1 read came back byte-for-byte identical to the m1's own first bytes,
`C3 66 01 FF FF...`, and its "crc" tracked changes to the m1).

So the m1 detects it directly: it **snapshots its own first bytes at `$0000`
before the bank switch**, reads them again after, and if they're identical the
board has no SM1.  It then reports `COMM_SM1_NONE` and the diag shows
**`SM1: NONE`** and passes, instead of running the crc and throwing a false
error.  This needs no bios knowledge and no crc table, so **no no-SM1 board
(any revision, any bios, including unibios-MVS) produces a false SM1 error** -
the boot-time host-bios skip is now just an optimisation that avoids the round
trip on boards it can identify up front.

### BIOS INFO menu item

A **BIOS INFO** entry on the main menu reports the host bios in full: header HW
(AES/MVS), region, latched runtime mode, Universe Bios detection (`$c000b0`),
the bios CRC32, the identified bios/board name, and whether the SM1 test will run
on this board.  Useful for confirming what the auto-skip detected, and for
identifying an unknown bios (the CRC is shown even when the name lookup misses).

### RETURN TO FLASHCART MENU

Flash carts give you an in-game "return to loader" button combo by **patching a
normal game's vblank handler** to forward the controller state to an on-cart
register each frame; the cart's MCU does the combo match and reloads its menu.
The diag hijacks the bios and runs its own vblank.

The BackBit Platinum Cart's loader return hook hides in unused exception-vector slots, repoints the vblank vector at itself, and performs a
`move.w (BIOS_P1CURRENT ^ $6b17), $2bacb0` 

* **press return combo** &mdash; the diag forwards the raw button
  state, so whatever combo the cart is set to just works

Darksoft/NeoSD's return to loader hook most likely uses uses a similar method;
***To Be Continued.**

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
