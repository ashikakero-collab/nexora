import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/online/online_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/core/game_contract.dart';
import '../../games/game_registry.dart';

/// ROOMS — opened by the big GAME button in the dock.
///  * Quick Play: pick a game -> real matchmaking (`nx_quick`) in that game's lobby.
///  * Create Room: pick a game -> a new public room (`nx_create_room`), others can join from this list.
///  * Open rooms: every public lobby on the server right now (no placeholder rows: empty/offline states only).
///  * All games: the arcade list (offline vs-bot / pass-and-play stays available there).
class RoomsPage extends ConsumerStatefulWidget {
  const RoomsPage({super.key});

  @override
  ConsumerState<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends ConsumerState<RoomsPage> {
  List<Map<String, dynamic>> _rooms = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_load(silent: true)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final OnlineService o = ref.read(onlineProvider);
    if (!silent && mounted) setState(() => _loading = true);
    try {
      if (!o.isOnline) await o.ensureSession();
      final SupabaseClient? c = o.client;
      if (c == null || c.auth.currentSession == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'offline';
          });
        }
        return;
      }
      final List<dynamic> rows = await c
          .from('nx_rooms')
          .select('id, code, game, seats, host, created_at, nx_room_players(count)')
          .eq('status', 'lobby')
          .eq('is_private', false)
          .eq('quick', false)
          .gte('updated_at', DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String())
          .order('created_at', ascending: false)
          .limit(40);
      if (!mounted) return;
      setState(() {
        _rooms = rows.map((dynamic r) => Map<String, dynamic>.from(r as Map)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'offline';
        });
      }
    }
  }

  Future<void> _pickGame(String action) async {
    final List<GameInfo> games = kGames.where((GameInfo g) => g.supportsOnline).toList();
    final GameInfo? g = await showModalBottomSheet<GameInfo>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _GamePickerSheet(games: games, title: action == 'quick'
          ? ctx.tx('بازی سریع — کدام بازی؟', 'Quick Play — which game?')
          : ctx.tx('ساخت اتاق — کدام بازی؟', 'Create room — which game?')),
    );
    if (g == null || !mounted) return;
    await context.push('/online/${g.id}?action=$action');
    unawaited(_load(silent: true));
  }

  int _count(Map<String, dynamic> r) {
    final dynamic p = r['nx_room_players'];
    if (p is List && p.isNotEmpty && p.first is Map) return ((p.first as Map)['count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return NxWorldScaffold(
      title: context.tx('اتاق‌ها', 'ROOMS'),
      palette: WorldPalette.arcade,
      dock: Nx2Tab.games,
      room: true,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: <Widget>[
            Nx2Banner(text: context.tx('اتاق‌های زنده', 'LIVE ROOMS'), height: 56),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: Nx2Button(
                  label: context.tx('بازی سریع', 'QUICK'),
                  icon: Icons.bolt_rounded,
                  kind: Nx2ButtonKind.pink,
                  height: 58,
                  onTap: () => _pickGame('quick'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Nx2Button(
                  label: context.tx('ساخت اتاق', 'NEW ROOM'),
                  icon: Icons.add_circle_rounded,
                  kind: Nx2ButtonKind.cyan,
                  height: 58,
                  onTap: () => _pickGame('create'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Nx2Button(
              label: context.tx('همه‌ی بازی‌ها (آفلاین و با ربات)', 'ALL GAMES (offline & vs bot)'),
              icon: Icons.sports_esports_rounded,
              kind: Nx2ButtonKind.violet,
              height: 50,
              fontSize: 13,
              onTap: () => context.push('/world/nexora_arcade'),
            ),
            const SizedBox(height: 18),
            Nx2SectionHeader(title: context.tx('اتاق‌های باز', 'Open rooms')),
            const SizedBox(height: 8),
            if (_loading && _rooms.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _rooms.isEmpty)
              _Empty(
                icon: Icons.wifi_off_rounded,
                text: context.tx('اتصال به سرور برقرار نشد. بازی آفلاین در «همه‌ی بازی‌ها» در دسترس است.',
                    'Could not reach the server. Offline games are under “All games”.'),
                onRetry: _load,
              )
            else if (_rooms.isEmpty)
              _Empty(
                icon: Icons.meeting_room_outlined,
                text: context.tx('الان اتاق بازی وجود ندارد. اولین اتاق را بساز!',
                    'No open rooms right now. Create the first one!'),
                onRetry: _load,
              )
            else
              for (final Map<String, dynamic> r in _rooms) _roomTile(r),
          ],
        ),
      ),
    );
  }

  Widget _roomTile(Map<String, dynamic> r) {
    final GameInfo? g = gameById('${r['game']}');
    final int n = _count(r), seats = (r['seats'] as num?)?.toInt() ?? 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Nx2Panel(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        onTap: () async {
          await context.push('/online/${r['game']}?room=${r['id']}');
          unawaited(_load(silent: true));
        },
        child: Row(children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (g?.accent ?? Nx2.cyan).withValues(alpha: 0.18),
              border: Border.all(color: g?.accent ?? Nx2.cyan, width: 1.5),
            ),
            child: Icon(Icons.sports_esports_rounded, color: g?.accent ?? Nx2.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(g == null ? '${r['game']}' : context.tx(g.nameFa, g.nameEn),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Nx2.text)),
              Text('${context.tx('کد', 'Code')} ${r['code']}',
                  style: const TextStyle(color: Nx2.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          Text('$n/$seats',
              style: const TextStyle(color: Nx2.cyan, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(width: 6),
          const Icon(Icons.login_rounded, color: Nx2.text),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, required this.onRetry});
  final IconData icon;
  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Nx2Panel(
      padding: const EdgeInsets.all(18),
      child: Column(children: <Widget>[
        Icon(icon, size: 40, color: Nx2.muted),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Nx2.text, fontSize: 13)),
        const SizedBox(height: 10),
        TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tx('تلاش دوباره', 'Retry'))),
      ]),
    );
  }
}

class _GamePickerSheet extends StatelessWidget {
  const _GamePickerSheet({required this.games, required this.title});
  final List<GameInfo> games;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Nx2Panel(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Nx2.text)),
            const SizedBox(height: 10),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.05,
                children: <Widget>[
                  for (final GameInfo g in games)
                    Nx2Pressable(
                      onTap: () => Navigator.pop(context, g),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: g.accent.withValues(alpha: 0.14),
                          border: Border.all(color: g.accent.withValues(alpha: 0.8)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                          Image.asset('assets/arcade/pedestals/${g.id}.webp',
                              height: 52, errorBuilder: (_, __, ___) => Icon(Icons.sports_esports_rounded, color: g.accent)),
                          const SizedBox(height: 4),
                          Text(context.tx(g.nameFa, g.nameEn),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Nx2.text)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
