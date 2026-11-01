#!/bin/sh
# Build whatever is missing or out of date, then play the animation in VICE.
# Extra arguments are passed on to x64sc (e.g. ./run_me.sh -ntsc).
set -e
cd "$(dirname "$0")" >/dev/null

X64SC=$(command -v x64sc || echo /Applications/vice-arm64-gtk3-3.10/bin/x64sc)
[ -x "$X64SC" ] || { echo "x64sc (VICE) not found" >&2; exit 1; }

# Out of date is decided by content hashes, not file dates, because git gives every file a
# new date on checkout. The hash files are committed, so a fresh clone is already up to date:
#   c64anim.d81.sha    inputs of the disk image: video, converter, player, disk builder
#   c64/source.sha     inputs of the converted frames: video and converter
#   frames/source.txt  video the extracted frames came from, and the frame rate
hash() { cat "$@" | shasum | cut -d' ' -f1; }

D81_HASH=$(hash c64.mp4 convert_c64.py player.asm build_player.sh)
if [ ! -f c64anim.d81 ] || [ "$(cat c64anim.d81.sha 2>/dev/null)" != "$D81_HASH" ]; then
    C64_HASH=$(hash c64.mp4 convert_c64.py)
    if [ ! -f c64/screen_100.bin ] || [ "$(cat c64/source.sha 2>/dev/null)" != "$C64_HASH" ]; then
        FRAMES_SOURCE="$(hash c64.mp4) fps=10"
        if [ "$(cat frames/source.txt 2>/dev/null)" != "$FRAMES_SOURCE" ]; then
            echo "extracting frames from c64.mp4..."
            mkdir -p frames
            rm -f frames/frame_*.png
            ffmpeg -v error -i c64.mp4 -vf fps=10 frames/frame_%03d.png
            echo "$FRAMES_SOURCE" > frames/source.txt
        fi

        echo "converting frames to C64 hires..."
        rm -f c64/bitmap_*.bin c64/screen_*.bin c64/preview_*.png
        python3 convert_c64.py
        echo "$C64_HASH" > c64/source.sha
    fi

    echo "building c64anim.d81..."
    ./build_player.sh
    echo "$D81_HASH" > c64anim.d81.sha
fi

# 512 KB REU; fast virtual drive (KERNAL traps) so the 100 frames load in about 40 seconds.
# VICE's startup chatter (missing CMD drive ROMs etc.) is harmless, so it goes to a log.
mkdir -p build
echo "starting VICE: the 100 frames load in about 40 seconds (one dot each), then the animation loops (close the window to quit)"
if ! "$X64SC" "$@" -reu -reusize 512 +drive8truedrive -trapdevice8 -autostart c64anim.d81 >build/vice.log 2>&1; then
    echo "VICE exited with an error; last lines of build/vice.log:" >&2
    tail -5 build/vice.log >&2
    exit 1
fi
