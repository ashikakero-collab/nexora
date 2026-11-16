import 'dart:math';

/// Pure-Dart Snakes & Ladders rules (no Flutter imports, deterministic).
/// Squares 1..100, 0 = not yet on the board. Exact 100 wins (overshoot
/// bounces back), a 6 earns another roll.

const int kSnlGoal = 100;

/// Ladder bottom -> top.
const Map<int, int> kSnlLadders = <int, int>{
  1: 38,
  4: 14,
  9: 31,
  21: 42,
  28: 84,
  36: 44,
  51: 67,
  71: 91,
  80: 100,
};

/// Snake head -> tail.
const Map<int, int> kSnlSnakes = <int, int>{
  16: 6,
  47: 26,
  49: 11,
  56: 53,
  62: 19,
  64: 60,
  87: 24,
  93: 73,
  95: 75,
  98: 78,
};

class SnlMoveResult {
  const SnlMoveResult({
    required this.seat,
    required this.roll,
    required this.from,
    required this.steps,
    required this.landed,
    required this.finalPos,
    required this.won,
    required this.extraTurn,
  });

  final int seat;
  final int roll;
  final int from;

  /// Every square visited while walking (bounce included), in order.
  final List<int> steps;

  /// Square reached by walking, before any snake or ladder.
  final int landed;
  final int finalPos;
  final bool won;
  final bool extraTurn;

  bool get climbed => finalPos > landed;
  bool get bitten => finalPos < landed;
}

class SnlRules {
  SnlRules._();

  /// Squares visited when walking [roll] steps from [from], bouncing off 100.
  static List<int> walk(int from, int roll) {
    final List<int> steps = <int>[];
    int pos = from;
    int dir = 1;
    for (int i = 0; i < roll; i++) {
      if (pos == kSnlGoal) dir = -1;
      pos += dir;
      steps.add(pos);
    }
    return steps;
  }

  /// Applies a ladder or snake on [square].
  static int resolve(int square) {
    final int? up = kSnlLadders[square];
    if (up != null) return up;
    final int? down = kSnlSnakes[square];
    if (down != null) return down;
    return square;
  }

  static bool isValidLayout() {
    for (final int k in kSnlLadders.keys) {
      if (kSnlSnakes.containsKey(k)) return false;
      if (kSnlLadders[k]! <= k) return false;
    }
    for (final int k in kSnlSnakes.keys) {
      if (kSnlSnakes[k]! >= k || k == kSnlGoal) return false;
    }
    return true;
  }
}

class SnlEngine {
  SnlEngine({required int playerCount, int? seed})
      : playerCount = playerCount < 2 ? 2 : (playerCount > 4 ? 4 : playerCount),
        _rng = Random(seed) {
    positions = List<int>.filled(this.playerCount, 0);
  }

  final int playerCount;
  final Random _rng;
  late List<int> positions;
  int turn = 0;
  int? winner;

  int rollDie() => _rng.nextInt(6) + 1;

  /// Moves the current player by [roll] and advances the turn.
  SnlMoveResult move(int roll) {
    final int seat = turn;
    final int from = positions[seat];
    final List<int> steps = SnlRules.walk(from, roll);
    final int landed = steps.isEmpty ? from : steps.last;
    final int finalPos = SnlRules.resolve(landed);
    positions[seat] = finalPos;
    final bool won = finalPos == kSnlGoal;
    if (won) winner = seat;
    final bool extra = !won && roll == 6;
    if (!won && !extra) turn = (turn + 1) % playerCount;
    return SnlMoveResult(
      seat: seat,
      roll: roll,
      from: from,
      steps: steps,
      landed: landed,
      finalPos: finalPos,
      won: won,
      extraTurn: extra,
    );
  }
}
