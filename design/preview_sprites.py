"""Renders assets/pixel/sprites.txt to a PNG sheet for eyeballing. Usage: preview_sprites.py out.png"""
import re, sys, zlib, struct
src = open('assets/pixel/sprites.txt').read().split('\n')
pal = {}; sprites = {}; errors = []
mode = None; cur = None
for i, line in enumerate(src, 1):
    if line.startswith('#'): continue
    if line.startswith('@palette'): mode = 'pal'; continue
    if line.startswith('@sprite'):
        parts = line.split(); cur = (parts[1], parts[2]); extra = dict(p.split('=') for p in parts[3:])
        sprites[cur] = {'rows': [], 'extra': extra, 'line': i}; mode = 'spr'; continue
    if not line.strip(): mode = None if mode == 'spr' else mode; continue
    if mode == 'pal':
        c, h = line.split(); pal[c] = tuple(int(h[j:j+2], 16) for j in (0, 2, 4))
    elif mode == 'spr': sprites[cur]['rows'].append(line)
for k, s in sprites.items():
    w = len(s['rows'][0])
    for j, r in enumerate(s['rows']):
        if len(r) != w: errors.append(f"{k} line {s['line']+1+j}: width {len(r)} != {w}: {r}")
for e in errors: print(e)
def derive(rows, mode):
    kind, _, n = mode.partition(':'); n = int(n) if n else 0
    w = len(rows[0]); blank = '.' * w
    if kind == 'breathe': return rows[1:n+1] + [rows[n]] + rows[n+1:] if rows[0] == blank else rows
    if kind == 'float': return rows[1:] + [blank] if rows[0] == blank else rows
    if kind == 'sway': return ['.' + r[:-1] if i < n else r for i, r in enumerate(rows)]
    return rows
frames = {}
for (name, f), s in sprites.items():
    frames[(name, f)] = s['rows']
    if 'frame1' in s['extra']: frames[(name, 'idle1')] = derive(s['rows'], s['extra']['frame1'])
TEAMS = {'b': {'t': (80, 130, 230), 'T': (40, 70, 160)}, 'r': {'t': (226, 84, 84), 'T': (138, 40, 60)}}
def px(rows, team):
    out = []
    for r in rows:
        out.append([TEAMS[team].get(c, pal.get(c)) if c != '.' else None for c in r])
    return out
S = 5; PAD = 4; BG = (36, 38, 52)
units = ['hero','knight','archer','golem','cavalry','mage','healer','warlord','pyromancer','titan']
cells = []
for team in 'br':
    for u in units:
        for f in ('idle0', 'idle1', 'attack'):
            if (u, f) in frames: cells.append(px(frames[(u, f)], team))
extra = [px(frames[(n, 'idle0')], 'b') for n in ('tree','mountain','crystal','crown','star','lock','heart','cursor')] + [px(frames[('tree','idle1')],'b')] + [px(frames[('flame', f)], 'b') for f in ('f0','f1','f2')]
rows_cells = [cells[i:i+15] for i in range(0, len(cells), 15)] + [extra]
cw = 24 + PAD; ch = 24 + PAD
Wp = 15 * cw + PAD; Hp = len(rows_cells) * ch + PAD
img = [[BG] * Wp for _ in range(Hp)]
for ri, row in enumerate(rows_cells):
    for ci, spr in enumerate(row):
        sh, sw = len(spr), len(spr[0])
        oy = PAD + ri * ch + (24 - sh); ox = PAD + ci * cw + (24 - sw) // 2
        for y in range(sh):
            for x in range(sw):
                if spr[y][x]: img[oy + y][ox + x] = spr[y][x]
raw = b''
for y in range(Hp * S):
    raw += b'\0' + b''.join(bytes(img[y // S][x // S]) for x in range(Wp * S))
def chunk(t, d): c = struct.pack('>I', len(d)) + t + d; return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', Wp*S, Hp*S, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
print('errors:', len(errors))
