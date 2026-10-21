"""Blender (headless) audio helper built on Blender's bundled audaspace + numpy, so no ffmpeg
or Python audio packages are needed.

    blender --background --factory-startup --python tools/blender/audio_tool.py -- decode in.flac out.npy
        mono float32 at 44100 Hz
    blender ... -- plot in.npy out.png [t0 t1]
        waveform envelope (top) and log spectrogram (bottom), 1 px column per time slice
    blender ... -- cut spec.json
        spec: {"src": "in.npy", "out_dir": "...", "cuts": [{"name", "t0", "t1", "fade_in",
        "fade_out", "gain_db", "loop", "highpass"}...]} -> 16-bit mono .wav files; a loop gets
        its tail cross-faded into its head so the seam is seamless. "match" scales a cut to a
        target RMS (whole clip, or loudest 100 ms); gain that would clip goes into
        out_dir/levels.json as a playback trim per sound (variants "x_0", "x_1" share "x"); trims
        of sounds not in the spec are kept. A cut with "grains": {"len", "rate", "dur", "seed",
        "min_rms"} is a texture instead: short Hann-windowed grains taken at random from the loud
        parts of t0..t1, overlap-added at random times into "dur" seconds (e.g. snow crunch ->
        skis carving).
"""
import json
import os
import sys
import wave

import aud
import bpy
import numpy as np

RATE = 44100


def decode(src, dst):
    snd = aud.Sound(src).resample(RATE, False)
    a = snd.data()                       # (frames, channels) float32
    mono = a.mean(axis=1).astype(np.float32)
    np.save(dst, mono)
    print(f"[audio] {src}: {len(mono) / RATE:.2f} s, peak {np.abs(mono).max():.3f}")


