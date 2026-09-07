"""向きの無い足場（ガレ場など）の側面の帯を、上面の元絵2枚から作る。

側面の帯は幅が 4 TILE（ヘックス幅2つ）に貼られ、上面は元絵 1024px が 1 ヘックス幅に敷かれる。
石の大きさを上面と揃えるには帯の幅を元絵2枚ぶん（約 2048px）にする必要がある。
2枚を 64px ずつ重ねて羽根合成し（継ぎ目の石を切らない）、左右の端も同じ幅で重ねて
横シームレスにする。高さは元絵の 1024 をそのまま使う＝帯の高さは世界で 4*1024/幅 ≒ 2.1 で、
盤の縁の落差 0.81 より高いので、縦の繰り返しは起きない（帯は上端から貼られる）。

使い方: uv run --no-project --with pillow --with numpy python godot/tools/gen_side_band.py A.jpg B.jpg out.png
"""
import sys
import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.float32)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.float32)
h, w = a.shape[:2]
ov = 64
W = 2 * w - 2 * ov
out = np.zeros((h, W, 3), np.float32)
ramp = np.linspace(0.0, 1.0, ov, dtype=np.float32)[None, :, None]

# A を左に、B を右に。A の右端 ov と B の左端 ov を羽根合成。
out[:, : w - ov] = a[:, : w - ov]
out[:, w - ov : w] = a[:, w - ov :] * (1 - ramp) + b[:, :ov] * ramp
out[:, w : W] = b[:, ov : w - ov]
# B の右端 ov を、帯の左端 ov（A の左端）に重ねて横シームレスにする。
out[:, :ov] = b[:, w - ov :] * (1 - ramp) + out[:, :ov] * ramp

Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(sys.argv[3])
print("saved", sys.argv[3], out.shape[1], "x", out.shape[0])
