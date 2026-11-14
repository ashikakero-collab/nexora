#!/usr/bin/env python3
"""Cut the owner's goal-skin art (white / fake-checkerboard backgrounds) to alpha -> assets/g/goals4/<name>.webp.

usage: tool/import_goals.py <image> <name> [<image> <name> ...]         single goal per image
       tool/import_goals.py --sheet <image> <n1,n2,...> <cols>x<rows>   a grid sheet of goals (row-major names)

Background = bright, near-neutral pixels (white + checker greys, lum >= --lum, sat < --sat). Only background
components that touch the image border OR are big enough to be a honeycomb hole (area >= --hole px) are removed, so
small white highlights inside the frame (ice glints, chrome) survive. Soft ~1 px edge, then the colour of the
semi-transparent edge pixels is de-matted against the local background (no white halo on dark grass). Trimmed,
max width 1024, webp q86. Prints a per-file report; check the montage written to /tmp/goals_montage.png.
"""
import argparse, os
import numpy as np
from PIL import Image
from scipy import ndimage as nd

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'g', 'goals4')


def cut(im, lum_t=205, sat_t=16, hole=260):
    a = np.asarray(im.convert('RGBA')).astype(np.float32)
    rgb = a[..., :3]
    if a[..., 3].min() < 250:  # real alpha already
        alpha = a[..., 3] / 255
    else:
        lum = rgb.mean(2)
        sat = rgb.max(2) - rgb.min(2)
        bg = (lum >= lum_t) & (sat < sat_t)
        bg = nd.binary_opening(bg, iterations=1)
        lab, n = nd.label(bg)
        areas = nd.sum(np.ones_like(lab), lab, index=np.arange(1, n + 1))
        edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
        keep = np.zeros(n + 1, bool)
        keep[1:] = areas >= hole
        keep[edge] = True
        keep[0] = False
        bg = keep[lab]
        bg = nd.binary_dilation(bg, iterations=1)  # eat the 1-px light rim left by JPEG / anti-aliasing
        alpha = 1 - nd.gaussian_filter(bg.astype(np.float32), .8)
        alpha = np.where(bg, 0, alpha)
        alpha = np.clip((alpha - .08) / .92, 0, 1)
        # de-matte: edge colour = (c - (1-a)*bgc)/a with bgc ~ white-ish
        bgc = 238.0
        m = (alpha > .02) & (alpha < .98)
        am = np.maximum(alpha, .25)[..., None]
        fixed = np.clip((rgb - (1 - am) * bgc) / am, 0, 255)
        rgb = np.where(m[..., None], fixed, rgb)
    out = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    img = Image.fromarray(out, 'RGBA')
    ys, xs = np.where(alpha > .05)
    return img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def save(img, name, maxw=1024):
    if img.width > maxw:
        img = img.resize((maxw, round(img.height * maxw / img.width)), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name + '.webp')
    img.save(p, 'WEBP', quality=86, method=6)
    print(name, img.size, os.path.getsize(p) // 1024, 'KB')
    return p


def montage(paths, dst='/tmp/goals_montage.png'):
    tw = 420
    tiles = []
    for p in paths:
        g = Image.open(p).convert('RGBA')
        tiles.append(g.resize((tw, round(g.height * tw / g.width)), Image.LANCZOS))
    th = max(t.height for t in tiles) + 8
    bgs = [(14, 16, 24), (36, 112, 48), (235, 235, 235)]
    out = Image.new('RGB', (tw * len(tiles), th * len(bgs)))
    for j, b in enumerate(bgs):
        for i, t in enumerate(tiles):
            cell = Image.new('RGB', (tw, th), b)
            cell.paste(t, (0, 4), t)
            out.paste(cell, (i * tw, j * th))
    out.save(dst)
    print('montage ->', dst)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--sheet', nargs=3, metavar=('IMAGE', 'NAMES', 'COLSxROWS'))
    ap.add_argument('--lum', type=int, default=205)
    ap.add_argument('--sat', type=int, default=16)
    ap.add_argument('--hole', type=int, default=260)
    ap.add_argument('pairs', nargs='*')
    o = ap.parse_args()
    written = []
    if o.sheet:
        img, names, grid = o.sheet
        names = names.split(',')
        cols, rows = map(int, grid.split('x'))
        full = cut(Image.open(img), o.lum, o.sat, o.hole)
        al = np.asarray(full)[..., 3] > 20
        lab, n = nd.label(nd.binary_dilation(al, iterations=8))
        objs = [s for s in nd.find_objects(lab) if (s[0].stop - s[0].start) * (s[1].stop - s[1].start) > al.size * .03]
        objs.sort(key=lambda s: (round(s[0].start / (al.shape[0] / rows)), s[1].start))
        assert len(objs) >= len(names), f'found {len(objs)} goals for {len(names)} names'
        for nm, s in zip(names, objs):
            sub = full.crop((s[1].start, s[0].start, s[1].stop, s[0].stop))
            # drop stray pixels of neighbours: keep only the largest alpha component
            sa = np.asarray(sub).copy()
            l2, n2 = nd.label(nd.binary_dilation(sa[..., 3] > 20, iterations=3))
            if n2 > 1:
                big = np.argmax(nd.sum(np.ones_like(l2), l2, index=np.arange(1, n2 + 1))) + 1
                sa[..., 3] = np.where(l2 == big, sa[..., 3], 0)
            written.append(save(Image.fromarray(sa, 'RGBA'), nm))
    for i in range(0, len(o.pairs), 2):
        written.append(save(cut(Image.open(o.pairs[i]), o.lum, o.sat, o.hole), o.pairs[i + 1]))
    if written:
        montage(written)
