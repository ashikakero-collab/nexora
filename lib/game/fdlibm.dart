// Pure-Dart port of the fdlibm routines V8 uses for Math.exp / sin / cos / atan2 (src/base/ieee754.cc).
//
// Why: dart:math calls the platform libm (glibc on Linux, bionic on Android, Apple libm on iOS), whose
// last-bit rounding differs from V8 and from each other. Using these functions in the engine makes the
// simulation (1) bit-identical to the original TypeScript engine and (2) bit-identical on every device,
// which is what the deterministic lockstep online mode relies on.
import 'dart:typed_data';

final ByteData _b = ByteData(8);

int _hi(double x) {
  _b.setFloat64(0, x);
  return _b.getInt32(0);
}

int _lo(double x) {
  _b.setFloat64(0, x);
  return _b.getUint32(4);
}

double _words(int hi, int lo) {
  _b.setInt32(0, hi);
  _b.setUint32(4, lo);
  return _b.getFloat64(0);
}

double _setHi(double x, int hi) {
  _b.setFloat64(0, x);
  _b.setInt32(0, hi);
  return _b.getFloat64(0);
}

// ---------------- exp ----------------
const double _huge = 1.0e+300;
const double _twom1000 = 9.33263618503218878990e-302;
const double _oThreshold = 7.09782712893383973096e+02;
const double _uThreshold = -7.45133219101941108420e+02;
const double _ln2HI0 = 6.93147180369123816490e-01, _ln2HI1 = -6.93147180369123816490e-01;
const double _ln2LO0 = 1.90821492927058770002e-10, _ln2LO1 = -1.90821492927058770002e-10;
const double _invln2 = 1.44269504088896338700e+00;
const double _P1 = 1.66666666666666019037e-01;
const double _P2 = -2.77777777770155933842e-03;
const double _P3 = 6.61375632143793436117e-05;
const double _P4 = -1.65339022054652515390e-06;
const double _P5 = 4.13813679705723846039e-08;

double fexp(double x) {
  double y, hi = 0, lo = 0, c, t;
  var k = 0;
  var hx = _hi(x);
  final xsb = (hx >> 31) & 1;
  hx &= 0x7fffffff;
  if (hx >= 0x40862E42) {
    if (hx >= 0x7ff00000) {
      if (((hx & 0xfffff) | _lo(x)) != 0) return x + x;
      return xsb == 0 ? x : 0.0;
    }
    if (x > _oThreshold) return double.infinity;
    if (x < _uThreshold) return 0.0;
  }
  if (hx > 0x3fd62e42) {
    if (hx < 0x3FF0A2B2) {
      hi = x - (xsb == 0 ? _ln2HI0 : _ln2HI1);
      lo = xsb == 0 ? _ln2LO0 : _ln2LO1;
      k = 1 - xsb - xsb;
    } else {
      k = (_invln2 * x + (xsb == 0 ? 0.5 : -0.5)).toInt();
      t = k.toDouble();
      hi = x - t * _ln2HI0;
      lo = t * _ln2LO0;
    }
    x = hi - lo;
  } else if (hx < 0x3e300000) {
    if (_huge + x > 1.0) return 1.0 + x;
  } else {
    k = 0;
  }
  t = x * x;
  c = x - t * (_P1 + t * (_P2 + t * (_P3 + t * (_P4 + t * _P5))));
  if (k == 0) return 1.0 - ((x * c) / (c - 2.0) - x);
  y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi);
  if (k >= -1021) {
    if (k == 1024) return _setHi(y, _hi(y) + ((k - 1) << 20)) * 2.0;
    return _setHi(y, _hi(y) + (k << 20));
  }
  return _setHi(y, _hi(y) + ((k + 1000) << 20)) * _twom1000;
}

// ---------------- sin / cos ----------------
const double _S1 = -1.66666666666666324348e-01;
const double _S2 = 8.33333333332248946124e-03;
const double _S3 = -1.98412698298579493134e-04;
const double _S4 = 2.75573137070700676789e-06;
const double _S5 = -2.50507602534068634195e-08;
const double _S6 = 1.58969099521155010221e-10;

