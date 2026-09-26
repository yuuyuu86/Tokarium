#!/usr/bin/env python3
"""Tokarium の 15 秒のイントロ動画を作る。

使い方: python3 scripts/video/intro.py   （必要: Pillow、ffmpeg）
build/video/tokarium-intro.mp4 ができる。

320×180 の小さな画面に 1 コマずつ描き、6 倍に拡大して 1920×1080 にする（1 ドット＝6 ピクセル）。
魚・装飾はアプリの描画から書き出したドット絵（docs/assets/sprites）、音はアプリの BGM と効果音を使う。
"""
import math, os, random, subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPR = os.path.join(ROOT, 'docs', 'assets', 'sprites')
SND = os.path.join(ROOT, 'Resources', 'Sounds')
OUT = os.path.join(ROOT, 'build', 'video')
FONT = os.path.join(ROOT, 'Resources', 'Fonts', 'DotGothic16-Regular.ttf')

W, H, SCALE, FPS, DUR = 320, 180, 6, 30, 15.0
SAND = 158

# アプリの色
ABYSS, DEEP, SEA, SANDC, GOLD, TEXT, DIM = (6, 18, 36), (11, 29, 54), (29, 79, 128), (242, 227, 179), (255, 213, 79), (244, 241, 230), (157, 180, 204)
BANDS = [(91, 184, 234), (74, 168, 224), (58, 152, 212), (46, 134, 196), (37, 116, 176), (30, 99, 156), (24, 84, 137), (19, 70, 119)]

f16 = ImageFont.truetype(FONT, 16)
f32 = ImageFont.truetype(FONT, 32)
f8 = ImageFont.truetype(FONT, 8)

_cache = {}
def sprite(path, k=1):
    key = (path, k)
    if key not in _cache:
        im = Image.open(os.path.join(SPR, path)).convert('RGBA')
        _cache[key] = im.resize((im.width * k, im.height * k), Image.NEAREST) if k != 1 else im
    return _cache[key]

def clamp(v, a=0.0, b=1.0): return max(a, min(b, v))
def seg(t, a, b): return clamp((t - a) / (b - a))
def ease_out(x): return 1 - (1 - x) ** 3
def ease_in(x): return x ** 3
def ease_io(x): return 3 * x * x - 2 * x ** 3
def back(x, s=1.9): x -= 1; return x * x * ((s + 1) * x + s) + 1
def steps(x, n): return math.floor(x * n) / n  # ドット絵らしく、動きを段にする

def text(d, xy, s, font=f16, fill=TEXT, shadow=ABYSS, anchor='la'):
    x, y = xy
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

rng = random.Random(4)
FISH = []
for i, (path, y, v, enter) in enumerate([
        ('fish/neon-{f}.png', 62, 22, 5.0), ('fish/neon-{f}.png', 66, 22, 5.08), ('fish/neon-{f}.png', 59, 22, 5.16),
        ('fish/neon-{f}.png', 70, 22, 5.24), ('fish/neon-{f}.png', 64, 22, 5.32),
        ('variants/guppy-gold.png', 40, -16, 5.3), ('fish/clown-{f}.png', 112, 14, 5.6), ('fish/angel-{f}.png', 90, -10, 5.8),
        ('variants/goldfish-red.png', 128, -12, 6.0), ('variants/betta-purple.png', 36, 11, 6.2), ('fish/m_claude2-{f}.png', 100, 9, 6.4)]):
    FISH.append(dict(path=path, y=y, v=v, enter=enter, phase=rng.random() * 6))

BUBBLES = [(rng.random(), rng.random() * 4) for _ in range(28)]
RAIN = [(40 + rng.random() * 240, 6.0 + i * 0.2 + rng.random() * 0.1) for i in range(14)]

