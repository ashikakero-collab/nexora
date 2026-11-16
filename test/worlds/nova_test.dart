import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/worlds/nova_gallery/data/nova_repository.dart';
import 'package:nexora/worlds/nova_gallery/models/nova_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NovaText', () {
    test('parses hashtags and mentions, ignoring e-mail style symbols', () {
      const text = 'Hello #NEXORA and #بازی_شب mail@host.com @Ali.';
      expect(NovaText.hashtags(text), <String>{'nexora', 'بازی_شب'});
      expect(NovaText.mentions(text), <String>{'ali'});
      final joined = NovaText.parse(text).map((NovaToken t) => t.display).join();
      expect(joined, text);
    });

    test('plain text yields a single text token', () {
      final tokens = NovaText.parse('just words');
      expect(tokens.length, 1);
      expect(tokens.single.kind, NovaTokenKind.text);
      expect(NovaText.hashtags('# alone'), isEmpty);
    });
  });

  group('LocalNovaRepository', () {
    late LocalStore store;
    late DateTime now;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = await LocalStore.init();
      now = DateTime(2026, 3, 1, 10);
    });

    LocalNovaRepository repo() => LocalNovaRepository(LocalStore(store.prefs), clock: () => now);

    test('post CRUD persists across instances', () async {
      final r = repo();
      final seeded = (await r.feed()).length;
      final p = await r.createPost(authorId: 'me', authorName: 'Sara', text: ' First #orbit post ');
      expect(p.text, 'First #orbit post');
      expect((await repo().feed()).length, seeded + 1);

      await r.updatePost(p.id, text: 'Edited #nova', visual: NovaVisual.none, motion: true);
      final again = await repo().post(p.id);
      expect(again!.text, 'Edited #nova');
      expect(again.motion, isTrue);
      expect(again.editedAt, isNotNull);

      final r2 = repo();
      expect(await r2.toggleLike(p.id, 'me'), isTrue);
      await r2.addComment(p.id, authorId: 'me', authorName: 'Sara', text: 'nice');
      expect(await r2.toggleSave(p.id), isTrue);
      final r3 = repo();
      final loaded = (await r3.post(p.id))!;
      expect(loaded.likeCount, 1);
      expect(loaded.comments.single.text, 'nice');
      expect(await r3.savedIds(), contains(p.id));
      expect((await r3.search('#nova')).map((NovaPost x) => x.id), contains(p.id));

      await r3.deletePost(p.id);
      final r4 = repo();
      expect(await r4.post(p.id), isNull);
      expect(await r4.savedIds(), isNot(contains(p.id)));
      expect((await r4.feed()).length, seeded);
    });

    test('stories expire after 24 hours and are purged', () async {
      final r = repo();
      final s = await r.createStory(authorId: 'me', authorName: 'Sara', text: 'hi', gradient: 2);
      expect(s.expiresAt, now.add(kStoryLifetime));
      expect((await r.activeStories()).length, 1);
      now = now.add(const Duration(hours: 23, minutes: 59));
      expect((await repo().activeStories()).length, 1);
      now = now.add(const Duration(minutes: 2));
      expect(await repo().activeStories(), isEmpty);
      expect(store.getJsonList(LocalNovaRepository.kStories), isEmpty);
    });
  });
}
