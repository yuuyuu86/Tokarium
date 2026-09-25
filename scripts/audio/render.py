#!/usr/bin/env python3
"""Audio/midi/*.mid を自作のシンセで音にして、Resources/Sounds/*.m4a に書き出す。

使い方: python3 scripts/audio/render.py [名前...]   （必要: pip3 install mido numpy。変換に macOS の afconvert）
  --wav  変換前の WAV も build/sounds に残す（聞き比べ用）

音源（サンプル）は使わず、波形を計算で作る。loopEnd の目印がある曲は、
区切りからはみ出した残響を曲の頭に重ねて、つなぎ目なくループするようにする。
"""
import os, subprocess, sys, wave
import numpy as np
import mido

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MIDI = os.path.join(ROOT, 'Audio', 'midi')
OUT = os.path.join(ROOT, 'Resources', 'Sounds')
WORK = os.path.join(ROOT, 'build', 'sounds')
SR = 44100
TAIL = 4.0  # 残響のために余分に作る秒数


def hz(note):
    return 440.0 * 2 ** ((note - 69) / 12)


# MARK: - MIDI を読む

def read_midi(path):
    """(音のリスト, ループの長さ[秒] または None)。音は (開始, 長さ, チャンネル, プログラム, ノート, 強さ, パン)。"""
    mid = mido.MidiFile(path)
    tempo = 500000
    # 全トラックをまとめて時刻順に読む（テンポ変化にも対応）
    merged = mido.merge_tracks(mid.tracks)
    t = 0.0
    program = [0] * 16
    pan = [64] * 16
    active = {}
    notes = []
    loop_end = None
    for msg in merged:
        t += mido.tick2second(msg.time, mid.ticks_per_beat, tempo)
        if msg.type == 'set_tempo':
            tempo = msg.tempo
        elif msg.type == 'marker' and msg.text == 'loopEnd':
            loop_end = t
        elif msg.type == 'program_change':
            program[msg.channel] = msg.program
        elif msg.type == 'control_change' and msg.control == 10:
            pan[msg.channel] = msg.value
        elif msg.type == 'note_on' and msg.velocity > 0:
            active[(msg.channel, msg.note)] = (t, msg.velocity)
        elif msg.type in ('note_off', 'note_on'):
            key = (msg.channel, msg.note)
            if key in active:
                start, vel = active.pop(key)
                ch = msg.channel
                notes.append((start, t - start, ch, program[ch], msg.note, vel, pan[ch]))
    return notes, loop_end


# MARK: - 楽器

def env_adsr(n_samples, dur, a, d, s, r):
    """アタック・ディケイ・サステイン・リリース。dur は鍵盤を押している長さ。"""
    t = np.arange(n_samples) / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    held = np.minimum(t, dur)
    at_release = np.where(held < a, held / max(a, 1e-4), s + (1 - s) * np.exp(-(held - a) / max(d, 1e-4)))
    after = t > dur
    e = np.where(after, at_release * np.exp(-(t - dur) / max(r, 1e-4)), e)
    return e


def additive(freq, t, partials, phase_mod=None):
    """倍音を足して波形を作る。partials は (倍率, 大きさ, 減衰の速さ)。ナイキストを超える倍音は入れない。"""
    out = np.zeros_like(t)
    base_phase = 2 * np.pi * freq * t if phase_mod is None else phase_mod
    for ratio, amp, decay in partials:
        if freq * ratio >= SR / 2 - 500:
            continue
        w = np.sin(base_phase * ratio)
        if decay:
            w *= np.exp(-t * decay)
        out += amp * w
    return out


def pulse_lead(freq, dur, vel):
    """やわらかい矩形波（25%）。少し遅れてビブラートがかかる。"""
    length = dur + 0.35
    t = np.arange(int(length * SR)) / SR
    vib = 1 + 0.0045 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.22) / 0.3, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    duty = 0.25
    partials = [(k, (2 / (k * np.pi)) * abs(np.sin(k * np.pi * duty)) * (0.82 ** k), 0) for k in range(1, 14)]
    w = additive(freq, t, partials, phase_mod=phase)
    return w * env_adsr(len(t), dur, 0.012, 0.18, 0.62, 0.12) * 0.55


