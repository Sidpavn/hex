"""Tiny isometric pixel-art toolkit for the diner sprites.

World units: one grid cell is 16 x 16 along u (right-down) and v (left-down),
z is height. A point projects to screen as (u - v, (u + v) / 2 - z), so a cell
diamond is 32 wide and 16 tall, and (0, 0, 0) is the cell's top vertex.
Light comes from the upper left: tops are brightest, +v faces (left) are
mid, +u faces (right) are darkest. Shadows lean cool, lights lean warm.
"""
import math
import struct
import zlib

Color = tuple


def hexc(s):
    s = s.lstrip('#')
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


WARM = (255, 238, 196)
COOL = (52, 34, 84)


def lighter(c, t=0.25):
    return mix(c, WARM, t)


def darker(c, t=0.3):
    return mix(c, COOL, t)


class Ramp:
    """Five tones of one material."""

    def __init__(self, base):
        self.base = base
        self.hi = lighter(base, 0.45)
        self.top = lighter(base, 0.22)
        self.left = base
        self.right = darker(base, 0.30)
        self.lo = darker(base, 0.50)


def ramp(h):
    return Ramp(hexc(h) if isinstance(h, str) else h)


class Img:
    def __init__(self, w, h, ox, oy):
        self.w, self.h, self.ox, self.oy = w, h, ox, oy
        self.p = [[None] * w for _ in range(h)]

    def put(self, x, y, c):
        x += self.ox
        y += self.oy
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.p[y][x] = c

    def get(self, x, y):
        x += self.ox
        y += self.oy
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.p[y][x]
        return None

    def solid(self, x, y):
        return self.get(x, y) is not None

    def blit(self, other, dx=0, dy=0):
        for y in range(other.h):
            for x in range(other.w):
                c = other.p[y][x]
                if c is not None:
                    self.put(x - other.ox + dx, y - other.oy + dy, c)

    def flipped(self):
        o = Img(self.w, self.h, self.w - 1 - self.ox, self.oy)
        for y in range(self.h):
            for x in range(self.w):
                o.p[y][self.w - 1 - x] = self.p[y][x]
        return o

    def outline(self, amount=0.55, inner=None):
        """Selective outline: edge pixels become a darker, cooler shade of
        themselves, so the sprite keeps its size."""
        edge = []
        for y in range(self.h):
            for x in range(self.w):
                c = self.p[y][x]
                if c is None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < self.w and 0 <= ny < self.h) or self.p[ny][nx] is None:
                        edge.append((x, y))
                        break
        for x, y in edge:
            self.p[y][x] = darker(self.p[y][x], amount)
        return self

    def save(self, path):
        raw = bytearray()
        for row in self.p:
            raw.append(0)
            for c in row:
                if c is None:
                    raw += b'\x00\x00\x00\x00'
                else:
                    raw += bytes((c[0], c[1], c[2], c[3] if len(c) > 3 else 255))

        def chunk(t, d):
            c = struct.pack('>I', len(d)) + t + d
            return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

        png = b'\x89PNG\r\n\x1a\n'
        png += chunk(b'IHDR', struct.pack('>IIBBBBB', self.w, self.h, 8, 6, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
        png += chunk(b'IEND', b'')
        with open(path, 'wb') as f:
            f.write(png)


def P(u, v, z=0):
    return (u - v, (u + v) // 2 - z)


def inside(poly, x, y):
    """Even-odd test at the pixel centre."""
    px, py = x + 0.5, y + 0.5
    n = len(poly)
    hit = False
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def fill(img, pts, color):
    """Fill a screen-space polygon. [color] is a colour or f(x, y) -> colour."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        for x in range(int(math.floor(min(xs))), int(math.ceil(max(xs))) + 1):
            if inside(pts, x, y):
                c = color(x, y) if callable(color) else color
                img.put(x, y, c)


def line(img, a, b, c):
    x0, y0 = a
    x1, y1 = b
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        img.put(x0, y0, c)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def rect(img, x, y, w, h, c):
    for yy in range(h):
        for xx in range(w):
            img.put(x + xx, y + yy, c)


def ellipse(img, cx, cy, rx, ry, color):
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx = (x + 0.5 - cx) / rx
            ny = (y + 0.5 - cy) / ry
            if nx * nx + ny * ny <= 1.0:
                c = color(x, y) if callable(color) else color
                img.put(x, y, c)


# ---------------------------------------------------------------- 3D pieces

def face_left(img, u0, u1, v, z0, z1, color):
    """The +v face (lower left). [color] may be f(u, z)."""
    pts = [P(u0, v, z0), P(u1, v, z0), P(u1, v, z1), P(u0, v, z1)]
    if callable(color):
        def f(x, y):
            u = x + v
            z = (u + v) // 2 - y
            return color(u, z)
        fill(img, pts, f)
    else:
        fill(img, pts, color)


def face_right(img, u, v0, v1, z0, z1, color):
    """The +u face (lower right). [color] may be f(v, z)."""
    pts = [P(u, v0, z0), P(u, v1, z0), P(u, v1, z1), P(u, v0, z1)]
    if callable(color):
        def f(x, y):
            v = u - x
            z = (u + v) // 2 - y
            return color(v, z)
        fill(img, pts, f)
    else:
        fill(img, pts, color)


def face_top(img, u0, u1, v0, v1, z, color):
    """The top. [color] may be f(u, v)."""
    pts = [P(u0, v0, z), P(u1, v0, z), P(u1, v1, z), P(u0, v1, z)]
    if callable(color):
        def f(x, y):
            s = y + z
            u = s + x / 2
            v = s - x / 2
            return color(u, v)
        fill(img, pts, f)
    else:
        fill(img, pts, color)


def shaded_side(base, hi, lo, z0, z1, ao_rows=2, hi_rows=2):
    """A left/right face shader for [box]: a solid contact-AO band of
    [ao_rows] right at the base (grounds the object against the floor) and
    a solid highlight band of [hi_rows] right at the top (a rim catching
    the light), flat [base] in between. Fixed pixel counts, not a fraction
    of the face's height, so a short object still reads as grounded and lit
    instead of the bands shrinking to nothing."""
    def f(coord, z):
        if z - z0 < ao_rows:
            return lo
        if z1 - z <= hi_rows:
            return hi
        return base
    return f


def shaded_top(base, hi, u0, u1, v0, v1, hi_depth=3, under=None):
    """A top-face shader for [box]: a solid highlight band [hi_depth] deep
    along the front edge (the corner nearest the camera), falling back to
    [under](u, v) elsewhere if given, else flat [base]."""
    def f(u, v):
        d = (u1 - u) + (v1 - v)
        if d <= hi_depth:
            return hi
        return under(u, v) if under else base
    return f


def box(img, u0, v0, u1, v1, z0, z1, r, top=None, left=None, right=None, edge=True):
    """A lit box. [top]/[left]/[right] override a face colour or shader."""
    face_left(img, u0, u1, v1, z0, z1, left or r.left)
    face_right(img, u1, v0, v1, z0, z1, right or r.right)
    face_top(img, u0, u1, v0, v1, z1, top or r.top)
    if edge:
        # Bright lip along the two front edges of the top.
        line(img, P(u0, v1, z1), P(u1, v1, z1), r.hi)
        line(img, P(u1, v1, z1), P(u1, v0, z1), lighter(r.top, 0.25))


def cylinder(img, cu, cv, rad, z0, z1, r, cap=None):
    """A round post or pot: an iso ellipse of radius [rad] extruded up."""
    cx, cy0 = P(cu, cv, z0)
    _, cy1 = P(cu, cv, z1)
    rx = rad
    ry = rad / 2.0

    def body(x, y):
        t = (x + 0.5 - cx) / rx
        if t < -0.35:
            return r.top
        if t < 0.25:
            return r.left
        return r.right

    for yy in range(int(cy1 - ry) - 1, int(cy0 + ry) + 2):
        for xx in range(int(cx - rx) - 1, int(cx + rx) + 2):
            t = (xx + 0.5 - cx) / rx
            if abs(t) > 1:
                continue
            h = ry * math.sqrt(max(0, 1 - t * t))
            if cy1 - h <= yy + 0.5 <= cy0 + h:
                img.put(xx, yy, body(xx, yy))
    ellipse(img, cx, cy1, rx, ry, cap or r.hi)


def noise(seed):
    s = [seed]

    def n():
        s[0] = (s[0] * 1103515245 + 12345) & 0x7fffffff
        return (s[0] >> 8) / 8388608.0
    return n


def shadow(img, cx, cy, rx, ry, alpha=64):
    """A soft-edged-free blob of translucent cool dark under something. Only
    paints where the sprite is still empty."""
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx = (x + 0.5 - cx) / rx
            ny = (y + 0.5 - cy) / ry
            if nx * nx + ny * ny <= 1.0 and not img.solid(x, y):
                img.put(x, y, (40, 20, 70, alpha))
