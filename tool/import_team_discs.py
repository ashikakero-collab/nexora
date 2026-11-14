#!/usr/bin/env python3
"""Slice team discs out of sheets (or single-disc images) and write 256 px circular webp discs.

usage:
  tool/import_team_discs.py detect OUTDIR img1 [img2 ...]   -> OUTDIR/<sheet>_<n>.webp + OUTDIR/index.json +
                                                             OUTDIR/contact.jpg (numbered, for identification)
                                                             + OUTDIR/overlay_<sheet>.jpg (detected circles)
  tool/import_team_discs.py place MAP.json                  -> copies the identified crops to their final asset
                                                             paths: {"<crop path>": "assets/g/teams4/<key>.webp"}
options (detect): --min-r 40  --thr 38  --dedupe 6  --size 256  --q 80  --inset .985

How a disc is found (works on dark AND light backgrounds):
  1. background colour = median of the image border; foreground = pixels whose colour differs from it by > --thr
     (alpha < 128 counts as background for images that already have transparency);
  2. holes filled, small specks opened away;
  3. discs = repeated maxima of the distance transform: the largest inscribed circle, suppress it, next one ...
     while the radius stays >= 55 % of the biggest disc on that sheet (sheets hold one disc size). Wings, shadows
     and labels next to a disc don't move the inscribed circle;
  4. the crop is the circle (radius * --inset to drop the anti-aliased dark/white rim) with a 1.2 px soft alpha
     edge, resized to --size with LANCZOS;
  5. de-dup: 64-bit DCT perceptual hash of the disc; crops within --dedupe bits of an earlier crop are dropped
     (index.json still lists them with "dup_of").
"""
import argparse, json, os, shutil, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as nd
from scipy.fft import dctn
from scipy.spatial import ConvexHull


