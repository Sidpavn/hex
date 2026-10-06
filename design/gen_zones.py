"""Generates the sample zone maps in assets/zones/. Run from the repo root.
Hand-edit the output freely; this only seeds the terrain.

Map legend:  . grass  f forest  ~ water  w bridge (a plank crossing over the water)
             ^ mountain  L lava  c crystal  @ spawn  1-9 portals  ' ' void
Rows use the "odd-r" layout: odd rows are shifted half a hex to the right.
"""
import math, random
from collections import deque

def neighbors(c, r):
    # odd-r offset neighbours
    if r % 2 == 0:
        d = [(1, 0), (-1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1)]
    else:
        d = [(1, 0), (-1, 0), (0, -1), (1, -1), (0, 1), (1, 1)]
    return [(c + dc, r + dr) for dc, dr in d]

def walkable(ch):
    return ch in '.fwc@123456789'

def reachable(g, a, b):
    H, W = len(g), len(g[0])
    seen = {a}; q = deque([a])
    while q:
        c, r = q.popleft()
        if (c, r) == b: return True
        for n, m in neighbors(c, r):
            if 0 <= n < W and 0 <= m < H and (n, m) not in seen and walkable(g[m][n]):
                seen.add((n, m)); q.append((n, m))
    return False

def blob(g, rng, ch, cx, cy, rad, only='.'):
    H, W = len(g), len(g[0])
    for r in range(H):
        for c in range(W):
            x = c + (0.5 if r % 2 else 0); d = math.hypot(x - cx, (r - cy) * 0.87)
            if d < rad * (0.75 + 0.5 * rng.random()) and g[r][c] in only:
                g[r][c] = ch

def meadow():
    rng = random.Random(11)
    W, H = 38, 30
    g = [['.'] * W for _ in range(H)]
    # forests
    for cx, cy, rad in [(6, 6, 4), (10, 22, 3.5), (30, 24, 4), (27, 9, 3), (4, 16, 3)]:
        blob(g, rng, 'f', cx, cy, rad)
    # lake in the west
    blob(g, rng, '~', 7, 12, 2.6)
    # river: meanders from top to bottom through the middle
    river = set()
    for r in range(H):
        cx = 18 + 4 * math.sin(r / 4.2) + (r - H / 2) * 0.05
        for c in range(W):
            x = c + (0.5 if r % 2 else 0)
            if abs(x - cx) < 1.4:
                g[r][c] = '~'
                river.add((c, r))
    # bridges: one row of the river only (never the lake)
    for fr in (8, 17, 24):
        for c in range(W):
            if (c, fr) in river: g[fr][c] = 'w'
    # mountain ridge in the north-east with a pass
    for r in range(2, 15):
        for c in range(26, W):
            ridge = abs((c - 26) * 0.9 - (14 - r) * 0.9 - 2)
            if ridge < 1.8: g[r][c] = '^'
    for r in range(2, 15):
        for c in range(26, W):
            if g[r][c] == '^' and 8 <= r <= 9: g[r][c] = '.'   # the pass
    # a lava pool and crystals
    blob(g, rng, 'L', 33, 20, 2.0)
    for (c, r) in [(24, 6), (31, 3), (12, 26), (3, 25), (20, 12), (34, 12)]:
        if g[r][c] == '.': g[r][c] = 'c'
    # landmarks: clear spawn, cave mouth at the foot of the ridge
    for (c, r, ch) in [(4, 24, '@'), (30, 12, '1')]:
        g[r][c] = ch
        for n, m in neighbors(c, r):
            if g[m][n] in '^~Lf': g[m][n] = '.'
    return g

