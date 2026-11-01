# C64 Animations

This project contains two pixel-art portrait animations that play at 10fps in Commodore 64 hires bitmap mode. They demonstrate two approaches, and which one fits depends on **how much of the picture moves**:

> **[`/reu`](reu/README.md)**: full-frame animation for high-motion video. Needs a C64 with a REU (512 KB+).
>
> **[`/blink`](blink/README.md)**: change-only animation for limited-motion video. Runs on a standard C64.

| Folder | Approach | Use it when | Source used here | Runs on |
|--------|----------|-------------|------------------|---------|
| `reu/` | full-frame | most of the picture changes every frame: camera moves, moving backgrounds, live-action-style footage | `c64.mp4`, made with deliberately heavy motion as a stress test | expanded C64 with a **REU of 512 KB or more** |
| `blink/` | change-only | only small parts move: faces, blinking lights, a character on a still background | a still image designed for the C64 in Gemini, animated in Google Flow with motion kept to a minimum | **standard C64**, nothing extra |

The REU is a standard Commodore expansion (the 1750), and it's built into modern devices such as the Ultimate 64 and Ultimate 1541 II.

Each folder has its own README with the full details. This page explains how the two differ and why.

## See them running

Screen recordings of both animations running in the VICE emulator:

- **[`reu.mp4`](reu.mp4)** (24 s): the end of the REU loading screen, one dot per frame, then the full-frame stress-test animation playing in its 15-column strip.
- **[`blink.mp4`](blink.mp4)** (20 s): the full-screen blinking spaceman, playing straight away on a standard C64 with no REU.

## At a glance

| | `reu/` | `blink/` |
|---|---|---|
| Source video | 720×1280 portrait, 24fps | 1280×720 landscape, 24fps |
| Picture on the C64 | 120×200 strip (15×25 cells) in the middle of the screen | full screen, 320×200 (40×25 cells) |
| Frames | 100 (10 s at 10fps) | 100 (10 s at 10fps) |
| Motion in the source | small movement everywhere | face only, everything else still |
| What's stored | every frame in full, 3,375 bytes each | first frame + only the cells that change |
| Cells changing per frame | ~260 of 375 (69%) | ~6 of 1,000 (0.6%) |
| Animation data | 337,500 bytes | 9,000 + 8,174 bytes |
| Delivered as | `c64anim.d81`: player plus 100 frame files | `blink.prg`: one 22.5 KB program (also `blink.d64`) |
| Hardware needed | REU of 512 KB or more | none |
| Loading in VICE (`run_me.sh`) | about 40 seconds (fast virtual drive) | instant |
| Loading on real hardware (standard loading) | over 10 minutes from a real 1581 | about 1 minute from a 1541 |
| How a frame is drawn | REU DMA copies the whole strip: 50 transfers, one per row of pixels or colors | the CPU copies only the changed cells, 9 bytes each |
| Converter settings | `GAMMA 0.85` (dark source lightened), no hold | `GAMMA 1.0`, hold filter `HOLD 2.0` |

## Why two approaches?

The difference comes from **how much motion each source video has**, and that was chosen on purpose at the two extremes.

**`reu/` is the stress test.** `c64.mp4` was made with a lot of motion on purpose, to push the C64 to its limit and see how it would cope. The head moves, the expression changes, the background shifts and lights flicker.  With that much changing, storing only the changes saves almost nothing: every frame has to be stored whole. 100 frames come to 337 KB, which is five times the C64's 64 KB of RAM and twice what a 1541 disk holds. So everything is loaded into a REU first, and the REU's hardware copier (DMA) moves frames into view fast enough for 10fps.

It works: the C64 does play that much motion at 10fps. The cost is expansion hardware, a long load on real drives, and a picture limited to a 15-column strip.

**`blink/` is the opposite: motion kept to a minimum on purpose, and art designed for the C64:**

- The still image was generated in **C64 palette colors**, at the C64's 16:10 shape, with flat shading and bold outlines. 
- Google Flow was told to keep the **camera, body, background and lighting completely still**, and move only the eyes and brow.

## Shared techniques

Both converters use the same core method:

- **C64 hires rules:** each 8×8 cell gets the 2 colors (out of the C64's 16, Pepto palette) that represent it best. Colors are compared in CIELAB, a color space where distances match how different colors look to the eye.
- **Ordered dithering:** an 8×8 Bayer pattern, a fixed dot arrangement. Unlike error-diffusion dithering, it keeps unchanged areas pixel-identical from frame to frame, so they don't shimmer.
- **Sticky colors:** a cell keeps its previous frame's color pair unless a new pair is clearly better, which reduces flicker.
- **Smooth playback:** the screen is updated just after the picture is drawn, with PAL/NTSC detection so it runs at 10fps on both.

## Lessons for next animations

Start by deciding how much motion you want. For heavy motion, plan on the `reu/` approach and a REU. For an animation that runs on any standard C64, follow what made `blink/` work:

1. **Generate the art for the C64.** Use only the 16 C64 colors, muted tones, a 16:10 frame, flat shading and bold outlines, and avoid skin tones lighter than the C64's light red.
2. **Keep everything still except what has to move:** a locked camera, a static background, constant lighting, no breathing.
3. **Give the video tool the original image,** not a C64-converted one; the converter adds the C64 dithering afterwards.
4. **Check before animating:** convert the still image and view it in VICE first.

## Running them

```sh
reu/run_me.sh      # starts VICE with a 512 KB REU and fast disk loading
blink/run_me.sh    # starts VICE; no REU needed
```

