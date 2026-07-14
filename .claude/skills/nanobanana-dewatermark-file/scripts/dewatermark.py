# /// script
# requires-python = ">=3.9"
# dependencies = ["pillow>=10", "numpy>=1.24", "opencv-python>=4.8"]
# ///
"""Remove the visible white "sparkle" watermark that Google's nano-banana
(Gemini image generation) stamps into the bottom-right area of an image.

Method (no neighbour-guessing / inpainting): the mark is a semi-transparent
white overlay  obs = (1-a)*bg + a*255  composited in sRGB space. The original
pixels survive underneath, so we invert the blend  bg = (obs - a*255)/(1-a)
using a bundled alpha matte of the sparkle, located per-image by shape matching
and fitted at sub-pixel precision. SynthID (the invisible watermark) is NOT
touched.

Usage:
    uv run dewatermark.py <input> [output]
Default output: "<input_stem>_clean.png" next to the input.
"""
import sys, os, argparse
import numpy as np
import cv2
from PIL import Image

W = 180
c0 = W // 2
YY, XX = np.mgrid[0:W, 0:W].astype(np.float64)

MATTE_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "nb_matte.npy")


def load_matte():
    m = np.load(MATTE_PATH).astype(np.float64)
    ys, xs = np.where(m > 0.08)
    tmpl = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1].astype(np.float32)
    return m, tmpl