double _kSin(double x, double y, int iy) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix < 0x3e400000) {
    if (x.toInt() == 0) return x;
  }
  final z = x * x;
  final v = z * x;
  final r = _S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)));
  if (iy == 0) return x + v * (_S1 + z * r);
  return x - ((z * (0.5 * y - v * r) - y) - v * _S1);
}

const double _C1 = 4.16666666666666019037e-02;
const double _C2 = -1.38888888888741095749e-03;
const double _C3 = 2.48015872894767294178e-05;
const double _C4 = -2.75573143513906633035e-07;
const double _C5 = 2.08757232129817482790e-09;
const double _C6 = -1.13596475577881948265e-11;

double _kCos(double x, double y) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix < 0x3e400000) {
    if (x.toInt() == 0) return 1.0;
  }
  final z = x * x;
  final r = z * (_C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6)))));
  if (ix < 0x3FD33333) return 1.0 - (0.5 * z - (z * r - x * y));
  final double qx = ix > 0x3fe90000 ? 0.28125 : _words(ix - 0x00200000, 0);
  final iz = 0.5 * z - qx;
  final a = 1.0 - qx;
  return a - (iz - (z * r - x * y));
}

const List<int> _npio2hw = [
  0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB, //
  0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB,
  0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
  0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB,
];
const double _invpio2 = 6.36619772367581382433e-01;
const double _pio2_1 = 1.57079632673412561417e+00;
const double _pio2_1t = 6.07710050650619224932e-11;
const double _pio2_2 = 6.07710050630396597660e-11;
const double _pio2_2t = 2.02226624879595063154e-21;
const double _pio2_3 = 2.02226624871116645580e-21;
const double _pio2_3t = 8.47842766036889956997e-32;

final Float64List _y = Float64List(2);

/// Argument reduction for |x| <= 2^19*(pi/2). Returns null outside that range.
int? _remPio2(double x) {
  final hx = _hi(x);
  final ix = hx & 0x7fffffff;
  double z, w, t, r, fn;
  if (ix <= 0x3fe921fb) {
    _y[0] = x;
    _y[1] = 0;
    return 0;
  }
  if (ix < 0x4002d97c) {
    if (hx > 0) {
      z = x - _pio2_1;
      if (ix != 0x3ff921fb) {
        _y[0] = z - _pio2_1t;
        _y[1] = (z - _y[0]) - _pio2_1t;
      } else {
        z -= _pio2_2;
        _y[0] = z - _pio2_2t;
        _y[1] = (z - _y[0]) - _pio2_2t;
      }
      return 1;
    } else {
      z = x + _pio2_1;
      if (ix != 0x3ff921fb) {
        _y[0] = z + _pio2_1t;
        _y[1] = (z - _y[0]) + _pio2_1t;
      } else {
        z += _pio2_2;
        _y[0] = z + _pio2_2t;
        _y[1] = (z - _y[0]) + _pio2_2t;
      }
      return -1;
    }
  }
  if (ix <= 0x413921fb) {
    t = x.abs();
    final n = (t * _invpio2 + 0.5).toInt();
    fn = n.toDouble();
    r = t - fn * _pio2_1;
    w = fn * _pio2_1t;
    if (n < 32 && ix != _npio2hw[n - 1]) {
      _y[0] = r - w;
    } else {
      final j = ix >> 20;
      _y[0] = r - w;
      var i = j - ((_hi(_y[0]) >> 20) & 0x7ff);
      if (i > 16) {
        t = r;
        w = fn * _pio2_2;
        r = t - w;
        w = fn * _pio2_2t - ((t - r) - w);
        _y[0] = r - w;
        i = j - ((_hi(_y[0]) >> 20) & 0x7ff);
        if (i > 49) {
          t = r;
          w = fn * _pio2_3;
          r = t - w;
          w = fn * _pio2_3t - ((t - r) - w);
          _y[0] = r - w;
        }
      }
    }
    _y[1] = (r - _y[0]) - w;
    if (hx < 0) {
      _y[0] = -_y[0];
      _y[1] = -_y[1];
      return -n;
    }
    return n;
  }
  return null;
}

