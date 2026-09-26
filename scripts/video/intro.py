#!/usr/bin/env python3
"""Tokarium の 30 秒のイントロ動画を作る。

使い方: python3 scripts/video/intro.py            動画を作る（build/video/tokarium-intro.mp4）
       python3 scripts/video/intro.py --stills   確認用に数コマだけ静止画で書き出す
必要: Pillow、ffmpeg

320×180 の小さな画面に 1 コマずつ描き、6 倍に拡大して 1920×1080 にする（1 ドット＝6 ピクセル）。
魚・装飾はアプリの描画から書き出したドット絵（docs/assets/sprites）、音はアプリの BGM と効果音を使う。
場面の時間は下の T にまとめてある。
"""
import math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPR = os.path.join(ROOT, 'docs', 'assets', 'sprites')
SND = os.path.join(ROOT, 'Resources', 'Sounds')
OUT = os.path.join(ROOT, 'build', 'video')
FONT = os.path.join(ROOT, 'Resources', 'Fonts', 'DotGothic16-Regular.ttf')

W, H, SCALE, FPS, DUR = 320, 180, 6, 30, 30.0
SAND = 158

# 場面の時間（秒）
T = dict(
    open=0.1, type=(0.6, 2.0), line2=2.25, line3=2.75, count=(3.0, 3.8), lift=(4.0, 4.45),
    gather=(4.0, 4.5), coin=4.5, fall=(5.2, 6.0), water=(5.35, 6.0), splash=5.98,
    decos=6.05, fish=6.5, hud=7.1, rain=8.0, caption=(8.25, 9.4, 10.3), feed=10.8,
    cards=12.9, card_len=1.75, logo=23.4, fade=29.2,
)

# アプリの色
ABYSS, DEEP, SEA, SANDC, GOLD, TEXT, DIM = (6, 18, 36), (11, 29, 54), (29, 79, 128), (242, 227, 179), (255, 213, 79), (244, 241, 230), (157, 180, 204)
BANDS = [(91, 184, 234), (74, 168, 224), (58, 152, 212), (46, 134, 196), (37, 116, 176), (30, 99, 156), (24, 84, 137), (19, 70, 119)]

f16 = ImageFont.truetype(FONT, 16)
f32 = ImageFont.truetype(FONT, 32)
# フォントは文字の上に余白を持つ（16px なら 4 ドット）。text() の y が文字の見た目の上端になるよう差し引く
PAD = {id(f): f.getmetrics()[0] - f.size for f in (f16, f32)}

_cache = {}
def sprite(path, k=1, silhouette=False):
    key = (path, k, silhouette)
    if key not in _cache:
        im = Image.open(os.path.join(SPR, path)).convert('RGBA')
        if k != 1:
            im = im.resize((im.width * k, im.height * k), Image.NEAREST)
        if silhouette:
            black = Image.new('RGBA', im.size, (4, 10, 22, 255))
            black.putalpha(im.getchannel('A'))
            im = black
        _cache[key] = im
    return _cache[key]

def clamp(v, a=0.0, b=1.0): return max(a, min(b, v))
def seg(t, a, b): return clamp((t - a) / (b - a))
def ease_out(x): return 1 - (1 - x) ** 3
def ease_in(x): return x ** 3
def ease_io(x): return 3 * x * x - 2 * x ** 3
def back(x, s=1.9): x -= 1; return x * x * ((s + 1) * x + s) + 1
def steps(x, n): return math.floor(x * n) / n  # ドット絵らしく、動きを段にする
def typed(s, t, a, b): return s[:int(len(s) * seg(t, a, b))]

def text(d, xy, s, font=f16, fill=TEXT, shadow=ABYSS, anchor='la'):
    """y は文字の見た目の上端。"""
    x, y = xy[0], xy[1] - PAD[id(font)]
    if shadow:
        d.text((x + 1, y + 1), s, font=font, fill=shadow, anchor=anchor)
    d.text((x, y), s, font=font, fill=fill, anchor=anchor)

