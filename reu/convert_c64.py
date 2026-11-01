#!/usr/bin/env python3
"""Convert frames/frame_NNN.png into C64 hires bitmap data (15x25 cells, 120x200 px).

Per frame, writes to c64/:
  bitmap_NNN.bin  3000 bytes: 375 cells row-major (15 per row), 8 bytes per cell, MSB = leftmost pixel
  screen_NNN.bin   375 bytes: one per cell, high nibble = color of 1-bits, low nibble = color of 0-bits
  preview_NNN.png  the converted frame rendered with the C64 palette (3x, for viewing)

Each 8x8 cell gets the pair of C64 colors that best represents it, with ordered (Bayer)
dithering between the pair. Ordered dithering is used instead of error diffusion so that
unchanged areas stay pixel-identical from frame to frame (no shimmer in the animation).
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

SRC_DIR = "frames"
OUT_DIR = "c64"
CROP = (0, 80, 720, 1280)          # drop the black bar at the top; 720x1200 -> /6 -> 120x200
COLS, ROWS = 15, 25
W, H = COLS * 8, ROWS * 8
DITHER_PENALTY = 1.0               # higher = fewer dithered cells, flatter colors
GAMMA = 0.85                       # <1 lifts midtones; the source is dark for the C64 palette
STICKY = 1.04                      # keep last frame's cell colors if within 4% of the best error

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


def load_frame(path):
    img = Image.open(path).convert("RGB").crop(CROP).resize((W, H), Image.BOX)
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
    bits = masks.reshape(-1, 8, 8)
    bitmap = np.packbits(bits, axis=2).reshape(-1).astype(np.uint8)
    screen = ((b << 4) | a).astype(np.uint8)
    return bitmap, screen


def render(choice, masks):
    a, b = PAIRS[choice, 0], PAIRS[choice, 1]
    idx = np.where(masks, b[:, None], a[:, None])                   # (N,64)
    idx = idx.reshape(ROWS, COLS, 8, 8).transpose(0, 2, 1, 3).reshape(H, W)
    return Image.fromarray(PALETTE[idx]).resize((W * 3, H * 3), Image.NEAREST)


def main():
    files = sorted(glob.glob(os.path.join(SRC_DIR, "frame_*.png")))
    if not files:
        sys.exit(f"no frames in {SRC_DIR}/")
    os.makedirs(OUT_DIR, exist_ok=True)
    prev = None
    for k, path in enumerate(files, 1):
        choice, masks = convert(load_frame(path), prev)
        prev = choice
        bitmap, screen = encode(choice, masks)
        bitmap.tofile(os.path.join(OUT_DIR, f"bitmap_{k:03d}.bin"))
        screen.tofile(os.path.join(OUT_DIR, f"screen_{k:03d}.bin"))
        render(choice, masks).save(os.path.join(OUT_DIR, f"preview_{k:03d}.png"))
        print(f"\r{k}/{len(files)}", end="", flush=True)
    print()


if __name__ == "__main__":
    main()
