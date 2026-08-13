#!/usr/bin/env python3
# Generate fix_font.s1: an ascii fix-layer font for the cart build so the diag
# has video output on AES (no board sfix there; the fix rom must come from the
# cart).  Tile index == ascii, matching what all the print code assumes.
#
# Glyphs come from a VGA 8x8 console font (psf/psf.gz).  Extra tiles the diag
# uses: $000 solid (color bars/video dac), $011 menu arrow, $016/$116 header
# line, $600 checkerboard / $620 blank (video dac fullscreen patterns).
#
# usage: gen-fix-font.py [font.psf(.gz)] [out.s1]
import gzip, struct, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else '/usr/share/consolefonts/Lat15-VGA8.psf.gz'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'fix_font.s1'
SIZE = 0x20000          # 128k, tiles $000-$fff


def load_psf(path):
    op = gzip.open if path.endswith('.gz') else open
    data = op(path, 'rb').read()
    if data[:2] == b'\x36\x04':                     # psf1
        mode, h = data[2], data[3]
        n = 512 if mode & 1 else 256
        off = 4
        glyphs = [data[off + i * h:off + (i + 1) * h] for i in range(n)]
        table = {}
        if mode & 6:
            i = off + n * h
            g = 0
            while g < n and i + 1 < len(data):
                v = struct.unpack_from('<H', data, i)[0]
                i += 2
                if v == 0xffff:
                    g += 1
                elif v != 0xfffe:
                    table.setdefault(v, g)
        return glyphs, h, table
    if data[:4] == b'\x72\xb5\x4a\x86':             # psf2
        _, hdr, flags, n, gsize, h, w = struct.unpack_from('<7I', data, 4)
        off = hdr
        glyphs = [data[off + i * gsize:off + (i + 1) * gsize] for i in range(n)]
        table = {}
        if flags & 1:
            i = off + n * gsize
            g = 0
            while g < n and i < len(data):
                if data[i] == 0xff:
                    g += 1
                    i += 1
                elif data[i] == 0xfe:
                    i += 1
                else:
                    ln = 1
                    while i + ln < len(data) and data[i + ln] not in (0xfe, 0xff) \
                            and (data[i + ln] & 0xc0) == 0x80:
                        ln += 1
                    table.setdefault(data[i:i + ln].decode('utf-8', 'replace'), g)
                    i += ln
        table = {ord(k) if isinstance(k, str) and len(k) == 1 else k: v
                 for k, v in table.items()}
        return glyphs, h, table
    raise SystemExit('not a psf font: ' + path)


# fix format: 32 bytes/tile, byte = 2 pixels (low nibble left), rows top-down,
# column pair order 4-5, 6-7, 0-1, 2-3 (byte groups $00, $08, $10, $18)
def encode(rows):
    t = bytearray(32)
    for r in range(8):
        pen = [(rows[r] >> (7 - x)) & 1 for x in range(8)]
        t[0x10 + r] = pen[0] | pen[1] << 4
        t[0x18 + r] = pen[2] | pen[3] << 4
        t[0x00 + r] = pen[4] | pen[5] << 4
        t[0x08 + r] = pen[6] | pen[7] << 4
    return t


glyphs, height, table = load_psf(SRC)
if height != 8:
    raise SystemExit('need an 8px font, got %dpx' % height)

out = bytearray(SIZE)


def place(tile, rows):
    out[tile * 32:tile * 32 + 32] = encode(rows)


for a in range(0x20, 0x7f):
    g = glyphs[table[a]] if table and a in table else glyphs[a]
    place(a, list(g))

place(0x000, [0xff] * 8)                                    # solid
place(0x011, [0x40, 0x60, 0x70, 0x78, 0x70, 0x60, 0x40, 0x00])  # arrow
place(0x016, [0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])  # overscore
place(0x116, [0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
place(0x600, [0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55])  # checker

open(OUT, 'wb').write(out)
print('%s: %d bytes, %d ascii glyphs from %s' % (OUT, SIZE, 0x7f - 0x20, SRC))
