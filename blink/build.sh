#!/bin/sh
# Build blink.prg and blink.d64 from the Google Flow video, only redoing what's out of date.
#
# Out of date is decided by content hashes, not file dates, because git gives every file a
# new date on checkout. Both hash files are committed, so a fresh clone is already up to date:
#   blink.prg.sha    inputs of blink.prg: converter, video, player, this script
#   data/source.sha  inputs of the converted data: converter and video
set -e
cd "$(dirname "$0")" >/dev/null

VIDEO=$(sed -n 's/^VIDEO = "\(.*\)"/\1/p' convert_blink.py)
hash() { cat "$@" | shasum | cut -d' ' -f1; }

PRG_HASH=$(hash convert_blink.py "$VIDEO" player.asm build.sh)
if [ -f blink.prg ] && [ -f blink.d64 ] && [ "$(cat blink.prg.sha 2>/dev/null)" = "$PRG_HASH" ]; then
    exit 0
fi

SOURCE_HASH=$(hash convert_blink.py "$VIDEO")
if [ ! -f data/deltas.bin ] || [ "$(cat data/source.sha 2>/dev/null)" != "$SOURCE_HASH" ]; then
    echo "converting video to C64 hires..."
    python3 convert_blink.py
    echo "$SOURCE_HASH" > data/source.sha
fi

acme -f cbm -o blink.prg player.asm
rm -f blink.d64
c1541 -format "blink,01" d64 blink.d64 -write blink.prg blink >/dev/null 2>&1
echo "$PRG_HASH" > blink.prg.sha
echo "built blink.prg ($(wc -c < blink.prg | tr -d ' ') bytes) and blink.d64"
