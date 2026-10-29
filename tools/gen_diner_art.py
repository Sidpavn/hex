#!/usr/bin/env python3
"""Draws every diner sprite into assets/diner/*.png and writes manifest.txt.

    python3 tools/gen_diner_art.py            # write the sprites
    python3 tools/gen_diner_art.py --sheet X  # also write a contact sheet PNG

The art is code on purpose: change a colour or a size here and every sprite
that uses it follows. Run it again after editing, then restart the app (hot
reload does not reload assets).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from iso import *  # noqa: E402,F401

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'diner')

SPRITES = {}  # name -> Img


def add(name, img, outline=None):
    if outline:
        img.outline(outline)
    SPRITES[name] = img


def cell_img(height, extra_w=0, depth=16):
    """A canvas whose origin (0, 0) is a cell's top vertex."""
    return Img(32 + extra_w, height + depth + 4, 16, height)


# ------------------------------------------------------------------ palette
CREAM = ramp('#f7e8c9')
PEACH = ramp('#ecc194')
WOOD = ramp('#c58a56')
WOOD_D = ramp('#8e5a37')
MINT = ramp('#9ad9c8')
STEEL = ramp('#b4bccb')
STEEL_D = ramp('#6d7790')
RED = ramp('#e2493f')
PINK = ramp('#f48fab')
BLUE = ramp('#5b9fe0')
GREEN = ramp('#5cb85a')
GREEN_D = ramp('#2f7d49')
MARBLE = ramp('#f6efe0')
GOLD = ramp('#f2c338')
GRASS = ramp('#74c456')
SAND = ramp('#e6cfa2')
CLAY = ramp('#dd7b46')
INK = hexc('#2a2036')


# ------------------------------------------------------------------ tiles
DIAMOND = [P(0, 0), P(16, 0), P(16, 16), P(0, 16)]


def floor_tile(name, r, seed):
    img = cell_img(0)
    n = noise(seed)

    def f(x, y):
        u = (y + x / 2.0)
        v = (y - x / 2.0)
        c = r.top
        # soft sheen toward the top corner, tiny speckles
        c = mix(c, r.hi, max(0, 0.30 - (u + v) / 60.0) * 0.5)
        if n() < 0.05:
            c = mix(c, r.left, 0.45)
        return c
    fill(img, DIAMOND_SCREEN, f)
    # darker rim on the two lower edges so tiles read as separate
    line(img, P(0, 16), P(16, 16), r.right)
    line(img, P(16, 16), P(16, 0), r.right)
    line(img, P(0, 0), P(16, 0), r.hi)
    line(img, P(0, 0), P(0, 16), r.hi)
    add(name, img)


DIAMOND_SCREEN = [(0, 0), (16, 8), (0, 16), (-16, 8)]


def grass_tile(name, seed, flowers=False):
    img = cell_img(0)
    n = noise(seed)
    fill(img, DIAMOND_SCREEN, lambda x, y: GRASS.top if n() > 0.18 else GRASS.left)
    # blades: little 2-pixel strokes
    for _ in range(14):
        x = int((n() - 0.5) * 24)
        y = int(n() * 12) + 2
        if inside(DIAMOND_SCREEN, x, y) and inside(DIAMOND_SCREEN, x, y - 1):
            img.put(x, y, GREEN_D.top)
            img.put(x, y - 1, GRASS.hi)
    if flowers:
        for col in ((255, 250, 235), (250, 140, 170)):
            x = int((n() - 0.5) * 18)
            y = int(n() * 8) + 4
            if inside(DIAMOND_SCREEN, x, y):
                img.put(x, y, col)
                img.put(x, y + 1, GREEN_D.top)
    add(name, img)


def lot_tile():
    img = cell_img(0)
    n = noise(11)
    fill(img, DIAMOND_SCREEN, lambda x, y: SAND.top if n() > 0.12 else SAND.left)
    for _ in range(6):
        x = int((n() - 0.5) * 20)
        y = int(n() * 10) + 3
        if inside(DIAMOND_SCREEN, x, y):
            img.put(x, y, SAND.hi)
            img.put(x + 1, y, SAND.right)
    add('lot', img)


def mat_tile():
    img = cell_img(0)
    pts = [P(2, 3, 0), P(14, 3, 0), P(14, 13, 0), P(2, 13, 0)]

    def f(x, y):
        s = y
        u = s + x / 2.0
        v = s - x / 2.0
        if min(u - 2, 14 - u, v - 3, 13 - v) < 1.5:
            return INK
        if min(u - 2, 14 - u, v - 3, 13 - v) < 3.0:
            return GOLD.top
        return RED.top if int(v) % 3 else RED.right
    fill(img, pts, f)
    add('mat', img)


def edge_tiles():
    for name, left in (('edge_l', True), ('edge_r', False)):
        img = cell_img(0, depth=24)
        def shade(a, z):
            if z < -4:
                return WOOD_D.lo
            return WOOD_D.right if left is False else WOOD_D.left
        if left:
            face_left(img, 0, 16, 16, -5, 0, lambda u, z: WOOD_D.left if z > -4 else WOOD_D.lo)
            line(img, P(0, 16, 0), P(16, 16, 0), WOOD.top)
        else:
            face_right(img, 16, 0, 16, -5, 0, lambda v, z: WOOD_D.right if z > -4 else WOOD_D.lo)
            line(img, P(16, 0, 0), P(16, 16, 0), WOOD.left)
        add(name, img)


WALL_H = 40


# Wallpapers and floors the player can choose, besides the ones the diner
# starts with: id, colours, and for walls a pattern. The ids are the ones in
# lib/diner/styles.dart.
WALL_STYLES = [
    ('cream', '#f1e2c4', '#fff6e4', 'plain'),
    ('sage', '#b7cfa4', '#f4f1dc', 'plain'),
    ('rose', '#f0b0c0', '#fff0f2', 'plain'),
    ('navy', '#5a6fa8', '#e8ecf6', 'plain'),
    ('stripe', '#8fcfc8', '#fff3d6', 'stripe'),
    ('brick', '#b5563f', '#e8d9c0', 'brick'),
]
FLOOR_STYLES = [
    ('slate', '#a9b2c4', '#8d97ad'),
    ('wood', '#c99a63', '#b3834d'),
    ('checker', '#f4f1ea', '#3b3a46'),
    ('terra', '#d98f6a', '#c47b57'),
    ('mint', '#bfe6d8', '#a2d4c3'),
]

# Furniture looks for the chair, bench, table and long table: each sells (or
# is earned, or is free) the same way across all four, but is picked for each
# piece on its own. The ids are the ones in lib/diner/styles.dart.
SEAT_STYLES = [
    {
        'id': 'mint',
        'chair_seat': '#9ad9c8', 'chair_wood': '#c58a56',
        'bench_seat': '#9ad9c8', 'bench_base': '#5fae99',
        'cloth': '#9ad9c8', 'cloth_light': '#c9ecdf', 'cloth_pale': '#eef8f3',
    },
    {
        'id': 'diner',
        'chair_seat': '#2e7d6b', 'chair_wood': '#3a3a46',
        'bench_seat': '#2e7d6b', 'bench_base': '#234f45',
        'cloth': '#2e7d6b', 'cloth_light': '#6fae9f', 'cloth_pale': '#eef2e2',
    },
    {
        'id': 'walnut',
        'chair_seat': '#caa06a', 'chair_wood': '#8e5a37',
        'bench_seat': '#caa06a', 'bench_base': '#8e5a37',
        'cloth': '#caa06a', 'cloth_light': '#e0c194', 'cloth_pale': '#f3e6cf',
    },
]


