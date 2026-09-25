#!/usr/bin/env python3
"""Tokarium の BGM と効果音を MIDI で作曲する。

使い方: python3 scripts/audio/compose.py   （必要: pip3 install mido）
Audio/midi/*.mid を書き出す。音にするのは scripts/audio/render.py。

楽器（プログラム番号は General MIDI に合わせてあるので、ふつうの MIDI プレイヤーでも鳴る）
  80 矩形波のリード / 10 オルゴール / 46 ハープ / 89 パッド / 38 ベース
  チャンネル10（打楽器）は水の音:
    30 水の流れ / 35 ことっ（置く音） / 42 カチッ
    36〜59 しずく（音が高いほど小さなしずく） / 60〜96 泡（音が高いほど小さな泡）
"""
import os, random
import mido

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'Audio', 'midi')
TPB = 480

NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def n(name):
    """'C4' 'Bb3' 'F#5' → MIDI のノート番号（C4 = 60）"""
    base = NAMES[name[0]]
    i = 1
    while i < len(name) and name[i] in '#b':
        base += 1 if name[i] == '#' else -1
        i += 1
    return base + 12 * (int(name[i:]) + 1)


class Song:
    def __init__(self, bpm, loop_beats=None):
        self.bpm = bpm
        self.loop_beats = loop_beats
        self.parts = []  # (名前, チャンネル, プログラム, パン, 音のリスト)

    def part(self, name, channel, program, pan=64):
        notes = []
        self.parts.append((name, channel, program, pan, notes))
        return notes

    def save(self, filename):
        mid = mido.MidiFile(type=1, ticks_per_beat=TPB)
        meta = mido.MidiTrack()
        meta.append(mido.MetaMessage('track_name', name='Tokarium', time=0))
        meta.append(mido.MetaMessage('set_tempo', tempo=mido.bpm2tempo(self.bpm), time=0))
        meta.append(mido.MetaMessage('time_signature', numerator=4, denominator=4, time=0))
        if self.loop_beats:
            # 繰り返しの区切り（render.py はここで折り返してつなぎ目なくループさせる）
            meta.append(mido.MetaMessage('marker', text='loopEnd', time=round(self.loop_beats * TPB)))
        meta.append(mido.MetaMessage('end_of_track', time=0))
        mid.tracks.append(meta)
        for name, ch, program, pan, notes in self.parts:
            tr = mido.MidiTrack()
            tr.append(mido.MetaMessage('track_name', name=name, time=0))
            if ch != 9:
                tr.append(mido.Message('program_change', channel=ch, program=program, time=0))
            tr.append(mido.Message('control_change', channel=ch, control=10, value=pan, time=0))
            events = []
            for start, dur, note, vel in notes:
                events.append((round(start * TPB), 1, mido.Message('note_on', channel=ch, note=note, velocity=vel)))
                events.append((round((start + dur) * TPB), 0, mido.Message('note_off', channel=ch, note=note, velocity=0)))
            events.sort(key=lambda e: (e[0], e[1]))
            now = 0
            for tick, _, msg in events:
                tr.append(msg.copy(time=tick - now))
                now = tick
            tr.append(mido.MetaMessage('end_of_track', time=0))
            mid.tracks.append(tr)
        os.makedirs(OUT, exist_ok=True)
        mid.save(os.path.join(OUT, filename))


def melody(notes, spec, start, vel=80):
    """'C5:1.5 A4:.5 r:1' のような書き方で旋律を足す。戻り値は終わりの拍。"""
    t = start
    for tok in spec.split():
        name, dur = tok.split(':')
        dur = float(dur)
        if name != 'r':
            notes.append((t, dur * 0.95, n(name), vel))
        t += dur
    return t


def add_bubbles(drums, rng, total_beats, beat_sec, every=(2.5, 6.0), vel=(34, 52)):
    """ときどき、いくつかの泡がのぼっていく。"""
    t = rng.uniform(0.5, 2.0) / beat_sec
    while t < total_beats - 0.5:
        count = rng.randint(1, 4)
        pitch = rng.randint(68, 84)
        for k in range(count):
            drums.append((t + k * rng.uniform(0.08, 0.2) / beat_sec, 0.1, min(96, pitch + k * rng.randint(1, 4)), rng.randint(*vel)))
        t += rng.uniform(*every) / beat_sec


# MARK: - 昼の曲（F メジャー・ゆったり）