def music_box(freq, dur, vel):
    """オルゴール: すぐ立ち上がり、高い倍音ほど早く消える。少しだけ金属っぽい倍音。"""
    length = max(dur, 0.2) + 1.8
    t = np.arange(int(length * SR)) / SR
    w = additive(freq, t, [(1, 1.0, 1.6), (2, 0.28, 3.5), (3, 0.08, 6), (4.21, 0.06, 9), (6.8, 0.03, 16)])
    a = np.clip(t / 0.002, 0, 1)
    # 押している長さが短ければ早めに消す
    damp = np.where(t > dur + 0.9, np.exp(-(t - dur - 0.9) / 0.25), 1.0)
    return w * a * damp * 0.5


def harp(freq, dur, vel):
    """はじいた弦（ハープ）。倍音ごとに減衰を変える。"""
    length = dur + 1.2
    t = np.arange(int(length * SR)) / SR
    partials = [(k, 1 / k ** 1.3, 1.4 + k * 0.9) for k in range(1, 11)]
    w = additive(freq, t, partials)
    a = np.clip(t / 0.003, 0, 1)
    damp = np.where(t > dur, np.exp(-(t - dur) / 0.35), 1.0)
    return w * a * damp * 0.45


def pad_voice(freq, dur, vel, detune=0.0):
    """パッド: 少しずらしたのこぎり波を重ね、ゆっくり立ち上げる。"""
    length = dur + 1.6
    t = np.arange(int(length * SR)) / SR
    f = freq * 2 ** (detune / 1200)
    partials = [(k, 1 / k ** 1.7, 0) for k in range(1, 9)]
    w = additive(f, t, partials)
    trem = 1 + 0.06 * np.sin(2 * np.pi * 0.23 * t + freq)
    return w * trem * env_adsr(len(t), dur, 0.9, 1.5, 0.8, 1.2) * 0.22


