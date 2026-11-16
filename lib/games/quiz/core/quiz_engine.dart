/// NEXORA Quiz rules engine (pure Dart, deterministic from a seed).
library;

import 'dart:math' as math;

import 'question_model.dart';

/// Bot skill (mirrors BotDifficulty in the game contract, kept Flutter-free).
enum QuizBotLevel { easy, normal, hard }

enum QuizPhase { picking, question, reveal, finished }

/// One player's answer in one round. [choice] is null when time ran out.
class QuizAnswer {
  const QuizAnswer({required this.choice, required this.elapsedMs, required this.correct, required this.points});

  final int? choice;
  final int elapsedMs;
  final bool correct;
  final int points;
}

/// What the bot will do for a question: which option and after how long.
class QuizBotPlan {
  const QuizBotPlan({required this.choice, required this.delayMs, required this.correct});

  final int choice;
  final int delayMs;
  final bool correct;
}

class QuizEngine {
  QuizEngine({
    required List<QuizQuestion> bank,
    int? seed,
    this.vsBot = true,
    this.botLevel = QuizBotLevel.normal,
  })  : _bank = List<QuizQuestion>.unmodifiable(bank),
        seed = seed ?? 20251112,
        _rng = math.Random(seed ?? 20251112);

  static const int rounds = 10;
  static const int timeLimitMs = 15000;
  static const int basePoints = 100;
  static const int maxSpeedBonus = 50;

  final List<QuizQuestion> _bank;
  final int seed;
  final bool vsBot;
  final QuizBotLevel botLevel;
  final math.Random _rng;

  QuizPhase phase = QuizPhase.picking;

  /// null = mixed.
  QuizCategory? category;
  List<QuizQuestion> questions = <QuizQuestion>[];
  int roundIndex = 0;
  final List<int> scores = <int>[0, 0];
  final List<int> correctCounts = <int>[0, 0];

  /// history[round][player]
  final List<List<QuizAnswer?>> history = <List<QuizAnswer?>>[];

  List<QuizAnswer?> _current = <QuizAnswer?>[null, null];

  QuizQuestion get currentQuestion => questions[roundIndex];
  List<QuizAnswer?> get currentAnswers => List<QuizAnswer?>.unmodifiable(_current);
  int get totalRounds => questions.length;
  bool get isLastRound => roundIndex >= questions.length - 1;

  /// Categories that actually have questions in the bank.
  List<QuizCategory> availableCategories() {
    final Set<QuizCategory> set = <QuizCategory>{};
    for (final QuizQuestion q in _bank) {
      set.add(q.category);
    }
    return QuizCategory.values.where((QuizCategory c) => set.contains(c)).toList();
  }

  int countFor(QuizCategory? c) => c == null ? _bank.length : _bank.where((QuizQuestion q) => q.category == c).length;

  // ---------------------------------------------------------------- selection

  /// Picks up to [rounds] distinct questions. [cat] null means mixed: questions
  /// are interleaved round-robin over categories so the match is varied. If a
  /// category has fewer than [rounds] questions the rest is filled from other
  /// categories (never repeating an id).
  List<QuizQuestion> selectQuestions(QuizCategory? cat) {
    final List<QuizQuestion> unique = <QuizQuestion>[];
    final Set<String> seen = <String>{};
    for (final QuizQuestion q in _bank) {
      if (seen.add(q.id)) unique.add(q);
    }
    final List<QuizQuestion> picked = <QuizQuestion>[];
    final Set<String> used = <String>{};

    void addFrom(List<QuizQuestion> pool) {
      for (final QuizQuestion q in pool) {
        if (picked.length >= rounds) return;
        if (used.add(q.id)) picked.add(q);
      }
    }

    if (cat != null) {
      final List<QuizQuestion> pool = unique.where((QuizQuestion q) => q.category == cat).toList();
      pool.shuffle(_rng);
      addFrom(pool);
    }
    if (picked.length < rounds) {
      // Mixed (or fill): round-robin over shuffled per-category pools.
      final Map<QuizCategory, List<QuizQuestion>> byCat = <QuizCategory, List<QuizQuestion>>{};
      for (final QuizQuestion q in unique) {
        if (used.contains(q.id)) continue;
        byCat.putIfAbsent(q.category, () => <QuizQuestion>[]).add(q);
      }
      final List<QuizCategory> order = byCat.keys.toList()..sort((QuizCategory a, QuizCategory b) => a.index - b.index);
      order.shuffle(_rng);
      for (final QuizCategory c in order) {
        byCat[c]!.shuffle(_rng);
      }
      int depth = 0;
      bool any = true;
      while (picked.length < rounds && any) {
        any = false;
        for (final QuizCategory c in order) {
          final List<QuizQuestion> pool = byCat[c]!;
          if (depth < pool.length) {
            any = true;
            if (picked.length < rounds && used.add(pool[depth].id)) picked.add(pool[depth]);
          }
        }
        depth++;
      }
    }
    return picked;
  }

