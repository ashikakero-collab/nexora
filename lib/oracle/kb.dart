// Oracle knowledge base + intent matcher (port of src/oracle/kb.ts; rule based, Persian + English, offline).
part 'kb_gen.dart';

class Intent {
  final String id;
  final List<String> kw;
  final String answer, mood;
  final List<String> actions;
  const Intent(this.id, this.kw, this.answer, this.mood, this.actions);
}

const _digits = {'۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4', '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9', '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9'};

String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[يى]'), 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp('[ةۀ]'), 'ه')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ؤ', 'و')
    .replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) => _digits[m[0]] ?? m[0]!)
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .replaceAll('\u200c', ' ')
    .replaceAll(RegExp('[^a-z0-9\u0600-\u06FF\\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

(Intent?, String?) matchIntent(String text) {
  final q = ' ${normalize(text)} ';
  if (q.trim().isEmpty) return (null, null);
  for (final (id, kws) in kActionKw) {
    if (kws.any((k) => q.contains(normalize(k)))) return (null, id);
  }
  Intent? best;
  var score = 0.0;
  for (final it in kIntents) {
    var s = 0.0;
    for (final k in it.kw) {
      final n = normalize(k);
      if (n.isNotEmpty && q.contains(n)) s += 1 + n.length / 6;
    }
    if (s > score) {
      score = s;
      best = it;
    }
  }
  return (score >= 1 ? best : null, null);
}