def compose_day():
    bpm = 72
    bars = 32
    song = Song(bpm, loop_beats=bars * 4)
    lead = song.part('Lead', 0, 80, pan=58)
    box = song.part('Music Box', 1, 10, pan=76)
    pad = song.part('Pad', 2, 89)
    bass = song.part('Bass', 3, 38)
    harp = song.part('Harp', 4, 46, pan=48)
    drums = song.part('Water', 9, 0)

    C = {
        'Fmaj7': (['F3', 'A3', 'C4', 'E4'], 'F2'),
        'Am7': (['E3', 'G3', 'A3', 'C4'], 'A2'),
        'Bbmaj7': (['F3', 'A3', 'Bb3', 'D4'], 'Bb2'),
        'C6': (['E3', 'G3', 'A3', 'C4'], 'C3'),
        'Gm7': (['F3', 'G3', 'Bb3', 'D4'], 'G2'),
        'C7sus': (['F3', 'G3', 'Bb3', 'C4'], 'C3'),
        'Dm7': (['F3', 'A3', 'C4', 'D4'], 'D3'),
        'Csus': (['F3', 'G3', 'C4', 'E4'], 'C3'),
    }
    prog_a = ['Fmaj7', 'Am7', 'Bbmaj7', 'C6', 'Fmaj7', 'Am7', 'Gm7', 'C7sus']
    prog_b = ['Dm7', 'Am7', 'Bbmaj7', 'Fmaj7', 'Gm7', 'Am7', 'Bbmaj7', 'Csus']
    progression = prog_a + prog_a + prog_b + prog_a

    for bar, name in enumerate(progression):
        voicing, root = C[name]
        b = bar * 4
        section = bar // 8
        # パッド: 小節いっぱいのやわらかい和音
        for v in voicing:
            pad.append((b, 4, n(v), 46 if section != 2 else 52))
        # ベース: ルートと5度をゆっくり
        r = n(root)
        fifth = r + 7
        if section == 2:
            bass.append((b, 3.8, r, 70))
        else:
            bass.append((b, 1.4, r, 74))
            bass.append((b + 1.5, 0.45, fifth, 56))
            bass.append((b + 2, 1.4, r, 66))
            bass.append((b + 3.5, 0.45, fifth, 52))
        # ハープ: 8分音符の分散和音（1オクターブ上）
        tones = [n(v) + 12 for v in voicing]
        pattern = [0, 2, 1, 3, 2, 1, 3, 2] if section != 2 else [0, 2, 3, 2]
        step = 4 / len(pattern)
        for i, idx in enumerate(pattern):
            vel = 50 if i % 2 == 0 else 38
            if section == 2:
                vel -= 6
            harp.append((b + i * step, step * 1.6, tones[idx], vel))

    # 旋律 A（8小節）
    mel_a = ('C5:1.5 A4:.5 C5:1 F5:1 | E5:3 C5:1 | D5:1.5 F5:.5 A5:1 G5:1 | G5:2 E5:1 C5:1 | '
             'A5:1.5 G5:.5 F5:1 C5:1 | E5:2 r:1 C5:1 | D5:1 F5:1 A5:1 G5:1 | G5:3 r:1').replace('|', '')
    mel_a2 = ('C5:1.5 A4:.5 C5:1 F5:1 | E5:3 C5:1 | D5:1.5 F5:.5 A5:1 G5:1 | G5:2 E5:1 C5:1 | '
              'A5:1.5 G5:.5 F5:1 C5:1 | E5:2 r:1 C5:1 | Bb4:1 D5:1 G5:1 E5:1 | F5:4').replace('|', '')
    mel_b = ('A5:2 F5:1 D5:1 | E5:2 C5:1 E5:1 | F5:1.5 D5:.5 A5:2 | G5:1 F5:1 C5:2 | '
             'D5:1 F5:1 Bb5:1 A5:1 | G5:1 E5:1 C5:2 | D5:1 F5:1 A5:1 C6:1 | Bb5:2 G5:2').replace('|', '')
    melody(lead, mel_a, 0, vel=78)
    melody(lead, mel_a2, 32, vel=80)
    melody(box, mel_b, 64, vel=84)
    melody(lead, mel_a, 96, vel=76)
    # 2回目の A はオルゴールが3度上で寄りそう
    counter = ('A5:4 | G5:4 | F5:4 | E5:4 | C6:4 | G5:4 | D5:2 E5:2 | A5:4').replace('|', '')
    melody(box, counter, 32, vel=52)
    # 最後の A では、区切りごとにきらめき
    for bar in (103, 111, 127):
        for i, v in enumerate(['C6', 'E6', 'G6', 'C7']):
            box.append((bar * 4 + 2 + i * 0.25, 0.5, n(v), 40 - i * 3))

    add_bubbles(drums, random.Random(7), bars * 4, 60 / bpm)
    song.save('bgm_day.mid')


