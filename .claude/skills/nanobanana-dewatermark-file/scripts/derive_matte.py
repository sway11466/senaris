# /// script
# requires-python = ">=3.9"
# dependencies = ["pillow>=10", "numpy>=1.24", "opencv-python>=4.8"]
# ///
"""MAINTAINER TOOL — regenerate assets/nb_matte.npy (the bundled sparkle matte).

Pick a nano-banana image whose watermark sits over a FLAT, fairly DARK background
(so the background can be modelled as a plane and the alpha estimated cleanly), read
the sparkle's center pixel, and run:

    uv run derive_matte.py <clean_flat_image> <cx> <cy>

It writes ../assets/nb_matte.npy. The default matte was derived from a wooden-floor
sample with the sparkle centered at (1075, 777) in a 1200x896 image.
"""
import os, sys
import numpy as np, cv2
from PIL import Image

W = 180; c0 = W // 2
YY, XX = np.mgrid[0:W, 0:W].astype(np.float64)
DST = os.path.join(os.path.dirname(__file__), "..", "assets", "nb_matte.npy")


def plane_bg(arr, r_in=60, r_out=88):
    r = np.hypot(XX - c0, YY - c0); m = (r > r_in) & (r < r_out)
    A = np.column_stack([XX[m], YY[m], np.ones(m.sum())]); bg = np.zeros_like(arr)
    for c in range(arr.shape[2]):
        coef, *_ = np.linalg.lstsq(A, arr[..., c][m], rcond=None)
        bg[..., c] = coef[0] * XX + coef[1] * YY + coef[2]
    return bg


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: derive_matte.py <clean_flat_image> <cx> <cy>")
    path, cx, cy = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    im = Image.open(path).convert("RGB")
    arr = np.asarray(im.crop((cx - c0, cy - c0, cx - c0 + W, cy - c0 + W)), np.float64) / 255.0
    bg = plane_bg(arr)
    a = np.clip((arr - bg) / np.maximum(1 - bg, 1e-6), 0, 1).mean(2)   # white overlay, sRGB
    # confine to star + soft edge; drop far-field background-estimation haze
    core = (a > 0.08).astype(np.float32)
    core = cv2.morphologyEx(core, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    sup = cv2.GaussianBlur(cv2.dilate(core, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))), (0, 0), 2.5)
    r = np.hypot(XX - c0, YY - c0); tp = np.clip((60 - r) / 14, 0, 1); tp = tp * tp * (3 - 2 * tp)
    matte = (a * sup * tp).astype(np.float32)
    np.save(DST, matte)
    print("saved %s  shape=%s peak=%.3f support=%d" % (DST, matte.shape, matte.max(), int((matte > 0.01).sum())))


if __name__ == "__main__":
    main()
