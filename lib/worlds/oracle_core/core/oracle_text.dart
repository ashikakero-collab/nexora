/// ORACLE text utilities (pure Dart): Persian/English normalization and
/// keyword matching used by the intent engine.
library;

// ======================= Normalization =======================

const String _punctuation = '.,!?;:()[]{}«»،؛؟"\'`~-_/\\|@#\$%^&*+=<>…“”‘’';

/// Normalizes Persian/Arabic letters (ي/ى→ی, ك→ک, ة→ه, أ/إ/آ→ا), Persian and
/// Arabic digits (→ 0-9), removes diacritics/tatweel, turns half-spaces and
/// punctuation into spaces, lower-cases and collapses whitespace.
String normalizeOracleText(String input) {
  final StringBuffer sb = StringBuffer();
  for (final int rune in input.runes) {
    int c = rune;
    if (c == 0x064A || c == 0x0649 || c == 0x0626) {
      c = 0x06CC; // ی
    } else if (c == 0x0643) {
      c = 0x06A9; // ک
    } else if (c == 0x0629 || c == 0x06C0 || c == 0x06BE) {
      c = 0x0647; // ه
    } else if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) {
      c = 0x0627; // ا
    } else if (c == 0x0624) {
      c = 0x0648; // و
    }
    if (c >= 0x06F0 && c <= 0x06F9) {
      c = 0x30 + (c - 0x06F0);
    } else if (c >= 0x0660 && c <= 0x0669) {
      c = 0x30 + (c - 0x0660);
    }
    // diacritics, superscript alef, tatweel
    if ((c >= 0x064B && c <= 0x065F) || c == 0x0670 || c == 0x0640) continue;
    // zero-width chars, nbsp, direction marks -> space
    if (c == 0x200C || c == 0x200D || c == 0x00A0 || c == 0x200E || c == 0x200F || c == 0x200B) {
      sb.write(' ');
      continue;
    }
    final String ch = String.fromCharCode(c);
    if (_punctuation.contains(ch)) {
      sb.write(' ');
      continue;
    }
    sb.write(ch);
  }
  return sb.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Latin digits -> Persian digits.
String faDigits(Object value) {
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer sb = StringBuffer();
  for (final int u in '$value'.codeUnits) {
    if (u >= 0x30 && u <= 0x39) {
      sb.write(fa[u - 0x30]);
    } else {
      sb.writeCharCode(u);
    }
  }
  return sb.toString();
}

// ======================= Keyword matching =======================

class _Kw {
  const _Kw(this.text, this.wholeWord);
  final String text;
  final bool wholeWord;
}

final Map<String, _Kw> _kwCache = <String, _Kw>{};

bool _isAscii(String s) {
  for (final int u in s.codeUnits) {
    if (u > 127) return false;
  }
  return true;
}

_Kw _compile(String raw) {
  final _Kw? cached = _kwCache[raw];
  if (cached != null) return cached;
  String k = raw;
  int mode = 0; // 0 auto, 1 prefix, 2 whole word
  if (k.endsWith('*')) {
    mode = 1;
    k = k.substring(0, k.length - 1);
  } else if (k.endsWith('=')) {
    mode = 2;
    k = k.substring(0, k.length - 1);
  }
  final String n = normalizeOracleText(k);
  final bool whole = mode == 2 || (mode == 0 && _isAscii(n));
  final _Kw kw = _Kw(n, whole);
  _kwCache[raw] = kw;
  return kw;
}

String _needle(_Kw kw) => kw.wholeWord ? ' ${kw.text} ' : ' ${kw.text}';

/// Length of the matched keyword (0 = no match). [padded] is ' text '.
int oracleMatchLen(String padded, String raw) {
  final _Kw kw = _compile(raw);
  if (kw.text.isEmpty) return 0;
  return padded.contains(_needle(kw)) ? kw.text.length : 0;
}

bool hasOracleKeyword(String normalized, List<String> keywords) {
  final String padded = ' $normalized ';
  for (final String k in keywords) {
    if (oracleMatchLen(padded, k) > 0) return true;
  }
  return false;
}

int oracleLastIndex(String normalized, List<String> keywords) {
  final String padded = ' $normalized ';
  int best = -1;
  for (final String k in keywords) {
    final _Kw kw = _compile(k);
    if (kw.text.isEmpty) continue;
    final int i = padded.lastIndexOf(_needle(kw));
    if (i > best) best = i;
  }
  return best;
}