# MARK: - 夜の曲（A マイナー・静か）

def compose_night():
    bpm = 60
    bars = 32
    song = Song(bpm, loop_beats=bars * 4)
    box = song.part('Music Box', 1, 10, pan=70)
    pad = song.part('Pad', 2, 89)
    bass = song.part('Bass', 3, 38)
    harp = song.part('Harp', 4, 46, pan=52)
    drums = song.part('Water', 9, 0)

    C = {
        'Am9': (['E3', 'G3', 'B3', 'C4'], 'A2'),
        'Fmaj7': (['E3', 'F3', 'A3', 'C4'], 'F2'),
        'Cmaj7': (['E3', 'G3', 'B3', 'C4'], 'C3'),
        'G6': (['D3', 'E3', 'G3', 'B3'], 'G2'),
        'Dm9': (['E3', 'F3', 'A3', 'C4'], 'D3'),
        'E': (['E3', 'G#3', 'B3', 'D4'], 'E2'),
    }
    prog = ['Am9', 'Fmaj7', 'Cmaj7', 'G6', 'Am9', 'Fmaj7', 'Dm9', 'E'] * 4

    for bar, name in enumerate(prog):
        voicing, root = C[name]
        b = bar * 4
        section = bar // 8
        for v in voicing:
            pad.append((b, 4, n(v), 50))
        bass.append((b, 3.9, n(root), 62))
        # ハープ: 4分音符でゆっくり上っていく
        tones = [n(v) + 12 for v in voicing]
        if section in (0, 2):
            for i in range(4):
                harp.append((b + i, 2.5, tones[i], 42 - i * 2))
        else:
            for i, idx in enumerate([0, 2, 3]):
                harp.append((b + i * 1.25, 2.5, tones[idx] + (12 if i == 2 else 0), 36))

    mel_1 = ('E5:2 B4:2 | C5:3 A4:1 | G4:2 B4:1 E5:1 | D5:4 | '
             'E5:1 G5:1 B5:2 | A5:2 E5:2 | F5:1 E5:1 D5:1 C5:1 | B4:4').replace('|', '')
    mel_3 = ('A5:1 B5:1 C6:2 | A5:2 G5:1 E5:1 | G5:3 E5:1 | D5:2 E5:1 G5:1 | '
             'E5:2 A5:2 | C6:1 B5:1 A5:2 | F5:1 A5:1 G5:1 E5:1 | B5:2 G#5:2').replace('|', '')
    melody(box, mel_1, 0, vel=78)
    melody(box, mel_3, 64, vel=80)
    # 2と4の区切りは、ぽつりぽつりと鳴るだけ
    for bar, v in [(9, 'E6'), (11, 'B5'), (13, 'C6'), (15, 'B5'), (25, 'A5'), (27, 'G5'), (29, 'E5'), (31, 'G#5')]:
        box.append((bar * 4 + 1, 2.5, n(v), 50))

    add_bubbles(drums, random.Random(11), bars * 4, 60 / bpm, every=(3.5, 8.0), vel=(28, 44))
    song.save('bgm_night.mid')


# MARK: - 効果音（テンポ60 = 1拍が1秒）

def sfx(name, build):
    song = Song(60)
    build(song)
    song.save(f'sfx_{name}.mid')


