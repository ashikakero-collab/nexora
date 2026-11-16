import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/quiz/core/question_bank.dart';
import 'package:nexora/games/quiz/core/question_model.dart';

void main() {
  test('quiz bank has enough questions', () {
    expect(kQuestionBank.length, greaterThanOrEqualTo(240));
  });

  test('quiz bank: every category has at least 27 questions', () {
    for (final QuizCategory c in QuizCategory.values) {
      final int n = kQuestionBank.where((QuizQuestion q) => q.category == c).length;
      expect(n, greaterThanOrEqualTo(27), reason: 'category ${c.name}');
    }
  });

  test('quiz bank: options, correct index and difficulty are valid', () {
    for (final QuizQuestion q in kQuestionBank) {
      expect(q.optionsFa.length, 4, reason: q.id);
      expect(q.optionsEn.length, 4, reason: q.id);
      expect(q.correct, inInclusiveRange(0, 3), reason: q.id);
      expect(q.difficulty, inInclusiveRange(1, 3), reason: q.id);
      expect(q.fa.trim(), isNotEmpty, reason: q.id);
      expect(q.en.trim(), isNotEmpty, reason: q.id);
      expect(q.optionsEn.toSet().length, 4, reason: q.id);
      expect(q.optionsFa.toSet().length, 4, reason: q.id);
      expect(q.id.startsWith('${q.category.name}_'), isTrue, reason: q.id);
    }
  });

  test('quiz bank: unique ids and no duplicate question text', () {
    final Set<String> ids = <String>{};
    final Set<String> en = <String>{};
    final Set<String> fa = <String>{};
    for (final QuizQuestion q in kQuestionBank) {
      expect(ids.add(q.id), isTrue, reason: 'duplicate id ${q.id}');
      expect(en.add(q.en.toLowerCase()), isTrue, reason: 'duplicate en ${q.id}');
      expect(fa.add(q.fa), isTrue, reason: 'duplicate fa ${q.id}');
    }
  });

  test('quiz bank: correct answers spread across all positions', () {
    final List<int> counts = List<int>.filled(4, 0);
    for (final QuizQuestion q in kQuestionBank) {
      counts[q.correct]++;
    }
    for (final int c in counts) {
      expect(c, greaterThan(kQuestionBank.length ~/ 8));
    }
  });
}
