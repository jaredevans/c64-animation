#!/bin/sh
# Build if needed, then play the blinking-man animation in VICE.
# Extra arguments are passed on to x64sc (e.g. ./run_me.sh -ntsc).
set -e
cd "$(dirname "$0")" >/dev/null

X64SC=$(command -v x64sc || echo /Applications/vice-arm64-gtk3-3.10/bin/x64sc)
[ -x "$X64SC" ] || { echo "x64sc (VICE) not found" >&2; exit 1; }

./build.sh                  # does nothing if blink.prg is up to date

# No REU needed: the whole animation fits in C64 RAM. The PRG is injected straight into memory.
# VICE's startup chatter (missing CMD drive ROMs etc.) is harmless, so it goes to a log.
echo "starting VICE: the animation loops (close the window to quit)"
if ! "$X64SC" "$@" -autostartprgmode 1 -autostart blink.prg >vice.log 2>&1; then
    echo "VICE exited with an error; last lines of vice.log:" >&2
    tail -5 vice.log >&2
    exit 1
fi
