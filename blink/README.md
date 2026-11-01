# Blinking Spaceman — Full-Screen C64 Animation

This is a full-screen (320×200) hires animation of a space pilot blinking and frowning. It plays at 10fps on a **stock Commodore 64**: one 22 KB program, with no REU, no disk loading while it plays, and no extra hardware.

It's the second animation in this project. The first one, in [`../reu/`](../reu/README.md), was a deliberate stress test: `c64.mp4` has heavy motion all over the picture to push the C64 to its limit. Its frames had to be stored whole, which needed a RAM Expansion Unit. This one goes the other way: motion is kept to a minimum on purpose and the art was made for the C64 from the start. As a result, the entire animation fits in about 8 KB of per-frame changes.

## 1. Making the source art with Gemini and Google Flow

### The still image (Gemini)

Gemini was given a prompt describing C64 constraints:

```
Pixel art portrait of a weathered space pilot with short dark hair and a square jaw,
head and shoulders, wearing a bulky dark grey (#444444, #6C6C6C) armored spacesuit with
orange (#6F4F25) and cyan (#70A4B2) accent panels and a white helmet collar ring, looking
slightly off-camera with a determined expression, in the style of a Commodore 64 hires
bitmap image.

Strict constraints:
- Use ONLY these 16 colors (the C64 palette), no other colors, no blending:
  #000000 black, #FFFFFF white, #68372B red, #70A4B2 cyan, #6F3D86 purple,
  #588D43 green, #352879 blue, #B8C76F yellow, #6F4F25 orange, #433900 brown,
  #9A6759 light red, #444444 dark grey, #6C6C6C grey, #9AD284 light green,
  #6C5EB5 light blue, #959595 light grey
- Muted, desaturated colors only; no neon or bright saturated tones
- Skin shaded ONLY with #9A6759 light red, #68372B red and #6F4F25 orange,
  with highlights in #959595 light grey or #FFFFFF white; no yellow or peach on skin
- Native resolution exactly 320x200 pixels; render each pixel as an exact 4x4
  block, for a 1280x800 output, on a perfectly regular grid with hard edges
- Aspect ratio 16:10, filling the whole frame
- Flat color areas with hard edges; shading done with a few solid tones or
  simple checkerboard dithering, never smooth gradients
- Each 8x8 pixel block should use only 2 colors; avoid many colors packed close together
- Bold black outlines, readable shapes, strong contrast; no details smaller than 2 pixels
- Simple, mostly solid black background with little detail
- No anti-aliasing, no blur, no glow, no scanlines, no CRT effect, no film grain,
  no noise, no text, no borders, no letterboxing
```

### The animation (Google Flow)

The original Gemini image, not a C64-converted version, was given to Google Flow as the starting frame. The prompt asked for small facial motion only, with everything else held still:

- blinks, a glance, a frown;
- a locked-off camera;
- no body or background movement, no lighting changes;
- a crisp pixel grid and no new colors.

Keeping everything else still is what makes the C64 version small: only the cells around the eyes and brow ever need to change. The result is `Man_blinking_in_pixel_art_618b030b.mp4`, 10 seconds at 1280×720, 24fps.

<details>
<summary>Flow prompt</summary>

```
Animate this exact pixel art image. It is a Commodore 64 style portrait and must
stay pixel-perfect: same pixel grid, same colors, same composition in every frame.

Motion (subtle, face only):
- The man blinks twice, naturally, a few seconds apart
- His eyes glance slowly to the left, hold, then return to looking forward
- A brief, slight tightening of the jaw and brow, then relax
- The final frame matches the first frame so the animation loops seamlessly

Must stay completely still:
- Locked-off static camera: no zoom, no pan, no drift, no shake, no parallax
- Body, spacesuit, helmet ring and background do not move at all
- No breathing motion, no head turn, no hair movement
- Lighting is constant: no flicker, glow, light sweeps or reflections moving

Style:
- Hard-edged square pixels, flat colors, no anti-aliasing, no motion blur,
  no smoothing, no morphing between frames
- No new colors; use only the colors already in the image
- No text, no UI, no particles, no effects, no audio
```



## 2. Converting to C64 hires (`convert_blink.py`)

1. **Frames:** `ffmpeg` samples the video at 10fps, giving 100 frames in `frames/`.
2. **Crop and scale:** each frame is cropped from 16:9 to the C64's 16:10 by trimming 64 pixels from each side. It's then scaled to 320×200 with area averaging.
3. **Per-cell colors:** the method is the same as in `../reu/`. Each 8×8 cell gets the best pair of C64 colors (Pepto palette, compared in CIELAB, a color space where distances match what the eye sees). Pixels within the pair are set with an 8×8 Bayer ordered dither, a fixed dot pattern that keeps unchanged areas identical between frames. The video is already bright, so midtones aren't lifted (`GAMMA = 1.0`).
4. **Hold unchanged cells:** this is new for this animation.

### Holding unchanged cells

The Flow video is very steady: on average, frames differ by only 0.34 brightness levels out of 255. Converted naively, though, about **156 of the 1,000 cells changed every frame**, and 823 cells changed at some point. The cause was video compression noise flipping individual dither dots.

