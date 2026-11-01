#!/bin/sh
# Build blink.prg and blink.d64 from the Google Flow video. Reconverts only when the converter changed.
set -e
cd "$(dirname "$0")" >/dev/null

if [ ! -f data/deltas.bin ] || [ convert_blink.py -nt data/deltas.bin ]; then
    echo "converting video to C64 hires..."
    python3 convert_blink.py
fi

acme -f cbm -o blink.prg player.asm
rm -f blink.d64
c1541 -format "blink,01" d64 blink.d64 -write blink.prg blink >/dev/null 2>&1
echo "built blink.prg ($(wc -c < blink.prg | tr -d ' ') bytes) and blink.d64"
