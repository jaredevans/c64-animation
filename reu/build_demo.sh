#!/bin/sh
# Build demo.prg playing COUNT frames starting at FIRST (default 11..20).
# 10 frames is about the limit: each frame is 3375 bytes and data lives in $4000-$cfff.
set -e
cd "$(dirname "$0")"
FIRST=${1:-11}
COUNT=${2:-10}

{
    echo "FRAME_COUNT = $COUNT"
    echo "* = \$4000"
    i=0
    while [ $i -lt "$COUNT" ]; do
        n=$(printf %03d $((FIRST + i)))
        echo "f$i: !binary \"c64/bitmap_$n.bin\""
        echo "    !binary \"c64/screen_$n.bin\""
        i=$((i + 1))
    done
    printf "frames_lo: !byte "; i=0; while [ $i -lt "$COUNT" ]; do [ $i -gt 0 ] && printf ", "; printf "<f$i"; i=$((i + 1)); done; echo
    printf "frames_hi: !byte "; i=0; while [ $i -lt "$COUNT" ]; do [ $i -gt 0 ] && printf ", "; printf ">f$i"; i=$((i + 1)); done; echo
} > demo_frames.asm

acme -f cbm -o demo.prg demo.asm
echo "built demo.prg (frames $FIRST..$((FIRST + COUNT - 1)))"