def wall_pieces(suffix='', wall_hex='#a6e0d1', trim_hex='#fff3d6',
                pattern='plain'):
    wall = ramp(wall_hex)
    trim = ramp(trim_hex)
    rail = WOOD

    def wallpaper(a, z):
        # a = along-wall coordinate
        c = wall.left
        if pattern == 'stripe':
            # wide bands of the colour and a paler one
            if (int(a) // 3) % 2:
                c = mix(c, trim.top, 0.6)
        elif pattern == 'brick':
            # courses of bricks, every other course shifted half a brick
            row = int(z) // 4
            if int(z) % 4 == 0 or (int(a) + 4 * (row % 2)) % 8 == 0:
                c = mix(wall.hi, trim.top, 0.5)
            elif (row * 5 + int(a) // 8) % 3 == 0:
                c = wall.right
        else:
            if int(a) % 8 < 1:
                c = wall.right
        if z > 28:
            c = mix(c, wall.hi, 0.35)
        return c

    def panel(a, z):
        c = WOOD.left if int(a) % 8 else WOOD.right
        return c

    # --- wall on the upper-right edge: the visible face is its +v side
    def make_a(name, deco=None):
        img = cell_img(WALL_H + 6)
        oy = img.oy
        # slab sits at the far (v 12..16) edge of its cell
        box(img, 0, 12, 16, 16, 0, WALL_H, trim,
            left=lambda u, z: (panel(u, z) if z < 12 else
                               (rail.hi if z < 14 else
                                (rail.top if z < 15 else wallpaper(u, z)))),
            right=trim.right, top=trim.hi, edge=False)
        # skirting + cap
        face_left(img, 0, 16, 16, 0, 2, WOOD_D.left)
        face_left(img, 0, 16, 16, WALL_H - 3, WALL_H, trim.top)
        line(img, P(0, 16, WALL_H - 3), P(16, 16, WALL_H - 3), trim.hi)
        if deco:
            deco(img)
        add(name + suffix, img)

    def window(img):
        for (a0, a1) in ((3, 13),):
            z0, z1 = 17, 34
            face_left(img, a0 - 1, a1 + 1, 16, z0 - 1, z1 + 1, trim.top)
            face_left(img, a0, a1, 16, z0, z1,
                      lambda u, z: mix(hexc('#8fd0f2'), hexc('#d8f2ff'), (z - z0) / (z1 - z0)))
            for u in range(a0, a1):
                if (u - a0) % 3 == 0 and u + 3 < a1:
                    pass
            face_left(img, a0 + 4, a0 + 6, 16, z0, z1, trim.top)
            face_left(img, a0, a1, 16, (z0 + z1) // 2, (z0 + z1) // 2 + 1, trim.top)
            # glint
            for k in range(3):
                img.put(P(a0 + 1 + k, 16, z1 - 2 - k)[0], P(a0 + 1 + k, 16, z1 - 2 - k)[1], (255, 255, 255))
            box(img, a0 - 2, 16, a1 + 2, 18, z0 - 3, z0 - 1, trim)

    def board(img):
        # a small chalkboard menu
        a0, a1, z0, z1 = 3, 13, 17, 31
        face_left(img, a0 - 1, a1 + 1, 16, z0 - 1, z1 + 1, WOOD.top)
        face_left(img, a0, a1, 16, z0, z1, hexc('#35504a'))
        for i, zz in enumerate((28, 25, 22)):
            for k in range(4 + (i % 2) * 2):
                x, y = P(a0 + 2 + k * 1, 16, zz)
                img.put(x, y, (240, 240, 226))
        x, y = P(a1 - 3, 16, 20)
        img.put(x, y, GOLD.top)
        img.put(x + 1, y, GOLD.top)

    make_a('wall_a')
    make_a('wall_a_window', window)
    make_a('wall_a_board', board)
    # --- wall on the upper-left edge: its visible face is +u
    def make_b(name, deco=None):
        img = cell_img(WALL_H + 6)
        box(img, 12, 0, 16, 16, 0, WALL_H, trim,
            left=trim.left,
            right=lambda v, z: (panel(v, z) if z < 12 else
                                (rail.right if z < 14 else
                                 (rail.top if z < 15 else darker(wallpaper(v, z), 0.2)))),
            top=trim.hi, edge=False)
        face_right(img, 16, 0, 16, 0, 2, WOOD_D.right)
        face_right(img, 16, 0, 16, WALL_H - 3, WALL_H, darker(trim.top, 0.2))
        if deco:
            deco(img)
        add(name + suffix, img)

    def window_b(img):
        a0, a1, z0, z1 = 3, 13, 17, 34
        face_right(img, 16, a0 - 1, a1 + 1, z0 - 1, z1 + 1, darker(trim.top, 0.2))
        face_right(img, 16, a0, a1, z0, z1,
                   lambda v, z: mix(hexc('#74b4dc'), hexc('#bfe3f5'), (z - z0) / (z1 - z0)))
        face_right(img, 16, a0 + 4, a0 + 6, z0, z1, darker(trim.top, 0.2))
        face_right(img, 16, a0, a1, (z0 + z1) // 2, (z0 + z1) // 2 + 1, darker(trim.top, 0.2))
        box(img, 16, a0 - 2, 18, a1 + 2, z0 - 3, z0 - 1, trim)

    make_b('wall_b')
    make_b('wall_b_window', window_b)
    # --- corner post
    img = cell_img(WALL_H + 8)
    box(img, 10, 10, 16, 16, 0, WALL_H + 3, trim, edge=False)
    face_left(img, 10, 16, 16, 0, 2, WOOD_D.left)
    box(img, 9, 9, 17, 17, WALL_H + 3, WALL_H + 5, WOOD)
    add('wall_corner' + suffix, img)


# -------------------------------------------------------------- fixtures
def table(suffix='', cloth=RED, light='#f7b3aa', pale='#fff6e8'):
    img = cell_img(34)
    # pedestal and foot
    cylinder(img, 8, 8, 5, 0, 2, ramp('#5b5266'))
    cylinder(img, 8, 8, 2, 2, 10, ramp('#8d8499'))
    # tablecloth top: a two-tone check, in an iso ellipse
    cx, cy = P(8, 8, 11)
    rx, ry = 14, 7
    def check(x, y):
        u = (y + 11) + x / 2.0
        v = (y + 11) - x / 2.0
        su, sv = int(u // 5) % 2, int(v // 5) % 2
        if su and sv:
            return cloth.top
        if su or sv:
            return hexc(light)
        return hexc(pale)
    # drape: a darker band under the rim
    ellipse(img, cx, cy + 2, rx, ry, cloth.right)
    ellipse(img, cx, cy + 1, rx, ry, cloth.left)
    ellipse(img, cx, cy, rx, ry, check)
    # little flower in a vase
    box(img, 7, 7, 9, 9, 11, 14, ramp('#9ccbe8'))
    x, y = P(8, 8, 16)
    img.put(x, y, PINK.top)
    img.put(x - 1, y, PINK.hi)
    img.put(x + 1, y, PINK.hi)
    img.put(x, y - 1, PINK.hi)
    img.put(x, y + 1, GOLD.top)
    add(f'table{suffix}', img, 0.55)


def chair(name, back, seat=RED, wood=WOOD):
    img = cell_img(26)
    leg = ramp('#7b4b2c')
    _ll = shaded_side(leg.left, leg.hi, leg.lo, 0, 7, ao_rows=1, hi_rows=1)
    _lr = shaded_side(leg.right, leg.hi, leg.lo, 0, 7, ao_rows=1, hi_rows=1)
    for (u, v) in ((3, 3), (11, 3), (3, 11), (11, 11)):
        box(img, u, v, u + 2, v + 2, 0, 7, leg, edge=False, left=_ll, right=_lr)
    box(img, 2, 2, 14, 14, 7, 9, wood)
    box(img, 3, 3, 13, 13, 9, 11, seat)
    h = 22
    if back == 'su':   # back on the low-u side (facing +u / SE)
        box(img, 2, 2, 4, 14, 9, h, wood,
            left=shaded_side(wood.left, wood.hi, wood.lo, 9, h),
            right=shaded_side(wood.right, wood.hi, wood.lo, 9, h))
    elif back == 'sv':  # facing +v / SW
        box(img, 2, 2, 14, 4, 9, h, wood,
            left=shaded_side(wood.left, wood.hi, wood.lo, 9, h),
            right=shaded_side(wood.right, wood.hi, wood.lo, 9, h))
    elif back == 'nu':  # facing -u / NW: back on the high-u side, kept low
        box(img, 12, 2, 14, 14, 9, 15, wood,
            left=shaded_side(wood.left, wood.hi, wood.lo, 9, 15, ao_rows=1, hi_rows=1),
            right=shaded_side(wood.right, wood.hi, wood.lo, 9, 15, ao_rows=1, hi_rows=1))
    else:               # facing -v / NE
        box(img, 2, 12, 14, 14, 9, 15, wood,
            left=shaded_side(wood.left, wood.hi, wood.lo, 9, 15, ao_rows=1, hi_rows=1),
            right=shaded_side(wood.right, wood.hi, wood.lo, 9, 15, ao_rows=1, hi_rows=1))
    add(name, img, 0.55)


def plant():
    img = cell_img(40)
    pot = ramp('#d9784a')
    cylinder(img, 8, 8, 6, 0, 9, pot, cap=hexc('#4a3326'))
    face_top(img, 6, 10, 6, 10, 9, hexc('#4a3326'))
    cx, cy = P(8, 8, 9)
    stem = hexc('#4f7a3a')
    stem_hi = hexc('#7fae56')
    # main stem up from the soil into the middle clump, and two branches out
    # to the side clumps
    for k in range(0, 18):
        img.put(cx, cy - k, stem)
        img.put(cx + 1, cy - k, stem_hi)
    for side in (-1, 1):
        for k in range(0, 7):
            x = cx + side * k
            y = cy - 10 - k
            img.put(x, y, stem)
            img.put(x, y - 1, stem_hi)
    blobs = [(-6, -17, 5, 4), (6, -17, 5, 4), (0, -22, 6, 5), (-3, -26, 4, 3),
             (3, -26, 4, 3), (0, -29, 3, 2)]
    for dx, dy, rx, ry in blobs:
        ellipse(img, cx + dx, cy + dy, rx, ry,
                lambda x, y, dx=dx, dy=dy: (GREEN.hi if (x - dx - cx) + (y - dy - cy) < -4
                                            else (GREEN.top if (x - dx - cx) + (y - dy - cy) < 0
                                                  else (GREEN_D.top if (x - dx - cx) + (y - dy - cy) > 4
                                                        else GREEN.left))))
    add('plant', img, 0.5)


def jukebox(f):
    """A jukebox, its lit glass front and speaker turned to face [f]: the
    same cabinet either way, just which side the glass and the grille sit
    on. Facing away from the camera ('nw'/'ne') it is the plain red back."""
    img = cell_img(46)
    body = ramp('#d9453d')
    box(img, 2, 3, 14, 13, 0, 30, body, edge=False,
        left=shaded_side(body.left, body.hi, body.lo, 0, 30, ao_rows=3, hi_rows=2),
        right=shaded_side(body.right, body.hi, body.lo, 0, 30, ao_rows=3, hi_rows=2))
    # base plinth
    box(img, 1, 2, 15, 14, 0, 3, WOOD_D, edge=False)
    # arched top: stepped boxes
    box(img, 3, 4, 13, 12, 30, 33, body, edge=False)
    box(img, 5, 5, 11, 11, 33, 35, body)
    # the lit glass front, an arched window of colour bands
    a0, a1, z0, z1 = 4, 12, 12, 30

    def glass(a, z):
        k = (z - z0) / (z1 - z0)
        if z > z1 - 3 and (a < a0 + 1 or a > a1 - 2):
            return body.left
        bands = [hexc('#5fd3d0'), hexc('#7ee0a0'), hexc('#ffd35a'), hexc('#ff9a5a'), hexc('#ff6f8a')]
        return bands[int(k * len(bands)) % len(bands)]

    if f == 'sw':
        # the front is the +v face; the +u face shows a side speaker
        face_left(img, a0, a1, 13, z0, z1, glass)
        face_left(img, a0 - 1, a0, 13, z0, z1, GOLD.top)
        face_left(img, a1, a1 + 1, 13, z0, z1, GOLD.top)
        for k in range(4):
            face_left(img, 5 + k * 2, 6 + k * 2, 13, 5, 10, body.lo)
        face_left(img, 9, 11, 13, 7, 8, GOLD.top)
        for k in range(3):
            for j in range(3):
                x, y = P(14, 5 + k * 2, 8 + j * 4)
                img.put(x, y, body.lo)
    elif f == 'se':
        # the front is the +u face; the +v face shows a side speaker
        face_right(img, 14, a0, a1, z0, z1, glass)
        face_right(img, 14, a0 - 1, a0, z0, z1, GOLD.top)
        face_right(img, 14, a1, a1 + 1, z0, z1, GOLD.top)
        for k in range(4):
            face_right(img, 14, 5 + k * 2, 6 + k * 2, 5, 10, body.lo)
        face_right(img, 14, 9, 11, 7, 8, GOLD.top)
        for k in range(3):
            for j in range(3):
                x, y = P(5 + k * 2, 13, 8 + j * 4)
                img.put(x, y, body.lo)
    # 'nw' and 'ne' face away from the camera: the plain cabinet back,
    # same as the shaded body already drawn.
    add(f'jukebox_{f}', img, 0.55)


def wall_tv(f):
    """A widescreen television hung high on a wall, its screen facing into the
    room. It is two tiles long and about sixteen to nine. [f] is the way it
    faces: 'sw' on the back wall, 'se' on the left wall."""
    case = ramp('#2c3040')
    # Up on the glass, well clear of the panelling and of anything standing
    # below it.
    z0, z1 = 20, 36
    n0, n1 = 3, 29            # the lit screen, in tile units along the wall

    def glow(a, z):
        if a < n0 or a > n1 or z < z0 + 2 or z > z1 - 2:
            return case.left
        # A calm picture: sky, a band of cloud, a strip of ground below.
        if z <= z0 + 4:
            return hexc('#6fae6a') if int(a) % 7 < 5 else hexc('#5a9a58')
        if z in (z0 + 8, z0 + 9) and 8 <= a <= 22:
            return hexc('#f2fbff')
        return hexc('#8fd8f4') if z < z1 - 6 else hexc('#a8e4fa')

    if f == 'sw':
        # Along the back wall: two tiles to the right of the first.
        img = cell_img(46, extra_w=32)
        box(img, 1, 0, 31, 2, z0, z1, case, edge=False)
        face_left(img, 1, 31, 2, z0, z1, glow)
        img.put(*P(6, 2, z1 - 3), (255, 255, 255))
        img.put(*P(7, 2, z1 - 4), (255, 255, 255))
    else:
        # Along the left wall: the second tile is down and to the left.
        img = Img(48, 46 + 32, 32, 46)
        box(img, 0, 1, 2, 31, z0, z1, case, edge=False)
        face_right(img, 2, 1, 31, z0, z1, glow)
        img.put(*P(2, 6, z1 - 3), (255, 255, 255))
        img.put(*P(2, 7, z1 - 4), (255, 255, 255))
    add(f'tv_{f}', img, 0.55)


def rug():
    img = cell_img(0)
    pts = [P(1, 1), P(15, 1), P(15, 15), P(1, 15)]
    def f(x, y):
        u = y + x / 2.0
        v = y - x / 2.0
        d = min(u - 1, 15 - u, v - 1, 15 - v)
        if d < 1.2:
            return hexc('#2d5b99')
        if d < 3:
            return hexc('#e8b73a')
        cu, cv = abs(u - 8), abs(v - 8)
        if cu + cv < 3:
            return hexc('#fff0d2')
        if cu + cv < 5:
            return RED.top
        return hexc('#4f8fd8') if int(u + v) % 4 else hexc('#5a9be4')
    fill(img, pts, f)
    add('rug', img)


FACINGS = ('se', 'sw', 'nw', 'ne')


def front_of(f):
    """Which visible face is the front: 'v' (left), 'u' (right) or None."""
    return {'sw': 'v', 'se': 'u'}.get(f)


def on_face(img, f, a0, a1, z0, z1, color, plane=15):
    """Paint a rectangle on the front face of a 1 cell box (does nothing when
    the front is turned away from the viewer)."""
    face = front_of(f)
    if face == 'v':
        face_left(img, a0, a1, plane, z0, z1, color)
    elif face == 'u':
        face_right(img, plane, a0, a1, z0, z1, color)


def on_back(img, f, a0, a1, z0, z1, color, plane=15):
    """The same on the face that shows when the front is turned away."""
    if f == 'nw':
        face_right(img, plane, a0, a1, z0, z1, color)
    elif f == 'ne':
        face_left(img, a0, a1, plane, z0, z1, color)


def counter(f):
    img = cell_img(32)
    body = ramp('#b8743f')
    _cl = shaded_side(body.left, body.hi, body.lo, 0, 13)
    _cr = shaded_side(body.right, body.hi, body.lo, 0, 13)
    box(img, 1, 1, 15, 15, 0, 13, body,
        left=lambda u, z: (body.right if (3 <= u <= 12 and 3 <= z <= 9 and
                                          (u in (3, 12) or z in (3, 9))) else _cl(u, z)),
        right=lambda v, z: (body.left if (3 <= v <= 12 and 3 <= z <= 9 and
                                          (v in (3, 12) or z in (3, 9))) else _cr(v, z)))
    box(img, 0, 0, 16, 16, 13, 15, MARBLE,
        top=shaded_top(
            MARBLE.top, MARBLE.hi, 0, 16, 0, 16,
            under=lambda u, v: MARBLE.top if (int(u + v * 0.7) % 7) else MARBLE.left,
        ))
    # cash register: its screen turns to the front
    reg = ramp('#4a4f63')
    box(img, 5, 5, 11, 11, 15, 18, reg)
    if f == 'sw':
        box(img, 6, 5, 10, 7, 18, 23, reg)
        face_left(img, 7, 9, 7, 19, 22, hexc('#7fe0c0'))
        img.put(*P(7, 7, 22), (255, 255, 255))
    elif f == 'se':
        box(img, 5, 6, 7, 10, 18, 23, reg)
        face_right(img, 7, 7, 9, 19, 22, hexc('#7fe0c0'))
        img.put(*P(7, 7, 22), (255, 255, 255))
    else:
        box(img, 6, 5, 10, 7, 18, 22, reg)
    # a tip jar at the other end
    box(img, 12, 11, 14, 13, 15, 19, ramp('#a8d8f0'))
    add(f'counter_{f}', img, 0.55)


def grill(f):
    img = cell_img(40)
    # the hood stands at the back, opposite the front
    def hood():
        if f == 'sw':
            box(img, 1, 1, 15, 4, 13, 26, STEEL)
            for k in range(3):
                face_left(img, 4 + k * 3, 6 + k * 3, 4, 17, 22, STEEL.lo)
            box(img, 0, 0, 16, 6, 26, 30, STEEL_D)
        elif f == 'se':
            box(img, 1, 1, 4, 15, 13, 26, STEEL)
            for k in range(3):
                face_right(img, 4, 4 + k * 3, 6 + k * 3, 17, 22, STEEL.lo)
            box(img, 0, 0, 6, 16, 26, 30, STEEL_D)
        elif f == 'nw':
            box(img, 12, 1, 15, 15, 13, 26, STEEL)
            for k in range(3):
                face_right(img, 15, 4 + k * 3, 6 + k * 3, 17, 22, STEEL.lo)
            box(img, 10, 0, 16, 16, 26, 30, STEEL_D)
        else:
            box(img, 1, 12, 15, 15, 13, 26, STEEL)
            for k in range(3):
                face_left(img, 4 + k * 3, 6 + k * 3, 15, 17, 22, STEEL.lo)
            box(img, 0, 10, 16, 16, 26, 30, STEEL_D)

    _gl = shaded_side(STEEL.left, STEEL.hi, STEEL.lo, 0, 12)
    _gr = shaded_side(STEEL.right, STEEL.hi, STEEL.lo, 0, 12)
    box(img, 1, 1, 15, 15, 0, 12, STEEL,
        left=lambda u, z: (STEEL.right if (u in (2, 14) or z == 11) else _gl(u, z)),
        right=lambda v, z: (STEEL.lo if (v in (2, 14) or z == 11) else _gr(v, z)))
    if f in ('sw', 'se'):
        hood()
    box(img, 2, 2, 14, 14, 12, 13, STEEL_D)
    face_top(img, 3, 13, 3, 13, 13, hexc('#3b3445'))
    for (u, v) in ((5, 5), (9, 8)):
        cx, cy = P(u + 2, v + 2, 13)
        ellipse(img, cx, cy, 4, 2, hexc('#8a4b2d'))
        ellipse(img, cx - 1, cy - 1, 2, 1, hexc('#b86a3f'))
    for k in range(5):
        x, y = P(5 + k * 2, 13, 13)
        img.put(x, y, hexc('#ff8a3d') if k % 2 else hexc('#ffc457'))
    # knobs on the front face
    for k, col in enumerate((GOLD.top, RED.top, GOLD.top)):
        a = 4 + k * 4
        if f == 'sw':
            x, y = P(a, 15, 6)
        elif f == 'se':
            x, y = P(15, a, 6)
        else:
            continue
        rect(img, x, y, 2, 2, col)
        img.put(x, y, lighter(col, 0.5))
    if f in ('nw', 'ne'):
        hood()
    add(f'grill_{f}', img, 0.55)


def fryer(f):
    img = cell_img(34)
    body = ramp('#59607a')
    accent = ramp('#e0a526')
    _fl = shaded_side(body.left, body.hi, body.lo, 0, 13)
    _fr = shaded_side(body.right, body.hi, body.lo, 0, 13)
    box(img, 1, 1, 15, 15, 0, 13, body,
        left=lambda u, z: accent.base if z == 11 else _fl(u, z),
        right=lambda v, z: accent.right if z == 11 else _fr(v, z))
    # two oil wells with wire baskets
    box(img, 2, 2, 14, 14, 13, 14, body)
    for (u0, v0) in ((3, 3), (3, 9)):
        face_top(img, u0, u0 + 9, v0, v0 + 4, 14, hexc('#c88a1c'))
        face_top(img, u0 + 1, u0 + 5, v0 + 1, v0 + 3, 14, hexc('#e8b43a'))
        # basket: a little grid and a handle
        for k in range(3):
            x, y = P(u0 + 2 + k * 2, v0 + 2, 15)
            img.put(x, y, (250, 240, 200))
        box(img, u0 + 7, v0 + 1, u0 + 9, v0 + 3, 14, 19, ramp('#c04a3a'))
    # control panel on the front
    for k, col in enumerate((GREEN.top, RED.top)):
        a = 5 + k * 5
        if f == 'sw':
            x, y = P(a, 15, 7)
        elif f == 'se':
            x, y = P(15, a, 7)
        else:
            continue
        rect(img, x, y, 2, 2, col)
    # a splash guard at the back
    if f == 'sw':
        box(img, 1, 1, 15, 3, 14, 22, body)
    elif f == 'se':
        box(img, 1, 1, 3, 15, 14, 22, body)
    elif f == 'nw':
        box(img, 13, 1, 15, 15, 14, 22, body)
    else:
        box(img, 1, 13, 15, 15, 14, 22, body)
    add(f'fryer_{f}', img, 0.55)


def soda(f):
    img = cell_img(46)
    body = ramp('#3f8fd0')
    box(img, 2, 3, 14, 13, 0, 32, body, edge=False,
        left=shaded_side(body.left, body.hi, body.lo, 0, 32, ao_rows=3, hi_rows=3),
        right=shaded_side(body.right, body.hi, body.lo, 0, 32, ao_rows=3, hi_rows=3))
    box(img, 1, 2, 15, 14, 0, 3, STEEL_D, edge=False)
    box(img, 3, 4, 13, 12, 32, 35, ramp('#2f6fa8'))
    # front: a glass panel of coloured syrup, three nozzles, a drip tray
    def panel_v(u, z):
        if u in (4, 11) or z in (14, 29):
            return GOLD.top
        k = int((u - 4) // 3) % 3
        return [RED.top, GREEN.top, hexc('#ffb23f')][k]
    if f == 'sw':
        face_left(img, 4, 12, 13, 14, 30, panel_v)
        for k in range(3):
            face_left(img, 5 + k * 3, 6 + k * 3, 13, 9, 12, STEEL.top)
        box(img, 4, 13, 12, 15, 5, 7, STEEL)
    elif f == 'se':
        face_right(img, 14, 4, 12, 14, 30, lambda v, z: panel_v(v + 0, z))
        for k in range(3):
            face_right(img, 14, 5 + k * 3, 6 + k * 3, 9, 12, STEEL.top)
        box(img, 14, 4, 16, 12, 5, 7, STEEL)
    elif f == 'nw':
        face_right(img, 14, 4, 12, 20, 22, GOLD.top)
    else:
        face_left(img, 4, 12, 13, 20, 22, GOLD.top)
    # a stack of cups on top
    cx, cy = P(8, 8, 36)
    ellipse(img, cx, cy, 3, 1.5, (250, 250, 246))
    rect(img, cx - 2, cy, 4, 3, (240, 90, 90))
    add(f'soda_{f}', img, 0.55)


def espresso(f):
    img = cell_img(36)
    body = ramp('#6b4a3a')
    chrome = ramp('#cfd6e4')
    _el = shaded_side(body.left, body.hi, body.lo, 0, 11)
    _er = shaded_side(body.right, body.hi, body.lo, 0, 11)
    box(img, 1, 1, 15, 15, 0, 11, body,
        left=lambda u, z: GOLD.base if z == 10 else _el(u, z),
        right=lambda v, z: GOLD.right if z == 10 else _er(v, z))
    # the machine itself: a polished steel block with two group heads
    box(img, 3, 3, 13, 13, 11, 22, chrome)
    box(img, 2, 2, 14, 14, 22, 24, ramp('#a7b0c4'))
    # group heads and cups on the front side
    for k in range(2):
        a = 5 + k * 5
        if f == 'sw':
            box(img, a, 13, a + 2, 15, 12, 15, STEEL_D)
            x, y = P(a, 15, 11)
        elif f == 'se':
            box(img, 13, a, 15, a + 2, 12, 15, STEEL_D)
            x, y = P(15, a, 11)
        else:
            continue
        rect(img, x - 1, y, 3, 2, (250, 250, 246))
    # a pressure gauge
    if f == 'sw':
        x, y = P(8, 13, 19)
    elif f == 'se':
        x, y = P(13, 8, 19)
    else:
        x, y = P(8, 3, 19)
    ellipse(img, x, y, 2, 2, (250, 250, 240))
    img.put(x, y, RED.top)
    add(f'espresso_{f}', img, 0.55)


def oven(f):
    img = cell_img(46)
    brick = ramp('#c0583f')
    box(img, 1, 1, 15, 15, 0, 14, brick,
        left=lambda u, z: (brick.lo if z < 2 else
                           (brick.hi if z >= 12 else
                            (brick.right if (int(u) + int(z // 3)) % 4 == 0 else brick.left))),
        right=lambda v, z: (brick.lo if z < 2 else
                            (brick.hi if z >= 12 else
                             (brick.lo if (int(v) + int(z // 3)) % 4 == 0 else brick.right))))
    # a stepped dome on top
    box(img, 2, 2, 14, 14, 14, 20, brick)
    box(img, 4, 4, 12, 12, 20, 25, brick)
    box(img, 6, 6, 10, 10, 25, 28, brick)
    # the mouth, with a fire inside, on the front
    def mouth_v(u, z):
        if u < 5 or u > 11 or z < 14 or z > 21:
            return None
        if z > 19 and (u < 6 or u > 10):
            return None
        return hexc('#ff9a3d') if z < 17 and 6 <= u <= 10 else hexc('#4a2a22')
    if f == 'sw':
        face_left(img, 5, 11, 15, 14, 21,
                  lambda u, z: mouth_v(u, z) or brick.left)
    elif f == 'se':
        face_right(img, 15, 5, 11, 14, 21,
                   lambda v, z: mouth_v(v, z) or brick.right)
    # a chimney at the back
    if f == 'sw':
        box(img, 7, 2, 10, 5, 28, 38, ramp('#8d6a58'))
    elif f == 'se':
        box(img, 2, 7, 5, 10, 28, 38, ramp('#8d6a58'))
    elif f == 'nw':
        box(img, 11, 7, 14, 10, 28, 38, ramp('#8d6a58'))
    else:
        box(img, 7, 11, 10, 14, 28, 38, ramp('#8d6a58'))
    add(f'oven_{f}', img, 0.55)


def freezer(f):
    img = cell_img(30)
    body = ramp('#e8f0f8')
    # The blue accent stripe already sits at the top and reads as the
    # highlight there, so the shared shader only needs to add the base AO.
    _zl = shaded_side(body.left, body.hi, body.lo, 0, 13, hi_rows=0)
    _zr = shaded_side(body.right, body.hi, body.lo, 0, 13, hi_rows=0)
    box(img, 1, 1, 15, 15, 0, 13, body,
        left=lambda u, z: BLUE.base if z in (11, 12) else _zl(u, z),
        right=lambda v, z: BLUE.right if z in (11, 12) else _zr(v, z))
    # a glass lid over rows of tubs in different flavours
    face_top(img, 2, 14, 2, 14, 13,
              shaded_top(hexc('#bfe2f5'), lighter(hexc('#bfe2f5'), 0.35), 2, 14, 2, 14))
    cols = [hexc('#f9d6e0'), hexc('#fff2b8'), hexc('#cfa27a'), hexc('#bfe7c8')]
    for i in range(2):
        for j in range(2):
            u0 = 3 + i * 5
            v0 = 3 + j * 5
            face_top(img, u0, u0 + 4, v0, v0 + 4, 14, cols[(i * 2 + j) % 4])
    # a label on the front
    if f == 'sw':
        face_left(img, 5, 11, 15, 4, 9, hexc('#3f8fd0'))
        face_left(img, 6, 10, 15, 6, 7, (255, 255, 255))
    elif f == 'se':
        face_right(img, 15, 5, 11, 4, 9, hexc('#3f8fd0'))
        face_right(img, 15, 6, 10, 6, 7, (255, 255, 255))
    add(f'freezer_{f}', img, 0.55)


def bench(f, suffix='', seat=PINK, base='#b3576f'):
    """A bench seats two. Facing se or nw it runs along the y axis."""
    along_y = f in ('se', 'nw')
    img = cell_img(30, extra_w=32)
    img.ox = 16
    if along_y:
        img = Img(32 + 16, 30 + 36 + 16, 32, 30)
    base = ramp(base)
    L = 32
    if not along_y:
        box(img, 1, 2, L - 1, 14, 0, 7, base, edge=False,
            left=shaded_side(base.left, base.hi, base.lo, 0, 7, ao_rows=1, hi_rows=1),
            right=shaded_side(base.right, base.hi, base.lo, 0, 7, ao_rows=1, hi_rows=1))
        box(img, 1, 3, L - 1, 14, 7, 10, seat)
        if f == 'sw':
            box(img, 1, 2, L - 1, 5, 10, 22, seat,
                left=lambda u, z: (seat.hi if z > 20 else (seat.left if int(u) % 6 else seat.right)))
        else:
            box(img, 1, 11, L - 1, 14, 10, 15, seat,
                left=shaded_side(seat.left, seat.hi, seat.lo, 10, 15, ao_rows=1, hi_rows=1),
                right=shaded_side(seat.right, seat.hi, seat.lo, 10, 15, ao_rows=1, hi_rows=1))
    else:
        box(img, 2, 1, 14, L - 1, 0, 7, base, edge=False,
            left=shaded_side(base.left, base.hi, base.lo, 0, 7, ao_rows=1, hi_rows=1),
            right=shaded_side(base.right, base.hi, base.lo, 0, 7, ao_rows=1, hi_rows=1))
        box(img, 3, 1, 14, L - 1, 7, 10, seat)
        if f == 'se':
            box(img, 2, 1, 5, L - 1, 10, 22, seat,
                right=lambda v, z: (seat.hi if z > 20 else (seat.right if int(v) % 6 else seat.lo)))
        else:
            box(img, 11, 1, 14, L - 1, 10, 15, seat,
                left=shaded_side(seat.left, seat.hi, seat.lo, 10, 15, ao_rows=1, hi_rows=1),
                right=shaded_side(seat.right, seat.hi, seat.lo, 10, 15, ao_rows=1, hi_rows=1))
    add(f'bench_{f}{suffix}', img, 0.55)


def long_table(f, suffix='', cloth=RED, light='#f7b3aa', pale='#fff6e8'):
    """A table two tiles long, with the same check cloth and a vase at
    each end of the cloth's middle. 'sw' lies along x, 'se' along y."""
    along_y = f == 'se'
    img = cell_img(34, extra_w=32)
    img.ox = 16
    if along_y:
        img = Img(32 + 16, 34 + 36 + 16, 32, 34)
    leg = ramp('#5b5266')
    L = 32

    def check(u, v):
        su, sv = int(u // 5) % 2, int(v // 5) % 2
        if su and sv:
            return cloth.top
        if su or sv:
            return hexc(light)
        return hexc(pale)

    _ll = shaded_side(leg.left, leg.hi, leg.lo, 0, 9, ao_rows=2, hi_rows=1)
    _lr = shaded_side(leg.right, leg.hi, leg.lo, 0, 9, ao_rows=2, hi_rows=1)
    if not along_y:
        for cu in (8, 24):
            box(img, cu - 2, 6, cu + 2, 10, 0, 9, leg, edge=False, left=_ll, right=_lr)
        box(img, 1, 2, L - 1, 14, 9, 11, cloth, top=check)
        box(img, 14, 6, 18, 10, 11, 14, ramp('#9ccbe8'))
    else:
        for cv in (8, 24):
            box(img, 6, cv - 2, 10, cv + 2, 0, 9, leg, edge=False, left=_ll, right=_lr)
        box(img, 2, 1, 14, L - 1, 9, 11, cloth, top=check)
        box(img, 6, 14, 10, 18, 11, 14, ramp('#9ccbe8'))
    add(f'longTable_{f}{suffix}', img, 0.55)


# ------------------------------------------------------------------ people
import people  # noqa: E402

CAST = {
    'chef': people.Spec('#6b4a2f', 'short', top='jacket', shirt='#fbf6ea',
                        pants='#4a6fb5', skin='light'),
    'cust_a': people.Spec('#3b2a1e', 'spiky', top='hoodie', shirt='#5aa0e6',
                          pants='#394a7a', skin='light'),
    'cust_b': people.Spec('#e8b640', 'long', top='dress', shirt='#f487a6',
                          bottom='skirt', skin='pale'),
    'cust_c': people.Spec('#2b2230', 'short', top='tee', shirt='#66c06a',
                          pants='#6a4a35', skin='brown', glasses=True),
    'cust_d': people.Spec('#d4d4de', 'bun', top='cardigan', shirt='#9a7ad0',
                          bottom='longskirt', pants='#6b5a8c', skin='pale'),
    'cust_e': people.Spec('#c4622d', 'short', top='tee', shirt='#f2c338',
                          bottom='shorts', pants='#3f78c4', skin='tan',
                          child=True, cap='#e2493f'),
    'cust_f': people.Spec('#d9742c', 'ponytail', top='tee', shirt='#3fb7b0',
                          pants='#2e3a5c', skin='tan', extra='stripe'),
    'waiter': people.Spec('#3b2a1e', 'short', top='tee', shirt='#4a6fb5',
                          pants='#2e3a5c', skin='tan', extra='apron'),
}


def shifted_down(img, n):
    out = Img(img.w, img.h, img.ox, img.oy)
    for y in range(img.h - n):
        for x in range(img.w):
            out.p[y + n][x] = img.p[y][x]
    return out


def people_sprites():
    for name, spec in CAST.items():
        for d in ('sw', 'nw'):
            for fr in ('s0', 's1', '0', '1', '2', '3'):
                img = people.draw(spec, d, fr)
                img.outline(0.6)
                shadow(img, 0, 0, 8, 3)
                add(f'{name}_{d}_{fr}', img)
            # seated: body only, hips on the origin, thighs out front
            seat = people.draw(spec, d, 's0', seated=True)
            legh = 6 if spec.child else 8
            seat = shifted_down(seat, legh)
            if d == 'sw':
                rect(seat, -9, -2, 9, 4, spec.pants.left if spec.bottom != 'skirt' else spec.skin.left)
                rect(seat, -9, -2, 9, 1, spec.pants.top if spec.bottom != 'skirt' else spec.skin.top)
                rect(seat, -1, -1, 4, 3, spec.pants.right if spec.bottom != 'skirt' else spec.skin.right)
                rect(seat, -11, 1, 4, 3, spec.shoe.left)
                rect(seat, -11, 1, 4, 1, spec.shoe.top)
            seat.outline(0.6)
            add(f'{name}_{d}_sit', seat)


# ------------------------------------------------------------------ icons
def icons():
    # coin
    c = Img(10, 10, 5, 5)
    ellipse(c, 0, 0, 4.5, 4.5, GOLD.base)
    ellipse(c, 0, 0, 3.2, 3.2, GOLD.top)
    rect(c, -1, -2, 2, 4, GOLD.right)
    rect(c, -3, -3, 2, 1, (255, 252, 230))
    c.outline(0.55)
    add('coin', c)
    # warning
    w = Img(11, 11, 5, 5)
    ellipse(w, 0, 0, 5, 5, RED.base)
    ellipse(w, -1, -1, 3, 3, RED.top)
    rect(w, -1, -3, 2, 4, (255, 255, 255))
    rect(w, -1, 2, 2, 1, (255, 255, 255))
    w.outline(0.6)
    add('warn', w)
    # what is left on a table: a used plate, crumbs, a cup on its side
    m = Img(16, 12, 8, 6)
    ellipse(m, -1, 1, 5.5, 2.6, (238, 238, 232))
    ellipse(m, -1, 1, 3.6, 1.6, (214, 214, 206))
    for dx, dy in ((-3, 1), (-1, 0), (0, 2), (1, 0)):
        rect(m, dx, dy, 1, 1, hexc('#9a6a3c'))
    rect(m, 3, 0, 1, 1, hexc('#e2493f'))
    rect(m, 4, 2, 3, 3, (250, 250, 246))
    rect(m, 4, 2, 3, 1, hexc('#8b6b52'))
    m.outline(0.5)
    add('mess', m)

    def burger(img, cx, cy, w):
        ellipse(img, cx, cy - 3, w, 2.4, hexc('#e8a04a'))
        rect(img, cx - w, cy - 2, 2 * w, 1, GREEN.top)
        rect(img, cx - w, cy - 1, 2 * w, 1, hexc('#8a4b2d'))
        ellipse(img, cx, cy + 1, w, 1.8, hexc('#d9904a'))
        rect(img, cx - 2, cy - 5, 2, 1, hexc('#fff0c8'))

    def cheeseburger(img, cx, cy, w):
        ellipse(img, cx, cy - 4, w, 2.4, hexc('#e8a04a'))
        rect(img, cx - w, cy - 3, 2 * w, 1, GREEN.top)
        rect(img, cx - w - 1, cy - 2, 2 * w + 2, 1, hexc('#ffd23f'))
        rect(img, cx - w, cy - 1, 2 * w, 1, hexc('#8a4b2d'))
        ellipse(img, cx, cy + 1, w, 1.8, hexc('#d9904a'))
        rect(img, cx - 2, cy - 6, 2, 1, hexc('#fff0c8'))

    def pizza(img, cx, cy, w):
        ellipse(img, cx, cy, w + 2, w * 0.8, hexc('#e0a85a'))
        ellipse(img, cx, cy, w + 0.5, w * 0.55, hexc('#e2493f'))
        ellipse(img, cx, cy, w - 0.5, w * 0.4, hexc('#ffd86a'))
        for dx, dy in ((-2, -1), (1, 0), (-1, 1), (2, -1)):
            rect(img, cx + dx, cy + dy, 1, 1, hexc('#b32a2a'))
        # a slice taken out
        rect(img, cx + 2, cy + 1, 3, 1, (0, 0, 0, 0)) if False else None

    def fries(img, cx, cy, w):
        rect(img, cx - 3, cy - 1, 7, 5, RED.base)
        rect(img, cx - 3, cy - 1, 7, 1, RED.hi)
        for k in range(-3, 4, 2):
            rect(img, cx + k, cy - 5 - (k % 3 == 0) - (abs(k) < 2), 1, 5, hexc('#f5d04a'))
        rect(img, cx - 2, cy + 1, 5, 1, (255, 255, 255))

    def drink(img, cx, cy, w):
        rect(img, cx - 3, cy - 3, 7, 7, (250, 250, 246))
        rect(img, cx - 3, cy - 1, 7, 4, hexc('#ff6f61'))
        rect(img, cx + 2, cy - 6, 1, 4, hexc('#3fb7b0'))
        rect(img, cx - 3, cy - 3, 7, 1, (255, 255, 255))

    def coffee(img, cx, cy, w):
        rect(img, cx - 3, cy - 2, 6, 5, (250, 250, 246))
        rect(img, cx - 3, cy - 2, 6, 2, hexc('#5a3322'))
        rect(img, cx + 3, cy - 1, 2, 3, (250, 250, 246))
        rect(img, cx + 4, cy, 1, 1, hexc('#7b8aa0'))
        rect(img, cx - 1, cy - 5, 1, 2, (220, 224, 232))
        rect(img, cx + 1, cy - 6, 1, 2, (220, 224, 232))

    def icecream(img, cx, cy, w):
        # a cone and two scoops
        for r in range(5):
            rect(img, cx - 2 + r // 2, cy + r, 5 - r, 1, hexc('#e0a050'))
        ellipse(img, cx, cy - 1, 3.2, 2.6, hexc('#f9d6e0'))
        ellipse(img, cx, cy - 4, 2.8, 2.4, hexc('#cfa27a'))
        rect(img, cx - 1, cy - 6, 1, 1, RED.top)

    def hotdog(img, cx, cy, w):
        # a long bun, the sausage poking out of both ends, a line of mustard
        rect(img, cx - 4, cy - 1, 9, 4, hexc('#e8a04a'))
        rect(img, cx - 3, cy - 2, 7, 1, hexc('#f0b765'))
        rect(img, cx - 5, cy, 11, 2, hexc('#b8452f'))
        rect(img, cx - 5, cy, 11, 1, hexc('#d65f43'))
        for k in range(-3, 4, 2):
            rect(img, cx + k, cy - 1, 1, 1, hexc('#f5d04a'))
            rect(img, cx + k + 1, cy, 1, 1, hexc('#f5d04a'))

    def onionrings(img, cx, cy, w):
        # a stack of three golden rings
        for dx, dy in ((-2, 1), (2, 1), (0, -2)):
            ellipse(img, cx + dx, cy + dy, 3.2, 2.6, hexc('#c98a2e'))
            ellipse(img, cx + dx, cy + dy, 2.4, 1.9, hexc('#e8b04a'))
            ellipse(img, cx + dx, cy + dy, 1.2, 0.9, hexc('#7a5a14'))

    def chicken(img, cx, cy, w):
        # a bun with a crisp fillet hanging out, lettuce and a pickle
        ellipse(img, cx, cy - 3, w, 2.4, hexc('#e8a04a'))
        rect(img, cx - w, cy - 2, 2 * w, 1, GREEN.top)
        ellipse(img, cx, cy - 1, w + 1.5, 1.8, hexc('#c98a2e'))
        ellipse(img, cx, cy - 1, w + 0.5, 1.2, hexc('#e0a850'))
        ellipse(img, cx, cy + 1, w, 1.8, hexc('#d9904a'))
        rect(img, cx - 2, cy - 5, 2, 1, hexc('#fff0c8'))

    def nuggets(img, cx, cy, w):
        for dx, dy in ((-3, 1), (1, 2), (-1, -2), (3, -1)):
            ellipse(img, cx + dx, cy + dy, 2.4, 2.0, hexc('#c98a2e'))
            ellipse(img, cx + dx - 0.5, cy + dy - 0.5, 1.6, 1.3, hexc('#e8b04a'))
        rect(img, cx + 4, cy + 2, 2, 2, hexc('#e2493f'))

    def milkshake(img, cx, cy, w):
        # a tall cup of pink shake with cream, a cherry and a straw
        rect(img, cx - 3, cy - 2, 7, 7, (250, 250, 246))
        rect(img, cx - 3, cy - 1, 7, 5, hexc('#f4a6c0'))
        rect(img, cx - 3, cy - 1, 7, 1, hexc('#f9c4d6'))
        ellipse(img, cx, cy - 3, 3.4, 1.8, (255, 255, 255))
        rect(img, cx, cy - 6, 1, 2, RED.base)
        rect(img, cx + 2, cy - 7, 1, 5, hexc('#3fb7b0'))

    def baconburger(img, cx, cy, w):
        # a tall one: two patties, cheese and bacon between the buns
        ellipse(img, cx, cy - 6, w, 2.4, hexc('#e8a04a'))
        rect(img, cx - w, cy - 5, 2 * w, 1, hexc('#ffd23f'))
        rect(img, cx - w, cy - 4, 2 * w, 1, hexc('#8a4b2d'))
        for k in range(-w, w, 2):
            rect(img, cx + k, cy - 3, 1, 1, hexc('#c0392b'))
            rect(img, cx + k + 1, cy - 3, 1, 1, hexc('#f0b0a0'))
        rect(img, cx - w, cy - 2, 2 * w, 1, hexc('#ffd23f'))
        rect(img, cx - w, cy - 1, 2 * w, 1, hexc('#8a4b2d'))
        ellipse(img, cx, cy + 1, w, 1.8, hexc('#d9904a'))
        rect(img, cx - 2, cy - 8, 2, 1, hexc('#fff0c8'))

    def sundae(img, cx, cy, w):
        # a glass dish, two scoops, chocolate sauce and a cherry
        rect(img, cx - 3, cy + 1, 7, 3, (230, 238, 246))
        rect(img, cx - 1, cy + 4, 3, 1, (210, 220, 232))
        ellipse(img, cx - 1, cy - 1, 2.8, 2.4, hexc('#f9d6e0'))
        ellipse(img, cx + 2, cy - 2, 2.4, 2.2, hexc('#fff2b8'))
        rect(img, cx - 2, cy - 1, 5, 1, hexc('#5a3322'))
        rect(img, cx, cy - 5, 1, 2, RED.top)

    dishes = (
        ('burger', burger),
        ('cheeseburger', cheeseburger),
        ('pizza', pizza),
        ('fries', fries),
        ('soda', drink),
        ('coffee', coffee),
        ('iceCream', icecream),
        ('hotDog', hotdog),
        ('onionRings', onionrings),
        ('chickenSandwich', chicken),
        ('nuggets', nuggets),
        ('milkshake', milkshake),
        ('baconBurger', baconburger),
        ('sundae', sundae),
    )
    for name, draw_dish in dishes:
        # a plate to set down on a table
        p = Img(16, 14, 8, 8)
        ellipse(p, 0, 1, 7, 3.5, (250, 250, 246))
        ellipse(p, 0, 1, 5, 2.4, (222, 226, 236))
        draw_dish(p, 0, 0, 4)
        p.outline(0.55)
        add(f'plate_{name}', p)
        # a small icon for order bubbles
        ic = Img(13, 13, 6, 6)
        draw_dish(ic, 0, 0, 4)
        ic.outline(0.5)
        add(f'ico_{name}', ic)


# ------------------------------------------------------------------ the city
STONE = ramp('#cfcac2')
ASPHALT = ramp('#575c6b')


def flat_tile(name, base, seed, speckle=0.08, seams=False):
    img = cell_img(0)
    n = noise(seed)

    def f(x, y):
        u = y + x / 2.0
        v = y - x / 2.0
        c = base.top
        if n() < speckle:
            c = mix(c, base.left, 0.6)
        if seams and (int(u) % 8 == 0 or int(v) % 8 == 0):
            c = mix(c, base.right, 0.35)
        return c
    fill(img, DIAMOND_SCREEN, f)
    line(img, P(0, 0), P(16, 0), base.hi)
    line(img, P(0, 0), P(0, 16), base.hi)
    add(name, img)


def curb_tile():
    img = cell_img(0)
    # the pavement's raised edge: a stone lip along the road side
    fill(img, DIAMOND_SCREEN, lambda x, y: STONE.top)
    face_left(img, 0, 16, 16, -3, 0, STONE.right)
    line(img, P(0, 16, 0), P(16, 16, 0), STONE.hi)
    line(img, P(0, 0), P(16, 0), STONE.hi)
    add('curb', img)


def road_tile(name, dashed):
    img = cell_img(0)
    n = noise(21 if dashed else 22)
    fill(img, DIAMOND_SCREEN, lambda x, y: ASPHALT.top if n() > 0.1 else ASPHALT.left)
    if dashed:
        # a broken yellow line along the far edge of this lane
        for u0 in (1, 9):
            pts = [P(u0, 14), P(u0 + 5, 14), P(u0 + 5, 16), P(u0, 16)]
            fill(img, pts, hexc('#f2c338'))
    add(name, img)


def road_v_tile():
    """A lane of the side street, which runs the other way: the broken line
    is along its +u edge."""
    img = cell_img(0)
    n = noise(24)
    fill(img, DIAMOND_SCREEN, lambda x, y: ASPHALT.top if n() > 0.1 else ASPHALT.left)
    for v0 in (1, 9):
        pts = [P(14, v0), P(16, v0), P(16, v0 + 5), P(14, v0 + 5)]
        fill(img, pts, hexc('#f2c338'))
    add('road_v', img)


def crosswalk_h_tile():
    """A crossing over the side street: the bars run along the street."""
    img = cell_img(0)
    n = noise(25)
    fill(img, DIAMOND_SCREEN, lambda x, y: ASPHALT.top if n() > 0.1 else ASPHALT.left)
    for v0 in (2, 6, 10, 14):
        pts = [P(1, v0), P(15, v0), P(15, v0 + 2), P(1, v0 + 2)]
        fill(img, pts, (240, 238, 232))
    add('crosswalk_h', img)


def crosswalk_tile():
    img = cell_img(0)
    n = noise(23)
    fill(img, DIAMOND_SCREEN, lambda x, y: ASPHALT.top if n() > 0.1 else ASPHALT.left)
    for u0 in (2, 6, 10, 14):
        pts = [P(u0, 1), P(u0 + 2, 1), P(u0 + 2, 15), P(u0, 15)]
        fill(img, pts, (240, 238, 232))
    add('crosswalk', img)


def block_building(name, w, d, H, wall_hex, roof_hex, awning=None,
                   trim_hex='#fff3d6'):
    """A whole building as one sprite, [w] by [d] cells and [H] tall. Its two
    visible walls are single unbroken faces, with windows set out along them
    in rows, not a row of separate blocks. A street-facing building gets a
    shopfront and an awning along its whole front. The sprite's origin is the
    top vertex of its first cell."""
    wall = ramp(wall_hex)
    roof = ramp(roof_hex)
    trim = ramp(trim_hex)
    glass = hexc('#8cc4e6')
    glass_hi = hexc('#d4eefb')
    U, V = 16 * w, 16 * d
    img = Img(16 * (w + d) + 8, 8 * (w + d) + H + 14, 16 * d + 4, H + 10)
    storey = 16

    def windows(a, z, base, dark):
        c = base
        if int(z) % 4 == 0:
            c = mix(c, dark, 0.14)
        if z < 2:
            return wall.lo
        if z >= H - 4:
            return trim.top  # cornice
        k = int(a) % 12
        zz = (int(z) - 20) % storey if z >= 20 else -1
        if zz >= 0 and 4 <= zz <= 12 and 3 <= k <= 8:
            if zz in (4, 12) or k in (3, 8) or k == 5 and zz > 4:
                return trim.top
            return glass_hi if zz > 9 and k < 6 else glass
        return c

    def south(u, z):
        if awning and z < 18:
            k = int(u) % 28
            if 3 <= k <= 24 and 3 <= z <= 13:
                if k in (3, 24) or z in (3, 13) or k == 14:
                    return trim.right
                return glass_hi if z > 9 and k < 12 else glass
            if z < 2:
                return wall.lo
            return wall.right if z >= 14 else wall.left
        return windows(u, z, wall.left, wall.lo)

    def east(v, z):
        return windows(v, z, wall.right, wall.lo)

    box(img, 0, 0, U, V, 0, H, wall, left=south, right=east, top=roof.top)
    # a parapet round the roof and a few things standing on it
    box(img, 0, 0, U, 3, H, H + 3, trim, edge=False)
    box(img, 0, V - 3, U, V, H, H + 3, trim, edge=False)
    box(img, 0, 3, 3, V - 3, H, H + 3, trim, edge=False)
    box(img, U - 3, 3, U, V - 3, H, H + 3, trim, edge=False)
    unit = ramp('#9aa3b2')
    for i in range(max(1, w // 3)):
        box(img, 16 + i * 40, 20, 34 + i * 40, 34, H + 3, H + 10, unit)
    if awning:
        aw = ramp(awning)
        box(img, 4, V, U - 4, V + 5, 14, 19, aw,
            top=lambda u, v: aw.top if int(u) % 6 < 3 else (250, 246, 238))
    add(name, img, 0.5)


# --------------------------------------------------- the rest of the town

def town_building(name, w, d, H, wall_hex, roof_hex, style, accent,
                  trim_hex='#fff3d6', roof_extra=None):
    """A neighbour of a given [style]: a 'shop' with a shopfront and a sign
    band, 'flats' with windows on every floor and balconies, a glass 'tower',
    or a 'warehouse' with a big door. [w] by [d] cells and [H] tall, as one
    sprite with its origin at the top vertex of its first cell."""
    wall = ramp(wall_hex)
    roof = ramp(roof_hex)
    trim = ramp(trim_hex)
    acc = ramp(accent)
    glass = hexc('#8cc4e6')
    glass_hi = hexc('#d4eefb')
    dark = hexc('#3b4150')
    U, V = 16 * w, 16 * d
    img = Img(16 * (w + d) + 8, 8 * (w + d) + H + 14, 16 * d + 4, H + 10)

    def shop_face(u, z, side):
        base = wall.left if side == 'S' else wall.right
        if z < 2:
            return wall.lo
        if z >= H - 3:
            return trim.top
        # the sign band over the shopfront, with a few "letters"
        if 17 <= z <= 23:
            if z in (17, 23) or u < 3 or u > (U if side == 'S' else V) - 3:
                return acc.lo
            letter = int(u) % 6 < 3 and int(z) % 2 == 0
            return hexc('#fff6dc') if letter else acc.left
        if z < 17:
            span = U if side == 'S' else V
            k = int(u) % 24
            if 3 <= u <= span - 3 and 3 <= z <= 14:
                if k in (0, 1) or z in (3, 14):
                    return trim.top
                if k == 12 and side == 'S':  # a door
                    return dark
                return glass_hi if z > 9 and k < 10 else glass
            return base
        # upper floors: a row of windows
        if H > 30 and 28 <= z <= H - 8:
            k = int(u) % 14
            zz = (int(z) - 28) % 18
            if 4 <= k <= 9 and 3 <= zz <= 12:
                if k in (4, 9) or zz in (3, 12):
                    return trim.top
                return glass
        return base

    def flats_face(u, z, side):
        base = wall.left if side == 'S' else wall.right
        if z < 2:
            return wall.lo
        if z >= H - 3:
            return trim.top
        span = U if side == 'S' else V
        k = int(u) % 16
        zz = (int(z) - 6) % 16
        if z >= 6 and 4 <= k <= 11 and 4 <= zz <= 12 and 4 <= u <= span - 4:
            if k in (4, 11) or zz in (4, 12):
                return trim.top
            return glass_hi if zz > 9 and k < 8 else glass
        # a balcony slab under each floor
        if z >= 6 and zz == 3 and 3 <= k <= 12 and 4 <= u <= span - 4:
            return trim.right
        if z < 14 and 5 <= k <= 10 and 4 <= u <= span - 4 and side == 'S':
            return dark  # the street door and lobby
        return base

    def tower_face(u, z, side):
        base = wall.left if side == 'S' else wall.right
        if z < 2:
            return wall.lo
        if z >= H - 4:
            return trim.top
        span = U if side == 'S' else V
        k = int(u) % 8
        zz = (int(z) - 2) % 8
        if 3 <= u <= span - 3 and 1 <= k <= 6 and 1 <= zz <= 6:
            return glass_hi if (zz > 3 and k < 4) else glass
        return base

    def warehouse_face(u, z, side):
        base = wall.left if side == 'S' else wall.right
        if z < 2:
            return wall.lo
        if z >= H - 3:
            return trim.top
        span = U if side == 'S' else V
        # a roller door, and a band of corrugation
        if side == 'S' and 20 <= u <= 56 and z <= 20:
            return dark if int(z) % 4 else acc.left
        if 3 <= z <= H - 6 and int(u) % 6 == 0:
            return wall.right if side == 'S' else wall.lo
        if H - 14 <= z <= H - 9 and 6 <= u <= span - 6 and int(u) % 14 < 8:
            return glass
        return base

    face = {'shop': shop_face, 'flats': flats_face, 'tower': tower_face,
            'warehouse': warehouse_face}[style]
    box(img, 0, 0, U, V, 0, H, wall,
        left=lambda u, z: face(u, z, 'S'),
        right=lambda v, z: face(v, z, 'E'), top=roof.top)
    # a parapet round the roof
    box(img, 0, 0, U, 3, H, H + 3, trim, edge=False)
    box(img, 0, V - 3, U, V, H, H + 3, trim, edge=False)
    box(img, 0, 3, 3, V - 3, H, H + 3, trim, edge=False)
    box(img, U - 3, 3, U, V - 3, H, H + 3, trim, edge=False)
    # an awning along a shop, or a sign board on a flat roof
    if style == 'shop':
        aw = ramp(accent)
        box(img, 4, V, U - 4, V + 5, 14, 19, aw,
            top=lambda u, v: aw.top if int(u) % 6 < 3 else (250, 246, 238))
    unit = ramp('#9aa3b2')
    extra = roof_extra or ('tank' if style == 'flats' else 'units')
    if extra == 'tank':
        cylinder(img, U // 2, V // 2, 9, H + 3, H + 17, ramp('#8d8f9a'))
    elif extra == 'units':
        for i in range(max(1, w // 3)):
            box(img, 14 + i * 36, 18, 30 + i * 36, 32, H + 3, H + 9, unit)
    elif extra == 'board':
        box(img, 8, V // 2 - 2, U - 8, V // 2 + 2, H + 3, H + 15, acc)
    add(name, img, 0.5)


def hedge():
    img = cell_img(10)
    bush = ramp('#3f8f4a')
    n = noise(71)
    box(img, 1, 3, 15, 13, 0, 9, bush,
        left=lambda u, z: bush.left if n() > 0.2 else bush.top,
        right=lambda v, z: bush.right if n() > 0.2 else bush.left,
        top=lambda u, v: bush.top if n() > 0.25 else bush.hi)
    add('hedge', img, 0.5)


def flower_bed():
    img = cell_img(8)
    wood = ramp('#8d6a4a')
    box(img, 1, 2, 15, 14, 0, 5, wood,
        left=shaded_side(wood.left, wood.hi, wood.lo, 0, 5, ao_rows=1, hi_rows=1),
        right=shaded_side(wood.right, wood.hi, wood.lo, 0, 5, ao_rows=1, hi_rows=1))
    face_top(img, 2, 14, 3, 13, 5, ramp('#5a3f2a').top)
    n = noise(73)
    for _ in range(14):
        cx, cy = P(int(2 + n() * 12), int(3 + n() * 10), 5)
        col = [(240, 90, 120), (250, 220, 90), (250, 250, 240),
               (170, 120, 230)][int(n() * 4) % 4]
        img.put(cx, cy - 1, col)
        img.put(cx, cy, hexc('#3f8f4a'))
    add('flower_bed', img, 0.5)


def broad_tree():
    """A rounder, taller tree than the planter ones, for parks and verges."""
    img = cell_img(60)
    trunk = ramp('#6e4a2c')
    box(img, 7, 7, 9, 9, 0, 22, trunk, edge=False)
    leaf = ramp('#3c9a52')
    leaf_d = ramp('#2a7a45')
    cx, cy = P(8, 8, 28)
    for dx, dy, rx, ry in ((-10, 2, 9, 7), (10, 2, 9, 7), (0, -4, 12, 9),
                           (-6, -12, 9, 7), (6, -12, 9, 7), (0, -18, 8, 6)):
        ellipse(img, cx + dx, cy + dy, rx, ry,
                lambda x, y, dx=dx, dy=dy: (
                    leaf.hi if (x - dx - cx) + (y - dy - cy) < -6 else
                    (leaf.top if (x - dx - cx) + (y - dy - cy) < 0 else
                     (leaf_d.left if (x - dx - cx) + (y - dy - cy) > 6
                      else leaf.left))))
    add('tree_broad', img, 0.5)


def pine_tree():
    img = cell_img(58)
    trunk = ramp('#6e4a2c')
    box(img, 7, 7, 9, 9, 0, 10, trunk, edge=False)
    dark = ramp('#2b6f4d')
    cx, cy = P(8, 8, 8)
    for i, (rx, ry, up) in enumerate(((13, 7, 0), (10, 6, 10), (7, 5, 20),
                                      (4, 3, 29))):
        ellipse(img, cx, cy - up, rx, ry,
                lambda x, y, cx=cx: (dark.top if x < cx - 2 else
                                     (dark.left if x < cx + 3 else dark.right)))
    add('tree_pine', img, 0.5)


def fountain():
    img = cell_img(30)
    stone = ramp('#cfcac2')
    water = hexc('#7cc4ea')
    cu = cv = 8
    cylinder(img, cu, cv, 14, 0, 6, stone)
    cx, cy = P(cu, cv, 6)
    ellipse(img, cx, cy, 11, 5, water)
    cylinder(img, cu, cv, 3, 6, 18, stone)
    ex, ey = P(cu, cv, 18)
    ellipse(img, ex, ey, 7, 3, stone.hi)
    ellipse(img, ex, ey, 5, 2, water)
    for dy in range(-9, 0, 2):
        img.put(ex, ey + dy, (230, 245, 255))
    add('fountain', img, 0.5)


def bus_stop():
    img = cell_img(40)
    post = ramp('#4a5568')
    glass = ramp('#9ad0e8')
    _pl = shaded_side(post.left, post.hi, post.lo, 0, 30, ao_rows=2, hi_rows=2)
    _pr = shaded_side(post.right, post.hi, post.lo, 0, 30, ao_rows=2, hi_rows=2)
    box(img, 1, 5, 3, 7, 0, 30, post, edge=False, left=_pl, right=_pr)
    box(img, 13, 5, 15, 7, 0, 30, post, edge=False, left=_pl, right=_pr)
    face_left(img, 3, 13, 6, 4, 28, glass.top)
    box(img, 0, 3, 16, 10, 30, 33, ramp('#d9453d'))
    # the sign
    box(img, 7, 11, 9, 12, 0, 26, post, edge=False)
    box(img, 5, 11, 11, 12, 22, 29, ramp('#f2c338'), edge=False)
    # a bench inside
    box(img, 3, 7, 13, 10, 5, 8, ramp('#8e5a37'))
    add('bus_stop', img, 0.5)


def postbox():
    img = cell_img(26)
    red = ramp('#d9453d')
    cylinder(img, 8, 8, 6, 0, 18, red)
    box(img, 5, 6, 11, 7, 12, 14, ramp('#2a2036'), edge=False)
    add('postbox', img, 0.5)


def street_bin():
    img = cell_img(18)
    grey = ramp('#6d7790')
    cylinder(img, 8, 8, 5, 0, 11, grey)
    cylinder(img, 8, 8, 6, 11, 13, ramp('#4a5568'))
    add('bin', img, 0.5)


def hydrant():
    img = cell_img(16)
    red = ramp('#d33f33')
    cylinder(img, 8, 8, 3, 0, 9, red)
    cylinder(img, 8, 8, 4, 9, 11, ramp('#a82a22'))
    box(img, 4, 7, 12, 9, 5, 7, red, edge=False)
    add('hydrant', img, 0.5)


def bollards():
    img = cell_img(14)
    post = ramp('#3d4252')
    for u in (3, 8, 13):
        cylinder(img, u, 8, 2, 0, 9, post)
        cx, cy = P(u, 8, 8)
        img.put(cx, cy, (242, 195, 56))
    add('bollards', img, 0.5)


def bike_rack():
    img = cell_img(14)
    steel = ramp('#8a93a6')
    for u in (3, 8, 13):
        box(img, u - 1, 7, u, 9, 0, 9, steel, edge=False)
        box(img, u - 1, 7, u + 3, 9, 9, 10, steel, edge=False)
    add('bike_rack', img, 0.5)


def park_bench():
    img = cell_img(18)
    wood = ramp('#a9733f')
    iron = ramp('#3d4252')
    box(img, 2, 4, 3, 12, 0, 6, iron, edge=False)
    box(img, 13, 4, 14, 12, 0, 6, iron, edge=False)
    box(img, 1, 3, 15, 13, 6, 8, wood)
    box(img, 1, 3, 15, 5, 8, 15, wood,
        left=shaded_side(wood.left, wood.hi, wood.lo, 8, 15, ao_rows=1, hi_rows=1),
        right=shaded_side(wood.right, wood.hi, wood.lo, 8, 15, ao_rows=1, hi_rows=1))
    add('bench_park', img, 0.5)


def park_tile(name, seed):
    img = cell_img(0)
    n = noise(seed)
    g = ramp('#86d063')
    fill(img, DIAMOND_SCREEN, lambda x, y: g.top if n() > 0.15 else g.left)
    for _ in range(5):
        x = int((n() - 0.5) * 22)
        y = int(n() * 10) + 3
        if inside(DIAMOND_SCREEN, x, y):
            img.put(x, y, [(255, 250, 235), (250, 140, 170),
                           (250, 220, 90)][int(n() * 3) % 3])
    add(name, img)


def plaza_tile(name, seed):
    flat_tile(name, ramp('#d6cfc0'), seed, speckle=0.06, seams=True)


def car_park_tile(name, seed, bay):
    img = cell_img(0)
    n = noise(seed)
    fill(img, DIAMOND_SCREEN,
         lambda x, y: ASPHALT.top if n() > 0.12 else ASPHALT.left)
    if bay:
        # a white line along the two long edges of the bay
        line(img, P(1, 1), P(1, 15), (222, 222, 214))
        line(img, P(15, 1), P(15, 15), (222, 222, 214))
    add(name, img)


def neighbourhood():
    # shops, flats, an office and a warehouse: one sprite each
    town_building('shop_bakery', 4, 4, 26, '#f3d7c4', '#b5654a', 'shop',
                  '#e8628a')
    town_building('shop_laundry', 5, 4, 26, '#cfe4f2', '#7d8fa3', 'shop',
                  '#3d8fd1', roof_extra='board')
    town_building('shop_arcade', 5, 4, 30, '#5b4b8a', '#3a3358', 'shop',
                  '#f2c338', roof_extra='board')
    town_building('shop_cafe', 4, 4, 24, '#c9e2b8', '#8c6a4c', 'shop',
                  '#d24b3a')
    town_building('flats_a', 4, 5, 72, '#b86b4e', '#5c5b66', 'flats',
                  '#e8e0d0')
    town_building('flats_b', 4, 5, 60, '#d9c7a2', '#7a6f60', 'flats',
                  '#8a7560')
    town_building('office', 4, 4, 84, '#9fb7cf', '#5d6878', 'tower',
                  '#d8e6f2')
    town_building('warehouse', 6, 5, 26, '#a9adb5', '#6a6f7a', 'warehouse',
                  '#d9453d')
    hedge()
    flower_bed()
    broad_tree()
    pine_tree()
    fountain()
    bus_stop()
    postbox()
    street_bin()
    hydrant()
    bollards()
    bike_rack()
    park_bench()
    park_tile('park_a', 81)
    park_tile('park_b', 82)
    plaza_tile('plaza_a', 83)
    plaza_tile('plaza_b', 84)
    car_park_tile('carpark', 85, False)
    car_park_tile('carpark_bay', 86, True)


def street_lamp():
    img = cell_img(54)
    pole = ramp('#3d4252')
    box(img, 7, 7, 9, 9, 0, 3, pole, edge=False)
    box(img, 7, 7, 9, 9, 3, 44, pole, edge=False,
        left=shaded_side(pole.left, pole.hi, pole.lo, 3, 44, ao_rows=2, hi_rows=2),
        right=shaded_side(pole.right, pole.hi, pole.lo, 3, 44, ao_rows=2, hi_rows=2))
    box(img, 5, 5, 11, 11, 44, 48, pole)
    cx, cy = P(8, 8, 48)
    ellipse(img, cx, cy - 1, 4, 2, hexc('#fff3b0'))
    add('lamp', img, 0.5)


def special_board():
    """The chalkboard that stands outside the door when there is a special: a
    wooden frame, a few chalk lines and a red price tag."""
    img = cell_img(30)
    frame = ramp('#8e5a37')
    # two splayed feet, then the board between them
    box(img, 3, 5, 5, 10, 0, 4, frame, edge=False)
    box(img, 11, 5, 13, 10, 0, 4, frame, edge=False)
    board = ramp('#2f4a40')

    def face(u, z):
        if u < 4 or u > 12 or z < 7 or z > 23:
            return frame.left
        # chalk: a heading, two lines of writing, and a red tag at the corner
        if 19 <= z <= 20 and 5 <= u <= 11:
            return hexc('#f4f1e6')
        if z in (15, 16) and 5 <= u <= 10:
            return hexc('#cfd8d2')
        if z in (11, 12) and 5 <= u <= 8:
            return hexc('#cfd8d2')
        if 9 <= z <= 13 and 9 <= u <= 11:
            return hexc('#d94a3a')
        return board.left

    box(img, 3, 7, 13, 9, 5, 25, frame, edge=False)
    face_left(img, 3, 13, 9, 5, 25, face)
    add('special_board', img, 0.55)


def vending(on=True, cash=False):
    """A vending machine on the pavement outside: a red cabinet with a glass
    front of drinks, a lit sign on top and a coin slot, facing the street.
    Switched off it is the same red machine with its lights out: the glass and
    the sign dark, the coin slot unlit. With
    takings waiting a gold coin floats above it."""
    img = cell_img(54)
    body = ramp('#c9473b')
    dark = ramp('#2c3040')
    # The left (+v) face is entirely redrawn below by `front`; only the
    # right (+u) side profile stays as the plain body colour, so that is
    # the one worth shading here.
    box(img, 3, 4, 13, 12, 0, 36, body,
        right=shaded_side(body.right, body.hi, body.lo, 0, 36, ao_rows=3, hi_rows=2))

    cans = [hexc('#f2c338'), hexc('#4a9de0'), hexc('#e2e8ee'),
            hexc('#6ec16a'), hexc('#e2493f')]

    def front(u, z):
        if u < 4 or u > 12 or z < 2 or z > 35:
            return body.left
        # the sign: a pale strip across the top, dark when it is off
        if z >= 31:
            return hexc('#fff3b0') if on else dark.right
        # the glass: rows of cans on shelves, or just dark glass
        if 15 <= z <= 29 and 5 <= u <= 10:
            if not on:
                return dark.left if int(z) % 5 != 4 else dark.right
            if int(z) % 5 == 4:
                return dark.left
            return cans[(int(u) + int(z) // 5) % len(cans)]
        # the panel: coin slot and a tray
        if 8 <= z <= 13 and 5 <= u <= 11:
            if z == 11 and 7 <= u <= 9:
                return hexc('#f2c338') if on else dark.right
            return dark.left
        if 3 <= z <= 6 and 5 <= u <= 11:
            return dark.right
        return body.left

    face_left(img, 3, 13, 12, 0, 36, front)
    if cash:
        cx, cy = P(8, 8, 46)
        ellipse(img, cx, cy, 5, 5, hexc('#7a5a14'))
        ellipse(img, cx, cy, 4, 4, hexc('#f2c338'))
        ellipse(img, cx - 1, cy - 1, 2, 2, hexc('#ffe58a'))
        rect(img, cx, cy - 3, 1, 6, hexc('#b8841a'))
    add(('vending' if on else 'vending_off') + ('_cash' if cash else ''), img, 0.55)


def street_tree():
    img = cell_img(54)
    planter = ramp('#8d6a4a')
    box(img, 3, 3, 13, 13, 0, 6, planter)
    face_top(img, 4, 12, 4, 12, 6, hexc('#5a3f2a'))
    trunk = ramp('#7b4b2c')
    box(img, 7, 7, 9, 9, 6, 22, trunk, edge=False)
    cx, cy = P(8, 8, 22)
    for dx, dy, rx, ry in ((-7, -3, 7, 5), (7, -3, 7, 5), (0, -9, 8, 6),
                           (-4, -14, 6, 5), (4, -14, 6, 5), (0, -18, 5, 4)):
        ellipse(img, cx + dx, cy + dy, rx, ry,
                lambda x, y, dx=dx, dy=dy: (GREEN.hi if (x - dx - cx) + (y - dy - cy) < -5
                                            else (GREEN.top if (x - dx - cx) + (y - dy - cy) < 0
                                                  else (GREEN_D.top if (x - dx - cx) + (y - dy - cy) > 5
                                                        else GREEN.left))))
    add('tree', img, 0.5)


def front_walls():
    """Low walls along the front and the right, so the room has an edge you
    can see over, and the only way in is the doorway."""
    plaster = ramp('#f1e4c4')
    cap = WOOD
    FH = 11

    def slats(a, z):
        if z >= FH - 2:
            return cap.top
        if z < 2:
            return plaster.lo
        return plaster.left if int(z) % 4 else plaster.right

    img = cell_img(FH + 4)
    box(img, 0, 13, 16, 16, 0, FH, plaster, left=slats,
        right=lambda v, z: plaster.right, top=cap.top)
    add('front_l', img, 0.5)

    # The same wall on the far side of a cell: between the dining room and
    # the yard, low enough to see over.
    img = cell_img(FH + 4)
    box(img, 0, 0, 16, 3, 0, FH, plaster, left=slats,
        right=lambda v, z: plaster.right, top=cap.top)
    add('low_back', img, 0.5)

    img = cell_img(FH + 4)
    box(img, 13, 0, 16, 16, 0, FH, plaster, left=plaster.left,
        right=lambda v, z: (cap.right if z >= FH - 2 else
                            (plaster.lo if z < 2 else
                             (plaster.right if int(z) % 4 else plaster.lo))),
        top=cap.top)
    add('front_r', img, 0.5)


def edge_walls():
    """Walls that stand on the border between two tiles, in the brown
    panelling of the room's own walls: a slab for the stretch between two
    grid points, and a post for each grid point where a wall starts, ends or
    turns. Slabs and posts are the same height and the same thickness, so a
    run is one unbroken wall, and corners, tees and crosses are just posts
    with slabs reaching them. A sprite's origin is the grid point at the top
    of its tile, so the slab 'x' runs from there along x, 'y' along y."""
    H = 14

    def boards(a, z):
        if z < 2:
            return WOOD_D.left
        if z >= H - 2:
            return WOOD.hi
        return WOOD.left if int(a) % 8 else WOOD.right

    def boards_right(a, z):
        if z < 2:
            return WOOD_D.lo
        if z >= H - 2:
            return WOOD.left
        return WOOD.right if int(a) % 8 else WOOD.lo

    def canvas():
        return Img(48, 34, 24, 20)

    img = canvas()
    box(img, 2, -2, 14, 2, 0, H, WOOD, edge=False,
        left=lambda u, z: boards(u, z),
        right=lambda v, z: boards_right(v, z), top=WOOD.top)
    add('wall_edge_x', img, 0.5)

    img = canvas()
    box(img, -2, 2, 2, 14, 0, H, WOOD, edge=False,
        left=lambda u, z: boards(u + 3, z),
        right=lambda v, z: boards_right(v, z), top=WOOD.top)
    add('wall_edge_y', img, 0.5)

    img = canvas()
    box(img, -2, -2, 2, 2, 0, H, WOOD, edge=False,
        left=lambda u, z: boards(1, z),
        right=lambda v, z: boards_right(1, z), top=WOOD.top)
    add('wall_post', img, 0.5)


def pass_edge():
    """The serving hatch, set in a wall on the border between two tiles: the
    same panelled slab as the wall, a steel ledge across it where plates are
    set down from either side, a steel frame over the ledge and a warming
    lamp. Two sprites, for a hatch along x and one along y. Posts stand at its
    ends, as at the ends of any wall."""
    H = 14
    steel = ramp('#b4bccb')
    dark = ramp('#8a93a6')
    lamp = ramp('#f2c338')

    def boards(a, z):
        if z < 2:
            return WOOD_D.left
        if z >= H - 2:
            return WOOD.hi
        return WOOD.left if int(a) % 8 else WOOD.right

    def boards_right(a, z):
        if z < 2:
            return WOOD_D.lo
        if z >= H - 2:
            return WOOD.left
        return WOOD.right if int(a) % 8 else WOOD.lo

    def build(name, along_x):
        img = Img(48, 52, 24, 38)

        def B(u0, v0, u1, v1, z0, z1, r, **kw):
            if along_x:
                box(img, u0, v0, u1, v1, z0, z1, r, **kw)
            else:
                box(img, v0, u0, v1, u1, z0, z1, r, **kw)

        wl = lambda u, z: boards(u, z)
        wr = lambda v, z: boards_right(v, z)
        trim = WOOD_D
        T = 26   # the frame stands well above the low wall beside it

        def W(u0, v0, u1, v1, z0, z1):
            B(u0, v0, u1, v1, z0, z1, WOOD, edge=False, left=wl, right=wr,
              top=WOOD.top)

        # the wall under the opening, two uprights and a beam over it, a dark
        # trim round the opening, a steel counter reaching out on both sides
        # with a lip, and a warm lamp under the beam: a serving window that
        # stands taller than the wall it is set in
        W(2, -2, 14, 2, 0, 8)
        W(2, -2, 4, 2, 8, T)
        W(12, -2, 14, 2, 8, T)
        W(2, -2, 14, 2, 22, T)
        B(4, -2, 5, 2, 8, 22, trim, edge=False)
        B(11, -2, 12, 2, 8, 22, trim, edge=False)
        B(4, -2, 12, 2, 21, 22, trim, edge=False)
        B(4, -4, 12, 4, 8, 9, steel)
        B(4, -5, 12, -4, 7, 9, dark, edge=False)
        B(4, 4, 12, 5, 7, 9, dark, edge=False)
        B(6, -1, 10, 1, 18, 21, lamp, edge=False)
        add(name, img, 0.5)

    build('pass_edge_x', True)
    build('pass_edge_y', False)


def doorway(name, open_):
    img = cell_img(40)
    frame = ramp('#6b3f26')
    _dl = shaded_side(frame.left, frame.hi, frame.lo, 0, 30, ao_rows=2, hi_rows=2)
    _dr = shaded_side(frame.right, frame.hi, frame.lo, 0, 30, ao_rows=2, hi_rows=2)
    box(img, 0, 12, 3, 16, 0, 30, frame, left=_dl, right=_dr)
    box(img, 13, 12, 16, 16, 0, 30, frame, left=_dl, right=_dr)
    box(img, 0, 12, 16, 16, 28, 33, frame)
    # a hanging sign, green when the doors are open and red when they are shut
    plate = ramp('#4cae5a' if open_ else '#d9453d')
    face_left(img, 4, 12, 15, 17, 26, hexc('#2a2036'))
    face_left(img, 5, 11, 15, 18, 25, plate.left)
    face_left(img, 5, 11, 15, 22, 25, plate.top)
    if open_:
        for k in range(3):
            x, y = P(6 + k * 2, 15, 21)
            img.put(x, y, (255, 255, 255))
    else:
        for k in range(4):
            x, y = P(6 + k, 15, 21)
            img.put(x, y, (255, 255, 255))
    add(name, img, 0.5)


def city():
    flat_tile('sidewalk_a', STONE, 31, seams=True)
    flat_tile('sidewalk_b', ramp('#c6c1b9'), 32, seams=True)
    curb_tile()
    road_tile('road_a', False)
    road_tile('road_b', True)
    crosswalk_tile()
    road_v_tile()
    crosswalk_h_tile()
    # under the buildings, where nobody sees it, and the plain pavement
    flat_tile('concrete_a', ramp('#b9b8b2'), 33, speckle=0.12, seams=True)
    flat_tile('concrete_b', ramp('#aeada8'), 34, speckle=0.12, seams=True)
    # the neighbours, each one sprite: sizes match `buildings` in city.dart
    block_building('block_lf', 8, 7, 56, '#c25b45', '#6b6a78', awning='#e2493f')
    block_building('block_lb', 8, 7, 44, '#8fa8c8', '#6b6a78')
    block_building('block_rf', 4, 7, 40, '#e8c9a0', '#9a6a52', awning='#f2c338')
    block_building('block_rb', 4, 7, 52, '#e8d3a3', '#7a7f8c')
    neighbourhood()
    street_lamp()
    special_board()
    vending()
    vending(on=False)
    vending(cash=True)
    vending(on=False, cash=True)
    street_tree()
    emotes()
    moods()
    front_walls()
    edge_walls()
    pass_edge()
    doorway('door_open', True)
    doorway('door_closed', False)


# ----------------------------------------------------------------- emotes
def emotes():
    """Little pictures over someone's head when something happens to them."""
    def bubble():
        b = Img(18, 20, 9, 18)
        ellipse(b, 0, -9, 8, 7.5, (255, 255, 255))
        rect(b, -2, -2, 4, 2, (255, 255, 255))
        rect(b, -1, 0, 2, 1, (255, 255, 255))
        return b

    # a coin: they tipped
    b = bubble()
    ellipse(b, 0, -9, 4.2, 4.2, GOLD.base)
    ellipse(b, 0, -9, 3.0, 3.0, GOLD.top)
    rect(b, -1, -11, 2, 4, GOLD.right)
    rect(b, -3, -11, 1, 1, (255, 252, 230))
    b.outline(0.5)
    add('emote_coin', b)

    # three dots: given up on the queue
    b = bubble()
    for dx in (-4, -1, 2):
        rect(b, dx, -9, 2, 2, hexc('#7a7488'))
    b.outline(0.5)
    add('emote_sigh', b)

    # a green swirl: a table nobody cleared
    b = bubble()
    g = hexc('#58a85a')
    rect(b, -4, -12, 6, 1, g)
    rect(b, -5, -11, 1, 3, g)
    rect(b, -4, -8, 6, 1, g)
    rect(b, 2, -11, 1, 2, g)
    rect(b, -2, -10, 3, 1, g)
    b.outline(0.5)
    add('emote_yuck', b)

    # oops: a sweat drop
    b = bubble()
    cx, cy = 0, -9
    for dy, w in ((-4, 1), (-3, 2), (-2, 3), (-1, 4), (0, 4), (1, 4), (2, 3)):
        rect(b, cx - w // 2 - (w % 2 == 0 and 0), cy + dy, w, 1, hexc('#4aa8e8'))
    rect(b, cx - 2, cy - 1, 1, 1, hexc('#d4f0ff'))
    b.outline(0.5)
    add('emote_oops', b)

    # heart
    b = bubble()
    for x, y in ((-4, -12), (-3, -12), (1, -12), (2, -12)):
        rect(b, x, y, 2, 1, RED.top)
    rect(b, -5, -11, 10, 3, RED.top)
    rect(b, -4, -8, 8, 1, RED.top)
    rect(b, -3, -7, 6, 1, RED.top)
    rect(b, -2, -6, 4, 1, RED.top)
    rect(b, -1, -5, 2, 1, RED.top)
    rect(b, -4, -11, 2, 1, (255, 210, 205))
    b.outline(0.5)
    add('emote_heart', b)

    # star
    b = bubble()
    gold = GOLD.top
    rect(b, -1, -14, 2, 2, gold)
    rect(b, -2, -12, 4, 2, gold)
    rect(b, -5, -11, 10, 2, gold)
    rect(b, -3, -9, 6, 2, gold)
    rect(b, -4, -7, 3, 2, gold)
    rect(b, 1, -7, 3, 2, gold)
    rect(b, -1, -13, 1, 1, (255, 250, 220))
    b.outline(0.5)
    add('emote_star', b)


# ------------------------------------------------------------------- moods
def moods():
    """Four faces for how someone feels about working here."""
    palette = {
        3: hexc('#5cc46a'),  # happy
        2: hexc('#f2c338'),  # content
        1: hexc('#f08a3c'),  # fed up
        0: hexc('#e2493f'),  # about to go
    }
    for m, col in palette.items():
        img = Img(14, 14, 7, 7)
        ellipse(img, 0, 0, 6.2, 6.2, col)
        ellipse(img, -1.5, -1.8, 3.5, 3, lighter(col, 0.35))
        ink = INK
        # eyes
        if m == 0:
            for sx in (-3, 1):
                rect(img, sx, -2, 3, 1, ink)           # angry brows
                rect(img, sx + (1 if sx < 0 else 0), -1, 2, 2, ink)
        else:
            rect(img, -3, -2, 2, 2, ink)
            rect(img, 1, -2, 2, 2, ink)
        # mouth
        if m == 3:
            rect(img, -3, 2, 1, 1, ink)
            rect(img, 2, 2, 1, 1, ink)
            rect(img, -2, 3, 4, 1, ink)
        elif m == 2:
            rect(img, -2, 3, 4, 1, ink)
        elif m == 1:
            rect(img, -2, 2, 4, 1, ink)
            rect(img, -3, 3, 1, 1, ink)
            rect(img, 2, 3, 1, 1, ink)
        else:
            rect(img, -2, 2, 4, 1, ink)
            rect(img, -3, 3, 1, 1, ink)
            rect(img, 2, 3, 1, 1, ink)
        img.outline(0.55)
        add(f'mood_{m}', img)


CAR_COLORS = {
    'red': '#d9473d',
    'blue': '#4a86d6',
    'sun': '#e8b83a',
}
GLASS = ramp('#9fd8ee')
TYRE = ramp('#2f3040')


def car(color, f):
    """A car, two cells long and as wide as a lane, so it stands up against
    the people around it. The canvas origin is the middle of the cell it
    stands in; its front is the end that points along [f]."""
    body = ramp(CAR_COLORS[color])
    img = Img(62, 58, 31, 40)

    def B(a0, b0, a1, b1, z0, z1, r, **kw):
        # (a, b) run along and across the car; the front is at +a.
        if f == 'se':
            u0, v0, u1, v1 = a0, b0, a1, b1
        elif f == 'nw':
            u0, v0, u1, v1 = -a1, -b1, -a0, -b0
        elif f == 'sw':
            u0, v0, u1, v1 = b0, a0, b1, a1
        else:
            u0, v0, u1, v1 = -b1, -a1, -b0, -a0
        box(img, u0, v0, u1, v1, z0, z1, r, **kw)

    shadow(img, 0, 4, 23, 10)
    for a in (-11, 11):
        for b in (-7, 7):
            B(a - 4, b - 1, a + 4, b + 1, 0, 7, TYRE, edge=False)
    B(-17, -7, 17, 7, 3, 12, body,
      left=shaded_side(body.left, body.hi, body.lo, 3, 12),
      right=shaded_side(body.right, body.hi, body.lo, 3, 12))
    # a lower bonnet and boot, a cabin between them
    B(-10, -6, 7, 6, 12, 20, GLASS)
    B(-10, -6, 7, 6, 19, 22, body)
    B(8, -5, 17, 5, 12, 13, ramp('#c9ccd8'), edge=False)
    # lights: yellow at the front, red at the back
    B(17, -6, 19, -3, 6, 9, ramp('#fbe38a'), edge=False)
    B(17, 3, 19, 6, 6, 9, ramp('#fbe38a'), edge=False)
    B(-19, -6, -17, -3, 6, 9, ramp('#d83a3a'), edge=False)
    B(-19, 3, -17, 6, 6, 9, ramp('#d83a3a'), edge=False)
    add(f'car_{color}_{f}', img, 0.5)


def window_ledge():
    """The serving ledge behind the takeaway window, two cells wide, in the
    right-hand wall: a counter top with a paper bag and a bell."""
    img = Img(48, 82, 32, 30)
    body = ramp('#b8743f')
    box(img, 3, 1, 13, 31, 0, 10, body,
        left=shaded_side(body.left, body.hi, body.lo, 0, 10, ao_rows=2, hi_rows=1),
        right=shaded_side(body.right, body.hi, body.lo, 0, 10, ao_rows=2, hi_rows=1))
    box(img, 2, 0, 16, 32, 10, 12, MARBLE)
    box(img, 8, 6, 13, 12, 12, 19, ramp('#d9b98a'))
    face_right(img, 13, 7, 11, 13, 17, hexc('#a97c4f'))
    box(img, 9, 21, 12, 24, 12, 15, GOLD, edge=False)
    box(img, 5, 14, 8, 18, 12, 14, ramp('#4a4f63'))
    add('window_se', img, 0.55)


def window_front():
    """The right-hand wall where the takeaway window is: an opening two cells
    wide to hand things out of, under a striped awning. Two pieces, one for
    each cell."""
    plaster = ramp('#f1e4c4')
    cap = WOOD
    FH = 11
    stripe_a, stripe_b = ramp('#e2493f'), ramp('#fbf3e0')

    def piece(name, pillar, offset):
        img = cell_img(FH + 10, extra_w=16)
        right = lambda v, z: (cap.right if z >= FH - 2 else
                              (plaster.lo if z < 2 else
                               (plaster.right if int(z) % 4 else plaster.lo)))
        lo, hi = pillar
        box(img, 13, lo, 16, hi, 0, FH, plaster, left=plaster.left,
            right=right, top=cap.top)
        rest = (hi, 16) if lo == 0 else (0, lo)
        box(img, 13, rest[0], 16, rest[1], 0, 2, plaster, left=plaster.left,
            right=right, top=cap.top)
        box(img, 13, rest[0], 16, rest[1], 9, FH, plaster, left=plaster.left,
            right=right, top=cap.top)

        def tint(v):
            return stripe_a if int(v + offset) % 4 < 2 else stripe_b
        box(img, 13, 0, 24, 16, FH + 1, FH + 3, stripe_a,
            left=lambda u, z: stripe_a.left,
            right=lambda v, z: tint(v).right,
            top=lambda u, v: tint(v).top)
        add(name, img, 0.5)

    piece('front_win_r0', (0, 3), 0)
    piece('front_win_r1', (13, 16), 16)


def build():
    floor_tile('floor_a', CREAM, 1)
    floor_tile('floor_b', PEACH, 2)
    for k, (sid, hex_a, hex_b) in enumerate(FLOOR_STYLES):
        floor_tile(f'floor_a_s_{sid}', ramp(hex_a), 10 + k)
        floor_tile(f'floor_b_s_{sid}', ramp(hex_b), 20 + k)
    floor_tile('kitchen_a', ramp('#d3e4e6'), 3)
    floor_tile('kitchen_b', ramp('#b3ccd2'), 4)
    floor_tile('kitchenFloor', ramp('#d3e4e6'), 3)
    grass_tile('grass_a', 3)
    grass_tile('grass_b', 4, flowers=True)
    lot_tile()
    mat_tile()
    edge_tiles()
    wall_pieces()
    for sid, wall_hex, trim_hex, pattern in WALL_STYLES:
        wall_pieces(f'_s_{sid}', wall_hex, trim_hex, pattern)
    for f in FACINGS:
        counter(f)
        grill(f)
        fryer(f)
        soda(f)
        espresso(f)
        oven(f)
        freezer(f)
        bench(f)
        jukebox(f)
    for c in CAR_COLORS:
        for f in FACINGS:
            car(c, f)
    window_ledge()
    window_front()
    table()
    long_table('sw')
    long_table('se')
    chair('chair_se', 'su')
    chair('chair_sw', 'sv')
    chair('chair_nw', 'nu')
    chair('chair_ne', 'nv')
    for s in SEAT_STYLES:
        sid = s['id']
        suffix = f'_s_{sid}'
        chair_seat, chair_wood = ramp(s['chair_seat']), ramp(s['chair_wood'])
        chair(f'chair_se{suffix}', 'su', seat=chair_seat, wood=chair_wood)
        chair(f'chair_sw{suffix}', 'sv', seat=chair_seat, wood=chair_wood)
        chair(f'chair_nw{suffix}', 'nu', seat=chair_seat, wood=chair_wood)
        chair(f'chair_ne{suffix}', 'nv', seat=chair_seat, wood=chair_wood)
        bench_seat = ramp(s['bench_seat'])
        for f in FACINGS:
            bench(f, suffix=suffix, seat=bench_seat, base=s['bench_base'])
        cloth = ramp(s['cloth'])
        table(suffix=suffix, cloth=cloth,
              light=s['cloth_light'], pale=s['cloth_pale'])
        long_table('sw', suffix=suffix, cloth=cloth,
                   light=s['cloth_light'], pale=s['cloth_pale'])
        long_table('se', suffix=suffix, cloth=cloth,
                    light=s['cloth_light'], pale=s['cloth_pale'])
    plant()
    wall_tv('sw')
    wall_tv('se')
    rug()
    people_sprites()
    icons()
    city()


def sheet(path, scale=3):
    names = sorted(SPRITES)
    cols = 8
    cw = 64
    ch = 80
    rows = (len(names) + cols - 1) // cols
    img = Img(cols * cw, rows * ch, 0, 0)
    for y in range(img.h):
        for x in range(img.w):
            img.p[y][x] = (236, 236, 228) if ((x // 8) + (y // 8)) % 2 else (226, 226, 218)
    for i, n in enumerate(names):
        s = SPRITES[n]
        ox = (i % cols) * cw + cw // 2
        oy = (i // cols) * ch + ch - 22
        for y in range(s.h):
            for x in range(s.w):
                c = s.p[y][x]
                if c is not None:
                    img.put(ox + x - s.ox, oy + y - s.oy, c)
    # upscale
    big = Img(img.w * scale, img.h * scale, 0, 0)
    for y in range(img.h):
        for x in range(img.w):
            c = img.p[y][x]
            for dy in range(scale):
                for dx in range(scale):
                    big.p[y * scale + dy][x * scale + dx] = c
    big.save(path)
    return names


if __name__ == '__main__':
    build()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith('.png') or f == 'manifest.txt':
            os.remove(os.path.join(OUT, f))
    with open(os.path.join(OUT, 'manifest.txt'), 'w') as m:
        m.write('# name width height anchor_x anchor_y trim_x trim_y trim_w trim_h\n')
        m.write('# (generated by tools/gen_diner_art.py)\n')
        for n, s in sorted(SPRITES.items()):
            s.save(os.path.join(OUT, n + '.png'))
            xs = [x for y in range(s.h) for x in range(s.w) if s.p[y][x] is not None]
            ys = [y for y in range(s.h) for x in range(s.w) if s.p[y][x] is not None]
            tx, ty = (min(xs), min(ys)) if xs else (0, 0)
            tw, th = (max(xs) - tx + 1, max(ys) - ty + 1) if xs else (1, 1)
            m.write(f'{n} {s.w} {s.h} {s.ox} {s.oy} {tx} {ty} {tw} {th}\n')
    if '--sheet' in sys.argv:
        sheet(sys.argv[sys.argv.index('--sheet') + 1])
    print(len(SPRITES), 'sprites')
