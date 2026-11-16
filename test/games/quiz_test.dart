import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/quiz/core/question_bank.dart';
import 'package:nexora/games/quiz/core/question_model.dart';
import 'package:nexora/games/quiz/core/quiz_engine.dart';

List<QuizQuestion> _synthBank() {
  final List<QuizQuestion> out = <QuizQuestion>[];
  for (final QuizCategory c in QuizCategory.values) {
    final int n = c == QuizCategory.media ? 4 : 14; // media is deliberately short
    for (int i = 0; i < n; i++) {
      out.add(QuizQuestion(
        id: '${c.name}_$i',
        category: c,
        difficulty: 1 + i % 3,
        fa: 'سؤال $i',
        en: 'Question $i',
        optionsFa: const <String>['a', 'b', 'c', 'd'],
        optionsEn: const <String>['a', 'b', 'c', 'd'],
        correct: i % 4,
      ));
    }
  }
  return out;
}

void main() {
  final List<QuizQuestion> bank = _synthBank();

  group('selection', () {
    test('10 rounds, no repeats, right category, for many seeds', () {
      for (int seed = 0; seed < 200; seed++) {
        final QuizEngine e = QuizEngine(bank: bank, seed: seed);
        final List<QuizQuestion> qs = e.selectQuestions(QuizCategory.space);
        expect(qs.length, QuizEngine.rounds);
        expect(qs.map((QuizQuestion q) => q.id).toSet().length, QuizEngine.rounds);
        expect(qs.every((QuizQuestion q) => q.category == QuizCategory.space), isTrue);
      }
    });

    test('mixed spans several categories without repeats', () {
      final QuizEngine e = QuizEngine(bank: bank, seed: 7);
      final List<QuizQuestion> qs = e.selectQuestions(null);
      expect(qs.length, 10);
      expect(qs.map((QuizQuestion q) => q.id).toSet().length, 10);
      expect(qs.map((QuizQuestion q) => q.category).toSet().length, greaterThanOrEqualTo(5));
    });

    test('short category is filled from others, still no repeats', () {
      final QuizEngine e = QuizEngine(bank: bank, seed: 3);
      final List<QuizQuestion> qs = e.selectQuestions(QuizCategory.media);
      expect(qs.length, 10);
      expect(qs.map((QuizQuestion q) => q.id).toSet().length, 10);
      expect(qs.where((QuizQuestion q) => q.category == QuizCategory.media).length, 4);
    });

    test('same seed gives same questions', () {
      final List<String> a = QuizEngine(bank: bank, seed: 42).selectQuestions(null).map((QuizQuestion q) => q.id).toList();
      final List<String> b = QuizEngine(bank: bank, seed: 42).selectQuestions(null).map((QuizQuestion q) => q.id).toList();
      expect(a, b);
    });
  });

  group('scoring', () {
    test('correct = 100 + speed bonus up to 50', () {
      expect(QuizEngine.scoreFor(correct: true, elapsedMs: 0), 150);
      expect(QuizEngine.scoreFor(correct: true, elapsedMs: 7500), 125);
      expect(QuizEngine.scoreFor(correct: true, elapsedMs: 14999), 100);
      expect(QuizEngine.scoreFor(correct: false, elapsedMs: 0), 0);
    });

    test('round flow accumulates scores and times out', () {
      final QuizEngine e = QuizEngine(bank: bank, seed: 1, vsBot: false)..start(QuizCategory.science);
      final QuizQuestion q = e.currentQuestion;
      expect(e.submit(0, q.correct, 0), isTrue);
      expect(e.submit(0, q.correct, 0), isFalse); // no double answers
      expect(e.phase, QuizPhase.question);
      e.submit(1, (q.correct + 1) % 4, 2000);
      expect(e.phase, QuizPhase.reveal);
      expect(e.scores, <int>[150, 0]);
      e.next();
      e.timeUp();
      expect(e.phase, QuizPhase.reveal);
      expect(e.scores, <int>[150, 0]);
    });
  });

  group('bot', () {
    for (final QuizBotLevel lvl in QuizBotLevel.values) {
      test('accuracy roughly matches for $lvl', () {
        int correct = 0;
        const int n = 4000;
        int totalDelay = 0;
        for (int s = 0; s < n; s++) {
          final math.Random rng = math.Random(s * 31 + 5);
          final QuizQuestion q = bank[s % bank.length];
          final QuizBotPlan p = QuizEngine.planBot(q, lvl, rng);
          expect(p.choice, inInclusiveRange(0, 3));
          expect(p.delayMs, lessThan(QuizEngine.timeLimitMs));
          expect(p.correct, p.choice == q.correct);
          if (p.correct) correct++;
          totalDelay += p.delayMs;
        }
        expect(correct / n, closeTo(QuizEngine.accuracyFor(lvl), 0.04));
        expect(totalDelay / n, greaterThan(1000));
      });
    }

    test('harder bots answer faster on average', () {
      double avg(QuizBotLevel l) {
        final math.Random rng = math.Random(9);
        int t = 0;
        for (int i = 0; i < 2000; i++) {
          t += QuizEngine.planBot(bank[i % bank.length], l, rng).delayMs;
        }
        return t / 2000;
      }

      expect(avg(QuizBotLevel.hard), lessThan(avg(QuizBotLevel.normal)));
      expect(avg(QuizBotLevel.normal), lessThan(avg(QuizBotLevel.easy)));
    });
  });

  group('winner', () {
    test('full match: player who always answers correctly wins', () {
      final QuizEngine e = QuizEngine(bank: bank, seed: 11, vsBot: false)..start(null);
      while (e.phase != QuizPhase.finished) {
        final QuizQuestion q = e.currentQuestion;
        e.submit(0, (q.correct + 1) % 4, 1000);
        e.submit(1, q.correct, 5000);
        e.next();
      }
      expect(e.history.length, 10);
      expect(e.winner(), 1);
      expect(e.correctCounts[1], 10);
    });

    test('equal play is a draw', () {
      final QuizEngine e = QuizEngine(bank: bank, seed: 12)..start(QuizCategory.history);
      while (e.phase != QuizPhase.finished) {
        e.submit(0, e.currentQuestion.correct, 3000);
        e.submit(1, e.currentQuestion.correct, 3000);
        e.next();
      }
      expect(e.winner(), -1);
    });
  });

  test('shipped bank is well formed', () {
    expect(kQuestionBank, isNotEmpty);
    final Set<String> ids = <String>{};
    for (final QuizQuestion q in kQuestionBank) {
      expect(ids.add(q.id), isTrue, reason: 'duplicate id ${q.id}');
      expect(q.optionsFa.length, 4, reason: q.id);
      expect(q.optionsEn.length, 4, reason: q.id);
      expect(q.correct, inInclusiveRange(0, 3), reason: q.id);
    }
    final QuizEngine e = QuizEngine(bank: kQuestionBank, seed: 5)..start(null);
    expect(e.questions.map((QuizQuestion q) => q.id).toSet().length, e.questions.length);
  });
}