def save_png(rgb, path):
    h, w, _ = rgb.shape
    img = bpy.data.images.new("plot", w, h, alpha=False)
    px = np.ones((h, w, 4), np.float32)
    px[..., :3] = rgb[::-1]
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def plot(src, dst, t0=None, t1=None):
    x = np.load(src)
    a = int((t0 or 0.0) * RATE)
    b = int(t1 * RATE) if t1 else len(x)
    x = x[a:b]
    w = 1600
    hop = max(1, len(x) // w)
    n = 1024
    env_h, spec_h = 160, 256
    out = np.zeros((env_h + spec_h, w, 3), np.float32)
    win = np.hanning(n).astype(np.float32)
    for c in range(w):
        seg = x[c * hop:c * hop + hop]
        if len(seg) == 0:
            break
        pk = min(1.0, float(np.abs(seg).max()) * 2.0)
        rms = min(1.0, float(np.sqrt((seg ** 2).mean())) * 6.0)
        out[env_h - int(pk * (env_h - 1)):env_h, c] = (0.35, 0.45, 0.6)
        out[env_h - int(rms * (env_h - 1)):env_h, c] = (0.9, 0.9, 0.5)
        mid = c * hop + hop // 2
        fr = x[max(0, mid - n // 2):mid + n // 2]
        if len(fr) < n:
            fr = np.pad(fr, (0, n - len(fr)))
        mag = np.abs(np.fft.rfft(fr * win))[1:]
        # Log-frequency rows from 40 Hz to 16 kHz.
        f = np.geomspace(40, 16000, spec_h)
        idx = np.clip((f / (RATE / n)).astype(int), 0, len(mag) - 1)
        db = 20 * np.log10(mag[idx] + 1e-6)
        v = np.clip((db + 30) / 60, 0, 1)
        out[env_h:, c, 0] = v[::-1]
        out[env_h:, c, 1] = v[::-1] ** 2
        out[env_h:, c, 2] = v[::-1] ** 4 * 0.5 + 0.1 * v[::-1]
    # Second ticks.
    secs = len(x) / RATE
    step = 1.0 if secs < 30 else 5.0
    t = 0.0
    while t < secs:
        c = int(t * RATE / hop)
        if c < w:
            out[:8, c] = (1, 0.3, 0.3)
        t += step
    save_png(out, dst)
    print(f"[audio] plot {dst}: {secs:.2f} s, {hop / RATE * 1000:.1f} ms/px, ticks every {step} s")


def write_wav(path, y):
    y = np.clip(y, -1.0, 1.0)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((y * 32767).astype("<i2").tobytes())


def highpass(y, hz):
    k = np.exp(-2 * np.pi * hz / RATE)
    out = np.empty_like(y)
    lp = 0.0
    for i in range(len(y)):          # one-pole; clips are short
        lp = lp * k + y[i] * (1 - k)
        out[i] = y[i] - lp
    return out


def granular(src, g, xfade):
    rng = np.random.default_rng(g.get("seed", 1))
    n = int(g.get("len", 0.06) * RATE)
    win = np.hanning(n)
    # Grain starts only where the source is loud enough (inside the crunches, not the gaps).
    e = np.sqrt(np.convolve(src ** 2, np.ones(n) / n, mode="valid"))
    ok = np.nonzero(e > e.max() * g.get("min_rms", 0.25))[0]
    total = int((g.get("dur", 3.0) + xfade) * RATE)
    y = np.zeros(total + n)
    count = int(g.get("rate", 80) * total / RATE)
    for t in rng.integers(0, total, count):
        a = ok[rng.integers(0, len(ok))]
        gr = src[a:a + n] / max(e[a], 1e-6) * rng.uniform(0.5, 1.0)
        y[t:t + n] += gr * win * (1 if rng.random() < 0.5 else -1)
    return y[:total]


def cut(spec_path):
    spec = json.load(open(spec_path, encoding="utf-8"))
    os.makedirs(spec["out_dir"], exist_ok=True)
    cache = {}
    out = []
    for c in spec["cuts"]:
        src = c.get("src", spec.get("src"))
        if src not in cache:
            cache[src] = np.load(src)
        x = cache[src]
        y = x[int(c["t0"] * RATE):int(c["t1"] * RATE)].astype(np.float64)
        y = y - y.mean()
        if c.get("grains"):
            y = granular(y, c["grains"], c.get("xfade", 0.4) if c.get("loop") else 0.0)
        if c.get("highpass"):
            y = highpass(y, c["highpass"])
        if c.get("loop"):
            xf = int(c.get("xfade", 0.4) * RATE)
            head, body, tail = y[:xf], y[xf:len(y) - xf], y[len(y) - xf:]
            r = np.linspace(0, 1, xf)
            # Equal-power blend: the tail fades out as the head fades in at the seam.
            seam = tail * np.cos(r * np.pi / 2) + head * np.sin(r * np.pi / 2)
            y = np.concatenate([body, seam])
        else:
            fi = int(c.get("fade_in", 0.003) * RATE)
            fo = int(c.get("fade_out", 0.05) * RATE)
            if fi > 0:
                y[:fi] *= np.linspace(0, 1, fi)
            if fo > 0:
                y[-fo:] *= np.linspace(1, 0, fo)
        if c.get("normalize", True):
            y = y / max(np.abs(y).max(), 1e-6) * 0.89
        if "match" in c:
            # Loudness of the sound this replaces: whole-clip RMS, or the loudest 100 ms.
            if c.get("match_mode", "rms100") == "rms":
                have = np.sqrt((y ** 2).mean())
            else:
                win = int(0.1 * RATE)
                e = np.convolve(y ** 2, np.ones(win), mode="valid") / win if len(y) > win else [(y ** 2).mean()]
                have = np.sqrt(np.max(e))
            k = c["match"] / max(have, 1e-6)
            y = y * k
        y = y * 10 ** (c.get("gain_db", 0.0) / 20)
        out.append((c["name"], y))
    # A peaky recording would clip at the matched level: scale it down and apply the rest of
    # the gain at playback. Variants ("pop_0", "pop_1") share one trim so they stay matched.
    groups = {}
    for name, y in out:
        base = name.rsplit("_", 1)[0] if name.rsplit("_", 1)[-1].isdigit() else name
        groups.setdefault(base, []).append(np.abs(y).max())
    levels = {b: round(max(0.0, 20 * np.log10(max(pk) / 0.99)), 2) for b, pk in groups.items()}
    for name, y in out:
        base = name.rsplit("_", 1)[0] if name.rsplit("_", 1)[-1].isdigit() else name
        y = y * 10 ** (-levels[base] / 20)
        path = os.path.join(spec["out_dir"], name + ".wav")
        write_wav(path, y)
        print(f"[audio] {path}: {len(y) / RATE:.2f} s")
    path = os.path.join(spec["out_dir"], "levels.json")
    old = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    old = {b: v for b, v in old.items() if b not in levels}
    levels = {b: v for b, v in levels.items() if v > 0.0}
    levels = {**old, **levels}
    with open(os.path.join(spec["out_dir"], "levels.json"), "w", encoding="utf-8") as f:
        json.dump(levels, f, indent=1, sort_keys=True)
    print(f"[audio] playback trims (dB): {levels}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    cmd = argv[0]
    if cmd == "decode":
        decode(argv[1], argv[2])
    elif cmd == "plot":
        plot(argv[1], argv[2], *(float(v) for v in argv[3:5]))
    elif cmd == "cut":
        cut(argv[1])


main()
