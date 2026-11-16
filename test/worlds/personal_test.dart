import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/worlds/personal_orbit/core/challenge_store.dart';
import 'package:nexora/worlds/personal_orbit/core/challenges.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChallengeDef _def(String id) =>
    <ChallengeDef>[...kDailyChallenges, ...kWeeklyChallenges].firstWhere((ChallengeDef d) => d.id == id);

void main() {
  late LocalStore store;
  late ProfileService profile;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    store = LocalStore(prefs);
    LocalStore.setForTest(store);
    profile = ProfileService(store);
    await profile.createIdentity(name: 'Tester');
  });

  test('activity challenge progresses with real matches and is claimed exactly once', () {
    final ChallengeDef play3 = _def('d_play3');
    ChallengeStore.touch(profile, store: store);
    for (int i = 0; i < 3; i++) {
      profile.recordGame(gameId: 'carrom', gameNameFa: 'کارم', gameNameEn: 'Carrom', outcome: i == 0 ? 'win' : 'loss');
    }
    final DateTime now = DateTime.now();
    final ChallengeBook book = ChallengeStore.touch(profile, store: store, now: now);
    final List<ChallengeEvent> events = ChallengeStore.eventsOf(profile);
    expect(book.progress(play3, now, profile.counters, events), 3);
    expect(book.canClaim(play3, now, profile.counters, events), isTrue);

    final int coinsBefore = profile.coins;
    final int xpBefore = profile.xp;
    final AwardOutcome? first = ChallengeStore.claim(profile, play3, store: store, now: now);
    expect(first, isNotNull);
    expect(profile.coins, greaterThanOrEqualTo(coinsBefore + play3.coins));
    expect(profile.xp, xpBefore + play3.xp);

    final int coinsAfter = profile.coins;
    final AwardOutcome? second = ChallengeStore.claim(profile, play3, store: store, now: now);
    expect(second, isNull);
    expect(profile.coins, coinsAfter);

    // Persisted: a fresh load still knows it is claimed.
    expect(ChallengeStore.load(store).isClaimed(play3), isTrue);
  });

  test('incomplete challenge cannot be claimed', () {
    final ChallengeDef win1 = _def('d_win1');
    final DateTime now = DateTime.now();
    ChallengeStore.touch(profile, store: store, now: now);
    profile.recordGame(gameId: 'ludo', gameNameFa: 'لودو', gameNameEn: 'Ludo', outcome: 'loss');
    final DateTime later = DateTime.now();
    final ChallengeBook book = ChallengeStore.touch(profile, store: store, now: later);
    expect(book.progress(win1, later, profile.counters, ChallengeStore.eventsOf(profile)), 0);
    expect(ChallengeStore.claim(profile, win1, store: store, now: later), isNull);
  });

  test('counter challenge only counts progress after the period baseline', () {
    final ChallengeDef post = _def('d_post1');
    profile.bump('nova.posts'); // before the period was seen: not counted
    final DateTime now = DateTime.now();
    ChallengeBook book = ChallengeStore.touch(profile, store: store, now: now);
    expect(book.progress(post, now, profile.counters, const <ChallengeEvent>[]), 0);
    expect(ChallengeStore.claim(profile, post, store: store, now: now), isNull);

    profile.bump('nova.posts');
    book = ChallengeStore.touch(profile, store: store, now: now);
    expect(book.progress(post, now, profile.counters, const <ChallengeEvent>[]), 1);
    expect(ChallengeStore.claim(profile, post, store: store, now: now), isNotNull);
    expect(ChallengeStore.claim(profile, post, store: store, now: now), isNull);
  });

  test('a new day resets daily claims but keeps weekly state per week', () {
    final DateTime day1 = DateTime(2026, 11, 14, 10); // Saturday
    final DateTime day2 = DateTime(2026, 11, 15, 10); // Sunday, same week
    expect(periodKey(ChallengePeriod.daily, day1) == periodKey(ChallengePeriod.daily, day2), isFalse);
    expect(periodKey(ChallengePeriod.weekly, day1), periodKey(ChallengePeriod.weekly, day2));
    final ChallengeBook book = ChallengeBook();
    book.roll(day1, profile.counters);
    book.stateFor(ChallengePeriod.daily)!.claimed.add('d_play3');
    book.roll(day2, profile.counters);
    expect(book.isClaimed(_def('d_play3')), isFalse);
  });

  test('daily reward is claimable once per day and starts a streak', () {
    expect(profile.canClaimDaily, isTrue);
    expect(profile.claimDaily(), isNotNull);
    expect(profile.streak, 1);
    expect(profile.canClaimDaily, isFalse);
    expect(profile.claimDaily(), isNull);
  });
}
