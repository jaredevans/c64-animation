#!/usr/bin/env python3
"""Convert the Google Flow video into a full-screen C64 hires animation (40x25 cells, 320x200 px).

Writes:
  frames/frame_NNN.png   frames extracted from the video at FPS
  preview/frame_NNN.png  each frame as it looks on the C64 (3x)
  data/bitmap.bin        8000 bytes: first frame's bitmap ($2000 layout)
  data/screen.bin        1000 bytes: first frame's screen RAM (high nibble = 1-bit color)
  data/deltas.bin        per-frame changes, ending with a change back to frame 1 so it loops

Delta stream, one record per changed cell:
  bitmap addr hi, bitmap addr lo, screen addr hi, screen addr lo, 8 bitmap bytes, 1 screen byte
A 0 byte ends a frame; a $FF byte ends the stream (the player restarts from the top).

The video is nearly static, but compression noise would still flip dither dots in hundreds of
cells per frame. A cell is only reconverted when its source pixels have moved more than HOLD
(mean CIELAB distance) away from what it was last converted from, so only real motion - blinks,
eyes, mouth - ends up in the delta stream.
"""
import glob
import os
import subprocess
import sys

import numpy as np
from PIL import Image

VIDEO = "Man_blinking_in_pixel_art_618b030b.mp4"
FPS = 10
COLS, ROWS = 40, 25
W, H = COLS * 8, ROWS * 8
BITMAP, SCREEN = 0x2000, 0x0400
DITHER_PENALTY = 1.0               # higher = fewer dithered cells, flatter colors
GAMMA = 1.0                        # <1 lifts midtones
STICKY = 1.04                      # keep last frame's cell colors if within 4% of the best error
HOLD = 2.0                         # reconvert a cell only if its source changed more than this

# Pepto PAL palette
PALETTE = np.array([
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
    (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
    (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
    (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95),
], dtype=np.uint8)

BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21],
], dtype=np.float64)
THRESH = ((BAYER8 + 0.5) / 64.0).reshape(64)