def fg_mask(im, thr):
    a = np.asarray(im.convert('RGBA')).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3]
    b = 6
    border = np.concatenate([rgb[:b].reshape(-1, 3), rgb[-b:].reshape(-1, 3), rgb[:, :b].reshape(-1, 3), rgb[:, -b:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    diff = np.sqrt(((rgb - bg) ** 2).sum(2))
    m = (diff > thr) & (al > 128)
    if al.min() < 128:  # real transparency: alpha is the mask
        m = al > 128
    m = nd.binary_opening(m, iterations=2)
    m = nd.binary_closing(m, iterations=2)
    raw = m.copy()
    m = nd.binary_fill_holes(m)
    return m, bg, raw


def find_discs(m, min_r):
    dt = nd.distance_transform_edt(m)
    h, w = m.shape
    out = []
    first = None
    work = dt.copy()
    for _ in range(80):
        i = int(np.argmax(work))
        r = float(work.flat[i])
        if r < min_r or (first and r < first * .55):
            break
        cy, cx = divmod(i, w)
        first = first or r
        out.append((cx, cy, r))
        R = int(r * 1.6) + 1
        y0, y1, x0, x1 = max(0, cy - R), min(h, cy + R), max(0, cx - R), min(w, cx + R)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        win = work[y0:y1, x0:x1]
        win[(xx - cx) ** 2 + (yy - cy) ** 2 < R * R] = 0
    return out


def hough_discs(raw, R, min_votes=.33):
    """Circles of radius ~R from the outer edge of the foreground: every edge pixel votes R px inward (along the
    smoothed mask gradient), for radii .94R..1.06R. Finds dark discs whose filled mask is broken."""
    h, w = raw.shape
    ms = nd.gaussian_filter(raw.astype(np.float32), 2)
    gy, gx = np.gradient(ms)
    mag = np.hypot(gx, gy)
    ys, xs = np.nonzero(mag > .08)
    ux, uy = gx[ys, xs] / mag[ys, xs], gy[ys, xs] / mag[ys, xs]
    acc = np.zeros((h, w), np.float32)
    for k in (.94, .97, 1.0, 1.03, 1.06):
        cx = np.round(xs + ux * R * k).astype(int)
        cy = np.round(ys + uy * R * k).astype(int)
        ok = (cx >= 0) & (cx < w) & (cy >= 0) & (cy < h)
        np.add.at(acc, (cy[ok], cx[ok]), 1)
    acc = nd.gaussian_filter(acc, 3)
    out, best = [], None
    for _ in range(80):
        i = int(np.argmax(acc))
        v = float(acc.flat[i])
        if best is None:
            best = v
        if v < best * min_votes or v <= 0:
            break
        cy, cx = divmod(i, w)
        out.append((cx, cy, R))
        Rr = int(R * 1.5)
        y0, y1, x0, x1 = max(0, cy - Rr), min(h, cy + Rr), max(0, cx - Rr), min(w, cx + Rr)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        acc[y0:y1, x0:x1][(xx - cx) ** 2 + (yy - cy) ** 2 < Rr * Rr] = 0
    return out


def refine(raw, c):
    """Best radius (.9..1.1 R) = the one whose circle runs along the most foreground->background transitions."""
    cx, cy, R = c
    ms = nd.gaussian_filter(raw.astype(np.float32), 1.5)
    th = np.linspace(0, 2 * np.pi, 360, endpoint=False)
    best = (-1, R)
    for r in np.arange(R * .9, R * 1.1, 1):
        xi = np.clip((cx + np.cos(th) * (r - 2)).astype(int), 0, raw.shape[1] - 1)
        yi = np.clip((cy + np.sin(th) * (r - 2)).astype(int), 0, raw.shape[0] - 1)
        xo = np.clip((cx + np.cos(th) * (r + 2)).astype(int), 0, raw.shape[1] - 1)
        yo = np.clip((cy + np.sin(th) * (r + 2)).astype(int), 0, raw.shape[0] - 1)
        sc = float((ms[yi, xi] - ms[yo, xo]).sum())
        if sc > best[0]:
            best = (sc, r)
    return (cx, cy, best[1])


def order_rows(discs):
    """Reading order: group into rows (centres within 0.7 r vertically), each row left -> right."""
    rows = []
    for c in sorted(discs, key=lambda c: c[1]):
        if rows and abs(c[1] - rows[-1][0][1]) < c[2] * .7:
            rows[-1].append(c)
        else:
            rows.append([c])
    return [c for r in rows for c in sorted(r, key=lambda c: c[0])]


def phash(img):
    # hash the disc's centre (the circular cut-out would dominate a full-frame hash) + mean colour
    w = img.width
    img = img.convert('RGB').crop((int(w * .18), int(w * .18), int(w * .82), int(w * .82)))
    g = np.asarray(img.convert('L').resize((32, 32), Image.LANCZOS)).astype(np.float32)
    d = dctn(g, norm='ortho')[:8, :8].flatten()
    med = np.median(d[1:])
    return int(''.join('1' if v > med else '0' for v in d), 2)


def ham(a, b):
    return bin(a ^ b).count('1')


def cut(im, cx, cy, r, size, inset):
    r2 = r * inset
    pad = int(r2 + 3)
    a = np.asarray(im.convert('RGBA')).astype(np.float32)
    h, w = a.shape[:2]
    x0, y0 = int(round(cx)) - pad, int(round(cy)) - pad
    canvas = np.zeros((2 * pad, 2 * pad, 4), np.float32)
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(w, x0 + 2 * pad), min(h, y0 + 2 * pad)
    canvas[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = a[sy0:sy1, sx0:sx1]
    yy, xx = np.mgrid[0:2 * pad, 0:2 * pad]
    d = np.sqrt((xx + .5 - (cx - x0)) ** 2 + (yy + .5 - (cy - y0)) ** 2)
    alpha = np.clip((r2 - d) / 1.2 + .5, 0, 1)
    canvas[..., 3] = alpha * 255
    img = Image.fromarray(canvas.astype(np.uint8), 'RGBA')
    return img.resize((size, size), Image.LANCZOS)


def detect(o):
    os.makedirs(o.outdir, exist_ok=True)
    index, hashes = [], []
    for si, path in enumerate(o.images):
        im = Image.open(path)
        m, bg, raw = fg_mask(im, o.thr)
        discs = find_discs(m, o.min_r)
        if len(discs) > 1 or o.hough:
            # sheet: take the typical disc radius from the clean (filled) discs, then Hough for all of them
            rs = sorted(c[2] for c in discs)
            R = float(np.median(rs[len(rs) // 2:]))
            discs = [refine(raw, c) for c in hough_discs(raw, R)]
        discs = order_rows(discs)
        ov = im.convert('RGB').copy()
        dr = ImageDraw.Draw(ov)
        for n, (cx, cy, r) in enumerate(discs):
            img = cut(im, cx, cy, r, o.size, o.inset)
            hv = phash(img)
            mc = np.asarray(img.convert('RGB').resize((8, 8))).reshape(-1, 3).mean(0)
            dup = next((e['file'] for e, (hh, cc) in zip(index, hashes) if 'dup_of' not in e and ham(hv, hh) <= o.dedupe and np.abs(cc - mc).max() < 18), None)
            name = f's{si:02d}_{n:02d}.webp'
            rec = {'file': name, 'sheet': os.path.basename(path), 'sheet_idx': si, 'n': n, 'cx': round(cx), 'cy': round(cy), 'r': round(r, 1), 'phash': f'{hv:016x}'}
            if dup:
                rec['dup_of'] = dup
            else:
                img.save(os.path.join(o.outdir, name), 'WEBP', quality=o.q, method=6)
            index.append(rec)
            hashes.append((hv, mc))
            dr.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 0, 80) if dup else (0, 255, 120), width=4)
            dr.text((cx - 10, cy - 10), str(n), fill=(255, 255, 0))
        ov.thumbnail((900, 900))
        ov.save(os.path.join(o.outdir, f'overlay_{si:02d}.jpg'), quality=80)
        print(f'{os.path.basename(path)}: {len(discs)} discs, bg {bg.round()}')
    json.dump(index, open(os.path.join(o.outdir, 'index.json'), 'w'), indent=1)
    # contact sheet of unique crops
    uniq = [e for e in index if 'dup_of' not in e]
    cs, cols = 128, 10
    rows = (len(uniq) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cs, rows * (cs + 16)), (40, 40, 48))
    dr = ImageDraw.Draw(sheet)
    for k, e in enumerate(uniq):
        t = Image.open(os.path.join(o.outdir, e['file'])).resize((cs, cs))
        x, y = (k % cols) * cs, (k // cols) * (cs + 16)
        sheet.paste(t, (x, y), t)
        dr.text((x + 4, y + cs + 2), e['file'][:-5], fill=(255, 255, 255))
    sheet.save(os.path.join(o.outdir, 'contact.jpg'), quality=85)
    print('unique', len(uniq), 'of', len(index), '->', o.outdir)


def place(o):
    m = json.load(open(o.map))
    for src, dst in m.items():
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
    print('placed', len(m))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest='cmd', required=True)
    d = sp.add_parser('detect')
    d.add_argument('outdir')
    d.add_argument('images', nargs='+')
    d.add_argument('--min-r', type=float, default=40)
    d.add_argument('--thr', type=float, default=38)
    d.add_argument('--dedupe', type=int, default=5)
    d.add_argument('--size', type=int, default=256)
    d.add_argument('--q', type=int, default=80)
    d.add_argument('--inset', type=float, default=.985)
    d.add_argument('--hough', action='store_true', help='force the Hough pass for a sheet with a single clean disc')
    p = sp.add_parser('place')
    p.add_argument('map')
    o = ap.parse_args()
    detect(o) if o.cmd == 'detect' else place(o)
