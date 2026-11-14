// Port of src/ui/theme.ts: colours, gradients, fonts, number formatting.
import 'package:flutter/widgets.dart';

class C {
  static const bg = Color(0xff030614);
  static const bg2 = Color(0xff060b22);
  static const panel = Color(0xc70e163a);
  static const panel2 = Color(0xe6080c22);
  static const glass = Color(0x9e0e1840);
  static const line = Color(0x3d6eaaff);
  static const lineHi = Color(0xbf78dcff);
  static const cyan = Color(0xff4fe3ff);
  static const sky = Color(0xff7fc8ff);
  static const blue = Color(0xff3b82ff);
  static const indigo = Color(0xff6d5bff);
  static const violet = Color(0xffa35bff);
  static const pink = Color(0xffff4fa3);
  static const gold = Color(0xffffd257);
  static const orange = Color(0xffff8a3a);
  static const red = Color(0xffff4a5a);
  static const green = Color(0xff3dffa8);
  static const text = Color(0xffeef4ff);
  static const dim = Color(0xff93a7d8);
  static const dim2 = Color(0xff5f6f9e);
}

/// Font families (variable fonts; weight chosen with FontWeight -> 'wght' axis).
class F {
  static const title = 'Orbitron'; // 900
  static const head = 'Orbitron'; // 700
  static const body = 'Exo2'; // 600
  static const bold = 'Exo2'; // 800
  static const fa = 'Vazirmatn'; // 500
  static const faB = 'Vazirmatn'; // 800
  static const num = 'Oxanium';
}

class G {
  static const primary = [C.cyan, Color(0xff5b8cff), C.violet];
  static const gold = [Color(0xff8a5200), Color(0xffd39420), Color(0xffffe08a)];
  static const green = [Color(0xff0a6b4a), Color(0xff16b77a), Color(0xff5dffbf)];
  static const red = [Color(0xff5a0f24), Color(0xffa3203f), Color(0xffff5b74)];
  static const dark = [Color(0xff151f4a), Color(0xff1d2b63), Color(0xff2a3f86)];
  static const violet = [Color(0xff3a1d8a), Color(0xff6d3bff), Color(0xffc08bff)];
}

const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Persian digits with Persian thousands separator (like Number.toLocaleString('fa-IR')).
String fa(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('٬');
    b.write(_faDigits[s.codeUnitAt(i) - 48]);
  }
  return (neg ? '−' : '') + b.toString();
}

String faNum(Object s) => s.toString().replaceAllMapped(RegExp(r'\d'), (m) => _faDigits[int.parse(m[0]!)]);

String en(num n) {
  final s = n.abs().round().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class SP {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

Color hexColor(String h) {
  var s = h.replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length == 6) s = 'ff$s';
  return Color(int.parse(s, radix: 16));
}

Color withA(Color c, double a) => c.withValues(alpha: a);
