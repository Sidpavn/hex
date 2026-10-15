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
    # survey stake at the top corner
    box(img, 6, 6, 8, 8, 0, 9, WOOD)
    rect(img, P(6, 6, 9)[0] + 0, P(6, 6, 9)[1] - 1, 2, 1, RED.top)
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


def wall_pieces():
    wall = ramp('#a6e0d1')
    trim = ramp('#fff3d6')
    rail = WOOD

    def wallpaper(a, z):
        # a = along-wall coordinate
        c = wall.left
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
        add(name, img)

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
        add(name, img)

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
    add('wall_corner', img)


# -------------------------------------------------------------- fixtures
def counter():
    img = cell_img(30)
    body = ramp('#b8743f')
    box(img, 1, 1, 15, 15, 0, 13, body,
        left=lambda u, z: (body.lo if z < 2 else
                           (body.hi if z > 11 else
                            (body.right if (3 <= u <= 12 and 3 <= z <= 9 and
                                            (u in (3, 12) or z in (3, 9))) else body.left))),
        right=lambda v, z: (body.lo if z < 2 else (body.right if z <= 11 else body.left)))
    # marble top slab, slightly proud
    box(img, 0, 0, 16, 16, 13, 15, MARBLE,
        top=lambda u, v: MARBLE.top if (int(u + v * 0.7) % 7) else MARBLE.left)
    # a mug and a little bell
    box(img, 9, 8, 13, 12, 15, 19, RED)
    face_top(img, 10, 12, 9, 11, 19, hexc('#5a3322'))
    box(img, 3, 4, 6, 7, 15, 17, GOLD)
    add('counter', img, 0.55)


def grill():
    img = cell_img(40)
    # steel base cabinet
    box(img, 1, 1, 15, 15, 0, 12, STEEL,
        left=lambda u, z: (STEEL.lo if z < 2 else
                           (STEEL.right if (u in (2, 14) or z == 11) else STEEL.left)))
    # knobs on the front
    for k, col in enumerate((GOLD.top, RED.top, GOLD.top)):
        x, y = P(4 + k * 4, 15, 6)
        rect(img, x, y, 2, 2, col)
        img.put(x, y, lighter(col, 0.5))
    # recessed hot plate
    box(img, 2, 2, 14, 14, 12, 13, STEEL_D)
    face_top(img, 3, 13, 3, 13, 13, hexc('#3b3445'))
    # patties
    for (u, v) in ((5, 5), (9, 8)):
        ellipse(img, *P(u + 2, v + 2, 13), 4, 2, hexc('#8a4b2d'))
        ellipse(img, P(u + 2, v + 2, 13)[0] - 1, P(u + 2, v + 2, 13)[1] - 1, 2, 1, hexc('#b86a3f'))
    # glowing embers at the front
    for k in range(5):
        x, y = P(5 + k * 2, 13, 13)
        img.put(x, y, hexc('#ff8a3d') if k % 2 else hexc('#ffc457'))
    # back panel with vents and a hood
    box(img, 1, 1, 15, 4, 13, 26, STEEL)
    for k in range(3):
        face_left(img, 4 + k * 3, 6 + k * 3, 4, 17, 22, STEEL.lo)
    box(img, 0, 0, 16, 6, 26, 30, STEEL_D)
    add('grill', img, 0.55)