def shift(img, dx, dy):
    M = np.float32([[1, 0, dx], [0, 1, dy]])
    return cv2.warpAffine(img.astype(np.float32), M, (img.shape[1], img.shape[0]),
                          flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def plane_bg(arr, r_in=60, r_out=88):
    """least-squares plane background per channel from an annulus around center."""
    r = np.hypot(XX - c0, YY - c0)
    m = (r > r_in) & (r < r_out)
    A = np.column_stack([XX[m], YY[m], np.ones(m.sum())])
    bg = np.zeros_like(arr)
    for c in range(arr.shape[2]):
        coef, *_ = np.linalg.lstsq(A, arr[..., c][m], rcond=None)
        bg[..., c] = coef[0] * XX + coef[1] * YY + coef[2]
    return bg


# The mark sits at a near-fixed spot; expressed as a fraction of image size so
# it tracks other resolutions. Observed on 1200x896 nano-banana output.
ANCHOR_REL = (1075 / 1200.0, 777 / 896.0)
SEARCH_R = 60          # only look this far from the anchor -> ignores far-away
                       # look-alikes (flag poles, table edges) that outscore a faint mark


def detect(im, tmpl):
    """find the sparkle center by shape matching in a small box around the anchor.
    returns (cx, cy, score). Restricting the search to the anchor neighbourhood is
    what makes busy / low-contrast backgrounds localize correctly."""
    Wd, Hd = im.size
    ax, ay = int(round(Wd * ANCHOR_REL[0])), int(round(Hd * ANCHOR_REL[1]))
    th, tw = tmpl.shape
    hw, hh = tw // 2 + SEARCH_R, th // 2 + SEARCH_R
    zx, zy = max(0, ax - hw), max(0, ay - hh)
    zx1, zy1 = min(Wd, ax + hw), min(Hd, ay + hh)
    zone = np.asarray(im.crop((zx, zy, zx1, zy1)).convert("L"), np.float32)
    if zone.shape[0] < th or zone.shape[1] < tw:
        return ax, ay, 0.0                       # image too small -> use anchor
    resid = np.clip(zone - cv2.GaussianBlur(zone, (0, 0), 18), 0, None).astype(np.float32)
    res = cv2.matchTemplate(resid, tmpl, cv2.TM_CCOEFF_NORMED)
    # anchor prior: prefer matches near the expected spot so a faint mark isn't
    # beaten by a brighter look-alike (tile highlight, edge) a few dozen px away.
    ry, rx = np.mgrid[0:res.shape[0], 0:res.shape[1]]
    xa, ya = ax - tw // 2 - zx, ay - th // 2 - zy
    prior = np.exp(-((rx - xa) ** 2 + (ry - ya) ** 2) / (2.0 * 22.0 ** 2))
    loc = np.unravel_index(int((res * prior).argmax()), res.shape)
    score = float(res[loc])
    return zx + loc[1] + tw // 2, zy + loc[0] + th // 2, score


def remove_at(padded, cx, cy, matte):
    """un-composite the sparkle in a window centered on (cx,cy) of the padded image."""
    # window in padded coords (sparkle stays at c0 thanks to reflect-padding)
    arr = padded[cy:cy + W, cx:cx + W].astype(np.float64) / 255.0
    bg = plane_bg(arr)
    E = arr - bg
    dW = 1.0 - bg

    def resid_for(mt):
        M = mt[..., None] * dW
        sup = mt > 0.02
        s = (E[sup] * M[sup]).sum() / max((M[sup] * M[sup]).sum(), 1e-9)
        return ((E[sup] - s * M[sup]) ** 2).sum(), s

    best = None
    for dy in range(-7, 8):
        for dx in range(-7, 8):
            rr, s = resid_for(shift(matte, dx, dy))
            if best is None or rr < best[0]:
                best = (rr, dx, dy, s)
    _, bx, by, _ = best
    for ddx in np.arange(-0.75, 0.76, 0.25):
        for ddy in np.arange(-0.75, 0.76, 0.25):
            rr, s = resid_for(shift(matte, bx + ddx, by + ddy))
            if rr < best[0]:
                best = (rr, bx + ddx, by + ddy, s)
    _, dx, dy, _ = best
    al = shift(matte, dx, dy)

    # --- choose the opacity that best CANCELS the star, not the one the plane
    # background implies. The plane-bg least-squares scale is biased by texture /
    # gradients under the mark, which left a faint whole-star ghost. Instead pick the
    # scale that makes the de-marked region smoothest (background-independent). The
    # true opacity is ~constant across nano-banana output, so this lands near 1.0. ---
    r = np.hypot(XX - c0, YY - c0)
    sup = (al > 0.05) | (r < 46)

    def roughness(s):
        a = np.clip(s * al, 0, 0.97)[..., None]
        rec = np.clip((arr - a) / (1 - a), 0, 1)
        gx = np.abs(np.diff(rec, axis=1))[:-1, :]
        gy = np.abs(np.diff(rec, axis=0))[:, :-1]
        return (gx + gy)[sup[:-1, :-1]].sum()

    s = min(np.arange(0.80, 1.201, 0.02), key=roughness)
    a = np.clip(s * al, 0, 0.97)[..., None]
    rec = np.clip((arr - a) / (1 - a), 0, 1)
    out = padded.copy()
    out[cy:cy + W, cx:cx + W] = (rec * 255.0 + 0.5).astype(np.uint8)
    return out


def dewatermark(path, out_path=None, min_score=0.45):
    im = Image.open(path).convert("RGB")
    matte, tmpl = load_matte()
    Wd, Hd = im.size

    # detection is confined to the anchor neighbourhood, so the location is always
    # sane; a low score just means a faint / low-contrast mark, not a wrong spot.
    cx, cy, score = detect(im, tmpl)
    note = "" if score >= min_score else " (low-confidence: faint mark near anchor)"

    # reflect-pad so the window is always full & centered on the sparkle
    src = np.asarray(im)
    padded = np.pad(src, ((c0, c0), (c0, c0), (0, 0)), mode="reflect")
    out = remove_at(padded, cx, cy, matte)              # cx,cy are padded coords (== orig + c0 offset cancels)
    out = out[c0:c0 + Hd, c0:c0 + Wd]

    if out_path is None:
        stem, _ = os.path.splitext(path)
        out_path = stem + "_clean.png"
    Image.fromarray(out).save(out_path)
    print("[@ %d,%d  score=%.2f%s]  %s -> %s" % (cx, cy, score, note, path, out_path))
    return out_path


def main():
    ap = argparse.ArgumentParser(description="Remove nano-banana visible watermark from one image.")
    ap.add_argument("input")
    ap.add_argument("output", nargs="?", default=None)
    args = ap.parse_args()
    if not os.path.isfile(args.input):
        sys.exit("input not found: " + args.input)
    dewatermark(args.input, args.output)


if __name__ == "__main__":
    main()