def draw_tank(img, d, t, water_top=0):
    # 水の段
    bh = math.ceil(SAND / len(BANDS))
    for i, c in enumerate(BANDS):
        y0 = i * bh
        if y0 + bh < water_top:
            continue
        d.rectangle((0, max(y0, water_top), W, min(y0 + bh, SAND)), fill=c)
    # 水面
    if water_top < SAND:
        for x in range(0, W, 8):
            d.point([(x + (int(t * 8) % 8), water_top), (x + 1 + (int(t * 8) % 8), water_top)], fill=(200, 235, 255))
    # 光の筋
    ray = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ray)
    for k in range(4):
        x0 = 30 + k * 80 + round(math.sin(t * 0.8 + k) * 4)
        rd.polygon([(x0, water_top), (x0 + 9, water_top), (x0 + 30, SAND), (x0 + 18, SAND)], fill=(255, 255, 255, 18))
    img.alpha_composite(ray)
    # 砂
    d.rectangle((0, SAND, W, H), fill=(216, 190, 126))
    d.line((0, SAND, W, SAND), fill=(232, 212, 154))
    r2 = random.Random(9)
    for _ in range(160):
        d.point((r2.randrange(W), r2.randrange(SAND + 2, H)), fill=(200, 169, 106) if r2.random() < .5 else (238, 221, 176))