def frame_box(d, x0, y0, x1, y1, border=SANDC, fill=DEEP):
    """ドット絵の枠（角を1段落とす）。"""
    d.rectangle((x0 + 1, y0, x1 - 1, y1), fill=ABYSS)
    d.rectangle((x0, y0 + 1, x1, y1 - 1), fill=ABYSS)
    d.rectangle((x0 + 2, y0 + 1, x1 - 2, y1 - 1), fill=border)
    d.rectangle((x0 + 1, y0 + 2, x1 - 1, y1 - 2), fill=border)
    d.rectangle((x0 + 2, y0 + 2, x1 - 2, y1 - 2), fill=fill)

def coin(d, cx, cy, t, r=3):
    w = max(1, round(r * abs(math.cos(t * 7))))
    d.rectangle((cx - w - 1, cy - r - 1, cx + w + 1, cy + r + 1), fill=(106, 74, 0))
    d.rectangle((cx - w, cy - r, cx + w, cy + r), fill=GOLD)
    d.rectangle((cx - w, cy - r + 1, cx - w + max(0, w // 2), cy), fill=(255, 240, 160))

def sparkle(d, x, y, c=(255, 246, 176)):
    d.point([(x, y - 1), (x, y), (x, y + 1), (x - 1, y), (x + 1, y)], fill=c)

# ---------- 水槽 ----------

DECOS = [('tallgrass', 18, 0.00), ('sword', 44, 0.08), ('castle', 84, 0.16), ('anemone', 124, 0.24), ('coral', 148, 0.3),
         ('airstone', 170, 0.36), ('chest', 194, 0.42), ('ship', 244, 0.5), ('fern', 292, 0.58), ('lotus', 308, 0.64), ('starfish', 108, 0.7)]
FRONT = {'starfish', 'sword', 'fern'}

rng = random.Random(4)
FISH = []
for path, y, v, enter in [
        ('fish/neon-{f}.png', 62, 22, 0.0), ('fish/neon-{f}.png', 66, 22, 0.08), ('fish/neon-{f}.png', 59, 22, 0.16),
        ('fish/neon-{f}.png', 70, 22, 0.24), ('fish/neon-{f}.png', 64, 22, 0.32),
        ('variants/guppy-gold.png', 40, -16, 0.3), ('fish/clown-{f}.png', 112, 14, 0.6), ('fish/angel-{f}.png', 90, -10, 0.8),
        ('variants/goldfish-red.png', 128, -12, 1.0), ('variants/betta-purple.png', 36, 11, 1.2), ('fish/m_claude2-{f}.png', 100, 9, 1.4)]:
    FISH.append(dict(path=path, y=y, v=v, enter=T['fish'] + enter, phase=rng.random() * 6))

BUBBLES = [(rng.random(), rng.random() * 4) for _ in range(28)]
RAIN = [(40 + rng.random() * 240, T['rain'] + i * 0.3 + rng.random() * 0.1) for i in range(14)]
FEED_X = 160
PELLETS = [(FEED_X + rng.uniform(-22, 22), rng.uniform(0, 0.4)) for _ in range(14)]

def draw_tank(img, d, t, water_top=0):
    bh = math.ceil(SAND / len(BANDS))
    for i, c in enumerate(BANDS):
        y0 = i * bh
        if y0 + bh < water_top:
            continue
        d.rectangle((0, max(y0, water_top), W, min(y0 + bh, SAND)), fill=c)
    if water_top < SAND:
        for x in range(0, W, 8):
            d.point([(x + (int(t * 8) % 8), water_top), (x + 1 + (int(t * 8) % 8), water_top)], fill=(200, 235, 255))
    ray = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ray)
    for k in range(4):
        x0 = 30 + k * 80 + round(math.sin(t * 0.8 + k) * 4)
        rd.polygon([(x0, water_top), (x0 + 9, water_top), (x0 + 30, SAND), (x0 + 18, SAND)], fill=(255, 255, 255, 18))
    img.alpha_composite(ray)
    d.rectangle((0, SAND, W, H), fill=(216, 190, 126))
    d.line((0, SAND, W, SAND), fill=(232, 212, 154))
    r2 = random.Random(9)
    for _ in range(160):
        d.point((r2.randrange(W), r2.randrange(SAND + 2, H)), fill=(200, 169, 106) if r2.random() < .5 else (238, 221, 176))

def draw_decos(img, t, front=False):
    for name, x, delay in DECOS:
        if (name in FRONT) != front:
            continue
        start = T['decos'] + delay * 1.3
        p = seg(t, start, start + 0.35)
        if p <= 0:
            continue
        sp = sprite(f'deco/{name}.png')
        rise = 1 - back(steps(p, 6))
        y = SAND + (3 if front else 1) - sp.height + round(rise * sp.height)
        img.alpha_composite(sp, (x - sp.width // 2, y))

def fish_pos(f, t, sp):
    age = t - f['enter']
    start = -sp.width if f['v'] > 0 else W
    x = start + f['v'] * age
    x = (x + sp.width) % (W + sp.width * 2) - sp.width
    y = f['y'] + math.sin(t * 2 + f['phase']) * 2
    # 餌の時間は、餌のまわりに集まってくる
    pull = ease_io(seg(t, T['feed'] + 0.3, T['feed'] + 1.2)) * (1 - ease_io(seg(t, T['feed'] + 2.6, T['feed'] + 3.4)))
    if pull > 0:
        tx = FEED_X - sp.width / 2 + math.sin(f['phase'] * 3) * 34
        ty = 70 + math.cos(f['phase'] * 2) * 24
        x, y = x + (tx - x) * pull, y + (ty - y) * pull
    return round(x), round(y)

def draw_fish(img, t):
    for f in FISH:
        if t < f['enter']:
            continue
        frame = int((t + f['phase']) * 6) % 2
        sp = sprite(f['path'].format(f=frame), 2)
        x, y = fish_pos(f, t, sp)
        facing_right = f['v'] > 0
        pull = seg(t, T['feed'] + 0.3, T['feed'] + 2.6)
        if 0 < pull < 1:
            facing_right = x + sp.width / 2 < FEED_X
        img.alpha_composite(sp if facing_right else sp.transpose(Image.FLIP_LEFT_RIGHT), (x, y))

def draw_pellets(d, t):
    for x, delay in PELLETS:
        age = t - T['feed'] - delay
        if 0 <= age < 1.9:
            y = 4 + min(age * 40, 70)
            d.point((round(x + math.sin(age * 4 + x) * 2), round(y)), fill=(139, 74, 28))

def draw_bubbles(d, t):
    for k, (off, dly) in enumerate(BUBBLES):
        if t < T['decos'] + 0.35 + dly:
            continue
        y = SAND - 4 - ((t - dly) * 26 + off * 40) % (SAND - 8)
        x = 170 + round(math.sin(t * 3 + k) * 2) + (k % 3) - 1
        d.point([(x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)], fill=(230, 245, 255))

def draw_rain(d, t):
    for x, start in RAIN:
        age = t - start
        if 0 <= age <= 1.2:
            coin(d, round(x), round(-6 + ease_in(age / 1.2) * (SAND - 4)), t + x, r=3)
        elif 1.2 < age < 1.5:
            sparkle(d, round(x), SAND - 6 - round((age - 1.2) * 20))

def draw_hud(d, t):
    if t < T['hud']:
        return
    p = ease_out(seg(t, T['hud'], T['hud'] + 0.3))
    x0 = 246 + round((1 - p) * 90)
    frame_box(d, x0, 5, x0 + 68, 25)
    got = sum(1 for (_, s) in RAIN if t > s + 1.2)
    coin(d, x0 + 10, 15, t, r=3)
    text(d, (x0 + 60, 7), f'{50 + got * 155:,}', fill=GOLD, shadow=None, anchor='ra')

# ---------- 場面 ----------

CMD = '$ claude "fix the flaky test"'
TOKENS = 486210

def scene_terminal(img, d, t):
    d.rectangle((0, 0, W, H), fill=ABYSS)
    for y in range(0, H, 3):  # かすかな走査線
        d.line((0, y, W, y), fill=(8, 22, 42))
    open_p = back(seg(t, T['open'], T['open'] + 0.35))
    if open_p <= 0:
        return None
    cx, cy, hw, hh = 160, 88, 146, max(2, round(48 * open_p))
    lift = round(ease_in(seg(t, *T['lift'])) * -150)
    x0, y0, x1, y1 = cx - hw, cy - hh + lift, cx + hw, cy + hh + lift
    frame_box(d, x0, y0, x1, y1)
    if open_p < 0.9:
        return None
    for i, c in enumerate([(229, 83, 75), GOLD, (95, 208, 104)]):
        d.rectangle((x0 + 7 + i * 7, y0 + 6, x0 + 10 + i * 7, y0 + 9), fill=c)
    d.line((x0 + 5, y0 + 13, x1 - 5, y0 + 13), fill=SEA)
    n = int(len(CMD) * seg(t, *T['type']))
    cursor = '_' if int(t * 4) % 2 and n < len(CMD) else ''
    text(d, (x0 + 8, y0 + 20), CMD[:n] + cursor, shadow=None)
    if t > T['line2']:
        text(d, (x0 + 14, y0 + 39), '• Update parser.ts (+12 −3)', fill=DIM, shadow=None)
    if t > T['line3']:
        text(d, (x0 + 14, y0 + 58), '• Run tests — 42 passed', fill=(95, 208, 104), shadow=None)
    tok_xy = (x0 + 14, y0 + 77)
    if T['count'][0] < t < T['gather'][0]:
        k = ease_out(seg(t, *T['count']))
        shown = f'{int(TOKENS * k):,}'
        glow = GOLD if t < T['count'][1] or int(t * 10) % 2 else (255, 244, 194)
        text(d, tok_xy, '*', fill=(191, 233, 201), shadow=None)
        text(d, (tok_xy[0] + 16, tok_xy[1]), shown, fill=glow, shadow=None)
        text(d, (tok_xy[0] + 22 + d.textlength(shown, font=f16), tok_xy[1]), 'tokens', fill=DIM, shadow=None)
    return tok_xy

def scene_coin(d, t, tok_xy):
    """数字がドットに砕けて集まり、コインになって水へ落ちる。"""
    g0, g1 = T['gather']
    if t < g0 or t > T['fall'][1] + 0.1:
        return
    r = random.Random(3)
    gather = ease_io(seg(t, g0, g1))
    if t < g1 + 0.05 and tok_xy:
        for i in range(70):
            sx, sy = tok_xy[0] + 16 + r.random() * 60, tok_xy[1] + 4 + r.random() * 10
            ex, ey = 160 + r.randint(-2, 2), 70 + r.randint(-2, 2)
            burst = math.sin(gather * math.pi) * 20
            ang = r.random() * math.tau
            x = sx + (ex - sx) * gather + math.cos(ang) * burst
            y = sy + (ey - sy) * gather + math.sin(ang) * burst
            d.point((round(x), round(y)), fill=GOLD if i % 3 else (255, 244, 194))
    if t >= T['coin']:
        pop = back(seg(t, T['coin'], T['coin'] + 0.3))
        cy = 70 + ease_in(seg(t, *T['fall'])) * 90
        coin(d, 160, round(cy), t * 1.4, r=max(1, round(10 * pop)))
        if t < T['fall'][0]:
            text(d, (160, 36), '+1 コイン', fill=GOLD, anchor='ma')
            for k in range(4):
                a = t * 5 + k * 1.57
                sparkle(d, 160 + round(math.cos(a) * 20), 70 + round(math.sin(a) * 16))

def scene_splash(d, t):
    p = seg(t, T['splash'], T['splash'] + 0.8)
    if 0 < p < 1:
        rad = 4 + p * 40
        for k in range(20):
            a = k / 20 * math.tau
            d.point((round(160 + math.cos(a) * rad), round(96 + math.sin(a) * rad * 0.35)), fill=(230, 245, 255))

def scene_caption(img, t):
    a, b, out = T['caption']
    if not (a < t < out + 0.5):
        return
    fade = 1 - seg(t, out, out + 0.4)
    l1, l2 = typed('AIを使うほど、', t, a, a + 0.55), typed('水槽がにぎやかになる。', t, b, b + 0.9)
    box = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(box)
    bd.fontmode = '1'
    frame_box(bd, 60, 52, 260, 100)
    text(bd, (160, 58), l1, anchor='ma')
    text(bd, (160, 78), l2, fill=SANDC, anchor='ma')
    box.putalpha(box.getchannel('A').point(lambda v: int(v * fade)))
    img.alpha_composite(box)

CARDS = [
    ('品種改良', '1種類につき 13 品種'),
    ('ミッション & ランク', '毎日のミッションで Lv.20 へ'),
    ('隠れた魚', '条件がそろうと迷いこむ'),
    ('デスクトップで泳ぐ', 'ウィジェットにも'),
    ('8つのAIに対応', 'このMacの記録を読むだけ'),
    ('オリジナルBGM', '昼と夜で変わる曲と効果音'),
]

def card_content(card, cd, i, x, lt):
    if i == 0:
        for k, v in enumerate(['wild', 'gold', 'sunset', 'blue', 'purple', 'sakura', 'panda']):
            pop = back(seg(lt, 0.1 + k * 0.06, 0.3 + k * 0.06))
            if pop > 0:
                sp = sprite(f'variants/guppy-{v}.png', 2)
                card.alpha_composite(sp, (x + 12 + k * 32, 92 + round(math.sin(lt * 8 + k)) + round((1 - pop) * 10)))
    elif i == 1:
        fill = ease_out(seg(lt, 0.15, 1.0))
        text(cd, (x + 12, 92), f'Lv.{1 + int(fill * 19)}', fill=GOLD)
        for c in range(22):
            cd.rectangle((x + 60 + c * 7, 96, x + 65 + c * 7, 104), fill=GOLD if c < fill * 22 else ABYSS)
        for k in range(3):
            if lt > 0.4 + k * 0.15:
                sparkle(cd, x + 200 + k * 10, 86 + (k % 2) * 6, c=GOLD)
    elif i == 2:
        for k, sid in enumerate(['hotaru', 'cavefish', 'rainbowmedaka', 'coelacanth']):
            shown = lt > 0.35 + k * 0.25
            sp = sprite(f'fish/{sid}-0.png', 2 if sid != 'coelacanth' else 1, silhouette=not shown)
            card.alpha_composite(sp, (x + 14 + k * 56, 106 - sp.height // 2))
            if not shown:
                text(cd, (x + 14 + k * 56 + sp.width // 2, 82), '?', fill=DIM, shadow=None, anchor='ma')
            elif lt < 0.55 + k * 0.25:
                sparkle(cd, x + 14 + k * 56 + sp.width, 96, c=GOLD)
    elif i == 3:
        cd.rectangle((x + 20, 86, x + 120, 118), fill=(122, 92, 158))
        cd.rectangle((x + 20, 86, x + 120, 89), fill=(220, 220, 230))
        cd.rectangle((x + 30, 94, x + 100, 114), fill=(58, 152, 212))
        fx = x + 34 + round((lt * 40) % 56)
        cd.rectangle((fx, 102, fx + 7, 105), fill=GOLD)
        for k in range(3):
            cd.rectangle((x + 108, 94 + k * 7, x + 114, 99 + k * 7), fill=SANDC)
        card.alpha_composite(sprite('fish/neon-0.png', 2), (x + 150, 96 + round(math.sin(lt * 6) * 2)))
    elif i == 4:
        names = ['Claude', 'Codex', 'Gemini', 'Qwen', 'OpenCode', 'Copilot']
        for k, nm in enumerate(names):
            if lt > 0.1 + k * 0.1:
                cx, cy = x + 12 + (k % 3) * 74, 84 + (k // 3) * 21
                cd.rectangle((cx, cy, cx + 70, cy + 18), fill=SEA)
                text(cd, (cx + 35, cy + 1), nm, shadow=None, anchor='ma')
    else:
        for k in range(12):
            h = 4 + round(abs(math.sin(lt * 7 + k * 0.9)) * 22)
            cd.rectangle((x + 16 + k * 10, 118 - h, x + 22 + k * 10, 118), fill=GOLD)
        for k in range(3):
            nx, ny = x + 160 + k * 22, 108 - round(((lt * 20 + k * 9) % 26))
            text(cd, (nx, ny), '♪', fill=SANDC, shadow=None)

def scene_cards(img, t):
    for i, (title, sub) in enumerate(CARDS):
        start = T['cards'] + i * T['card_len']
        end = start + T['card_len'] - 0.2
        if not (start <= t < end + 0.2):
            continue
        pin = ease_out(steps(seg(t, start, start + 0.22), 8))
        pout = ease_in(steps(seg(t, end - 0.12, end + 0.1), 8))
        x = round(40 + (1 - pin) * 300 - pout * 320)
        card = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        cd.fontmode = '1'
        frame_box(cd, x, 34, x + 240, 128, border=GOLD, fill=(18, 39, 68))
        text(cd, (x + 12, 42), title, fill=GOLD)
        text(cd, (x + 12, 62), sub, fill=DIM, shadow=None)
        card_content(card, cd, i, x, t - start)
        img.alpha_composite(card)

LOGO = 'Tokarium'

def scene_logo(img, d, t):
    s = T['logo']
    if t < s:
        return
    dim = ease_out(seg(t, s, s + 0.4))
    img.alpha_composite(Image.new('RGBA', (W, H), ABYSS + (int(175 * dim),)))
    icon = Image.open(os.path.join(ROOT, 'docs', 'assets', 'icon', 'favicon-32.png')).convert('RGBA')
    ip = back(seg(t, s + 0.1, s + 0.4))
    if ip > 0:
        img.alpha_composite(icon, (160 - 16, 22 + round((1 - ip) * -30)))
    total = d.textlength(LOGO, font=f32)
    for i, ch in enumerate(LOGO):
        p = seg(t, s + 0.2 + i * 0.07, s + 0.5 + i * 0.07)
        if p > 0:
            x = 160 - total / 2 + d.textlength(LOGO[:i], font=f32)
            y = 62 - round((1 - back(steps(p, 6))) * 40)
            text(d, (round(x) + 2, y + 2), ch, font=f32, fill=ABYSS, shadow=None)
            text(d, (round(x), y), ch, font=f32, fill=SANDC)
    if t > s + 1.0:
        for k in range(6):
            a = t * 3 + k
            sparkle(d, 160 + round(math.cos(a * 1.3 + k) * 80), 76 + round(math.sin(a + k) * 26), c=GOLD)
    text(d, (160, 104), typed('Mac のためのドット絵アクアリウム', t, s + 1.0, s + 1.5), anchor='ma')
    if t > s + 1.9:
        text(d, (160, 128), 'yuuyuu86.github.io/Tokarium', fill=GOLD, anchor='ma')
    if t > s + 2.4:
        text(d, (160, 148), '無料・macOS 14 以降', fill=DIM, anchor='ma')

def render(t):
    img = Image.new('RGBA', (W, H), ABYSS + (255,))
    d = ImageDraw.Draw(img)
    d.fontmode = '1'  # 文字もドットのまま
    tok_xy = scene_terminal(img, d, t) if t < T['water'][1] + 0.1 else None
    w0, w1 = T['water']
    if t >= w0:
        draw_tank(img, d, t, water_top=max(0, round(H - ease_out(seg(t, w0, w1)) * H)))
        d = ImageDraw.Draw(img)
        d.fontmode = '1'
        if t >= T['decos']:
            draw_decos(img, t)
            draw_bubbles(d, t)
            draw_pellets(d, t)
            draw_fish(img, t)
            draw_decos(img, t, front=True)
            draw_rain(d, t)
            draw_hud(d, t)
    scene_coin(d, t, tok_xy)
    scene_splash(d, t)
    scene_caption(img, t)
    scene_cards(img, t)
    scene_logo(img, d, t)
    fade = seg(t, T['fade'], DUR)
    if fade > 0:
        img.alpha_composite(Image.new('RGBA', (W, H), ABYSS + (int(255 * fade),)))
    fade_in = 1 - seg(t, 0, 0.25)
    if fade_in > 0:
        img.alpha_composite(Image.new('RGBA', (W, H), (0, 0, 0, int(255 * fade_in))))
    return img.convert('RGB').resize((W * SCALE, H * SCALE), Image.NEAREST)

def sfx_list():
    """効果音（秒, 名前, 音量）。"""
    c0 = T['cards']
    return ([(0.7, 'click', .5), (1.2, 'click', .5), (1.7, 'click', .5), (T['line3'], 'click', .4), (T['count'][1], 'sparkle', .6),
             (T['coin'], 'coin', .9), (T['splash'], 'tap', 1.0), (T['decos'] + 0.1, 'place', .6), (T['decos'] + 0.6, 'place', .5),
             (T['rain'] + 0.3, 'coin', .45), (T['rain'] + 1.8, 'coin', .4), (T['feed'], 'feed', .8), (T['feed'] + 1.0, 'eat', .7),
             (T['feed'] + 1.4, 'eat', .6), (T['feed'] + 1.9, 'eat', .6)]
            + [(c0 + i * T['card_len'], 'buy' if i == 0 else 'sparkle', .6) for i in range(len(CARDS))]
            + [(T['logo'] + 0.55, 'fanfare', .9)])

def main():
    os.makedirs(OUT, exist_ok=True)
    video = os.path.join(OUT, 'intro-video.mp4')
    enc = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W * SCALE}x{H * SCALE}',
                            '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-tune', 'animation',
                            '-pix_fmt', 'yuv420p', video], stdin=subprocess.PIPE)
    for i in range(int(DUR * FPS)):
        enc.stdin.write(render(i / FPS).tobytes())
    enc.stdin.close()
    enc.wait()

    # 音: BGM（頭から、入りと終わりをやわらかく）＋効果音
    inputs = ['-i', video, '-i', os.path.join(SND, 'bgm_day.m4a')]
    filters = [f'[1:a]atrim=0:{DUR},afade=t=in:d=0.6,afade=t=out:st={DUR - 1.8}:d=1.8,volume=0.85[bgm]']
    labels = ['[bgm]']
    for k, (at, name, vol) in enumerate(sfx_list()):
        inputs += ['-i', os.path.join(SND, f'sfx_{name}.m4a')]
        ms = int(at * 1000)
        filters.append(f'[{k + 2}:a]adelay={ms}|{ms},volume={vol * 1.8}[s{k}]')
        labels.append(f'[s{k}]')
    filters.append(''.join(labels) + f'amix=inputs={len(labels)}:normalize=0,alimiter=limit=0.9,atrim=0:{DUR}[a]')
    final = os.path.join(OUT, 'tokarium-intro.mp4')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *inputs, '-filter_complex', ';'.join(filters),
                    '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', final], check=True)
    os.remove(video)
    print('作成しました:', final)

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--stills':
        os.makedirs(OUT, exist_ok=True)
        for s in [1.5, 3.5, 4.3, 4.8, 5.8, 7.2, 9.0, 11.5, 13.6, 15.3, 17.4, 19.0, 20.8, 22.5, 25.4]:
            render(s).save(os.path.join(OUT, f'still-{s:05.2f}.png'))
        print('確認用の静止画:', OUT)
    else:
        main()