def cave():
    rng = random.Random(5)
    W, H = 28, 22
    g = [['^'] * W for _ in range(H)]
    def carve(c, r, rad):
        for rr in range(H):
            for cc in range(W):
                x = cc + (0.5 if rr % 2 else 0)
                if math.hypot(x - c, (rr - r) * 0.87) < rad: g[rr][cc] = '.'
    # winding tunnel with chambers
    pts = [(3, 19), (8, 16), (12, 12), (9, 8), (14, 4), (20, 6), (23, 11), (20, 16), (24, 19)]
    for (a, b), (c, d) in zip(pts, pts[1:]):
        steps = 14
        for i in range(steps + 1):
            carve(a + (c - a) * i / steps, b + (d - b) * i / steps, 1.5)
    for (cx, cy, rad) in [(3, 19, 2.3), (14, 4, 2.6), (23, 11, 2.8), (24, 19, 2.2)]:
        carve(cx, cy, rad)
    blob(g, rng, '~', 12, 12, 1.4, only='.')
    blob(g, rng, 'L', 22, 12, 1.2, only='.')
    for (c, r) in [(14, 3), (22, 10), (9, 8), (24, 20)]:
        if g[r][c] == '.': g[r][c] = 'c'
    g[19][3] = '1'
    for n, m in neighbors(3, 19):
        if g[m][n] in '^~L': g[m][n] = '.'
    return g

def near(g, c, r):
    # nearest walkable plain-ground tile to (c, r)
    H, W = len(g), len(g[0])
    best = None
    for rr in range(H):
        for cc in range(W):
            if g[rr][cc] in '.f':
                d = abs(cc - c) + abs(rr - r) * 1.2
                if best is None or d < best[0]: best = (d, cc, rr)
    return best[1], best[2]

def enemy(g, kind, behavior, *pts):
    pts = [near(g, c, r) for c, r in pts]
    first = f'{pts[0][0]} {pts[0][1]}'
    rest = ' '.join(f'{c},{r}' for c, r in pts[1:])
    return f'enemy {kind} {first} {behavior}' + (f' {rest}' if rest else '')

def prop(g, line_fmt, c, r):
    cc, rr = near(g, c, r)
    return line_fmt.format(c=cc, r=rr)

def write(name, title, dark, g, portals, enemies=()):
    lines = [f'zone {name}', f'name {title}', f'dark {1 if dark else 0}']
    lines += portals
    lines += list(enemies)
    lines.append('map')
    lines += [''.join(row) for row in g]
    open(f'assets/zones/{name}.txt', 'w').write('\n'.join(lines) + '\n')

m = meadow()
# the meadow must connect spawn to the cave mouth
spawn = next((c, r) for r, row in enumerate(m) for c, ch in enumerate(row) if ch == '@')
mouth = next((c, r) for r, row in enumerate(m) for c, ch in enumerate(row) if ch == '1')
assert reachable(m, spawn, mouth), 'meadow not connected'
c = cave()
assert reachable(c, (3, 19), (24, 19)), 'cave not connected'
write('meadow', 'Whispering Meadow', False, m, ['portal 1 cave 1 cave'] + [
    prop(m, 'camp {c} {r}', 7, 23),
    prop(m, 'npc mara Old_Mara {c} {r} healer', 8, 22),
], [
    enemy(m, 'knight', 'patrol', (14, 24), (14, 19)),
    enemy(m, 'archer', 'guard', (22, 18)),
    enemy(m, 'knight', 'guard', (25, 22)),
    enemy(m, 'cavalry', 'wander', (9, 3)),
    enemy(m, 'golem', 'sleep', (29, 13)),
])
write('cave', 'Hollow Deep', True, c, ['portal 1 meadow 1 cave_exit'] + [
    prop(c, 'camp {c} {r}', 5, 18),
    prop(c, 'item lantern {c} {r} lantern Old_Lantern', 14, 3),
], [
    enemy(c, 'knight', 'patrol', (9, 8), (12, 12)),
    enemy(c, 'archer', 'guard', (20, 6)),
    enemy(c, 'golem', 'sleep', (22, 11)),
    enemy(c, 'mage', 'guard', (14, 5)),
])
print('ok')