def draw_decos(img, t, layer_front=False):
    for name, x, delay in DECOS:
        front = name in ('starfish', 'sword', 'fern')
        if front != layer_front:
            continue
        p = seg(t, 4.55 + delay * 1.3, 4.55 + delay * 1.3 + 0.35)
        if p <= 0:
            continue
        sp = sprite(f'deco/{name}.png')
        rise = 1 - back(steps(p, 6))
        y = SAND + (3 if front else 1) - sp.height + round(rise * sp.height)
        img.alpha_composite(sp, (x - sp.width // 2, y))

def draw_fish(img, t):
    for f in FISH:
        if t < f['enter']:
            continue
        frame = int((t + f['phase']) * 6) % 2
        sp = sprite(f['path'].format(f=frame), 2)
        age = t - f['enter']
        start = -sp.width if f['v'] > 0 else W
        x = start + f['v'] * age
        x = (x + sp.width) % (W + sp.width * 2) - sp.width
        y = f['y'] + round(math.sin(t * 2 + f['phase']) * 2)
        s = sp if f['v'] > 0 else sp.transpose(Image.FLIP_LEFT_RIGHT)
        img.alpha_composite(s, (round(x), y))

def draw_bubbles(d, t):
    for k, (off, dly) in enumerate(BUBBLES):
        if t < 4.9 + dly:
            continue
        y = SAND - 4 - ((t - 4.9 - dly) * 26 + off * 40) % (SAND - 8)
        x = 170 + round(math.sin(t * 3 + k) * 2) + (k % 3) - 1
        d.point([(x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)], fill=(230, 245, 255))

# ---------- 場面 ----------

CMD = '$ claude "fix the flaky test"'
TOKENS = 486210

def scene_terminal(img, d, t):
    d.rectangle((0, 0, W, H), fill=ABYSS)
    for y in range(0, H, 3):  # かすかな走査線
        d.line((0, y, W, y), fill=(8, 22, 42))
    open_p = back(clamp(seg(t, 0.05, 0.35)))
    if open_p <= 0:
        return None
    cx, cy, hw, hh = 160, 84, 146, max(2, round(40 * open_p))
    lift = round(ease_in(seg(t, 2.95, 3.35)) * -140)
    x0, y0, x1, y1 = cx - hw, cy - hh + lift, cx + hw, cy + hh + lift
    frame_box(d, x0, y0, x1, y1)
    if open_p < 0.9:
        return None
    for i, c in enumerate([(229, 83, 75), GOLD, (95, 208, 104)]):
        d.rectangle((x0 + 7 + i * 7, y0 + 6, x0 + 10 + i * 7, y0 + 9), fill=c)
    d.line((x0 + 5, y0 + 13, x1 - 5, y0 + 13), fill=SEA)
    n = int(len(CMD) * seg(t, 0.4, 1.35))
    text(d, (x0 + 8, y0 + 16), CMD[:n] + ('_' if int(t * 4) % 2 and n < len(CMD) else ''), fill=TEXT, shadow=None)
    if t > 1.5:
        text(d, (x0 + 14, y0 + 34), '• Update parser.ts (+12 −3)', font=f16, fill=DIM, shadow=None)
    tok_xy = (x0 + 14, y0 + 52)
    if t > 1.85:
        k = ease_out(seg(t, 1.85, 2.55))
        shown = f'{int(TOKENS * k):,}'
        scatter = seg(t, 2.8, 3.15)
        if scatter <= 0:
            glow = GOLD if t < 2.55 or int(t * 10) % 2 else (255, 244, 194)
            text(d, tok_xy, '* ', fill=(191, 233, 201), shadow=None)
            text(d, (tok_xy[0] + 16, tok_xy[1]), shown, fill=glow, shadow=None)
            text(d, (tok_xy[0] + 16 + d.textlength(shown, font=f16) + 6, tok_xy[1]), 'tokens', fill=DIM, shadow=None)
    return tok_xy

def scene_coin(img, d, t, tok_xy):
    """数字がドットに砕けて集まり、コインになって水へ落ちる。"""
    if t < 2.8 or t > 4.6:
        return
    r = random.Random(3)
    gather = ease_io(seg(t, 2.8, 3.2))
    if t < 3.25 and tok_xy:
        for i in range(60):
            sx, sy = tok_xy[0] + 16 + r.random() * 60, tok_xy[1] + 4 + r.random() * 10
            ex, ey = 160 + r.randint(-2, 2), 70 + r.randint(-2, 2)
            burst = math.sin(gather * math.pi) * 18
            ang = r.random() * math.tau
            x = sx + (ex - sx) * gather + math.cos(ang) * burst
            y = sy + (ey - sy) * gather + math.sin(ang) * burst
            d.point((round(x), round(y)), fill=GOLD if i % 3 else (255, 244, 194))
    if t >= 3.2:
        pop = back(seg(t, 3.2, 3.45))
        fall = ease_in(seg(t, 3.75, 4.45))
        cy = 70 + fall * 90
        size = max(1, round(10 * pop))
        coin(d, 160, round(cy), t * 1.4, r=size)
        if t < 3.8:
            text(d, (160, 36), '+1 コイン', fill=GOLD, anchor='ma')
            for k in range(4):
                a = t * 5 + k * 1.57
                sparkle(d, 160 + round(math.cos(a) * 20), 70 + round(math.sin(a) * 16))

def scene_ripple(d, t):
    p = seg(t, 4.42, 5.2)
    if 0 < p < 1:
        rad = 4 + p * 40
        for k in range(20):
            a = k / 20 * math.tau
            d.point((round(160 + math.cos(a) * rad), round(96 + math.sin(a) * rad * 0.35)), fill=(230, 245, 255))

def scene_hud(img, d, t):
    if t < 5.6:
        return
    p = ease_out(seg(t, 5.6, 5.9))
    x0 = 246 + round((1 - p) * 90)
    frame_box(d, x0, 5, x0 + 68, 25, fill=DEEP)
    got = sum(1 for (_, s) in RAIN if t > s + 1.2)
    coin(d, x0 + 10, 15, t, r=3)
    text(d, (x0 + 60, 7), f'{50 + got * 155:,}', fill=GOLD, shadow=None, anchor='ra')

def scene_rain(d, t):
    for x, start in RAIN:
        age = t - start
        if 0 <= age <= 1.2:
            y = -6 + ease_in(age / 1.2) * (SAND - 4)
            coin(d, round(x), round(y), t + x, r=3)
        elif 1.2 < age < 1.5:
            sparkle(d, round(x), SAND - 6 - round((age - 1.2) * 20))

def typed(s, t, a, b): return s[:int(len(s) * seg(t, a, b))]

def scene_caption(img, d, t):
    if not (6.3 < t < 9.6):
        return
    fade = 1 - seg(t, 9.25, 9.55)
    if fade <= 0:
        return
    l1, l2 = typed('AIを使うほど、', t, 6.35, 6.9), typed('水槽がにぎやかになる。', t, 7.35, 8.2)
    box = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(box)
    frame_box(bd, 60, 52, 260, 100, fill=(11, 29, 54))
    text(bd, (160, 58), l1, anchor='ma')
    text(bd, (160, 78), l2, fill=SANDC, anchor='ma')
    box.putalpha(box.getchannel('A').point(lambda a: int(a * fade)))
    img.alpha_composite(box)

CARDS = [
    (9.55, '品種改良', '1種類につき 13 品種'),
    (10.65, 'ミッション & ランク', '毎日のミッションで Lv.20 へ'),
    (11.75, 'デスクトップで泳ぐ', 'ウィジェットにも'),
]

def scene_cards(img, d, t):
    for i, (start, title, sub) in enumerate(CARDS):
        end = start + 1.1
        if not (start <= t < end + 0.2):
            continue
        pin = ease_out(steps(seg(t, start, start + 0.22), 8))
        pout = ease_in(steps(seg(t, end - 0.12, end + 0.1), 8))
        x = round(40 + (1 - pin) * 300 - pout * 320)
        card = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        frame_box(cd, x, 34, x + 240, 128, border=GOLD, fill=(18, 39, 68))
        text(cd, (x + 12, 42), title, fill=GOLD)
        text(cd, (x + 12, 62), sub, fill=DIM, shadow=None)
        lt = t - start
        if i == 0:
            vs = ['wild', 'gold', 'sunset', 'blue', 'purple', 'sakura', 'panda']
            for k, v in enumerate(vs):
                sp = sprite(f'variants/guppy-{v}.png', 2)
                bob = round(math.sin(lt * 8 + k) * 1)
                pop = back(seg(lt, 0.1 + k * 0.05, 0.3 + k * 0.05))
                if pop > 0:
                    card.alpha_composite(sp, (x + 12 + k * 32, 92 + bob + round((1 - pop) * 10)))
        elif i == 1:
            fill = ease_out(seg(lt, 0.15, 0.85))
            lv = 1 + int(fill * 19)
            text(cd, (x + 12, 92), f'Lv.{lv}', fill=GOLD)
            cells = 22
            for c in range(cells):
                cd.rectangle((x + 60 + c * 7, 96, x + 65 + c * 7, 104), fill=GOLD if c < fill * cells else ABYSS)
            for k in range(3):
                if lt > 0.3 + k * 0.15:
                    sparkle(cd, x + 200 + k * 10, 86 + (k % 2) * 6, c=GOLD)
        else:
            cd.rectangle((x + 20, 86, x + 120, 118), fill=(122, 92, 158))
            cd.rectangle((x + 20, 86, x + 120, 89), fill=(220, 220, 230))
            cd.rectangle((x + 30, 94, x + 100, 114), fill=(58, 152, 212))
            fx = x + 34 + round((lt * 40) % 56)
            cd.rectangle((fx, 102, fx + 7, 105), fill=GOLD)
            for k in range(3):
                cd.rectangle((x + 108, 94 + k * 7, x + 114, 99 + k * 7), fill=SANDC)
            wd = sprite('fish/neon-0.png', 2)
            card.alpha_composite(wd, (x + 150, 96 + round(math.sin(lt * 6) * 2)))
        img.alpha_composite(card)

LOGO = 'Tokarium'

def scene_logo(img, d, t):
    if t < 12.8:
        return
    dim = ease_out(seg(t, 12.8, 13.2))
    veil = Image.new('RGBA', (W, H), ABYSS + (int(170 * dim),))
    img.alpha_composite(veil)
    icon = Image.open(os.path.join(ROOT, 'docs', 'assets', 'icon', 'favicon-32.png')).convert('RGBA')
    ip = back(seg(t, 12.9, 13.2))
    if ip > 0:
        img.alpha_composite(icon, (160 - 16, 22 + round((1 - ip) * -30)))
    total = d.textlength(LOGO, font=f32)
    for i, ch in enumerate(LOGO):
        x = 160 - total / 2 + d.textlength(LOGO[:i], font=f32)
        p = seg(t, 13.0 + i * 0.07, 13.3 + i * 0.07)
        if p > 0:
            y = 62 - round((1 - back(steps(p, 6))) * 40)
            text(d, (round(x) + 2, y + 2), ch, font=f32, fill=(6, 18, 36), shadow=None)
            text(d, (round(x), y), ch, font=f32, fill=SANDC, shadow=ABYSS)
    if t > 13.75:
        for k in range(6):
            a = t * 3 + k
            sparkle(d, 160 + round(math.cos(a * 1.3 + k) * 80), 76 + round(math.sin(a + k) * 26), c=GOLD)
    sub = typed('Mac のためのドット絵アクアリウム', t, 13.75, 14.15)
    text(d, (160, 104), sub, fill=TEXT, anchor='ma')
    if t > 14.2:
        text(d, (160, 128), 'yuuyuu86.github.io/Tokarium', fill=GOLD, anchor='ma')
    if t > 14.35:
        text(d, (160, 148), '無料・macOS 14 以降', fill=DIM, anchor='ma')

def render(t):
    img = Image.new('RGBA', (W, H), ABYSS + (255,))
    d = ImageDraw.Draw(img)
    d.fontmode = '1'  # 文字もドットのまま
    tok_xy = None
    if t < 4.6:
        tok_xy = scene_terminal(img, d, t)
    water_top = round(H - ease_out(seg(t, 3.9, 4.5)) * H) if t < 4.5 else 0
    if t >= 3.9:
        draw_tank(img, d, t, water_top=max(0, water_top))
        d = ImageDraw.Draw(img); d.fontmode = '1'
        if t >= 4.5:
            draw_decos(img, t)
            draw_bubbles(d, t)
            draw_fish(img, t)
            draw_decos(img, t, layer_front=True)
            scene_rain(d, t)
            scene_hud(img, d, t)
    scene_coin(img, d, t, tok_xy)
    scene_ripple(d, t)
    scene_caption(img, d, t)
    scene_cards(img, d, t)
    scene_logo(img, d, t)
    fade = seg(t, 14.6, 15.0)
    if fade > 0:
        img.alpha_composite(Image.new('RGBA', (W, H), ABYSS + (int(255 * fade),)))
    fade_in = 1 - seg(t, 0, 0.25)
    if fade_in > 0:
        img.alpha_composite(Image.new('RGBA', (W, H), (0, 0, 0, int(255 * fade_in))))
    return img.convert('RGB').resize((W * SCALE, H * SCALE), Image.NEAREST)

# 効果音（秒, 名前, 音量）
SFX = [(0.45, 'click', .5), (0.85, 'click', .5), (1.25, 'click', .5), (2.55, 'sparkle', .6), (3.22, 'coin', .9), (4.42, 'tap', 1.0),
       (4.6, 'place', .6), (5.0, 'place', .5), (6.1, 'coin', .45), (7.2, 'coin', .4), (8.3, 'coin', .4), (9.55, 'buy', .6),
       (10.65, 'sparkle', .7), (11.75, 'sparkle', .7), (13.35, 'fanfare', .9)]

def main():
    os.makedirs(OUT, exist_ok=True)
    video = os.path.join(OUT, 'intro-video.mp4')
    n = int(DUR * FPS)
    enc = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W * SCALE}x{H * SCALE}',
                            '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-tune', 'animation',
                            '-pix_fmt', 'yuv420p', video], stdin=subprocess.PIPE)
    for i in range(n):
        enc.stdin.write(render(i / FPS).tobytes())
    enc.stdin.close()
    enc.wait()

    # 音: BGM（頭から15秒、入りと終わりをやわらかく）＋効果音
    inputs = ['-i', video, '-i', os.path.join(SND, 'bgm_day.m4a')]
    filters = [f'[1:a]atrim=0:{DUR},afade=t=in:d=0.6,afade=t=out:st={DUR - 1.4}:d=1.4,volume=0.85[bgm]']
    labels = ['[bgm]']
    for k, (at, name, vol) in enumerate(SFX):
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
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == '--stills':
        # 確認用に数コマだけ書き出す
        os.makedirs(OUT, exist_ok=True)
        for s in [0.3, 1.2, 2.6, 3.0, 3.4, 4.2, 4.7, 5.6, 7.0, 8.6, 9.8, 10.9, 12.0, 13.4, 14.3]:
            render(s).save(os.path.join(OUT, f'still-{s:05.2f}.png'))
        print('確認用の静止画:', OUT)
    else:
        main()
