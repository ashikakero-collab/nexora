import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/worlds/orbit_network/data/orbit_repository.dart';
import 'package:nexora/worlds/orbit_network/data/orbit_shared_inbox.dart';
import 'package:nexora/worlds/orbit_network/models/orbit_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await LocalStore.init();
    now = DateTime(2026, 5, 1, 9);
  });

  LocalOrbitRepository repo() => LocalOrbitRepository(LocalStore(store.prefs), clock: () => now);

  group('LocalOrbitRepository', () {
    test('Saved Orbit always exists and cannot be deleted', () async {
      final r = repo();
      final chats = await r.chats(ownerId: 'me');
      expect(chats.first.id, kSavedOrbitId);
      expect(await r.deleteChat(kSavedOrbitId), isFalse);
    });

    test('chats and messages persist across instances', () async {
      final r = repo();
      final g = await r.createChat(kind: OrbitChatKind.group, name: ' Squad ', ownerId: 'me', ownerName: 'Sara');
      expect(g.name, 'Squad');
      now = now.add(const Duration(minutes: 1));
      final m = await r.send(chatId: g.id, authorId: 'me', authorName: 'Sara', text: ' hello orbit ');
      expect(m.text, 'hello orbit');
      expect(m.delivery, OrbitDelivery.queued);

      final r2 = repo();
      final msgs = await r2.messages(g.id);
      expect(msgs.length, 2); // system "group_created" + ours
      expect(msgs.first.kind, OrbitMessageKind.system);
      expect(msgs.last.text, 'hello orbit');
      expect((await r2.chat(g.id))!.name, 'Squad');

      expect(await r2.editMessage(g.id, m.id, 'hello again'), isTrue);
      await r2.toggleStar(g.id, m.id);
      final r3 = repo();
      expect((await r3.lastMessage(g.id))!.text, 'hello again');
      expect((await r3.starred()).single.id, m.id);
      expect((await r3.search('again')).single.id, m.id);

      await r3.deleteMessage(g.id, m.id);
      final r4 = repo();
      final deleted = (await r4.messages(g.id)).last;
      expect(deleted.deleted, isTrue);
      expect(deleted.text, isEmpty);
      expect(await r4.starred(), isEmpty);

      expect(await r4.deleteChat(g.id), isTrue);
      expect(await repo().messages(g.id), isEmpty);
    });

    test('saved orbit messages are read; channels only accept the owner', () async {
      final r = repo();
      await r.chats(ownerId: 'me');
      final s = await r.send(chatId: kSavedOrbitId, authorId: 'me', authorName: 'Sara', text: 'note');
      expect(s.delivery, OrbitDelivery.read);
      final ch = await r.createChat(kind: OrbitChatKind.channel, name: 'News', ownerId: 'me', ownerName: 'Sara');
      await expectLater(r.send(chatId: ch.id, authorId: 'other', authorName: 'X', text: 'hi'), throwsStateError);
      await r.send(chatId: ch.id, authorId: 'me', authorName: 'Sara', text: 'ok');
      expect((await repo().messages(ch.id)).last.text, 'ok');
    });
  });

  group('OrbitSharedInbox', () {
    test('parses millis and ISO dates, rejects invalid entries', () {
      final a = SharedItem.fromJson(<String, dynamic>{'type': 'nova_post', 'id': 'p1', 'text': 't', 'at': 1000, 'author': 'Sara'});
      expect(a!.at, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(a.extra['author'], 'Sara');
      expect(a.key, 'nova_post:p1');
      final b = SharedItem.fromJson(<String, dynamic>{'type': 'game_invite', 'id': 'uno', 'at': '2026-01-02T03:04:05.000'});
      expect(b!.at, DateTime(2026, 1, 2, 3, 4, 5));
      expect(b.gameId, 'uno');
      expect(SharedItem.fromJson('nope'), isNull);
      expect(SharedItem.fromJson(<String, dynamic>{'id': 'x'}), isNull);
      final c = SharedItem.fromJson(<String, dynamic>{'type': 'community_invite', 'id': 'c1', 'gameId': 'carrom'});
      expect(c!.gameId, 'carrom');
    });

    test('add de-duplicates, read sorts newest first, remove and clear work', () async {
      final inbox = OrbitSharedInbox(store);
      await inbox.add(SharedItem(type: SharedItem.novaPost, id: 'p1', text: 'old', at: DateTime(2026, 1, 1)));
      await inbox.add(SharedItem(type: SharedItem.communityInvite, id: 'c1', text: 'join', at: DateTime(2026, 1, 2)));
      await inbox.add(SharedItem(type: SharedItem.novaPost, id: 'p1', text: 'new', at: DateTime(2026, 1, 3)));
      final items = OrbitSharedInbox(LocalStore(store.prefs)).read();
      expect(items.length, 2);
      expect(items.first.text, 'new');
      await inbox.remove('community_invite:c1');
      expect(inbox.read().single.key, 'nova_post:p1');
      await inbox.clear();
      expect(inbox.read(), isEmpty);
    });
  });
}
