import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/ui2/nx2_assets.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../../games/game_registry.dart';

/// Real global rankings: per-game rating (online matches) and overall XP.
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.initialGame});
  final String? initialGame;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  String? _game; // null = global XP
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _game = widget.initialGame;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final OnlineService o = ref.read(onlineProvider);
    if (!o.isOnline) await o.ensureSession();
    final SupabaseClient? c = o.client;
    if (c == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<dynamic> rows = _game == null
          ? await c
              .from('nx_leaderboard_global')
              .select()
              .order('xp', ascending: false)
              .limit(50)
          : await c
              .from('nx_leaderboard')
              .select()
              .eq('game', _game!)
              .order('rating', ascending: false)
              .order('won', ascending: false)
              .limit(50);
      if (!mounted) return;
      setState(() => _rows = rows
          .map((dynamic r) => Map<String, dynamic>.from(r as Map))
          .toList());
    } catch (e) {
      if (mounted)
        setState(() => _error = context.tx(
            'بارگیری رتبه‌بندی ممکن نشد', 'Could not load rankings'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? me = ref.watch(onlineProvider).uid;
    final NxThemeColors visual = NxThemeColors.of(context);
    return NxWorldScaffold(
      title: context.tx('رتبه‌بندی جهانی', 'GLOBAL RANKINGS'),
      palette: WorldPalette.arcade,
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, 6, NxSpace.md, 0),
          child: GlassPanel(
            blur: false,
            borderColor: visual.accent.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: <Widget>[
              Image.asset(Nx2Assets.tilesTileRanking,
                  width: 52, height: 52, cacheWidth: 160,
                  errorBuilder: (_, __, ___) => Icon(Icons.leaderboard_rounded,
                      color: visual.accent, size: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(context.tx('رده‌بندی بازیکنان', 'PLAYER RANKINGS'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(
                          _game == null
                              ? context.tx('رتبه بر پایه‌ی XP', 'Ranked by XP')
                              : context.tx(
                                  'رتبه و بردهای بازی', 'Game rating and wins'),
                          style: TextStyle(color: visual.muted, fontSize: 11)),
                    ]),
              ),
              NxPill(
                  label: '${_rows.length}',
                  icon: Icons.people_alt_rounded,
                  color: visual.accent),
            ]),
          ),
        ),
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: NxSpace.md, vertical: 8),
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(context.tx('همه (XP)', 'All (XP)')),
                  selected: _game == null,
                  selectedColor: visual.accent.withValues(alpha: 0.22),
                  side: BorderSide(
                      color: _game == null
                          ? visual.accent
                          : visual.border.withValues(alpha: 0.55)),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _game = null);
                    _load();
                  },
                ),
              ),
              for (final GameInfo g in kGames)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(context.tx(g.nameFa, g.nameEn)),
                    selected: _game == g.id,
                    selectedColor: visual.accent.withValues(alpha: 0.22),
                    side: BorderSide(
                        color: _game == g.id
                            ? visual.accent
                            : visual.border.withValues(alpha: 0.55)),
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _game = g.id);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.cloud_off_rounded,
                                size: 38, color: visual.muted),
                            const SizedBox(height: 8),
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(context.tx('تلاش دوباره', 'Retry')),
                            ),
                          ]),
                    )
                  : _rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              context.tx(
                                  'هنوز کسی در این بخش بازی آنلاین ثبت نکرده. اولین نفر باش!',
                                  'No online results here yet. Be the first!'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(NxSpace.md),
                            itemCount: _rows.length,
                            itemBuilder: (BuildContext context, int i) {
                              final Map<String, dynamic> r = _rows[i];
                              final bool mine = r['user_id'] == me;
                              final Color medal = i == 0
                                  ? visual.accent
                                  : i == 1
                                      ? const Color(0xFFC0C8D8)
                                      : i == 2
                                          ? const Color(0xFFCD8A55)
                                          : NxColors.textDim;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassPanel(
                                  blur: false,
                                  tint: i == 0
                                      ? visual.accent.withValues(alpha: 0.07)
                                      : null,
                                  borderColor: mine
                                      ? visual.accent
                                      : (i < 3
                                          ? medal.withValues(alpha: 0.58)
                                          : null),
                                  child: Row(children: <Widget>[
                                    if (i < 3)
                                      Image.asset(
                                          <String>[
                                            Nx2Assets.badgesRankGold,
                                            Nx2Assets.badgesRankSilver,
                                            Nx2Assets.badgesRankBronze
                                          ][i],
                                          width: 42,
                                          height: 42,
                                          cacheWidth: 130)
                                    else
                                    Container(
                                      width: 38,
                                      height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: medal.withValues(
                                            alpha: i < 3 ? 0.18 : 0.08),
                                        border: Border.all(
                                            color: medal.withValues(
                                                alpha: i < 3 ? 0.55 : 0.22)),
                                      ),
                                      child: Text('${i + 1}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 17,
                                              color: medal)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                                '${r['username'] ?? 'Pilot'}${mine ? context.tx(' (تو)', ' (you)') : ''}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800)),
                                            Text(
                                              context.tx(
                                                  '${r['won'] ?? 0} برد از ${r['played'] ?? 0} بازی آنلاین',
                                                  '${r['won'] ?? 0} wins of ${r['played'] ?? 0} online games'),
                                              style: TextStyle(
                                                  color: visual.muted,
                                                  fontSize: 12),
                                            ),
                                          ]),
                                    ),
                                    Text(
                                      _game == null
                                          ? 'XP ${r['xp'] ?? 0}'
                                          : '${r['rating'] ?? 1000}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: visual.accent),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
