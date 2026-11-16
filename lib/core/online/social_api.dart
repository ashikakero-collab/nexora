import 'package:supabase_flutter/supabase_flutter.dart';

/// A real NEXORA user (public profile row).
class NxUser {
  const NxUser({required this.id, required this.username, this.avatar, this.level = 1, this.onlineAt, this.bio});
  final String id;
  final String username;
  final String? avatar;
  final int level;
  final DateTime? onlineAt;
  final String? bio;

  bool get isOnlineNow => onlineAt != null && DateTime.now().toUtc().difference(onlineAt!.toUtc()).inMinutes < 3;

  static NxUser fromRow(Map<String, dynamic> r) => NxUser(
        id: '${r['id']}',
        username: '${r['username'] ?? 'Pilot'}',
        avatar: r['avatar'] as String?,
        level: (r['level'] as num?)?.toInt() ?? 1,
        onlineAt: DateTime.tryParse('${r['online_at'] ?? ''}'),
        bio: r['bio'] as String?,
      );
}

class FriendRequest {
  const FriendRequest({required this.from, required this.to, required this.user, required this.incoming});
  final String from;
  final String to;
  final NxUser user;
  final bool incoming;
}

/// Friends / requests / search on the shared tables (follows + friend_requests), via the
/// same RPCs the other NEXORA app uses, so a friendship is the same in both apps.
class SocialApi {
  SocialApi(this.c);
  final SupabaseClient c;

  String get me => c.auth.currentUser!.id;

  static const String _cols = 'id, username, avatar, level, online_at, bio';

  Future<List<NxUser>> friends() async {
    final List<dynamic> mine = await c.from('follows').select('followee').eq('follower', me);
    final List<dynamic> back = await c.from('follows').select('follower').eq('followee', me);
    final Set<String> a = mine.map((dynamic r) => '${(r as Map)['followee']}').toSet();
    final Set<String> b = back.map((dynamic r) => '${(r as Map)['follower']}').toSet();
    final List<String> ids = a.intersection(b).toList();
    if (ids.isEmpty) return <NxUser>[];
    final List<dynamic> rows = await c.from('profiles').select(_cols).inFilter('id', ids);
    final List<NxUser> out = rows.map((dynamic r) => NxUser.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    out.sort((NxUser x, NxUser y) {
      if (x.isOnlineNow != y.isOnlineNow) return x.isOnlineNow ? -1 : 1;
      return x.username.toLowerCase().compareTo(y.username.toLowerCase());
    });
    return out;
  }

  Future<List<FriendRequest>> requests() async {
    final List<dynamic> rows = await c
        .from('friend_requests')
        .select('from_user, to_user, status')
        .or('from_user.eq.$me,to_user.eq.$me')
        .eq('status', 'pending');
    if (rows.isEmpty) return <FriendRequest>[];
    final Set<String> ids = <String>{};
    for (final dynamic r in rows) {
      final Map<dynamic, dynamic> m = r as Map;
      ids.add('${m['from_user']}');
      ids.add('${m['to_user']}');
    }
    ids.remove(me);
    final Map<String, NxUser> users = await profiles(ids.toList());
    final List<FriendRequest> out = <FriendRequest>[];
    for (final dynamic r in rows) {
      final Map<dynamic, dynamic> m = r as Map;
      final bool incoming = '${m['to_user']}' == me;
      final String other = incoming ? '${m['from_user']}' : '${m['to_user']}';
      final NxUser? u = users[other];
      if (u == null) continue;
      out.add(FriendRequest(from: '${m['from_user']}', to: '${m['to_user']}', user: u, incoming: incoming));
    }
    return out;
  }

  Future<Map<String, NxUser>> profiles(List<String> ids) async {
    if (ids.isEmpty) return <String, NxUser>{};
    final List<dynamic> rows = await c.from('profiles').select(_cols).inFilter('id', ids);
    return <String, NxUser>{
      for (final dynamic r in rows) '${(r as Map)['id']}': NxUser.fromRow(Map<String, dynamic>.from(r)),
    };
  }

  Future<NxUser?> profile(String id) async => (await profiles(<String>[id]))[id];

  Future<List<NxUser>> search(String q) async {
    final String t = q.trim().replaceAll('%', '').replaceAll(',', '');
    if (t.length < 2) return <NxUser>[];
    final List<dynamic> rows = await c.from('profiles').select(_cols).ilike('username', '%$t%').neq('id', me).limit(25);
    return rows.map((dynamic r) => NxUser.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<String> sendRequest(String userId) async => '${await c.rpc('send_friend_request', params: <String, dynamic>{'p_user': userId})}';
  Future<void> respond(String fromUser, bool accept) =>
      c.rpc('respond_friend_request', params: <String, dynamic>{'p_from': fromUser, 'p_accept': accept});
  Future<void> cancelRequest(String userId) => c.rpc('cancel_friend_request', params: <String, dynamic>{'p_user': userId});
  Future<void> removeFriend(String userId) => c.rpc('remove_friend', params: <String, dynamic>{'p_user': userId});
  Future<void> touchPresence() => c.rpc('touch_presence');
}
