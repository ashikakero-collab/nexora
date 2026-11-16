import 'dart:math';

import 'uno_models.dart';

/// Authoritative NX Cards rules engine (UNO-style). Pure Dart, deterministic for
/// a given seed so the same logic can later run server-side.
///
/// Rules implemented:
///  * 108-card deck, 7 cards dealt, the starting discard is always a number card.
///  * Match colour, number or symbol; Wild anytime; Wild Draw Four only when the
///    player holds no card of the active colour ([strictWildDrawFour]).
///  * Unable (or unwilling) to play: draw one card; the drawn card may be played
///    immediately if legal, otherwise the turn passes.
///  * Skip, Reverse (acts as Skip with 2 players), Draw Two, Wild Draw Four
///    (victim draws and loses the turn). No stacking.
///  * "NX!" call: a player going down to one card must have called it; until the
///    next player acts any opponent may catch them for a 2-card penalty.
///  * Draw pile empty -> discard (minus top card) is reshuffled into it.
///  * First to empty their hand wins and scores the points left in opponents' hands.
class UnoGame {
  UnoGame({required this.playerCount, int? seed, this.strictWildDrawFour = true, int handSize = 7})
      : assert(playerCount >= 2 && playerCount <= 6),
        _rng = Random(seed ?? 20251111) {
    hands = List<List<UnoCard>>.generate(playerCount, (_) => <UnoCard>[]);
    nxCalled = List<bool>.filled(playerCount, false);
    drawPile = buildUnoDeck()..shuffle(_rng);
    for (int r = 0; r < handSize; r++) {
      for (int p = 0; p < playerCount; p++) {
        hands[p].add(drawPile.removeLast());
      }
    }
    // Starting card must be a number card; others go back under the pile.
    UnoCard first = drawPile.removeLast();
    int guard = 0;
    while (first.kind != UnoKind.number && guard < 200) {
      drawPile.insert(0, first);
      first = drawPile.removeLast();
      guard++;
    }
    discard = <UnoCard>[first];
    activeColor = first.color ?? UnoColor.turquoise;
    events.add(const UnoEvent(UnoEventType.deal));
  }

  /// Builds an arbitrary state (tests, server restore).
  UnoGame.fromState({
    required List<List<UnoCard>> hands,
    required List<UnoCard> drawPile,
    required List<UnoCard> discard,
    required this.activeColor,
    this.current = 0,
    this.direction = 1,
    int? seed,
    this.strictWildDrawFour = true,
  })  : playerCount = hands.length,
        _rng = Random(seed ?? 7) {
    this.hands = hands.map((List<UnoCard> h) => List<UnoCard>.of(h)).toList();
    this.drawPile = List<UnoCard>.of(drawPile);
    this.discard = List<UnoCard>.of(discard);
    nxCalled = List<bool>.filled(playerCount, false);
  }

  final int playerCount;
  final bool strictWildDrawFour;
  final Random _rng;

  late List<List<UnoCard>> hands;
  late List<UnoCard> drawPile;
  late List<UnoCard> discard;
  late UnoColor activeColor;
  late List<bool> nxCalled;

  int current = 0;

  /// +1 clockwise (seat order), -1 after a Reverse.
  int direction = 1;

  /// Id of the card the current player just drew and may still play.
  int? drawnCardId;

  /// Seat that went down to one card without calling "NX!" and can be caught.
  int? vulnerable;

  int? winner;

  /// Append-only log. The UI keeps a cursor and animates new entries.
  final List<UnoEvent> events = <UnoEvent>[];

  bool get isOver => winner != null;
  UnoCard get topCard => discard.last;

  int nextSeat(int from, [int steps = 1]) {
    int s = (from + direction * steps) % playerCount;
    if (s < 0) s += playerCount;
    return s;
  }

  // --------------------------------------------------------------- legality

  /// Whether [card] may be played on the current discard by [player].
  bool isLegal(int player, UnoCard card) {
    if (card.isWild) {
      if (card.kind == UnoKind.wildDrawFour && strictWildDrawFour) {
        for (final UnoCard c in hands[player]) {
          if (c.id != card.id && !c.isWild && c.color == activeColor) return false;
        }
      }
      return true;
    }
    if (card.color == activeColor) return true;
    final UnoCard top = topCard;
    if (top.isWild) return false;
    return card.sameFace(top);
  }

