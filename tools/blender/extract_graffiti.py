"""Blender (headless) script: cut a graffiti piece out of a scanned roller-shutter texture
(Poly Haven, CC0) into an RGBA decal for the skate ramps.

    blender --background --factory-startup --python tools/blender/extract_graffiti.py -- \
        in.jpg out.png x y w h ribs

x y w h is the crop in pixels from the top-left; ribs is "rows" when the shutter's slats run
across the image (dark lines repeat down the rows), "cols" when they run up it. The slat shading
is divided out, the paint is keyed off the pale metal by its saturation and darkness, small holes
(white highlights inside letters) are closed, and colour is bled into the clear area so mipmaps
don't pick up a white fringe.
"""
import sys

import bpy
import numpy as np


def box(a, r, axis):
    """Mean over a window of 2r+1 along axis, edges clamped."""
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / (2 * r + 1)


def morph1(a, r, fn, axis):
    """Max/min filter of radius r along one axis (fn = np.maximum or np.minimum)."""
    pad = [(0, 0), (0, 0)]
    pad[axis] = (r, r)
    p = np.pad(a, pad, mode="edge")
    n = a.shape[axis]
    out = np.take(p, np.arange(0, n), axis=axis)
    for k in range(1, 2 * r + 1):
        out = fn(out, np.take(p, np.arange(k, k + n), axis=axis))
    return out


def morph(a, r, fn):
    """Square max/min filter of radius r."""
    return morph1(morph1(a, r, fn, 0), r, fn, 1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst = argv[0], argv[1]
    x, y, w, h = (int(v) for v in argv[2:6])
    ribs = argv[6]
    img = bpy.data.images.load(src)
    iw, ih = img.size
    px = np.empty(iw * ih * 4, np.float32)
    img.pixels.foreach_get(px)
    rgb = px.reshape(ih, iw, 4)[::-1, :, :3]          # top-down rows, sRGB values
    rgb = rgb[y:y + h, x:x + w].astype(np.float32)

    # Slats: a periodic pattern across them. The period comes from autocorrelation; a notch
    # filter (FFT across the slats) takes out that frequency and its harmonics, leaving the
    # paint's edges sharp.
    if ribs == "cols":
        rgb = rgb.transpose(1, 0, 2)
    prof = rgb.mean(axis=(1, 2))
    prof = prof - box(prof[:, None], 30, 0)[:, 0]
    lags = np.arange(12, 64)
    ac = np.array([np.dot(prof[:-k], prof[k:]) / (len(prof) - k) for k in lags])
    k = int(np.argmax(ac))
    period = float(lags[k])
    if 0 < k < len(ac) - 1:                                   # parabolic peak refinement
        a, b, c = ac[k - 1], ac[k], ac[k + 1]
        if a - 2 * b + c < 0:
            period += 0.5 * (a - c) / (a - 2 * b + c)
    rows = rgb.shape[0]
    p = np.concatenate([rgb, rgb[::-1]], axis=0)              # mirrored: no wrap-around seam
    spec = np.fft.rfft(p, axis=0)
    f = np.fft.rfftfreq(p.shape[0])
    f0 = 1.0 / period
    keep = np.ones_like(f)
    for m in range(1, 8):
        bw = 0.06 * f0 + 0.004 * m                            # wider for higher harmonics
        keep *= 1.0 - np.exp(-0.5 * ((f - m * f0) / bw) ** 2)
    rgb = np.fft.irfft(spec * keep[:, None, None], n=p.shape[0], axis=0)[:rows]
    rgb = np.clip(rgb, 0.0, 1.0).astype(np.float32)
    if ribs == "cols":
        rgb = rgb.transpose(1, 0, 2)
    print(f"[graffiti] slat period {period:.2f} px")

    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    alpha = np.maximum(smoothstep(0.09, 0.22, sat), smoothstep(0.46, 0.28, lum))
    alpha = morph(morph(alpha, 6, np.maximum), 6, np.minimum)    # close small holes
    # White highlights inside a piece are paint too: fill clear areas the border can't reach.
    clear = alpha < 0.5
    reach = np.zeros_like(clear)
    reach[0, :], reach[-1, :], reach[:, 0], reach[:, -1] = clear[0, :], clear[-1, :], clear[:, 0], clear[:, -1]
    for _ in range(4000):
        grown = morph(reach.astype(np.float32), 1, np.maximum) > 0.5
        grown &= clear
        if np.array_equal(grown, reach):
            break
        reach = grown
    outside = morph(reach.astype(np.float32), 2, np.maximum) > 0.5
    alpha = np.where(outside, alpha, 1.0)
    alpha = morph(alpha, 1, np.minimum)                          # drop single-pixel specks
    alpha = morph(alpha, 1, np.maximum)
    alpha = box(box(alpha, 1, 0), 1, 1)

    # Bleed paint colour outwards into the clear area.
    wsum = box(box(alpha, 10, 0), 10, 1)
    bled = box(box(rgb * alpha[..., None], 10, 0), 10, 1) / np.maximum(wsum, 1e-4)[..., None]
    rgb = np.where((alpha < 0.5)[..., None] & (wsum > 1e-3)[..., None], bled, rgb)

    out = np.concatenate([rgb, alpha[..., None]], axis=2)[::-1]
    o = bpy.data.images.new("decal", w, h, alpha=True)
    o.pixels.foreach_set(np.ascontiguousarray(out, dtype=np.float32).ravel())
    o.filepath_raw = dst
    o.file_format = "PNG"
    o.save()
    print(f"[graffiti] {dst}: {w}x{h}, coverage {alpha.mean():.2f}")


main()