def srgb_to_lab(rgb):
    c = rgb.astype(np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


PAL_LAB = srgb_to_lab(PALETTE)
PAIRS = np.array([(i, j) for i in range(16) for j in range(i, 16)])   # 136 pairs incl. solid colors
PA, PB = PAL_LAB[PAIRS[:, 0]], PAL_LAB[PAIRS[:, 1]]


def crop_16_10(size):
    """Largest centered 16:10 box."""
    w, h = size
    if w * 10 > h * 16:
        cw = round(h * 1.6)
        return ((w - cw) // 2, 0, (w - cw) // 2 + cw, h)
    ch = round(w / 1.6)
    return (0, (h - ch) // 2, w, (h - ch) // 2 + ch)


def load_frame(path):
    img = Image.open(path).convert("RGB")
    img = img.crop(crop_16_10(img.size)).resize((W, H), Image.BOX)
    rgb = 255.0 * (np.asarray(img) / 255.0) ** GAMMA
    lab = srgb_to_lab(rgb)
    # (ROWS*COLS, 64, 3): one row of 64 pixels per cell
    return lab.reshape(ROWS, 8, COLS, 8, 3).transpose(0, 2, 1, 3, 4).reshape(ROWS * COLS, 64, 3)


def score_pairs(cells):
    """Return (error per cell per pair, 1-bit masks per cell per pair)."""
    d = PB - PA                                                     # (P,3)
    dd = np.maximum((d * d).sum(-1), 1e-9)                          # (P,)
    rel = cells[:, None, :, :] - PA[None, :, None, :]               # (N,P,64,3)
    t = np.clip((rel * d[None, :, None, :]).sum(-1) / dd[None, :, None], 0, 1)   # (N,P,64)
    proj = PA[None, :, None, :] + t[..., None] * d[None, :, None, :]
    seg_err = ((cells[:, None] - proj) ** 2).sum(-1)                # color not reachable by this pair
    ones = t > THRESH[None, None, :]
    chosen = np.where(ones[..., None], PB[None, :, None, :], PA[None, :, None, :])
    noise = ((cells[:, None] - chosen) ** 2).sum(-1)                # dithering noise
    return (seg_err + DITHER_PENALTY * noise).sum(-1), ones


def convert(cells, prev_choice):
    err, ones = score_pairs(cells)
    choice = err.argmin(1)
    if prev_choice is not None:
        n = np.arange(len(cells))
        keep = err[n, prev_choice] <= err[n, choice] * STICKY
        choice = np.where(keep, prev_choice, choice)
    masks = ones[np.arange(len(cells)), choice]                     # (N,64) bool
    return choice, masks


def encode(choice, masks):
    a, b = PAIRS[choice, 0], PAIRS[choice, 1]
    # 0-bits -> color a (low nibble), 1-bits -> color b (high nibble)
    bitmap = np.packbits(masks.reshape(-1, 8, 8), axis=2).reshape(-1, 8).astype(np.uint8)
    screen = ((b << 4) | a).astype(np.uint8)
    return bitmap, screen


def render(choice, masks):
    a, b = PAIRS[choice, 0], PAIRS[choice, 1]
    idx = np.where(masks, b[:, None], a[:, None])                   # (N,64)
    idx = idx.reshape(ROWS, COLS, 8, 8).transpose(0, 2, 1, 3).reshape(H, W)
    return Image.fromarray(PALETTE[idx]).resize((W * 3, H * 3), Image.NEAREST)


def delta(old, new):
    """Records for every cell that differs between two (bitmap, screen) states, then a 0."""
    out = bytearray()
    changed = np.flatnonzero((old[0] != new[0]).any(1) | (old[1] != new[1]))
    for i in changed:
        bm, sc = BITMAP + i * 8, SCREEN + i
        out += bytes([bm >> 8, bm & 0xFF, sc >> 8, sc & 0xFF]) + new[0][i].tobytes() + bytes([new[1][i]])
    return out + b"\x00", len(changed)


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs("frames", exist_ok=True)
    if not os.path.exists("frames/frame_001.png"):
        subprocess.run(["ffmpeg", "-v", "error", "-i", VIDEO, "-vf", f"fps={FPS}", "frames/frame_%03d.png"], check=True)
    files = sorted(glob.glob("frames/frame_*.png"))
    if not files:
        sys.exit("no frames extracted")
    os.makedirs("preview", exist_ok=True)
    os.makedirs("data", exist_ok=True)

    states = []
    ref = choice = masks = None
    for k, path in enumerate(files, 1):
        cells = load_frame(path)
        new_choice, new_masks = convert(cells, choice)
        if ref is None:
            ref, choice, masks = cells.copy(), new_choice, new_masks
        else:
            moved = np.sqrt(((cells - ref) ** 2).sum(-1)).mean(1) > HOLD
            choice = np.where(moved, new_choice, choice)
            masks = np.where(moved[:, None], new_masks, masks)
            ref[moved] = cells[moved]
        states.append(encode(choice, masks))
        render(choice, masks).save(f"preview/frame_{k:03d}.png")
        print(f"\r{k}/{len(files)}", end="", flush=True)
    print()

    states[0][0].tofile("data/bitmap.bin")
    states[0][1].tofile("data/screen.bin")
    stream = bytearray()
    counts = []
    for old, new in zip(states, states[1:] + states[:1]):           # last frame leads back to the first
        d, n = delta(old, new)
        stream += d
        counts.append(n)
    stream += b"\xff"
    open("data/deltas.bin", "wb").write(stream)
    print(f"{len(files)} frames, changed cells per frame: mean {np.mean(counts):.1f}, max {max(counts)}; "
          f"deltas {len(stream)} bytes")


if __name__ == "__main__":
    main()
