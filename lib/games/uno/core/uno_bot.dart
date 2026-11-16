import 'dart:math';

import 'uno_engine.dart';
import 'uno_models.dart';

/// What a bot wants to do on its turn.
class UnoBotMove {
  const UnoBotMove.play(this.cardId, [this.color]) : draw = false;
  const UnoBotMove.draw()
      : draw = true,
        cardId = null,
        color = null;

  final bool draw;
  final int? cardId;
  final UnoColor? color;
}

/// Offline AI for NX Cards.
///  * easy: random legal card, random wild colour.
///  * normal: prefers matching the active colour, holds wilds until needed,
///    picks the colour it holds most.
///  * hard: also tracks opponents' hand sizes and fires action cards at the
///    next player when they (or the table leader) are close to winning,
///    dumps high-value cards otherwise.
class UnoBot {
  UnoBot._();

  static double nxCallChance(UnoBotLevel l) {
    switch (l) {
      case UnoBotLevel.easy:
        return 0.7;
      case UnoBotLevel.normal:
        return 0.9;
      case UnoBotLevel.hard:
        return 1.0;
    }
  }

  static double catchChance(UnoBotLevel l) {
    switch (l) {
      case UnoBotLevel.easy:
        return 0.3;
      case UnoBotLevel.normal:
        return 0.6;
      case UnoBotLevel.hard:
        return 0.9;
    }
  }

  static UnoColor bestColor(UnoGame g, int seat, Random rng, {int? excludingCardId}) {
    final Map<UnoColor, int> counts = <UnoColor, int>{};
    for (final UnoColor c in UnoColor.values) {
      counts[c] = 0;
    }
    for (final UnoCard card in g.hands[seat]) {
      if (card.id == excludingCardId) continue;
      final UnoColor? col = card.color;
      if (col != null) counts[col] = (counts[col] ?? 0) + 1;
    }
    UnoColor best = UnoColor.values[rng.nextInt(UnoColor.values.length)];
    int bestN = -1;
    for (final UnoColor c in UnoColor.values) {
      final int n = counts[c] ?? 0;
      if (n > bestN) {
        best = c;
        bestN = n;
      }
    }
    return best;
  }

  /// Chooses a move for [seat]. Always legal: if a card is returned it passes
  /// [UnoGame.isLegal]; otherwise the bot draws.
  static UnoBotMove decide(UnoGame g, int seat, UnoBotLevel level, Random rng) {
    final List<UnoCard> legal = g.legalCards(seat);
    if (legal.isEmpty) return const UnoBotMove.draw();
    UnoCard pick = legal.first;
    switch (level) {
      case UnoBotLevel.easy:
        pick = legal[rng.nextInt(legal.length)];
        break;
      case UnoBotLevel.normal:
        pick = _normalPick(g, seat, legal);
        break;
      case UnoBotLevel.hard:
        pick = _hardPick(g, seat, legal);
        break;
    }
    UnoColor? color;
    if (pick.isWild) {
      color = level == UnoBotLevel.easy
          ? UnoColor.values[rng.nextInt(UnoColor.values.length)]
          : bestColor(g, seat, rng, excludingCardId: pick.id);
    }
    return UnoBotMove.play(pick.id, color);
  }

  /// After drawing a playable card: play it or keep it.
  static bool playDrawn(UnoGame g, int seat, UnoBotLevel level, Random rng) {
    final int? id = g.drawnCardId;
    if (id == null) return false;
    if (level == UnoBotLevel.easy) return rng.nextDouble() < 0.9;
    final UnoCard? c = g.cardInHand(seat, id);
    if (c == null) return false;
    // Normal keeps a drawn plain Wild if it has other cards to work with.
    if (level == UnoBotLevel.normal && c.kind == UnoKind.wild && g.hands[seat].length > 3) return false;
    return true;
  }

  static UnoCard _normalPick(UnoGame g, int seat, List<UnoCard> legal) {
    final List<UnoCard> colorMatch =
        legal.where((UnoCard c) => !c.isWild && c.color == g.activeColor).toList();
    if (colorMatch.isNotEmpty) {
      colorMatch.sort((UnoCard a, UnoCard b) => b.points.compareTo(a.points));
      return colorMatch.first;
    }
    final List<UnoCard> faceMatch = legal.where((UnoCard c) => !c.isWild).toList();
    if (faceMatch.isNotEmpty) {
      // Switch into the colour we hold most of.
      final Map<UnoColor, int> counts = g.colorCounts(seat);
      faceMatch.sort((UnoCard a, UnoCard b) => (counts[b.color] ?? 0).compareTo(counts[a.color] ?? 0));
      return faceMatch.first;
    }
    // Only wilds: use the plain wild first, keep +4 for later if possible.
    final List<UnoCard> plain = legal.where((UnoCard c) => c.kind == UnoKind.wild).toList();
    if (plain.isNotEmpty) return plain.first;
    return legal.first;
  }

  static UnoCard _hardPick(UnoGame g, int seat, List<UnoCard> legal) {
    final int next = g.nextSeat(seat, 1);
    final int nextCount = g.hands[next].length;
    int leader = -1;
    int leaderCount = 999;
    for (int p = 0; p < g.playerCount; p++) {
      if (p == seat) continue;
      if (g.hands[p].length < leaderCount) {
        leaderCount = g.hands[p].length;
        leader = p;
      }
    }
    final bool threat = nextCount <= 2 || (next == leader && leaderCount <= 4);

    int score(UnoCard c) {
      int s = 0;
      switch (c.kind) {
        case UnoKind.wildDrawFour:
          s = threat ? 120 : -40;
          break;
        case UnoKind.drawTwo:
          s = threat ? 100 : 10;
          break;
        case UnoKind.skip:
          s = threat ? 90 : 8;
          break;
        case UnoKind.reverse:
          // Reversing sends the turn away from the threat (if >2 players).
          s = threat ? (g.playerCount > 2 ? 70 : 90) : 6;
          break;
        case UnoKind.wild:
          s = -30;
          break;
        case UnoKind.number:
          s = c.number; // dump high numbers first
          break;
      }
      if (!c.isWild && c.color == g.activeColor) s += 4;
      // Prefer staying in a colour we hold many of.
      final UnoColor? col = c.color;
      if (col != null) s += (g.colorCounts(seat)[col] ?? 0) * 3;
      // Going out soon: play wilds/actions before getting stuck with them.
      if (g.hands[seat].length <= 2 && c.isWild) s += 60;
      return s;
    }

    final List<UnoCard> sorted = List<UnoCard>.of(legal)
      ..sort((UnoCard a, UnoCard b) => score(b).compareTo(score(a)));
    return sorted.first;
  }
}