double fsin(double x) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix <= 0x3fe921fb) return _kSin(x, 0.0, 0);
  if (ix >= 0x7ff00000) return x - x;
  final n = _remPio2(x);
  if (n == null) return _fallbackSin(x);
  switch (n & 3) {
    case 0:
      return _kSin(_y[0], _y[1], 1);
    case 1:
      return _kCos(_y[0], _y[1]);
    case 2:
      return -_kSin(_y[0], _y[1], 1);
    default:
      return -_kCos(_y[0], _y[1]);
  }
}

double fcos(double x) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix <= 0x3fe921fb) return _kCos(x, 0.0);
  if (ix >= 0x7ff00000) return x - x;
  final n = _remPio2(x);
  if (n == null) return _fallbackCos(x);
  switch (n & 3) {
    case 0:
      return _kCos(_y[0], _y[1]);
    case 1:
      return -_kSin(_y[0], _y[1], 1);
    case 2:
      return -_kCos(_y[0], _y[1]);
    default:
      return _kSin(_y[0], _y[1], 1);
  }
}

// |x| > 2^19*pi/2 never occurs in the game; keep a defined (non-bit-exact) answer anyway.
double _fallbackSin(double x) => fsin(x % (2 * 3.141592653589793));
double _fallbackCos(double x) => fcos(x % (2 * 3.141592653589793));

// ---------------- atan / atan2 ----------------
const List<double> _atanhi = [4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01, 1.57079632679489655800e+00];
const List<double> _atanlo = [2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17, 6.12323399573676603587e-17];
const List<double> _aT = [
  3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01, -1.11111104054623557880e-01,
  9.09088713343650656196e-02, -7.69187620504482999495e-02, 6.66107313738753120669e-02, -5.83357013379057348645e-02,
  4.97687799461593236017e-02, -3.65315727442169155270e-02, 1.62858201153657823623e-02,
];

double fatan(double x) {
  final hx = _hi(x);
  final ix = hx & 0x7fffffff;
  int id;
  if (ix >= 0x44100000) {
    if (ix > 0x7ff00000 || (ix == 0x7ff00000 && _lo(x) != 0)) return x + x;
    return hx > 0 ? _atanhi[3] + _atanlo[3] : -_atanhi[3] - _atanlo[3];
  }
  if (ix < 0x3fdc0000) {
    if (ix < 0x3e400000) {
      if (_huge + x > 1.0) return x;
    }
    id = -1;
  } else {
    x = x.abs();
    if (ix < 0x3ff30000) {
      if (ix < 0x3fe60000) {
        id = 0;
        x = (2.0 * x - 1.0) / (2.0 + x);
      } else {
        id = 1;
        x = (x - 1.0) / (x + 1.0);
      }
    } else {
      if (ix < 0x40038000) {
        id = 2;
        x = (x - 1.5) / (1.0 + 1.5 * x);
      } else {
        id = 3;
        x = -1.0 / x;
      }
    }
  }
  final z = x * x;
  final w = z * z;
  final s1 = z * (_aT[0] + w * (_aT[2] + w * (_aT[4] + w * (_aT[6] + w * (_aT[8] + w * _aT[10])))));
  final s2 = w * (_aT[1] + w * (_aT[3] + w * (_aT[5] + w * (_aT[7] + w * _aT[9]))));
  if (id < 0) return x - x * (s1 + s2);
  final zz = _atanhi[id] - ((x * (s1 + s2) - _atanlo[id]) - x);
  return hx < 0 ? -zz : zz;
}

const double _tiny = 1.0e-300;
const double _piO4 = 7.8539816339744827900E-01;
const double _piO2 = 1.5707963267948965580E+00;
const double _pi = 3.1415926535897931160E+00;
const double _piLo = 1.2246467991473531772E-16;

