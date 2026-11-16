// Pure-Dart models for NX Cards (UNO-style rules). No Flutter imports.

enum UnoColor { turquoise, violet, gold, pink }

enum UnoKind { number, skip, reverse, drawTwo, wild, wildDrawFour }

/// Difficulty for the offline bot (mapped from BotDifficulty by the UI layer
/// so that this core stays free of Flutter imports).
enum UnoBotLevel { easy, normal, hard }

class UnoCard {
  const UnoCard({required this.id, required this.kind, this.color, this.number = -1});

  /// Unique id inside one deck (0..107).
  final int id;
  final UnoKind kind;

  /// null for wild cards.
  final UnoColor? color;

  /// 0..9 for number cards, -1 otherwise.
  final int number;

  bool get isWild => kind == UnoKind.wild || kind == UnoKind.wildDrawFour;
  bool get isAction => kind == UnoKind.skip || kind == UnoKind.reverse || kind == UnoKind.drawTwo;

  /// Scoring value when left in an opponent's hand.
  int get points {
    switch (kind) {
      case UnoKind.number:
        return number;
      case UnoKind.skip:
      case UnoKind.reverse:
      case UnoKind.drawTwo:
        return 20;
      case UnoKind.wild:
      case UnoKind.wildDrawFour:
        return 50;
    }
  }

  /// True when this card shows the same face (kind + number) as [other].
  bool sameFace(UnoCard other) {
    if (kind != other.kind) return false;
    if (kind == UnoKind.number) return number == other.number;
    return true;
  }

  @override
  String toString() {
    final String c = color == null ? 'wild' : color!.name;
    if (kind == UnoKind.number) return '$c-$number';
    return '$c-${kind.name}';
  }

  @override
  bool operator ==(Object other) => other is UnoCard && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum UnoEventType { deal, play, draw, skip, reverse, colorChosen, nxCall, nxCaught, reshuffle, win, pass }

/// Something that happened in the engine; the UI animates these in order.
class UnoEvent {
  const UnoEvent(this.type, {this.player = -1, this.card, this.count = 0, this.color});
  final UnoEventType type;
  final int player;
  final UnoCard? card;
  final int count;
  final UnoColor? color;

  @override
  String toString() => 'UnoEvent(${type.name}, p$player, $card, x$count, ${color?.name})';
}

/// Builds the standard 108-card deck (unshuffled).
/// Per colour: one 0, two of each 1-9, two Skip, two Reverse, two Draw Two (25).
/// Plus 4 Wild and 4 Wild Draw Four.
List<UnoCard> buildUnoDeck() {
  final List<UnoCard> deck = <UnoCard>[];
  int id = 0;
  for (final UnoColor c in UnoColor.values) {
    deck.add(UnoCard(id: id++, kind: UnoKind.number, color: c, number: 0));
    for (int n = 1; n <= 9; n++) {
      deck.add(UnoCard(id: id++, kind: UnoKind.number, color: c, number: n));
      deck.add(UnoCard(id: id++, kind: UnoKind.number, color: c, number: n));
    }
    for (int k = 0; k < 2; k++) {
      deck.add(UnoCard(id: id++, kind: UnoKind.skip, color: c));
      deck.add(UnoCard(id: id++, kind: UnoKind.reverse, color: c));
      deck.add(UnoCard(id: id++, kind: UnoKind.drawTwo, color: c));
    }
  }
  for (int k = 0; k < 4; k++) {
    deck.add(UnoCard(id: id++, kind: UnoKind.wild));
  }
  for (int k = 0; k < 4; k++) {
    deck.add(UnoCard(id: id++, kind: UnoKind.wildDrawFour));
  }
  return deck;
}