def table():
    img = cell_img(34)
    # pedestal and foot
    cylinder(img, 8, 8, 5, 0, 2, ramp('#5b5266'))
    cylinder(img, 8, 8, 2, 2, 10, ramp('#8d8499'))
    # tablecloth top: red/white check, in an iso ellipse
    cx, cy = P(8, 8, 11)
    rx, ry = 14, 7
    def check(x, y):
        u = (y + 11) + x / 2.0
        v = (y + 11) - x / 2.0
        su, sv = int(u // 5) % 2, int(v // 5) % 2
        if su and sv:
            return RED.top
        if su or sv:
            return hexc('#f7b3aa')
        return hexc('#fff6e8')
    # drape: a darker band under the rim
    ellipse(img, cx, cy + 2, rx, ry, RED.right)
    ellipse(img, cx, cy + 1, rx, ry, RED.left)
    ellipse(img, cx, cy, rx, ry, check)
    # little flower in a vase
    box(img, 7, 7, 9, 9, 11, 14, ramp('#9ccbe8'))
    x, y = P(8, 8, 16)
    img.put(x, y, PINK.top)
    img.put(x - 1, y, PINK.hi)
    img.put(x + 1, y, PINK.hi)
    img.put(x, y - 1, PINK.hi)
    img.put(x, y + 1, GOLD.top)
    add('table', img, 0.55)


def chair(name, back):
    img = cell_img(26)
    leg = ramp('#7b4b2c')
    for (u, v) in ((3, 3), (11, 3), (3, 11), (11, 11)):
        box(img, u, v, u + 2, v + 2, 0, 7, leg, edge=False)
    box(img, 2, 2, 14, 14, 7, 9, WOOD)
    box(img, 3, 3, 13, 13, 9, 11, RED)
    h = 22
    if back == 'su':   # back on the low-u side (facing +u / SE)
        box(img, 2, 2, 4, 14, 9, h, WOOD)
    elif back == 'sv':  # facing +v / SW
        box(img, 2, 2, 14, 4, 9, h, WOOD)
    elif back == 'nu':  # facing -u / NW: back on the high-u side, kept low
        box(img, 12, 2, 14, 14, 9, 15, WOOD)
    else:               # facing -v / NE
        box(img, 2, 12, 14, 14, 9, 15, WOOD)
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


def jukebox():
    img = cell_img(46)
    body = ramp('#d9453d')
    box(img, 2, 3, 14, 13, 0, 30, body, edge=False)
    # base plinth
    box(img, 1, 2, 15, 14, 0, 3, WOOD_D, edge=False)
    # arched top: stepped boxes
    box(img, 3, 4, 13, 12, 30, 33, body, edge=False)
    box(img, 5, 5, 11, 11, 33, 35, body)
    # front glass (the +v face) as an arched window
    a0, a1, z0, z1 = 4, 12, 12, 30
    def glass(u, z):
        k = (z - z0) / (z1 - z0)
        if z > z1 - 3 and (u < a0 + 1 or u > a1 - 2):
            return body.left
        bands = [hexc('#5fd3d0'), hexc('#7ee0a0'), hexc('#ffd35a'), hexc('#ff9a5a'), hexc('#ff6f8a')]
        return bands[int(k * len(bands)) % len(bands)]
    face_left(img, a0, a1, 13, z0, z1, glass)
    face_left(img, a0 - 1, a0, 13, z0, z1, GOLD.top)
    face_left(img, a1, a1 + 1, 13, z0, z1, GOLD.top)
    # speaker grille and coin slot on the lower front
    for k in range(4):
        face_left(img, 5 + k * 2, 6 + k * 2, 13, 5, 10, body.lo)
    face_left(img, 9, 11, 13, 7, 8, GOLD.top)
    # side speaker (the +u face)
    for k in range(3):
        for j in range(3):
            x, y = P(14, 5 + k * 2, 8 + j * 4)
            img.put(x, y, body.lo)
    add('jukebox', img, 0.55)


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


def bench():
    img = cell_img(30, extra_w=32)
    img.ox = 16
    seat = PINK
    box(img, 1, 2, 31, 14, 0, 7, ramp('#b3576f'), edge=False)
    box(img, 1, 3, 31, 14, 7, 10, seat)
    box(img, 1, 2, 31, 5, 10, 22, seat,
        left=lambda u, z: (seat.hi if z > 20 else (seat.left if int(u) % 6 else seat.right)))
    add('bench', img, 0.55)


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
    # plate with a burger
    p = Img(16, 12, 8, 7)
    ellipse(p, 0, 0, 7, 3.5, (250, 250, 246))
    ellipse(p, 0, 0, 5, 2.4, (222, 226, 236))
    ellipse(p, 0, -2, 4, 2, hexc('#e8a04a'))
    rect(p, -4, -1, 8, 1, GREEN.top)
    rect(p, -4, 0, 8, 1, hexc('#8a4b2d'))
    ellipse(p, 0, 1, 4, 1.5, hexc('#d9904a'))
    rect(p, -2, -4, 2, 1, hexc('#fff0c8'))
    p.outline(0.55)
    add('plate', p)
    # order bubble with a burger
    b = Img(20, 20, 10, 18)
    ellipse(b, 0, -8, 9, 7.5, (255, 255, 255))
    rect(b, -2, -2, 4, 2, (255, 255, 255))
    rect(b, -1, 0, 2, 1, (255, 255, 255))
    ellipse(b, 0, -11, 5, 2.5, hexc('#e8a04a'))
    rect(b, -5, -10, 10, 1, GREEN.top)
    rect(b, -5, -9, 10, 1, hexc('#8a4b2d'))
    ellipse(b, 0, -7, 5, 2, hexc('#d9904a'))
    rect(b, -2, -13, 2, 1, hexc('#fff0c8'))
    b.outline(0.5)
    add('bubble', b)


def build():
    floor_tile('floor_a', CREAM, 1)
    floor_tile('floor_b', PEACH, 2)
    grass_tile('grass_a', 3)
    grass_tile('grass_b', 4, flowers=True)
    lot_tile()
    mat_tile()
    edge_tiles()
    wall_pieces()
    counter()
    grill()
    table()
    chair('chair_se', 'su')
    chair('chair_sw', 'sv')
    chair('chair_nw', 'nu')
    chair('chair_ne', 'nv')
    plant()
    jukebox()
    rug()
    bench()
    people_sprites()
    icons()


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
