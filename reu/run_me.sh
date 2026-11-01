#!/bin/sh
# Build whatever is missing or out of date, then play the animation in VICE.
# Extra arguments are passed on to x64sc (e.g. ./run_me.sh -ntsc).
set -e
cd "$(dirname "$0")" >/dev/null

X64SC=$(command -v x64sc || echo /Applications/vice-arm64-gtk3-3.10/bin/x64sc)
[ -x "$X64SC" ] || { echo "x64sc (VICE) not found" >&2; exit 1; }

if [ ! -f frames/frame_100.png ]; then
    echo "extracting frames from c64.mp4..."
    mkdir -p frames
    ffmpeg -v error -i c64.mp4 -vf fps=10 frames/frame_%03d.png
fi

if [ ! -f c64/screen_100.bin ] || [ convert_c64.py -nt c64/screen_100.bin ]; then
    echo "converting frames to C64 hires..."
    python3 convert_c64.py
fi

if [ ! -f c64anim.d81 ] || [ -n "$(find player.asm build_player.sh c64 -newer c64anim.d81 | head -1)" ]; then
    echo "building c64anim.d81..."
    ./build_player.sh
fi

# 512 KB REU; fast virtual drive (KERNAL traps) so the 100 frames load in seconds.
# VICE's startup chatter (missing CMD drive ROMs etc.) is harmless, so it goes to a log.
mkdir -p build
echo "starting VICE: frames load for a few seconds, then the animation loops (close the window to quit)"
if ! "$X64SC" "$@" -reu -reusize 512 +drive8truedrive -trapdevice8 -autostart c64anim.d81 >build/vice.log 2>&1; then
    echo "VICE exited with an error; last lines of build/vice.log:" >&2
    tail -5 build/vice.log >&2
    exit 1
fi
