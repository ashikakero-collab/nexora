import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../data/supabase_nova_repository.dart';
import '../state/nova_controller.dart';

/// Followers / following of a real account (shared `follows` table), with a follow toggle for other people.
class NovaFollowBar extends ConsumerStatefulWidget {
  const NovaFollowBar({super.key, required this.uid, this.self = false});
  final String uid;
  final bool self;

  @override
  ConsumerState<NovaFollowBar> createState() => _NovaFollowBarState();
}

class _NovaFollowBarState extends ConsumerState<NovaFollowBar> {
  ({int followers, int following})? _n;
  bool? _following;
  bool _busy = false;

  SupabaseNovaRepository? get _repo => ref.read(novaControllerProvider).online;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SupabaseNovaRepository? r = _repo;
    if (r == null) return;
    try {
      final ({int followers, int following}) n = await r.followCounts(widget.uid);
      final bool? f = widget.self ? null : await r.isFollowing(widget.uid);
      if (mounted) {
        setState(() {
          _n = n;
          _following = f;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ({int followers, int following})? n = _n;
    Widget stat(String v, String l) => Expanded(
          child: Column(children: <Widget>[
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
          ]),
        );
    return Row(children: <Widget>[
      stat(n == null ? '–' : '${n.followers}', context.tx('دنبال‌کننده', 'Followers')),
      stat(n == null ? '–' : '${n.following}', context.tx('دنبال‌شونده', 'Following')),
      if (!widget.self && _following != null)
        Expanded(
          child: _following!
              ? OutlinedButton(
                  onPressed: _busy ? null : () => _toggle(false),
                  child: Text(context.tx('دنبال می‌کنی', 'Following')),
                )
              : FilledButton(
                  onPressed: _busy ? null : () => _toggle(true),
                  child: Text(context.tx('دنبال کن', 'Follow')),
                ),
        ),
    ]);
  }

  Future<void> _toggle(bool on) async {
    final SupabaseNovaRepository? r = _repo;
    if (r == null) return;
    setState(() => _busy = true);
    try {
      await r.setFollow(widget.uid, on);
    } catch (_) {}
    _busy = false;
    await _load();
  }
}

/// Looks up a real account by username and shows its follow bar (online), or null when not found.
class NovaUserLookup extends ConsumerWidget {
  const NovaUserLookup({super.key, required this.username});
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SupabaseNovaRepository? r = ref.read(novaControllerProvider).online;
    if (r == null) return const SizedBox.shrink();
    return FutureBuilder<List<dynamic>>(
      future: r.c.from('profiles').select('id, username, level, bio').ilike('username', username.replaceAll('%', '')).limit(1),
      builder: (BuildContext c, AsyncSnapshot<List<dynamic>> s) {
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
        if (s.data!.isEmpty) {
          return Text(c.tx('کاوشگری با این نام پیدا نشد.', 'No explorer with this name.'),
              style: const TextStyle(color: NxColors.textDim));
        }
        final Map<dynamic, dynamic> p = s.data!.first as Map;
        final String uid = '${p['id']}';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Lv ${p['level'] ?? 1}${(p['bio'] ?? '').toString().isEmpty ? '' : ' · ${p['bio']}'}',
              style: const TextStyle(color: NxColors.textDim)),
          const SizedBox(height: 10),
          NovaFollowBar(uid: uid, self: uid == r.me),
        ]);
      },
    );
  }
}
