import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/uno/core/uno_bot.dart';
import 'package:nexora/games/uno/core/uno_engine.dart';
import 'package:nexora/games/uno/core/uno_models.dart';

int _nextId = 1000;

UnoCard n(UnoColor c, int number) => UnoCard(id: _nextId++, kind: UnoKind.number, color: c, number: number);
UnoCard act(UnoColor c, UnoKind k) => UnoCard(id: _nextId++, kind: k, color: c);
UnoCard wild() => UnoCard(id: _nextId++, kind: UnoKind.wild);
UnoCard wild4() => UnoCard(id: _nextId++, kind: UnoKind.wildDrawFour);

List<UnoCard> filler(int count) =>
    List<UnoCard>.generate(count, (int i) => n(UnoColor.values[i % 4], (i % 9) + 1));

void main() {
  group('deck', () {
    test('has 108 cards with the right composition', () {
      final List<UnoCard> deck = buildUnoDeck();
      expect(deck.length, 108);
      expect(deck.map((UnoCard c) => c.id).toSet().length, 108);
      expect(deck.where((UnoCard c) => c.kind == UnoKind.wild).length, 4);
      expect(deck.where((UnoCard c) => c.kind == UnoKind.wildDrawFour).length, 4);
      expect(deck.where((UnoCard c) => c.kind == UnoKind.number).length, 76);
      for (final UnoColor col in UnoColor.values) {
        final Iterable<UnoCard> ofColor = deck.where((UnoCard c) => c.color == col);
        expect(ofColor.length, 25);
        expect(ofColor.where((UnoCard c) => c.kind == UnoKind.number && c.number == 0).length, 1);
        expect(ofColor.where((UnoCard c) => c.kind == UnoKind.number && c.number == 7).length, 2);
        expect(ofColor.where((UnoCard c) => c.kind == UnoKind.skip).length, 2);
        expect(ofColor.where((UnoCard c) => c.kind == UnoKind.reverse).length, 2);
        expect(ofColor.where((UnoCard c) => c.kind == UnoKind.drawTwo).length, 2);
      }
    });

    test('deal gives 7 cards each and starts on a number card', () {
      for (int seed = 0; seed < 20; seed++) {
        final UnoGame g = UnoGame(playerCount: 4, seed: seed);
        for (final List<UnoCard> h in g.hands) {
          expect(h.length, 7);
        }
        expect(g.discard.length, 1);
        expect(g.topCard.kind, UnoKind.number);
        expect(g.activeColor, g.topCard.color);
        expect(g.drawPile.length, 108 - 28 - 1);
      }
    });

    test('card points', () {
      expect(n(UnoColor.gold, 7).points, 7);
      expect(act(UnoColor.gold, UnoKind.skip).points, 20);
      expect(wild4().points, 50);
    });
  });

  group('legal play', () {
    test('matches colour, number or symbol; wild anytime', () {
      final UnoCard top = n(UnoColor.pink, 5);
      final UnoCard sameColor = n(UnoColor.pink, 9);
      final UnoCard sameNumber = n(UnoColor.gold, 5);
      final UnoCard other = n(UnoColor.gold, 3);
      final UnoCard w = wild();
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[sameColor, sameNumber, other, w],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[top],
        activeColor: UnoColor.pink,
      );
      expect(g.isLegal(0, sameColor), isTrue);
      expect(g.isLegal(0, sameNumber), isTrue);
      expect(g.isLegal(0, other), isFalse);
      expect(g.isLegal(0, w), isTrue);
      expect(g.legalCards(0).length, 3);
      expect(g.legalCards(1), isEmpty); // not their turn
      expect(g.play(0, other.id), isFalse);
      expect(g.play(0, w.id), isFalse, reason: 'wild needs a colour');
    });

    test('symbol matches symbol of another colour', () {
      final UnoCard top = act(UnoColor.violet, UnoKind.skip);
      final UnoCard skipGold = act(UnoColor.gold, UnoKind.skip);
      final UnoCard revGold = act(UnoColor.gold, UnoKind.reverse);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[skipGold, revGold, n(UnoColor.gold, 1)],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[top],
        activeColor: UnoColor.violet,
      );
      expect(g.isLegal(0, skipGold), isTrue);
      expect(g.isLegal(0, revGold), isFalse);
    });

    test('after a wild only the chosen colour (or a wild) matches', () {
      final UnoCard top = wild();
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[n(UnoColor.gold, 2), n(UnoColor.turquoise, 2)],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[top],
        activeColor: UnoColor.turquoise,
      );
      expect(g.legalCards(0).single.color, UnoColor.turquoise);
    });
  });

  group('action cards', () {
    test('skip jumps over the next player', () {
      final UnoCard s = act(UnoColor.gold, UnoKind.skip);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[s, ...filler(3)],
          filler(3),
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.play(0, s.id), isTrue);
      expect(g.current, 2);
    });

    test('reverse flips direction with 3 players', () {
      final UnoCard r = act(UnoColor.gold, UnoKind.reverse);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[r, ...filler(3)],
          filler(3),
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.play(0, r.id), isTrue);
      expect(g.direction, -1);
      expect(g.current, 2);
    });

    test('reverse acts as skip with 2 players', () {
      final UnoCard r = act(UnoColor.gold, UnoKind.reverse);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[r, ...filler(3)],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.play(0, r.id), isTrue);
      expect(g.current, 0);
    });

    test('draw two makes next player draw 2 and lose the turn', () {
      final UnoCard d2 = act(UnoColor.pink, UnoKind.drawTwo);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[d2, ...filler(3)],
          filler(3),
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.pink, 4)],
        activeColor: UnoColor.pink,
      );
      expect(g.play(0, d2.id), isTrue);
      expect(g.hands[1].length, 5);
      expect(g.current, 2);
    });

    test('wild draw four: strict legality, colour choice, +4 and skip', () {
      final UnoCard w4 = wild4();
      final UnoGame blocked = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[w4, n(UnoColor.gold, 8)],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(blocked.isLegal(0, w4), isFalse, reason: 'holds a gold card');

      final UnoCard w4b = wild4();
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[w4b, n(UnoColor.pink, 8), n(UnoColor.violet, 1)],
          filler(3),
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.isLegal(0, w4b), isTrue);
      expect(g.play(0, w4b.id, chosenColor: UnoColor.violet), isTrue);
      expect(g.activeColor, UnoColor.violet);
      expect(g.hands[1].length, 7);
      expect(g.current, 2);
    });
  });

  group('drawing', () {
    test('unplayable drawn card passes the turn; playable one may be played', () {
      final UnoCard drawnBad = n(UnoColor.violet, 3);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[n(UnoColor.turquoise, 1)],
          filler(3),
        ],
        drawPile: <UnoCard>[drawnBad],
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.draw(0), drawnBad);
      expect(g.current, 1);
      expect(g.hands[0].length, 2);

      final UnoCard drawnGood = n(UnoColor.gold, 9);
      final UnoGame g2 = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[n(UnoColor.turquoise, 1), n(UnoColor.pink, 2)],
          filler(3),
        ],
        drawPile: <UnoCard>[drawnGood],
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g2.draw(0), drawnGood);
      expect(g2.current, 0);
      expect(g2.drawnCardId, drawnGood.id);
      expect(g2.canDraw(0), isFalse);
      expect(g2.play(0, drawnGood.id), isTrue);
      expect(g2.current, 1);
    });

    test('empty draw pile reshuffles the discard pile', () {
      final List<UnoCard> discard = <UnoCard>[n(UnoColor.pink, 1), n(UnoColor.pink, 2), n(UnoColor.gold, 4)];
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[n(UnoColor.turquoise, 1), n(UnoColor.violet, 2)],
          filler(3),
        ],
        drawPile: <UnoCard>[],
        discard: discard,
        activeColor: UnoColor.gold,
      );
      g.draw(0);
      expect(g.discard.length, 1);
      expect(g.topCard.number, 4);
      expect(g.hands[0].length, 3);
      expect(g.drawPile.length, 1);
      expect(g.events.any((UnoEvent e) => e.type == UnoEventType.reshuffle), isTrue);
    });
  });

  group('NX call and winning', () {
    test('forgetting NX can be caught for +2', () {
      final UnoCard a = n(UnoColor.gold, 5);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[a, n(UnoColor.pink, 2)],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.play(0, a.id), isTrue);
      expect(g.vulnerable, 0);
      expect(g.catchNx(0), isFalse, reason: 'cannot catch yourself');
      expect(g.catchNx(1), isTrue);
      expect(g.hands[0].length, 3);
      expect(g.vulnerable, isNull);
    });

    test('calling NX before playing protects the player', () {
      final UnoCard a = n(UnoColor.gold, 5);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[a, n(UnoColor.pink, 2)],
          filler(3),
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.callNx(0), isTrue);
      expect(g.play(0, a.id), isTrue);
      expect(g.vulnerable, isNull);
      expect(g.catchNx(1), isFalse);
    });

    test('catch window closes when the next player acts', () {
      final UnoCard a = n(UnoColor.gold, 5);
      final UnoCard b = n(UnoColor.gold, 6);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[a, n(UnoColor.pink, 2)],
          <UnoCard>[b, ...filler(3)],
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      g.play(0, a.id);
      g.play(1, b.id);
      expect(g.catchNx(1), isFalse);
    });

    test('emptying the hand wins and scores opponents\' points', () {
      final UnoCard last = n(UnoColor.gold, 5);
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[
          <UnoCard>[last],
          <UnoCard>[n(UnoColor.pink, 9), act(UnoColor.pink, UnoKind.skip)],
          <UnoCard>[wild()],
        ],
        drawPile: filler(10),
        discard: <UnoCard>[n(UnoColor.gold, 4)],
        activeColor: UnoColor.gold,
      );
      expect(g.play(0, last.id), isTrue);
      expect(g.isOver, isTrue);
      expect(g.winner, 0);
      expect(g.scoreFor(0), 9 + 20 + 50);
      expect(g.play(1, g.hands[1].first.id), isFalse);
    });
  });

  group('bot', () {
    test('every level only makes legal moves and games finish', () {
      for (final UnoBotLevel level in UnoBotLevel.values) {
        for (int seed = 0; seed < 15; seed++) {
          final UnoGame g = UnoGame(playerCount: 2 + seed % 3, seed: seed);
          final Random rng = Random(seed);
          int guard = 0;
          while (!g.isOver && guard < 3000) {
            guard++;
            final int seat = g.current;
            if (g.drawnCardId != null) {
              if (UnoBot.playDrawn(g, seat, level, rng)) {
                final UnoCard c = g.cardInHand(seat, g.drawnCardId!)!;
                expect(g.play(seat, c.id, chosenColor: c.isWild ? UnoBot.bestColor(g, seat, rng) : null), isTrue);
              } else {
                expect(g.pass(seat), isTrue);
              }
              continue;
            }
            final UnoBotMove m = UnoBot.decide(g, seat, level, rng);
            if (m.draw) {
              expect(g.hasLegalPlay(seat), isFalse);
              g.draw(seat);
            } else {
              if (g.hands[seat].length == 2) g.callNx(seat);
              expect(g.play(seat, m.cardId!, chosenColor: m.color), isTrue);
            }
            int total = g.drawPile.length + g.discard.length;
            for (final List<UnoCard> h in g.hands) {
              total += h.length;
            }
            expect(total, 108, reason: 'cards are conserved');
          }
          expect(g.isOver, isTrue, reason: 'level $level seed $seed finished');
        }
      }
    });
  });
}