  /// Cards [player] may play right now (empty when it is not their turn).
  List<UnoCard> legalCards(int player) {
    if (isOver || player != current) return <UnoCard>[];
    final List<UnoCard> out = <UnoCard>[];
    for (final UnoCard c in hands[player]) {
      if (drawnCardId != null && c.id != drawnCardId) continue;
      if (isLegal(player, c)) out.add(c);
    }
    return out;
  }

  bool hasLegalPlay(int player) => legalCards(player).isNotEmpty;

  /// The player may draw (once per turn, only before drawing).
  bool canDraw(int player) => !isOver && player == current && drawnCardId == null;

  UnoCard? cardInHand(int player, int cardId) {
    for (final UnoCard c in hands[player]) {
      if (c.id == cardId) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------- actions

  /// Plays [cardId] from [player]'s hand. Wild cards need [chosenColor].
  /// Returns false (and changes nothing) when the move is illegal.
  bool play(int player, int cardId, {UnoColor? chosenColor}) {
    if (isOver || player != current) return false;
    final UnoCard? card = cardInHand(player, cardId);
    if (card == null) return false;
    if (drawnCardId != null && drawnCardId != cardId) return false;
    if (!isLegal(player, card)) return false;
    if (card.isWild && chosenColor == null) return false;

    _onPlayerActs(player);
    hands[player].removeWhere((UnoCard c) => c.id == cardId);
    discard.add(card);
    drawnCardId = null;
    events.add(UnoEvent(UnoEventType.play, player: player, card: card));

    if (card.isWild) {
      activeColor = chosenColor!;
      events.add(UnoEvent(UnoEventType.colorChosen, player: player, color: chosenColor));
    } else {
      activeColor = card.color!;
    }

    // NX bookkeeping.
    final int left = hands[player].length;
    if (left == 1) {
      if (!nxCalled[player]) {
        vulnerable = player;
      }
    } else if (left > 1) {
      nxCalled[player] = false;
    }

    final bool won = left == 0;

    switch (card.kind) {
      case UnoKind.number:
      case UnoKind.wild:
        if (!won) current = nextSeat(player, 1);
        break;
      case UnoKind.skip:
        events.add(UnoEvent(UnoEventType.skip, player: nextSeat(player, 1)));
        if (!won) current = nextSeat(player, 2);
        break;
      case UnoKind.reverse:
        direction = -direction;
        events.add(UnoEvent(UnoEventType.reverse, player: player));
        if (!won) {
          if (playerCount == 2) {
            events.add(UnoEvent(UnoEventType.skip, player: nextSeat(player, 1)));
            current = player;
          } else {
            current = nextSeat(player, 1);
          }
        }
        break;
      case UnoKind.drawTwo:
        final int v2 = nextSeat(player, 1);
        _give(v2, 2);
        events.add(UnoEvent(UnoEventType.skip, player: v2));
        if (!won) current = nextSeat(player, 2);
        break;
      case UnoKind.wildDrawFour:
        final int v4 = nextSeat(player, 1);
        _give(v4, 4);
        events.add(UnoEvent(UnoEventType.skip, player: v4));
        if (!won) current = nextSeat(player, 2);
        break;
    }

    if (won) {
      winner = player;
      vulnerable = null;
      events.add(UnoEvent(UnoEventType.win, player: player, count: scoreFor(player)));
    }
    return true;
  }

  /// Draws one card for the turn. If it is playable the player keeps the turn
  /// ([drawnCardId] is set) and may play it or [pass]; otherwise the turn passes.
  /// Returns the drawn card, or null when nothing could be drawn (turn passes).
  UnoCard? draw(int player) {
    if (!canDraw(player)) return null;
    _onPlayerActs(player);
    final List<UnoCard> got = _give(player, 1);
    if (got.isEmpty) {
      events.add(UnoEvent(UnoEventType.pass, player: player));
      current = nextSeat(player, 1);
      return null;
    }
    final UnoCard c = got.first;
    if (isLegal(player, c)) {
      drawnCardId = c.id;
    } else {
      events.add(UnoEvent(UnoEventType.pass, player: player));
      current = nextSeat(player, 1);
    }
    return c;
  }

  /// Keeps the playable drawn card and ends the turn.
  bool pass(int player) {
    if (isOver || player != current || drawnCardId == null) return false;
    drawnCardId = null;
    events.add(UnoEvent(UnoEventType.pass, player: player));
    current = nextSeat(player, 1);
    return true;
  }

  /// Declare "NX!". Valid on your turn with two cards (pre-call), or late with
  /// one card before anyone catches you.
  bool callNx(int player) {
    if (isOver) return false;
    final int n = hands[player].length;
    if (n == 1 && vulnerable == player) {
      vulnerable = null;
      nxCalled[player] = true;
      events.add(UnoEvent(UnoEventType.nxCall, player: player));
      return true;
    }
    if (n == 2 && current == player && !nxCalled[player]) {
      nxCalled[player] = true;
      events.add(UnoEvent(UnoEventType.nxCall, player: player));
      return true;
    }
    return false;
  }

  bool canCallNx(int player) {
    if (isOver) return false;
    final int n = hands[player].length;
    if (n == 1 && vulnerable == player) return true;
    return n == 2 && current == player && !nxCalled[player];
  }

  /// [catcher] catches the vulnerable player, who draws 2 cards.
  bool catchNx(int catcher) {
    final int? v = vulnerable;
    if (isOver || v == null || v == catcher) return false;
    vulnerable = null;
    _give(v, 2);
    events.add(UnoEvent(UnoEventType.nxCaught, player: v, count: 2));
    return true;
  }

  // ---------------------------------------------------------------- scoring

  int handPoints(int player) {
    int s = 0;
    for (final UnoCard c in hands[player]) {
      s += c.points;
    }
    return s;
  }

  /// Points [player] earns for winning: everything left in opponents' hands.
  int scoreFor(int player) {
    int s = 0;
    for (int p = 0; p < playerCount; p++) {
      if (p != player) s += handPoints(p);
    }
    return s;
  }

  // ---------------------------------------------------------------- helpers

  void _onPlayerActs(int player) {
    // The NX catch window closes once another player starts acting.
    if (vulnerable != null && vulnerable != player) vulnerable = null;
  }

  /// Moves up to [n] cards from the draw pile into [player]'s hand, reshuffling
  /// the discard pile when needed.
  List<UnoCard> _give(int player, int n) {
    final List<UnoCard> got = <UnoCard>[];
    for (int i = 0; i < n; i++) {
      if (drawPile.isEmpty) _reshuffle();
      if (drawPile.isEmpty) break;
      final UnoCard c = drawPile.removeLast();
      hands[player].add(c);
      got.add(c);
    }
    if (got.isNotEmpty) {
      events.add(UnoEvent(UnoEventType.draw, player: player, count: got.length));
      if (hands[player].length > 1) nxCalled[player] = false;
      if (vulnerable == player && hands[player].length > 1) vulnerable = null;
    }
    return got;
  }

  void _reshuffle() {
    if (discard.length <= 1) return;
    final UnoCard top = discard.removeLast();
    final List<UnoCard> rest = List<UnoCard>.of(discard);
    discard
      ..clear()
      ..add(top);
    rest.shuffle(_rng);
    drawPile.insertAll(0, rest);
    events.add(UnoEvent(UnoEventType.reshuffle, count: rest.length));
  }

  /// Number of colours of each kind in [player]'s hand (wilds excluded).
  Map<UnoColor, int> colorCounts(int player) {
    final Map<UnoColor, int> m = <UnoColor, int>{};
    for (final UnoColor c in UnoColor.values) {
      m[c] = 0;
    }
    for (final UnoCard card in hands[player]) {
      final UnoColor? col = card.color;
      if (col != null) m[col] = (m[col] ?? 0) + 1;
    }
    return m;
  }
}