double fatan2(double y, double x) {
  if (x.isNaN || y.isNaN) return x + y;
  final hx = _hi(x), ix = hx & 0x7fffffff, lx = _lo(x);
  final hy = _hi(y), iy = hy & 0x7fffffff, ly = _lo(y);
  if (((hx - 0x3ff00000) | lx) == 0) return fatan(y);
  var m = ((hy >> 31) & 1) | ((hx >> 30) & 2);
  if ((iy | ly) == 0) {
    switch (m) {
      case 0:
      case 1:
        return y;
      case 2:
        return _pi + _tiny;
      default:
        return -_pi - _tiny;
    }
  }
  if ((ix | lx) == 0) return hy < 0 ? -_piO2 - _tiny : _piO2 + _tiny;
  if (ix == 0x7ff00000) {
    if (iy == 0x7ff00000) {
      switch (m) {
        case 0:
          return _piO4 + _tiny;
        case 1:
          return -_piO4 - _tiny;
        case 2:
          return 3.0 * _piO4 + _tiny;
        default:
          return -3.0 * _piO4 - _tiny;
      }
    } else {
      switch (m) {
        case 0:
          return 0.0;
        case 1:
          return -0.0;
        case 2:
          return _pi + _tiny;
        default:
          return -_pi - _tiny;
      }
    }
  }
  if (iy == 0x7ff00000) return hy < 0 ? -_piO2 - _tiny : _piO2 + _tiny;
  final k = (iy - ix) >> 20;
  double z;
  if (k > 60) {
    z = _piO2 + 0.5 * _piLo;
    m &= 1;
  } else if (hx < 0 && k < -60) {
    z = 0.0;
  } else {
    z = fatan((y / x).abs());
  }
  switch (m) {
    case 0:
      return z;
    case 1:
      return -z;
    case 2:
      return _pi - (z - _piLo);
    default:
      return (z - _piLo) - _pi;
  }
}

// ---------------- log / pow ----------------
const double _ln2Hi = 6.93147180369123816490e-01;
const double _ln2Lo = 1.90821492927058770002e-10;
const double _two54 = 1.80143985094819840000e+16;
const double _Lg1 = 6.666666666666735130e-01;
const double _Lg2 = 3.999999999940941908e-01;
const double _Lg3 = 2.857142874366239149e-01;
const double _Lg4 = 2.222219843214978396e-01;
const double _Lg5 = 1.818357216161805012e-01;
const double _Lg6 = 1.531383769920937332e-01;
const double _Lg7 = 1.479819860511658591e-01;

double flog(double x) {
  var hx = _hi(x);
  final lx = _lo(x);
  var k = 0;
  if (hx < 0x00100000) {
    if (((hx & 0x7fffffff) | lx) == 0) return double.negativeInfinity;
    if (hx < 0) return double.nan;
    k -= 54;
    x *= _two54;
    hx = _hi(x);
  }
  if (hx >= 0x7ff00000) return x + x;
  k += (hx >> 20) - 1023;
  hx &= 0x000fffff;
  var i = (hx + 0x95f64) & 0x100000;
  x = _setHi(x, hx | (i ^ 0x3ff00000));
  k += i >> 20;
  final f = x - 1.0;
  double dk;
  if ((0x000fffff & (2 + hx)) < 3) {
    if (f == 0.0) {
      if (k == 0) return 0.0;
      dk = k.toDouble();
      return dk * _ln2Hi + dk * _ln2Lo;
    }
    final r = f * f * (0.5 - 0.33333333333333333 * f);
    if (k == 0) return f - r;
    dk = k.toDouble();
    return dk * _ln2Hi - ((r - dk * _ln2Lo) - f);
  }
  final s = f / (2.0 + f);
  dk = k.toDouble();
  final z = s * s;
  i = hx - 0x6147a;
  final w = z * z;
  final j = 0x6b851 - hx;
  final t1 = w * (_Lg2 + w * (_Lg4 + w * _Lg6));
  final t2 = z * (_Lg1 + w * (_Lg3 + w * (_Lg5 + w * _Lg7)));
  i |= j;
  final r = t2 + t1;
  if (i > 0) {
    final hfsq = 0.5 * f * f;
    if (k == 0) return f - (hfsq - s * (hfsq + r));
    return dk * _ln2Hi - ((hfsq - (s * (hfsq + r) + dk * _ln2Lo)) - f);
  }
  if (k == 0) return f - s * (f - r);
  return dk * _ln2Hi - ((s * (f - r) - dk * _ln2Lo) - f);
}

/// Deterministic pow for the engine's use (x >= 0). y == 2 is exact (x*x).
double fpow(double x, double y) {
  if (y == 2) return x * x;
  if (y == 1) return x;
  if (x == 1 || y == 0) return 1;
  if (x == 0) return y > 0 ? 0 : double.infinity;
  if (x < 0 || x.isNaN || y.isNaN) return double.nan;
  return fexp(y * flog(x));
}