So the converter remembers, for each cell, the source pixels it was last converted from. It reconverts the cell only when the source has moved more than `HOLD = 2.0` away (mean CIELAB distance across the cell). Everything else keeps its previous bitmap and colors exactly.

| | changed cells per frame | data size |
|---|---|---|
| Naive conversion | median 156 | far too big for RAM |
| With hold (`HOLD = 2.0`) | **mean 6, max 91** (during blinks) | **8,174 bytes** of changes |

The blinks, eye movement and brow furrow all survive; the noise doesn't.

### Output

| File | Contents |
|------|----------|
| `data/bitmap.bin` | 8000 bytes: first frame's bitmap |
| `data/screen.bin` | 1000 bytes: first frame's screen RAM (high nibble = color of 1-bits, low nibble = 0-bits) |
| `data/deltas.bin` | the per-frame changes (format below) |
| `preview/frame_NNN.png` | each frame as it looks on the C64, enlarged 3× |

The change stream holds one record per changed cell:

```
bitmap addr hi, bitmap addr lo, screen addr hi, screen addr lo, 8 bitmap bytes, 1 screen byte
```

A `0` byte ends a frame and `$FF` ends the stream. The last frame's changes lead back to frame 1, so the animation loops seamlessly.

## 3. The player (`player.asm`)

When the program starts, it:

1. switches off the BASIC ROM, so data above `$A000` would be readable if the animation grew;
2. detects PAL or NTSC from the number of raster lines the TV beam draws per screen;
3. copies the first frame's colors into screen RAM;
4. turns on hires bitmap mode.

The first frame's bitmap needs no copying, because the program loads it directly at `$2000`.

Then, every 5 screen refreshes on PAL (6 on NTSC), giving 10fps, it waits for raster line 251, just below the picture. From there it works through that frame's records, copying 8 bitmap bytes and 1 color byte to each changed cell's address. When it reaches `$FF` it jumps back to the start of the stream.

A typical frame changes 6 cells and takes about 1,300 CPU cycles to update, a small part of the roughly 20,000 cycles in one screen refresh.

**Memory map**

| Address | Contents |
|---------|----------|
| `$0801` | BASIC `SYS` line, player code, first frame's screen RAM (copied to `$0400` at startup) |
| `$0400–$07E7` | screen RAM (cell colors) |
| `$2000–$3F3F` | hires bitmap, loaded already holding frame 1 |
| `$4000–$5FED` | delta stream (8,174 bytes) |

The delta stream can grow up to `$CFFF`, about 36 KB, before the assembler stops with an error. That leaves room for much longer animations.

### Testing in VICE

| Situation | Result |
|-----------|--------|
| PAL | plays; screenshots 0.3 seconds apart differ, one of them mid-blink with eyes closed |
| NTSC | plays at the correct speed |

## Files

| File | Purpose |
|------|---------|
| `Gemini_Generated_Image_8heex48heex48hee.jpeg` | the Gemini still image (Google Flow's starting frame) |
| `Man_blinking_in_pixel_art_618b030b.mp4` | the Google Flow video, read by `convert_blink.py` |
| `convert_blink.py` | video → C64 frames, hold filter, first frame and change stream |
| `player.asm` | full-screen player (ACME) |
| `build.sh` | runs the converter if needed, assembles `blink.prg`, writes `blink.d64` |
| `run_me.sh` | builds if anything changed, then starts VICE |
| `frames/`, `preview/`, `data/` | extracted frames, C64 previews, data for the player |
| `blink.prg` | the program (22,511 bytes) |
| `blink.d64` | 1541 disk image containing `BLINK` |
| `vice.log` | VICE's log from the last run |

## How to run it

### Requirements

- **[VICE](https://vice-emu.sourceforge.io/)**: provides `x64sc` and `c1541`.
- **[ACME](https://sourceforge.net/projects/acme-crossass/)**: the 6502 assembler (`brew install acme`).
- **Python 3** with **Pillow** and **NumPy**.
- **ffmpeg**: needed for the first conversion, to extract the frames.

### In VICE

```sh
./run_me.sh
```

This rebuilds anything that's out of date, then opens VICE and plays the animation in a loop. No REU is needed. Extra arguments go straight to VICE; for example, `./run_me.sh -ntsc` runs it as an NTSC machine. To start it by hand instead:

```sh
x64sc -autostart blink.prg
```

### On real hardware

Copy `blink.d64` to a 1541 disk, an SD2IEC or an Ultimate, then:

```
LOAD"BLINK",8,1
RUN
```

On a 1541 with standard loading it takes about a minute to load, then plays.

### Changing it

These settings are at the top of `convert_blink.py`; run `./run_me.sh` afterwards to reconvert and rebuild:

- **`HOLD`:** lower keeps more subtle motion but costs more data; higher keeps only big changes like blinks.
- **`DITHER_PENALTY`:** higher gives fewer dithered cells and flatter colors.
- **`GAMMA`:** below 1 lightens the midtones.

To use a different video, change `VIDEO` and delete `frames/` so it gets extracted again.
