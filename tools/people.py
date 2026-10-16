"""Parametric chibi people for the diner.

One renderer draws every character from a spec: skin, hair style, outfit. The
origin (0, 0) is the point between the feet; y is negative upward. Characters
face down-left (`sw`) or up-left (`nw`); the other two facings are mirrors.
"""
from iso import *

SKINS = {
    'light': ramp('#f8cfa9'),
    'tan': ramp('#e3a877'),
    'brown': ramp('#c98f64'),
    'pale': ramp('#fbdcc2'),
}
INK = hexc('#2a2036')
SHOE = ramp('#5a4a63')
WHITE = (255, 255, 255)


class Spec:
    def __init__(self, hair, hair_style='short', top='tee', shirt='#6fb1e8',
                 bottom='pants', pants='#3f4c7a', skin='light', extra=None,
                 child=False, glasses=False, cap=None, trim=None, shoe=None):
        self.hair = ramp(hair)
        self.hair_style = hair_style
        self.top = top
        self.shirt = ramp(shirt)
        self.bottom = bottom
        self.pants = ramp(pants)
        self.skin = SKINS[skin]
        self.extra = extra
        self.child = child
        self.glasses = glasses
        self.cap = ramp(cap) if cap else None
        self.trim = ramp(trim) if trim else None
        self.shoe = ramp(shoe) if shoe else SHOE


def rect_(img, x, y, w, h, c):
    rect(img, x, y, w, h, c)


