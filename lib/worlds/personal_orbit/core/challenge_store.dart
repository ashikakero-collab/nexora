import '../../../core/profile/profile_service.dart';
import '../../../core/storage/local_store.dart';
import 'challenges.dart';

/// Persists the [ChallengeBook] in [LocalStore] and connects it to the profile.
class ChallengeStore {
  ChallengeStore._();

  static const String storageKey = 'personal.challenges.v1';

  static ChallengeBook load(LocalStore store) => ChallengeBook.fromJson(store.getJson(storageKey));

  static Future<void> save(LocalStore store, ChallengeBook book) => store.setJson(storageKey, book.toJson());

  static List<ChallengeEvent> eventsOf(ProfileService p) =>
      p.activity.map((ActivityEntry a) => ChallengeEvent(a.at, a.kind)).toList();

  /// Loads, rolls the period (snapshotting baselines) and persists if needed.
  /// Worlds call this when opened so baselines start as early as possible.
  static ChallengeBook touch(ProfileService p, {LocalStore? store, DateTime? now}) {
    final LocalStore s = store ?? LocalStore.instance;
    final ChallengeBook book = load(s);
    if (book.roll(now ?? DateTime.now(), p.counters)) {
      save(s, book);
    }
    return book;
  }

  /// Claims a completed challenge exactly once and awards XP/coins.
  /// Returns null when it is not claimable.
  static AwardOutcome? claim(ProfileService p, ChallengeDef def, {LocalStore? store, DateTime? now}) {
    final LocalStore s = store ?? LocalStore.instance;
    final DateTime t = now ?? DateTime.now();
    final ChallengeBook book = load(s);
    book.roll(t, p.counters);
    if (!book.claim(def, t, p.counters, eventsOf(p))) return null;
    save(s, book);
    return p.award('challenge.${def.id}',
        xp: def.xp, coins: def.coins, fa: 'چالش کامل شد: ${def.titleFa}', en: 'Challenge complete: ${def.titleEn}');
  }
}
