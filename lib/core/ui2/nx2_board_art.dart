import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Fits table/board artwork onto an existing (fixed) play geometry.
///
/// The art is cut into a grid by knot lines. Every knot pairs an art coordinate (source pixels) with the
/// destination coordinate it must land on (the game's own geometry units), so features such as pockets,
/// points or the bar sit exactly where the game logic expects them, while everything between two knots is
/// stretched linearly. Physics never reads any of this: it only decides how pixels are drawn.
class Nx2ArtMap {
  const Nx2ArtMap({required this.xs, required this.ys, this.quarterTurns = 0});

  /// Knots as [artCoord, dstCoord] pairs, ascending in both. Art x/y are measured on the art AFTER rotation
  /// by [quarterTurns] (clockwise), i.e. on the image as it is displayed.
  final List<List<double>> xs;
  final List<List<double>> ys;
  final int quarterTurns;

  double dstX(double ax) => _lerp(xs, ax);
  double dstY(double ay) => _lerp(ys, ay);

  static double _lerp(List<List<double>> k, double a) {
    for (int i = 1; i < k.length; i++) {
      if (a <= k[i][0] || i == k.length - 1) {
        final List<double> p = k[i - 1], q = k[i];
        return p[1] + (a - p[0]) / (q[0] - p[0]) * (q[1] - p[1]);
      }
    }
    return a;
  }
}

/// Paints [img] through [map]. Rotation is applied first (source image space -> displayed art space).
void nx2PaintMappedArt(Canvas canvas, ui.Image img, Nx2ArtMap map, {Paint? paint}) {
  final Paint p = paint ?? (Paint()..filterQuality = FilterQuality.medium);
  final double iw = img.width.toDouble(), ih = img.height.toDouble();
  final int q = map.quarterTurns % 4;
  // displayed art size
  final double aw = q.isOdd ? ih : iw;
  final List<List<double>> xs = map.xs, ys = map.ys;
  for (int i = 0; i + 1 < xs.length; i++) {
    for (int j = 0; j + 1 < ys.length; j++) {
      final double ax0 = xs[i][0], ax1 = xs[i + 1][0], ay0 = ys[j][0], ay1 = ys[j + 1][0];
      // tiny overlap hides hairline seams between cells
      final Rect dst = Rect.fromLTRB(xs[i][1], ys[j][1], xs[i + 1][1] + 0.6, ys[j + 1][1] + 0.6);
      if (q == 0) {
        canvas.drawImageRect(img, Rect.fromLTRB(ax0, ay0, ax1, ay1), dst, p);
      } else if (q == 1) {
        // displayed (x,y) <- source (y, ih - x)... clockwise turn: src x = ay, src y = ih - ax
        final Rect src = Rect.fromLTRB(ay0, aw - ax1, ay1, aw - ax0);
        canvas.save();
        canvas.translate(dst.left, dst.top);
        // map src (w=ay1-ay0, h=ax1-ax0) onto dst rotated 90deg clockwise
        canvas.scale(dst.width / src.height, dst.height / src.width);
        canvas.translate(src.height, 0);
        canvas.rotate(1.5707963267948966);
        canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, src.width, src.height), p);
        canvas.restore();
      } else {
        // not needed by any board yet
        canvas.drawImageRect(img, Rect.fromLTRB(ax0, ay0, ax1, ay1), dst, p);
      }
    }
  }
}

/// Small cache so a board image is decoded once per session.
class Nx2ImageCache {
  Nx2ImageCache._();
  static final Map<String, Future<ui.Image>> _c = <String, Future<ui.Image>>{};

  static Future<ui.Image> load(String asset) => _c.putIfAbsent(asset, () async {
        final ByteData d = await rootBundle.load(asset);
        final ui.Codec codec = await ui.instantiateImageCodec(d.buffer.asUint8List());
        final ui.FrameInfo f = await codec.getNextFrame();
        return f.image;
      });
}

/// Loads [asset] and paints it with [painter] once decoded ([fallback] until then / on error).
class Nx2ArtCanvas extends StatefulWidget {
  const Nx2ArtCanvas({super.key, required this.asset, required this.painter, required this.size, this.fallback});
  final String asset;
  final CustomPainter Function(ui.Image img) painter;
  final Size size;
  final Widget? fallback;

  @override
  State<Nx2ArtCanvas> createState() => _Nx2ArtCanvasState();
}

class _Nx2ArtCanvasState extends State<Nx2ArtCanvas> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant Nx2ArtCanvas old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) {
      _img = null;
      _load();
    }
  }

  Future<void> _load() async {
    final String a = widget.asset;
    try {
      final ui.Image i = await Nx2ImageCache.load(a);
      if (mounted && a == widget.asset) setState(() => _img = i);
    } catch (_) {
      // keep the fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? i = _img;
    if (i == null) {
      return SizedBox.fromSize(size: widget.size, child: widget.fallback);
    }
    return CustomPaint(size: widget.size, painter: widget.painter(i));
  }
}

/// A board skin choice shown in the in-game board picker.
class Nx2BoardChoice {
  const Nx2BoardChoice(this.id, this.nameFa, this.nameEn, this.thumb);
  final String id;
  final String nameFa;
  final String nameEn;
  final String thumb;
}

/// Round neon "change table/board" button used in every game HUD.
class Nx2BoardButton extends StatelessWidget {
  const Nx2BoardButton({super.key, required this.onTap, this.color = const Color(0xFF39E1FF), this.size = 30});
  final VoidCallback onTap;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: 'board',
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: <Widget>[
            Positioned.fill(child: Image.asset('assets/ui/nx2/frames/ring_neon.webp', fit: BoxFit.contain)),
            Icon(Icons.palette_rounded, size: size * 0.48, color: color),
          ]),
        ),
      ),
    );
  }
}