def shaded_rect(img, x, y, w, h, r, hi_row=True):
    """A block lit from the upper left: light left, dark right."""
    for i in range(w):
        col = r.top if i < max(1, w // 3) else (r.right if i >= w - max(1, w // 3) else r.left)
        rect(img, x + i, y, 1, h, col)
    if hi_row:
        rect(img, x, y, w, 1, r.hi)


def limb(img, x0, y0, x1, y1, w, c_light, c_dark):
    """A slanted limb from (x0, y0) to (x1, y1), [w] wide."""
    n = max(abs(y1 - y0), 1)
    for k in range(n + 1):
        t = k / n
        x = x0 + round((x1 - x0) * t)
        y = y0 + k
        for i in range(w):
            img.put(x + i, y, c_light if i < w / 2 else c_dark)


# Frames: which foot leads, how high the body bobs, how the arms swing.
FRAMES = {
    's0': dict(bob=0, lead=0, lift=0),
    's1': dict(bob=-1, lead=0, lift=0),
    '0': dict(bob=0, lead=1, lift=0),
    '1': dict(bob=-1, lead=0, lift=1),
    '2': dict(bob=0, lead=-1, lift=0),
    '3': dict(bob=-1, lead=0, lift=-1),
}


def draw(spec, facing, frame, seated=False):
    f = FRAMES.get(frame, FRAMES['s0'])
    img = Img(32, 52, 16, 44)
    bob = f['bob']
    lead = f['lead']
    lift = f['lift']
    back = facing == 'nw'
    # direction of travel on screen for this facing
    fx, fy = (-2, 1) if not back else (-2, -1)

    legh = 6 if spec.child else 8
    hip = -legh
    torso_h = 8 if spec.child else 10
    sh_y = hip - torso_h  # shoulder line (top of torso)
    head_c = sh_y - (5 if spec.child else 6)
    skin = spec.skin
    shirt = spec.shirt
    pants = spec.pants

    # ---------------------------------------------------------------- legs
    if not seated:
        for side in (-1, 1):  # -1: screen-left leg, +1: screen-right leg
            amt = 0
            if lead == 1:
                amt = 1 if side == -1 else -1
            elif lead == -1:
                amt = -1 if side == -1 else 1
            dx = fx * amt
            dy = fy * amt
            up = 0
            if lift == 1 and side == 1:
                up = -2
            if lift == -1 and side == -1:
                up = -2
            hx = side * 2 - 1
            if spec.bottom == 'longskirt':
                # feet peek out under the hem
                rect(img, hx + dx, -1 + dy + up, 3, 2, spec.shoe.left)
                continue
            foot_y = dy + up
            if spec.bottom in ('pants', 'shorts'):
                long_leg = spec.bottom == 'pants'
                end = foot_y if long_leg else hip + 3
                limb(img, hx, hip, hx + (dx if long_leg else dx // 2), end, 3,
                     pants.left if side == -1 else pants.left,
                     pants.right)
                if not long_leg:
                    limb(img, hx + dx // 2, end + 1, hx + dx, foot_y, 3, skin.left, skin.right)
            else:  # skirt / dress: bare legs
                limb(img, hx, hip + 2, hx + dx, foot_y, 3, skin.left, skin.right)
            # shoe
            sx = hx + dx - 1
            rect(img, sx, foot_y - 1, 5, 2, spec.shoe.left)
            rect(img, sx, foot_y - 1, 5, 1, spec.shoe.top)
            rect(img, sx + 3, foot_y, 2, 1, spec.shoe.lo)

    # ---------------------------------------------------------------- torso
    top_y = sh_y + bob
    if spec.bottom == 'longskirt' and not seated:
        # a long skirt from the waist to just above the shoes
        for r in range(legh):
            w = 10 + r // 2
            x0 = -w // 2
            y = hip + r + bob // 2
            for i in range(w):
                col = pants.top if i < w // 3 else (pants.right if i >= w - w // 3 else pants.left)
                img.put(x0 + i, y, col)
        rect(img, -6, -2, 13, 1, pants.lo)
    th = torso_h
    if spec.top == 'dress':
        # bodice then a flared skirt down to the knee
        shaded_rect(img, -5, top_y, 10, 5, shirt)
        for r in range(7):
            w = 10 + r
            x0 = -w // 2
            y = top_y + 5 + r
            for i in range(w):
                col = shirt.top if i < w // 3 else (shirt.right if i >= w - w // 3 else shirt.left)
                img.put(x0 + i, y, col)
        rect(img, -6, top_y + 11, 13, 1, shirt.lo)
    else:
        shaded_rect(img, -5, top_y, 10, th, shirt)
        # belt / waist line
        if spec.top in ('tee', 'hoodie', 'cardigan', 'jacket'):
            rect(img, -5, top_y + th - 1, 10, 1, pants.lo if spec.bottom == 'pants' else shirt.lo)

    # a waiter's long white apron
    if spec.extra == 'apron' and not seated:
        if not back:
            rect(img, -4, top_y + 3, 8, th - 2, WHITE)
            rect(img, 1, top_y + 3, 3, th - 2, hexc('#e6dff0'))
            rect(img, -4, top_y + th - 1, 8, 1, hexc('#cfc6e0'))
            img.put(-1, top_y + 5, GOLD_BTN)
        else:
            rect(img, -5, top_y + th - 4, 10, 1, WHITE)
            rect(img, -1, top_y + th - 3, 2, 3, WHITE)

    # collar / front details
    if spec.top == 'jacket':
        # double-breasted chef jacket with gold buttons
        if not back:
            rect(img, -1, top_y + 1, 1, th - 2, shirt.lo)
            for k in range(3):
                img.put(-3, top_y + 3 + k * 2, GOLD_BTN)
                img.put(2, top_y + 3 + k * 2, GOLD_BTN)
            rect(img, -5, top_y, 4, 2, shirt.hi)
            # neckerchief
            rect(img, -3, top_y - 1, 6, 2, RED_SCARF)
            img.put(0, top_y + 1, RED_SCARF)
        else:
            rect(img, -3, top_y, 6, 1, shirt.lo)
    elif spec.top == 'hoodie':
        rect(img, -5, top_y - 1, 10, 2, shirt.top)  # hood bunched at the neck
        rect(img, -4, top_y + 1, 8, 1, shirt.lo)
        if not back:
            rect(img, -3, top_y + th - 4, 6, 2, shirt.lo)  # pocket
            img.put(-1, top_y + 2, shirt.hi)
            img.put(1, top_y + 2, shirt.hi)
    elif spec.top == 'cardigan':
        if not back:
            rect(img, 0, top_y, 1, th, shirt.lo)
            rect(img, -2, top_y, 4, 1, WHITE)
            for k in range(2):
                img.put(-2, top_y + 3 + k * 3, shirt.hi)
        else:
            rect(img, -4, top_y + 2, 8, 1, shirt.lo)
    elif spec.top in ('tee', 'dress'):
        rect(img, -2, top_y, 4, 1, skin.left)  # round neckline
        if spec.extra == 'stripe' and not back:
            for r in (3, 6):
                rect(img, -5, top_y + r, 10, 1, shirt.hi)

    # ---------------------------------------------------------------- arms
    swing = 0
    if lead == 1:
        swing = 1
    elif lead == -1:
        swing = -1
    sleeve_long = spec.top in ('hoodie', 'cardigan', 'jacket')
    for side in (-1, 1):
        sx = -7 if side == -1 else 5
        s = swing if side == -1 else -swing
        ax = sx + (s * (fx // 2) if False else 0)
        hand_x = sx + (-s if not back else s)
        hand_y = top_y + th - 3 + (1 if s > 0 else 0) + (0 if not seated else -1)
        if seated:
            hand_x = sx + (side * -1)
        arm_len = hand_y - (top_y + 1)
        sleeve_end = top_y + 1 + (arm_len if sleeve_long else min(arm_len, 3))
        limb(img, sx, top_y + 1, hand_x, sleeve_end, 2,
             shirt.left if side == -1 else shirt.right,
             shirt.right if side == 1 else shirt.left)
        if not sleeve_long:
            limb(img, hand_x, sleeve_end + 1, hand_x, hand_y, 2, skin.left, skin.right)
        # hand
        rect(img, hand_x, hand_y, 2, 2, skin.left if side == -1 else skin.right)

    # ---------------------------------------------------------------- head
    hy = head_c + bob
    hr_x, hr_y = (6.4, 5.8) if not spec.child else (6.8, 6.2)
    # neck
    rect(img, -2, top_y - 2, 4, 3, skin.right)
    # head with light on the upper left
    ellipse(img, 0, hy, hr_x, hr_y, skin.left)
    ellipse(img, -1.4, hy - 1.2, hr_x - 2.2, hr_y - 2.2, skin.top)
    # shade down the right edge and under the chin
    for y in range(int(hy - hr_y), int(hy + hr_y) + 2):
        for x in (5, 6):
            if img.solid(x, y) and (x * x) / (hr_x * hr_x) + ((y - hy) ** 2) / (hr_y * hr_y) > 0.55:
                img.put(x, y, skin.right)
    rect(img, -4, int(hy + hr_y) - 1, 8, 1, skin.right)

    if not back:
        # ears (just the right one shows, as the face turns left)
        rect(img, 6, hy, 2, 3, skin.right)
        img.put(6, hy + 1, skin.lo)
        # eyes with a catch-light, brows, blush, nose, mouth
        for ex in (-4, 0):
            rect(img, ex, hy - 1, 2, 3, INK)
            img.put(ex, hy - 1, WHITE)
            img.put(ex + 1, hy + 1, (60, 40, 90))
            rect(img, ex - 1 if ex < 0 else ex, hy - 3, 3, 1, spec.hair.lo)
        rect(img, -5, hy + 2, 2, 1, BLUSH)
        rect(img, 1, hy + 2, 2, 1, BLUSH)
        img.put(-2, hy + 1, skin.right)
        rect(img, -3, hy + 3, 3, 1, MOUTH)
        if spec.glasses:
            for ex in (-5, -1):
                rect(img, ex, hy - 2, 4, 1, GLASS)
                rect(img, ex, hy + 2, 4, 1, GLASS)
                rect(img, ex, hy - 2, 1, 5, GLASS)
                rect(img, ex + 3, hy - 2, 1, 5, GLASS)
            rect(img, -1, hy - 1, 1, 1, GLASS)
    else:
        # left ear peeks out on the far side
        rect(img, -8, hy, 2, 3, skin.left)

    hair(img, spec, back, hy, hr_x, hr_y)

    if spec.cap is not None:
        cap = spec.cap
        ellipse(img, 0, hy - 3.2, 7.2, 4.6, cap.left)
        ellipse(img, -2, hy - 4.5, 4.5, 2.6, cap.top)
        rect(img, -7, int(hy - 3), 14, 2, cap.right)
        if not back:
            rect(img, -10, int(hy - 2), 8, 2, cap.hi)   # brim toward the viewer
            rect(img, -10, int(hy), 8, 1, cap.lo)
        else:
            rect(img, 1, int(hy - 3), 3, 1, cap.hi)

    if spec.top == 'jacket':
        toque(img, hy)

    if seated:
        # Only the upper body: legs are hidden by the table and chair.
        for y in range(img.h):
            for x in range(img.w):
                pass
    return img


GOLD_BTN = hexc('#f2c338')
RED_SCARF = hexc('#e2493f')
BLUSH = hexc('#f7a39c')
MOUTH = hexc('#c4565f')
GLASS = hexc('#f4efe6')


def hair(img, spec, back, hy, rx, ry):
    h = spec.hair
    st = spec.hair_style
    top = int(hy - ry)
    if st == 'none':
        return

    def cap_ellipse(extra_rx=0.8, extra_ry=0.6, dy=-0.8):
        ellipse(img, 0, hy + dy, rx + extra_rx, ry + extra_ry,
                lambda x, y: h.top if (x + y) < hy - 4 else (h.right if x > 3 else h.left))

    if st in ('short', 'spiky', 'ponytail', 'bun', 'long', 'bob'):
        if back:
            cap_ellipse(0.9, 0.9, 0.2)
            rect(img, -4, int(hy + ry) - 2, 8, 3, h.right)  # nape
            rect(img, -5, top, 4, 1, h.hi)
        else:
            # hair on the crown and a fringe over the forehead, sides tucked
            for x in range(-7, 8):
                for y in range(top - 2, int(hy) + 1):
                    nx = x / (rx + 0.9)
                    ny = (y - (hy - 0.8)) / (ry + 0.6)
                    if nx * nx + ny * ny > 1:
                        continue
                    fringe = hy - 3 + (1 if (x % 3 == 0) else 0) + (1 if x < -3 else 0)
                    if y <= fringe or abs(x) >= 6:
                        c = h.top if (x + y) < hy - 5 else (h.right if x > 3 else h.left)
                        img.put(x, y, c)
            rect(img, -5, top, 4, 1, h.hi)
            rect(img, 3, int(hy) - 3, 3, 3, h.right) if st != 'bob' else None
    if st == 'spiky':
        for sx, hgt in ((-4, 3), (-1, 4), (2, 3), (5, 2)):
            for k in range(hgt):
                img.put(sx, top - 1 - k, h.left if k else h.top)
                img.put(sx + 1, top - 1 - k + 1, h.right)
    elif st == 'long':
        if back:
            rect(img, -7, int(hy), 14, 9, h.left)
            rect(img, 2, int(hy), 5, 9, h.right)
            rect(img, -7, int(hy) + 8, 14, 1, h.lo)
        else:
            rect(img, -8, int(hy) - 1, 3, 9, h.left)
            rect(img, 5, int(hy) - 1, 3, 9, h.right)
            rect(img, -8, int(hy) + 8, 3, 1, h.lo)
            rect(img, 5, int(hy) + 8, 3, 1, h.lo)
    elif st == 'bob':
        for side, col in ((-8, h.left), (5, h.right)):
            rect(img, side, int(hy) - 1, 3, 6, col)
        if back:
            rect(img, -7, int(hy), 14, 5, h.left)
            rect(img, 2, int(hy), 5, 5, h.right)
    elif st == 'ponytail':
        if back:
            rect(img, 1, int(hy) - 1, 4, 3, hexc('#e2493f'))  # scrunchie
            rect(img, 1, int(hy) + 2, 4, 8, h.left)
            rect(img, 3, int(hy) + 2, 2, 8, h.right)
        else:
            rect(img, 6, int(hy) - 2, 3, 3, hexc('#e2493f'))
            rect(img, 6, int(hy) + 1, 3, 7, h.right)
    elif st == 'bun':
        ellipse(img, 0, top - 2.5, 3.4, 3.0, lambda x, y: h.top if x < 0 else h.right)
        rect(img, -1, top - 5, 2, 1, h.hi)


def toque(img, hy):
    """The chef's tall hat."""
    W = (255, 255, 255)
    W2 = hexc('#e6dff0')
    W3 = hexc('#cfc6e0')
    band_y = int(hy) - 6
    rect(img, -7, band_y, 14, 3, W)
    rect(img, 3, band_y, 4, 3, W2)
    rect(img, -7, band_y + 2, 14, 1, W3)
    for dx, dy, rx, ry in ((-4, -4, 4.5, 3.6), (4, -4, 4.5, 3.6), (0, -8, 6, 4.5)):
        ellipse(img, dx, band_y + dy, rx, ry,
                lambda x, y, dx=dx: W if x < dx + 1 else W2)
    for k in range(3):
        img.put(-3 + k * 3, band_y - 7 + (k % 2), W3)
