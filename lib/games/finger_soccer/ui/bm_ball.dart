// Rolling 3D ball (game.js ballTex / buildSphere / samp / renderBall), rendered on the CPU into an RGBA
// buffer and uploaded as an image. Same lighting constants as the JS.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

const int _ts = 256;

class BmBallRenderer {
  BmBallRenderer(this.n);

  final int n;
  Uint8List? _tex;
  late final Float32List _g = _buildSphere(n);
  late final Uint8List _out = Uint8List(n * n * 4);
  Float64List? _rp;
  final Float64List _rm = Float64List(9);
  final List<double> _sm = <double>[0, 0, 0];
  double hx = 0, hy = 0, hz = 0;
  ui.Image? image;
  int _shownRv = -1;
  bool _busy = false;
  bool _disposed = false;

  bool get ready => _tex != null;

  /// Builds the texture (game.js ballTex) from the ball artwork.
  Future<void> setTexture(ui.Image src) async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas cv = ui.Canvas(rec);
    cv.drawRect(const ui.Rect.fromLTWH(0, 0, 256, 256), ui.Paint()..color = const ui.Color(0xFF10161F));
    cv.drawImageRect(src, ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), const ui.Rect.fromLTWH(0, 0, 256, 256),
        ui.Paint()..filterQuality = ui.FilterQuality.high);
    final ui.Image im = await rec.endRecording().toImage(_ts, _ts);
    final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
    im.dispose();
    if (bd == null) return;
    final Uint8List d = bd.buffer.asUint8List();
    // Lighting normalisation: a 10x10 downsample blown back up (bilinear), mean luminance in the centre disc.
    final Float64List small = Float64List(10 * 10 * 3);
    const double cell = _ts / 10;
    for (int sy = 0; sy < 10; sy++) {
      for (int sx = 0; sx < 10; sx++) {
        double r = 0, g = 0, b = 0;
        int cnt = 0;
        for (int y = (sy * cell).floor(); y < ((sy + 1) * cell).floor(); y++) {
          for (int x = (sx * cell).floor(); x < ((sx + 1) * cell).floor(); x++) {
            final int i = (y * _ts + x) * 4;
            r += d[i];
            g += d[i + 1];
            b += d[i + 2];
            cnt++;
          }
        }
        final int o = (sy * 10 + sx) * 3;
        small[o] = r / cnt;
        small[o + 1] = g / cnt;
        small[o + 2] = b / cnt;
      }
    }
    final Float64List lum = Float64List(_ts * _ts);
    for (int y = 0; y < _ts; y++) {
      double fy = (y + .5) / cell - .5;
      fy = fy.clamp(0.0, 9.0);
      final int y0 = fy.floor().clamp(0, 9), y1 = math.min<int>(9, y0 + 1);
      final double wy = fy - y0;
      for (int x = 0; x < _ts; x++) {
        double fx = (x + .5) / cell - .5;
        fx = fx.clamp(0.0, 9.0);
        final int x0 = fx.floor().clamp(0, 9), x1 = math.min<int>(9, x0 + 1);
        final double wx = fx - x0;
        double ch(int k) {
          final double a = small[(y0 * 10 + x0) * 3 + k], b = small[(y0 * 10 + x1) * 3 + k];
          final double c2 = small[(y1 * 10 + x0) * 3 + k], e = small[(y1 * 10 + x1) * 3 + k];
          return (a * (1 - wx) + b * wx) * (1 - wy) + (c2 * (1 - wx) + e * wx) * wy;
        }

        lum[y * _ts + x] = ch(0) * .3 + ch(1) * .59 + ch(2) * .11;
      }
    }
    double m = 0;
    int cnt = 0;
    for (int i = 0; i < _ts * _ts; i++) {
      final double px = (i % _ts) / _ts - .5, py = (i ~/ _ts) / _ts - .5;
      if (px * px + py * py < .2) {
        m += lum[i];
        cnt++;
      }
    }
    m = cnt > 0 ? m / cnt : 128;
    if (m == 0 || m.isNaN) m = 128;
    for (int i = 0; i < _ts * _ts; i++) {
      final double f = _mx(.75, _mn(1.5, math.pow(m / _mx(24, lum[i]), .6).toDouble()));
      final int q = i * 4;
      d[q] = _mn(255, d[q] * f).toInt();
      d[q + 1] = _mn(255, d[q + 1] * f).toInt();
      d[q + 2] = _mn(255, d[q + 2] * f).toInt();
    }
    _tex = d;
    // half vector for the specular highlight
    const double lx = -.42, ly = -.55, lz = .72;
    final double l = math.sqrt(lx * lx + ly * ly + lz * lz);
    final double a = lx / l, b = ly / l, c = lz / l + 1, mm = math.sqrt(a * a + b * b + c * c);
    hx = a / mm;
    hy = b / mm;
    hz = c / mm;
    _shownRv = -1;
  }

  static Float32List _buildSphere(int n) {
    final Float32List g = Float32List(n * n * 6);
    final double h = n / 2;
    const double lx0 = -.42, ly0 = -.55, lz0 = .72;
    final double ll = math.sqrt(lx0 * lx0 + ly0 * ly0 + lz0 * lz0), lx = lx0 / ll, ly = ly0 / ll, lz = lz0 / ll;
    for (int j = 0; j < n; j++) {
      for (int i = 0; i < n; i++) {
        final double px = (i + .5 - h) / h, py = (j + .5 - h) / h, d2 = px * px + py * py;
        final int o = (j * n + i) * 6;
        final double d = math.sqrt(d2), cov = _mx(0, _mn(1, (1 - d) * h * 1.1 + .5));
        if (cov <= 0) {
          g[o + 4] = 0;
          continue;
        }
        final double z = math.sqrt(_mx(0, 1 - _mn(d2, 1))), dif = _mx(0, px * lx + py * ly + z * lz);
        final double fr = math.pow(1 - z, 2.4).toDouble(), wrap = _mx(0, (px * lx + py * ly + z * lz) * .5 + .5);
        final double lit = .50 + .58 * wrap * wrap + .14 * dif - .30 * fr;
        final double back = (math.pow(1 - z, 3) * _mx(0, -(px * lx + py * ly)) * .9).toDouble();
        g[o] = px;
        g[o + 1] = py;
        g[o + 2] = z;
        g[o + 3] = lit;
        g[o + 4] = cov;
        g[o + 5] = back;
      }
    }
    return g;
  }

  void _samp(Uint8List t, List<double> r, double px, double py, double pz, double k) {
    final double qx = r[0] * px + r[3] * py + r[6] * pz, qy = r[1] * px + r[4] * py + r[7] * pz;
    double u = _ts / 2 + qx * k - .5, v = _ts / 2 + qy * k - .5;
    if (u < 0) {
      u = 0;
    } else if (u > _ts - 1.01) {
      u = _ts - 1.01;
    }
    if (v < 0) {
      v = 0;
    } else if (v > _ts - 1.01) {
      v = _ts - 1.01;
    }
    final int u0 = u.toInt(), v0 = v.toInt();
    final double fu = u - u0, fv = v - v0;
    final int a = (v0 * _ts + u0) * 4, b = a + 4, c = a + _ts * 4, e = c + 4;
    final double w1 = (1 - fu) * (1 - fv), w2 = fu * (1 - fv), w3 = (1 - fu) * fv, w4 = fu * fv;
    _sm[0] = t[a] * w1 + t[b] * w2 + t[c] * w3 + t[e] * w4;
    _sm[1] = t[a + 1] * w1 + t[b + 1] * w2 + t[c + 1] * w3 + t[e + 1] * w4;
    _sm[2] = t[a + 2] * w1 + t[b + 2] * w2 + t[c + 2] * w3 + t[e + 2] * w4;
  }

  /// Re-renders when the ball's rotation counter changed (game.js renderBall).
  void update(List<double> r, int rv) {
    final Uint8List? t = _tex;
    if (t == null || _busy || _disposed || rv == _shownRv) return;
    final Float64List rp = _rp ??= Float64List.fromList(r);
    double dm = 0;
    for (int i = 0; i < 9; i++) {
      dm += (r[i] - rp[i]).abs();
    }
    final int taps = dm > .16 ? 3 : dm > .035 ? 2 : 1;
    for (int i = 0; i < 9; i++) {
      _rm[i] = (r[i] + rp[i]) * .5;
    }
    const double k = .93 * .5 * _ts;
    final Float32List g = _g;
    final Uint8List d = _out;
    for (int j = 0; j < n; j++) {
      for (int i = 0; i < n; i++) {
        final int o = (j * n + i) * 6, q = (j * n + i) * 4;
        final double cov = g[o + 4];
        if (cov <= 0) {
          d[q] = 0;
          d[q + 1] = 0;
          d[q + 2] = 0;
          d[q + 3] = 0;
          continue;
        }
        final double px = g[o], py = g[o + 1], pz = g[o + 2], lit = g[o + 3], back = g[o + 5];
        _samp(t, r, px, py, pz, k);
        double rr = _sm[0], gg = _sm[1], bb = _sm[2];
        if (taps > 1) {
          _samp(t, _rm, px, py, pz, k);
          final double w = taps == 3 ? .34 : .45;
          rr = rr * (1 - w) + _sm[0] * w;
          gg = gg * (1 - w) + _sm[1] * w;
          bb = bb * (1 - w) + _sm[2] * w;
          if (taps == 3) {
            _samp(t, rp, px, py, pz, k);
            rr = rr * .7 + _sm[0] * .3;
            gg = gg * .7 + _sm[1] * .3;
            bb = bb * .7 + _sm[2] * .3;
          }
        }
        final double sd = px * hx + py * hy + pz * hz;
        final double hl = pz > 0 ? (math.pow(_mx(0, sd), 46) * 150 + math.pow(_mx(0, sd), 7) * 20).toDouble() : 0;
        rr = rr * lit + hl + back * 70;
        gg = gg * lit + hl + back * 105;
        bb = bb * lit + hl + back * 150;
        // premultiplied alpha for decodeImageFromPixels (rgba8888 is premultiplied on most backends)
        final double a = cov;
        d[q] = (_mn(255, rr) * a).toInt();
        d[q + 1] = (_mn(255, gg) * a).toInt();
        d[q + 2] = (_mn(255, bb) * a).toInt();
        d[q + 3] = (cov * 255).toInt();
      }
    }
    rp.setAll(0, r);
    _busy = true;
    final int want = rv;
    ui.decodeImageFromPixels(Uint8List.fromList(d), n, n, ui.PixelFormat.rgba8888, (ui.Image img) {
      _busy = false;
      if (_disposed) {
        img.dispose();
        return;
      }
      image?.dispose();
      image = img;
      _shownRv = want;
    });
  }

  void dispose() {
    _disposed = true;
    image?.dispose();
    image = null;
  }
}


double _mn(double a, double b) => a < b ? a : b;
double _mx(double a, double b) => a > b ? a : b;