def compose_effects():
    rng = random.Random(3)

    def tap(s):  # 水をたたく: ぽちゃん
        d = s.part('Water', 9, 0)
        d.append((0, 0.12, 44, 96))
        d.append((0.05, 0.1, 76, 60))
        d.append((0.13, 0.1, 82, 44))

    def feed(s):  # 餌をまく: さらさら
        d = s.part('Water', 9, 0)
        for i in range(7):
            d.append((i * 0.055 + rng.uniform(0, 0.02), 0.05, rng.randint(52, 58), 70 - i * 4))

    def eat(s):  # ぱくっ
        d = s.part('Water', 9, 0)
        d.append((0, 0.06, 86, 80))

    def water(s):  # 水換え: ざーっと流れて、泡がのぼる
        d = s.part('Water', 9, 0)
        d.append((0, 1.3, 30, 100))
        for i in range(10):
            d.append((0.25 + i * 0.1 + rng.uniform(0, 0.04), 0.1, 64 + i * 2 + rng.randint(0, 3), 70))

    def coin(s):  # コイン: ティリン
        lead = s.part('Lead', 0, 80)
        melody(lead, 'B5:.07 E6:.4', 0, vel=90)

    def buy(s):  # 買う: チャリン
        lead = s.part('Lead', 0, 80)
        box = s.part('Music Box', 1, 10)
        melody(lead, 'E6:.06 G6:.06 C7:.3', 0, vel=80)
        box.append((0.12, 0.6, n('C6'), 70))
        box.append((0.12, 0.6, n('G6'), 60))

    def place(s):  # 装飾を置く: ことっ
        d = s.part('Water', 9, 0)
        d.append((0, 0.25, 35, 110))
        d.append((0.08, 0.1, 70, 50))
        d.append((0.18, 0.1, 76, 40))

    def error(s):  # できない: ぶぶっ（やわらかく）
        lead = s.part('Lead', 0, 80)
        melody(lead, 'E4:.09 r:.03 C4:.22', 0, vel=70)

    def medicine(s):  # 薬: こぽこぽ、きらっ
        d = s.part('Water', 9, 0)
        box = s.part('Music Box', 1, 10)
        for i, p in enumerate([62, 66, 70, 75]):
            d.append((i * 0.09, 0.1, p, 80))
        box.append((0.42, 0.8, n('E6'), 60))
        box.append((0.5, 0.8, n('B6'), 50))

    def sparkle(s):  # きらっ（お気に入り・成長）
        box = s.part('Music Box', 1, 10)
        for i, v in enumerate(['G6', 'B6', 'D7', 'G7']):
            box.append((i * 0.05, 0.6, n(v), 70 - i * 8))

    def treasure(s):  # 宝箱: 上っていく分散和音と和音
        harp = s.part('Harp', 4, 46)
        box = s.part('Music Box', 1, 10)
        for i, v in enumerate(['F5', 'A5', 'C6', 'F6']):
            harp.append((i * 0.07, 1.0, n(v), 80))
        for v in ['F6', 'A6', 'C7']:
            box.append((0.3, 1.2, n(v), 66))
        for i, v in enumerate(['C7', 'F7']):
            box.append((0.55 + i * 0.07, 0.6, n(v), 40))

    def fanfare(s):  # 実績: ちいさなファンファーレ
        lead = s.part('Lead', 0, 80, pan=56)
        box = s.part('Music Box', 1, 10, pan=72)
        bass = s.part('Bass', 3, 38)
        melody(lead, 'C5:.12 E5:.12 G5:.12 C6:.24 G5:.12 C6:.6', 0, vel=84)
        melody(box, 'r:.36 E6:.24 r:.12 E6:.6', 0, vel=60)
        bass.append((0, 0.3, n('C3'), 80))
        bass.append((0.36, 0.3, n('G2'), 70))
        bass.append((0.72, 0.7, n('C3'), 80))

    def birth(s):  # 稚魚が生まれた: やさしく上がる
        box = s.part('Music Box', 1, 10)
        pad = s.part('Pad', 2, 89)
        melody(box, 'C6:.14 D6:.14 E6:.14 G6:.7', 0, vel=74)
        for v in ['C4', 'E4', 'G4']:
            pad.append((0, 1.0, n(v), 40))

    def sad(s):  # 魚が死んでしまった: しずかに下がる
        box = s.part('Music Box', 1, 10)
        pad = s.part('Pad', 2, 89)
        melody(box, 'E5:.35 C5:.35 A4:1.0', 0, vel=64)
        for v in ['A3', 'C4', 'E4']:
            pad.append((0, 1.6, n(v), 36))

    def farewell(s):  # お別れ: 鐘のような和音
        box = s.part('Music Box', 1, 10)
        harp = s.part('Harp', 4, 46)
        for v in ['A4', 'E5', 'C#6']:
            box.append((0, 1.6, n(v), 56))
        for i, v in enumerate(['A3', 'E4', 'A4']):
            harp.append((0.05 + i * 0.1, 1.4, n(v), 46))

    def click(s):  # 画面の切り替え: かちっ
        d = s.part('Water', 9, 0)
        d.append((0, 0.03, 42, 90))

    for name, build in [('tap', tap), ('feed', feed), ('eat', eat), ('water', water), ('coin', coin), ('buy', buy),
                        ('place', place), ('error', error), ('medicine', medicine), ('sparkle', sparkle),
                        ('treasure', treasure), ('fanfare', fanfare), ('birth', birth), ('sad', sad),
                        ('farewell', farewell), ('click', click)]:
        sfx(name, build)


if __name__ == '__main__':
    compose_day()
    compose_night()
    compose_effects()
    print('書き出しました:', OUT)
