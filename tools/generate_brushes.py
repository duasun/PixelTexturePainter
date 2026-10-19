"""Create the bundled white 32px brush masks without external packages."""
from pathlib import Path
import math
import struct
import zlib

OUT = Path(__file__).resolve().parent.parent / "assets" / "brushes"
OUT.mkdir(parents=True, exist_ok=True)
N = 32
NAMES = [
    "01_round", "02_square", "03_diamond", "04_cross", "05_ring",
    "06_star", "07_soft_round", "08_soft_square", "09_splatter",
    "10_speckle", "11_hatch", "12_diagonal", "13_checker",
    "14_brick", "15_stipple", "16_grunge", "17_leaf", "18_slash",
    "19_triangles", "20_cloud",
]


def noise(x, y, salt=0):
    value = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
    value = (value ^ (value >> 13)) * 1274126177
    return (value & 65535) / 65535.0


def coverage(kind, x, y):
    u, v = (x + .5 - N / 2) / (N / 2), (y + .5 - N / 2) / (N / 2)
    r = math.hypot(u, v)
    a = math.atan2(v, u)
    if kind == 0: return 255 if r < .95 else 0
    if kind == 1: return 255 if max(abs(u), abs(v)) < .92 else 0
    if kind == 2: return 255 if abs(u) + abs(v) < 1.18 else 0
    if kind == 3: return 255 if (abs(u) < .22 or abs(v) < .22) and r < 1.1 else 0
    if kind == 4: return 255 if .58 < r < .88 else 0
    if kind == 5: return 255 if r < (.52 + .35 * math.cos(5 * a)) else 0
    if kind == 6: return int(255 * max(0, min(1, (1-r) * 1.6)))
    if kind == 7: return int(255 * max(0, min(1, (1-max(abs(u),abs(v))) * 1.5)))
    if kind == 8: return 255 if r < .95 and noise(x//2,y//2,8) > .34 else 0
    if kind == 9: return 255 if r < .95 and noise(x,y,9) > .75 else 0
    if kind == 10: return 255 if r < .96 and (x + y) % 7 < 2 else 0
    if kind == 11: return 255 if r < .96 and abs((x-y) % 12-6) < 3 else 0
    if kind == 12: return 255 if r < .96 and ((x//5+y//5) % 2 == 0) else 0
    if kind == 13: return 255 if r < .95 and (y % 8 < 2 or (x + (4 if y//8 % 2 else 0)) % 12 < 2) else 0
    if kind == 14: return 255 if r < .95 and (x % 6 == 2 and y % 6 == 2) else 0
    if kind == 15: return 255 if r < .9 and noise(x,y,15) > .25 and noise(x//4,y//4,16) > .3 else 0
    if kind == 16: return 255 if ((u + .18*v)**2 / .22 + (v - .15*u)**2 / 1.0) < 1 else 0
    if kind == 17: return 255 if abs(v-u*.8) < .22 and r < 1 else 0
    if kind == 18: return 255 if r < .95 and ((x//8 + y//8) % 3 == 0) and (x%8+y%8 < 9) else 0
    centers = [(-.42,-.1),(.35,-.35),(.25,.38),(-.3,.5)]
    return max(int(255*max(0, 1-math.hypot(u-cx,v-cy)/.55)) for cx,cy in centers)


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)


for kind, name in enumerate(NAMES):
    raw = bytearray()
    for y in range(N):
        raw.append(0)
        for x in range(N):
            raw.extend((255, 255, 255, coverage(kind, x, y)))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    (OUT / f"{name}.png").write_bytes(png)