def bass(freq, dur, vel):
    """三角波のベース。"""
    length = dur + 0.3
    t = np.arange(int(length * SR)) / SR
    partials = [(k, ((-1) ** ((k - 1) // 2)) / k ** 2, 0) for k in (1, 3, 5, 7, 9)]
    w = additive(freq, t, partials)
    return w * env_adsr(len(t), dur, 0.012, 0.4, 0.7, 0.15) * 0.8


def bubble(note, vel):
    """泡: 音程が上がりながら消える正弦波（泡がはじける音の近似）。"""
    radius = np.interp(note, [60, 96], [1.0, 0.25])
    f0 = 380 / radius
    length = 0.06 + 0.1 * radius
    t = np.arange(int(length * SR)) / SR
    f = f0 * (1 + t * (6 + 10 * (1 - radius)))
    phase = 2 * np.pi * np.cumsum(f) / SR
    e = np.clip(t / 0.003, 0, 1) * np.exp(-t / (0.02 + 0.03 * radius))
    return np.sin(phase) * e * 0.6


def drop(note, vel):
    """しずく・粒: 短く高い音から低い音へ。"""
    size = np.interp(note, [36, 59], [1.0, 0.2])
    f0 = 900 + 1800 * (1 - size)
    length = 0.05 + 0.06 * size
    t = np.arange(int(length * SR)) / SR
    f = f0 * np.exp(-t * 18) + f0 * 0.5
    phase = 2 * np.pi * np.cumsum(f) / SR
    e = np.clip(t / 0.001, 0, 1) * np.exp(-t / (0.012 + 0.02 * size))
    return np.sin(phase) * e * 0.55


def lowpass(x, cutoff):
    """FFT で周波数を切る簡単なフィルター（オフラインなのでこれで十分）。"""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1 / np.sqrt(1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(spec, len(x))


def bandpass(x, lo, hi):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1 / np.sqrt(1 + (freqs / hi) ** 4) * (1 / np.sqrt(1 + (lo / np.maximum(freqs, 1)) ** 4))
    return np.fft.irfft(spec, len(x))


def swoosh(dur, vel, rng):
    """水が流れる音: 形を変えていくノイズ。"""
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    body = bandpass(noise, 250, 2200)
    fizz = bandpass(noise, 3000, 7000) * 0.25
    e = np.clip(t / 0.08, 0, 1) * np.where(t > dur * 0.4, np.exp(-(t - dur * 0.4) / (dur * 0.35)), 1)
    wobble = 1 + 0.35 * np.sin(2 * np.pi * 3.1 * t) * np.sin(2 * np.pi * 0.7 * t)
    w = (body + fizz) * e * wobble
    return w / (np.max(np.abs(w)) + 1e-9) * 0.5


def thud(vel):
    """ことっ: 低い音程が下がる短い音と、砂のこすれるノイズ。"""
    t = np.arange(int(0.3 * SR)) / SR
    f = 180 * np.exp(-t * 9) + 70
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.06)
    rng = np.random.default_rng(5)
    sand = lowpass(rng.standard_normal(len(t)), 1500) * np.exp(-t / 0.03) * 0.15
    return (body + sand) * 0.7


def tick(vel):
    """カチッ: とても短い高い音。"""
    t = np.arange(int(0.035 * SR)) / SR
    w = np.sin(2 * np.pi * 2400 * t) * 0.6 + np.sin(2 * np.pi * 3700 * t) * 0.3
    return w * np.exp(-t / 0.006) * 0.4


# MARK: - 残響（作った響きの形とのたたみこみ）

def impulse_response(seconds, seed):
    """小さな部屋の響き。高い音ほど早く消える。左右で少し違う響きにする。"""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros(n)
    for lo, hi, decay in [(20, 500, 1.1), (500, 2000, 0.8), (2000, 6000, 0.5), (6000, 16000, 0.25)]:
        band = bandpass(rng.standard_normal(n), lo, hi)
        ir += band * np.exp(-t * 6.9 / (decay * 2.2))
    ir *= np.clip((t - 0.012) / 0.02, 0, 1)  # 少し遅れて響き始める
    return ir / np.sqrt(np.sum(ir ** 2))


def convolve(x, ir):
    size = len(x) + len(ir) - 1
    nfft = 1 << (size - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:len(x)]


# MARK: - ミックス

# プログラム番号 → (楽器, 音量, 残響へ送る量)
INSTRUMENTS = {
    80: (pulse_lead, 0.9, 0.22),
    10: (music_box, 0.8, 0.4),
    46: (harp, 0.7, 0.32),
    89: (pad_voice, 1.0, 0.45),
    38: (bass, 0.9, 0.06),
}
DRUM_REVERB = 0.3


def render(notes, total):
    n = int(total * SR)
    dry = np.zeros((2, n))
    wet = np.zeros((2, n))
    rng = np.random.default_rng(1)

    def mix(signal, start, gain, pan_value, send):
        i = int(start * SR)
        if i >= n:
            return
        s = signal[: n - i] * gain
        angle = (pan_value / 127) * np.pi / 2
        left, right = np.cos(angle), np.sin(angle)
        dry[0, i:i + len(s)] += s * left
        dry[1, i:i + len(s)] += s * right
        wet[0, i:i + len(s)] += s * left * send
        wet[1, i:i + len(s)] += s * right * send

    for start, dur, ch, program, note, vel, pan in notes:
        v = (vel / 127) ** 1.6
        if ch == 9:
            if note == 30:
                sig = swoosh(dur, vel, rng)
            elif note == 35:
                sig = thud(vel)
            elif note == 42:
                sig = tick(vel)
            elif 36 <= note <= 59:
                sig = drop(note, vel)
            else:
                sig = bubble(note, vel)
            mix(sig, start, v, pan + rng.integers(-18, 19), DRUM_REVERB)
            continue
        inst, gain, send = INSTRUMENTS.get(program, INSTRUMENTS[10])
        if inst is pad_voice:
            # 3つの声を少しずつずらし、左右に広げる
            for detune, p in [(-7, pan - 30), (0, pan), (7, pan + 30)]:
                mix(pad_voice(hz(note), dur, vel, detune), start, v * gain / 1.7, int(np.clip(p, 0, 127)), send)
        else:
            mix(inst(hz(note), dur, vel), start, v * gain, pan, send)

    irs = [impulse_response(3.0, 21), impulse_response(3.0, 22)]
    out = dry.copy()
    for c in range(2):
        out[c] += convolve(wet[c], irs[c]) * 0.9
    return out


def master(out, peak_db):
    # 耳につく高音を少しだけ丸め、低すぎる音を切る
    for c in range(out.shape[0]):
        out[c] = lowpass(out[c], 9000)
        out[c] -= lowpass(out[c], 35)
    peak = np.max(np.abs(out)) + 1e-9
    out *= (10 ** (peak_db / 20)) / peak
    return out


def fade_edges(out, fade_in=0.002, fade_out=0.05):
    a, b = int(fade_in * SR), int(fade_out * SR)
    out[:, :a] *= np.linspace(0, 1, a)
    out[:, -b:] *= np.linspace(1, 0, b)
    return out


def trim_silence(out, threshold_db=-60):
    level = np.max(np.abs(out), axis=0)
    above = np.nonzero(level > 10 ** (threshold_db / 20) * np.max(level))[0]
    return out[:, : above[-1] + int(0.02 * SR)] if len(above) else out


def write_wav(path, out):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(out.T, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(out.shape[0])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# 効果音ごとの音量（ほかの音とのつりあい。1 = いちばん大きい）
SFX_LEVEL = {
    'eat': -14, 'tap': -6, 'click': -12, 'feed': -6, 'water': -4, 'coin': -6, 'buy': -5, 'place': -4,
    'error': -8, 'medicine': -5, 'sparkle': -7, 'treasure': -3, 'fanfare': -3, 'birth': -4, 'sad': -6, 'farewell': -5,
}


def build(name, keep_wav):
    notes, loop_end = read_midi(os.path.join(MIDI, name + '.mid'))
    end = max(s + d for s, d, *_ in notes)
    if loop_end:
        # ループ: 区切りまでの長さ + 残響。はみ出した分を頭に重ねる
        out = render(notes, loop_end + TAIL)
        length = int(round(loop_end * SR))
        head = out[:, :length].copy()
        spill = out[:, length:]
        head[:, : spill.shape[1]] += spill
        out = master(head, -3.0)
    else:
        out = render(notes, end + 2.5)
        out = trim_silence(out)
        # 効果音はモノラルで十分
        out = out.mean(axis=0, keepdims=True)
        out = master(out, SFX_LEVEL.get(name.removeprefix('sfx_'), -6))
        out = fade_edges(out)
    wav = os.path.join(WORK, name + '.wav')
    write_wav(wav, out)
    os.makedirs(OUT, exist_ok=True)
    m4a = os.path.join(OUT, name + '.m4a')
    bitrate = '160000' if loop_end else '96000'
    subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', bitrate, wav, m4a], check=True)
    if not keep_wav:
        os.remove(wav)
    print(f'{os.path.basename(m4a)}: {out.shape[1] / SR:.2f} 秒' + ('（ループ）' if loop_end else ''))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    keep = '--wav' in sys.argv
    names = args or sorted(f[:-4] for f in os.listdir(MIDI) if f.endswith('.mid'))
    for name in names:
        build(name, keep)