  /// Chooses the category and starts round 1.
  void start(QuizCategory? cat) {
    category = cat;
    questions = selectQuestions(cat);
    roundIndex = 0;
    scores[0] = 0;
    scores[1] = 0;
    correctCounts[0] = 0;
    correctCounts[1] = 0;
    history.clear();
    _current = <QuizAnswer?>[null, null];
    phase = questions.isEmpty ? QuizPhase.finished : QuizPhase.question;
  }

  // ------------------------------------------------------------------ scoring

  /// 100 for a correct answer plus a speed bonus of up to 50 that falls
  /// linearly to 0 at the 15 s limit. Wrong / no answer = 0.
  static int scoreFor({required bool correct, required int elapsedMs}) {
    if (!correct) return 0;
    final int e = elapsedMs.clamp(0, timeLimitMs);
    final double frac = (timeLimitMs - e) / timeLimitMs;
    return basePoints + (maxSpeedBonus * frac).round();
  }

  /// Remaining time fraction 1..0 for a timer ring.
  static double remainingFraction(int elapsedMs) => (1 - elapsedMs / timeLimitMs).clamp(0.0, 1.0);

  static bool isTimeUp(int elapsedMs) => elapsedMs >= timeLimitMs;

  // ---------------------------------------------------------------------- bot

  static double accuracyFor(QuizBotLevel level) => switch (level) {
        QuizBotLevel.easy => 0.45,
        QuizBotLevel.normal => 0.65,
        QuizBotLevel.hard => 0.85,
      };

  /// [minMs, maxMs] answer-time window per level (a harder question adds a little).
  static List<int> answerWindowFor(QuizBotLevel level) => switch (level) {
        QuizBotLevel.easy => <int>[5500, 12500],
        QuizBotLevel.normal => <int>[3500, 9500],
        QuizBotLevel.hard => <int>[2000, 6500],
      };

  /// Decides the bot's answer for [q]. Always answers before the time limit.
  QuizBotPlan botPlan(QuizQuestion q) => planBot(q, botLevel, _rng);

  static QuizBotPlan planBot(QuizQuestion q, QuizBotLevel level, math.Random rng) {
    final bool correct = rng.nextDouble() < accuracyFor(level);
    int choice = q.correct;
    if (!correct) {
      final List<int> wrong = <int>[0, 1, 2, 3]..remove(q.correct);
      choice = wrong[rng.nextInt(wrong.length)];
    }
    final List<int> w = answerWindowFor(level);
    int delay = w[0] + rng.nextInt(w[1] - w[0] + 1);
    delay += (q.difficulty - 1) * 700;
    // Unsure bots hesitate a bit longer when wrong.
    if (!correct) delay += 400;
    delay = delay.clamp(800, timeLimitMs - 600);
    return QuizBotPlan(choice: choice, delayMs: delay, correct: correct);
  }

  // ------------------------------------------------------------------- rounds

  bool hasAnswered(int player) => _current[player] != null;
  bool get bothAnswered => _current[0] != null && _current[1] != null;

  /// Records [player]'s answer. Returns false if not accepted.
  bool submit(int player, int choice, int elapsedMs) {
    if (phase != QuizPhase.question) return false;
    if (player < 0 || player > 1 || _current[player] != null) return false;
    final int e = elapsedMs.clamp(0, timeLimitMs);
    final bool ok = choice == currentQuestion.correct && e < timeLimitMs;
    _current[player] = QuizAnswer(choice: choice, elapsedMs: e, correct: ok, points: scoreFor(correct: ok, elapsedMs: e));
    if (bothAnswered) _closeRound();
    return true;
  }

  /// Online: [player] ran out of time. Recorded explicitly (like an answer) so both phones agree.
  bool submitTimeout(int player) {
    if (phase != QuizPhase.question || player < 0 || player > 1 || _current[player] != null) return false;
    _current[player] = const QuizAnswer(choice: null, elapsedMs: timeLimitMs, correct: false, points: 0);
    if (bothAnswered) _closeRound();
    return true;
  }

  /// Time ran out: unanswered players get no points; round is revealed.
  void timeUp() {
    if (phase != QuizPhase.question) return;
    for (int p = 0; p < 2; p++) {
      _current[p] ??= const QuizAnswer(choice: null, elapsedMs: timeLimitMs, correct: false, points: 0);
    }
    _closeRound();
  }

  void _closeRound() {
    for (int p = 0; p < 2; p++) {
      final QuizAnswer a = _current[p]!;
      scores[p] += a.points;
      if (a.correct) correctCounts[p]++;
    }
    history.add(List<QuizAnswer?>.from(_current));
    phase = QuizPhase.reveal;
  }

  /// Moves from reveal to the next question (or finishes).
  void next() {
    if (phase != QuizPhase.reveal) return;
    if (isLastRound) {
      phase = QuizPhase.finished;
      return;
    }
    roundIndex++;
    _current = <QuizAnswer?>[null, null];
    phase = QuizPhase.question;
  }

  /// 0 or 1 for the winner, -1 for a draw. Ties on score are broken by correct answers.
  int winner() {
    if (scores[0] != scores[1]) return scores[0] > scores[1] ? 0 : 1;
    if (correctCounts[0] != correctCounts[1]) return correctCounts[0] > correctCounts[1] ? 0 : 1;
    return -1;
  }
}
