#!/bin/sh
# Build c64anim.d81: the REU player plus 100 frame files (F001..F100).
# Frame files are row-interleaved for the player: per cell row, 120 bitmap bytes then 15 screen bytes.
set -e
cd "$(dirname "$0")"
mkdir -p build

python3 - <<'EOF'
import numpy as np
for k in range(1, 101):
    bitmap = np.fromfile(f"c64/bitmap_{k:03d}.bin", np.uint8).reshape(25, 120)
    screen = np.fromfile(f"c64/screen_{k:03d}.bin", np.uint8).reshape(25, 15)
    with open(f"build/f{k:03d}.prg", "wb") as f:
        f.write(bytes([0x00, 0x40]) + np.hstack([bitmap, screen]).tobytes())
EOF

acme -f cbm -o build/player.prg player.asm

args=""
for k in $(seq -f %03g 1 100); do
    args="$args -write build/f$k.prg f$k"
done
rm -f c64anim.d81
c1541 -format "portrait,01" d81 c64anim.d81 -write build/player.prg player $args >/dev/null
echo "built c64anim.d81"
