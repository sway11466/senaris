---
name: nanobanana-dewatermark-file
description: Remove the visible white "sparkle" watermark that Google's nano-banana (Gemini image generation) stamps into the bottom-right of a SINGLE image file. Use when the user wants to erase / clean / remove the nano-banana (nanobanana / Gemini) watermark — 透かし・ウォーターマーク — from one image. Inverts the translucent overlay (no inpainting); does NOT touch the invisible SynthID.
---

# nano-banana de-watermark (single file)

Removes the visible bottom-right sparkle watermark from one nano-banana / Gemini–generated
image by **un-compositing** the semi-transparent white overlay, not by guessing from
neighbours. The original pixels survive underneath the translucent mark, so they are
recovered exactly. The invisible **SynthID watermark is intentionally left intact.**

## Usage

`uv` must be on PATH. The script declares its own dependencies (PEP 723), so uv builds an
ephemeral environment on first run — nothing else to install.

Run from the project root (path is repo-relative, so it works on any machine / terminal):

```
uv run --no-project ".claude/skills/nanobanana-dewatermark-file/scripts/dewatermark.py" <input> [output]
```

- `<input>` — path to the image to clean.
- `[output]` — path for the cleaned image. Optional at the CLI level; if omitted the
  script writes `<input_stem>_clean.png` beside the input.

### Output path — ASK when the user didn't give one

When this skill runs **through Claude** (not a raw terminal call), do not silently use the
default output name. Behaviour:

- If the user specified a destination, pass it as the 2nd argument and proceed.
- If the user did NOT specify where to save the result, **ask them first** — confirm the
  destination before running. Offer sensible options they can pick from:
  `<input_stem>_clean.png` beside the input (the default), a path they type, or overwriting
  the original. Only run after the destination is settled.

(Direct terminal use keeps the convenience default when the 2nd argument is omitted.)

The script prints where it placed the mark and the match score, e.g.
`[detected @ 1080,776 score=0.94] in.png -> in_clean.png`.
A low score falls back to a relative anchor position automatically.

## Scope & limits

- Tuned to nano-banana output at **1200×896** (fixes the sparkle's pixel size). The mark
  sits at a near-fixed spot; detection searches a small box around a resolution-relative
  anchor with a proximity prior, so busy/low-contrast backgrounds still localize. A
  *scaled* mark at a very different resolution may leave more residue (multi-scale not
  yet added).
- Flat / dark backgrounds under the mark come out cleanest. Bright, low-contrast
  backgrounds leave a slightly larger (still faint) trace, because less original signal
  survives there.
- Removes only the **visible** mark. SynthID remains — this is deliberate.
- One file at a time. A batch/folder counterpart (`nanobanana-dewatermark-folder`) is
  planned separately.

## How it works (maintainers)

sRGB compositing: `obs = (1-a)·bg + a·white`. Invert it: `bg = (obs - a·white)/(1-a)`.
The sparkle alpha matte is bundled at `assets/nb_matte.npy` (derived once from a clean flat
sample). Per image it is located by shape matching (`cv2.matchTemplate`) inside a box around
a resolution-relative anchor, weighted by a Gaussian proximity prior, at 0.25 px precision.

The mark's opacity is ~constant across nano-banana output, so the removal uses a single
overall alpha-scale. IMPORTANT: that scale is chosen to make the de-marked region *smoothest*
(a background-independent objective), NOT by least-squares against an estimated background.
The earlier plane-background least-squares scale was biased by gradients/texture under the
mark and left a faint whole-star ghost; the smoothness objective lands near 1.0 and removes
it. No blur, no inpainting. To regenerate the matte, run `scripts/derive_matte.py` on a clean
flat-background sample (see that file's header).
