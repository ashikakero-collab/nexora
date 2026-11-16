import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/ui2/nx2_assets.dart';
import '../../../core/ui2/nx2_widgets.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../../games/game_registry.dart';
import '../data/models.dart';
import '../data/tournament_repository.dart';
import '../domain/bracket.dart';
import '../domain/prize_split.dart';
import 't_common.dart';

/// Tournaments list: registering / upcoming / live / finished / mine, with filters and live countdowns.
class TournamentsPage extends ConsumerStatefulWidget {
  const TournamentsPage({super.key, this.game, this.joinCode});

  /// Optional game filter (e.g. opened from finger soccer).
  final String? game;

  /// Deep link nexora://t/<code>: join right away.
  final String? joinCode;

  @override
  ConsumerState<TournamentsPage> createState() => _TournamentsPageState();
}

enum _FeeFilter { all, free, paid }

enum _KindFilter { all, knockout, league }

class _TournamentsPageState extends ConsumerState<TournamentsPage>
    with TClockUser<TournamentsPage> {
  List<Tournament> _all = <Tournament>[];
  Map<String, TEntry> _mine = <String, TEntry>{};
  List<TMatch> _myMatches = <TMatch>[];
  bool _loading = true;
  String? _error;
  int _unread = 0;
  bool _organizer = false;
  _FeeFilter _fee = _FeeFilter.all;
  _KindFilter _kind = _KindFilter.all;
  late String? _game = widget.game;
  RealtimeChannel? _ch;
  Timer? _debounce;
  Timer? _poll;

  TournamentRepository get _repo => ref.read(tournamentRepoProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(
        const Duration(seconds: 45), (_) => unawaited(_load(silent: true)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String? code = widget.joinCode;
      if (code != null && code.isNotEmpty && mounted) unawaited(_join(code));
    });
  }

  // The client the realtime channel was opened on (ref cannot be used in dispose()).
  SupabaseClient? _chClient;

  void _subscribe() {
    if (_ch != null) return;
    final SupabaseClient? c = ref.read(onlineProvider).client;
    if (c == null || !ref.read(onlineProvider).isOnline) return;
    _chClient = c;
    _ch = c
        .channel('nxt:list:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_tournaments',
          callback: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 600),
                () => unawaited(_load(silent: true)));
          },
        )
        .subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    final OnlineService o = ref.read(onlineProvider);
    if (!o.configured) {
      setState(() {
        _loading = false;
        _error = 'offline';
      });
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      await o.ensureSession();
      final List<dynamic> res = await Future.wait<dynamic>(<Future<dynamic>>[
        _repo.list(),
        _repo.myEntries(),
        _repo.myOpenMatches(),
        _repo.notifications(),
        _repo.myRole(),
      ]);
      if (!mounted) return;
      setState(() {
        _all = res[0] as List<Tournament>;
        _mine = res[1] as Map<String, TEntry>;
        _myMatches = res[2] as List<TMatch>;
        _unread = (res[3] as List<TNotification>)
            .where((TNotification n) => !n.read)
            .length;
        _organizer = ((res[4] as ({bool admin, bool organizer})).organizer);
        _loading = false;
        _error = null;
      });
      _subscribe();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    final RealtimeChannel? ch = _ch;
    final SupabaseClient? c = _chClient;
    if (ch != null && c != null) unawaited(c.removeChannel(ch));
    super.dispose();
  }

  List<Tournament> _forTab(TTab tab) {
    Iterable<Tournament> l = _all;
    if (_game != null) l = l.where((Tournament t) => t.game == _game);
    if (_fee == _FeeFilter.free) l = l.where((Tournament t) => t.isFree);
    if (_fee == _FeeFilter.paid) l = l.where((Tournament t) => !t.isFree);
    if (_kind == _KindFilter.knockout)
      l = l.where(
          (Tournament t) => !t.format.isLeague && t.format != TFormat.groupsKo);
    if (_kind == _KindFilter.league)
      l = l.where(
          (Tournament t) => t.format.isLeague || t.format == TFormat.groupsKo);
    if (tab == TTab.mine) {
      l = l.where((Tournament t) =>
          _mine.containsKey(t.id) || t.createdBy == _repo.uid);
    } else {
      l = l.where((Tournament t) => t.tab == tab && t.status != 'draft');
    }
    final List<Tournament> out = l.toList();
    if (tab == TTab.finished) {
      out.sort((Tournament a, Tournament b) =>
          (b.finishedAt ?? b.startAt).compareTo(a.finishedAt ?? a.startAt));
    }
    return out;
  }

  Future<void> _join(String code) async {
    final bool fa = ref.read(settingsProvider).isFa;
    final TResult r = await _repo.joinCode(code);
    if (!mounted) return;
    final String? t = r.data['tournament_id'] as String?;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok
          ? (fa
              ? 'ثبت شد: ${entryStatusName(context, '${r.data['status']}')}'
              : 'Done: ${entryStatusName(context, '${r.data['status']}')}')
          : tErrorText(r.error, fa)),
    ));
    if (t != null) {
      unawaited(_load(silent: true));
      unawaited(context.push('/tournaments/$t'));
    }
  }

  Future<void> _enterCode() async {
    final TextEditingController c = TextEditingController();
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('ورود با کد دعوت', 'Enter invite code')),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 9,
          decoration: const InputDecoration(hintText: 'ABCD2345'),
          onSubmitted: (String v) => Navigator.pop(ctx, v),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text(ctx.tx('ثبت‌نام', 'Join'))),
        ],
      ),
    );
    c.dispose();
    if (code != null && code.trim().isNotEmpty) await _join(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final OnlineService o = ref.watch(onlineProvider);
    final List<(TTab, String)> tabs = <(TTab, String)>[
      (TTab.registering, context.tx('ثبت‌نام', 'Registering')),
      (TTab.upcoming, context.tx('به‌زودی', 'Upcoming')),
      (TTab.live, context.tx('زنده', 'Live')),
      (TTab.finished, context.tx('تمام‌شده', 'Finished')),
      (TTab.mine, context.tx('مال من', 'Mine')),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: NxWorldScaffold(
        title: context.tx('تورنمنت‌ها', 'TOURNAMENTS'),
        palette: WorldPalette.arcade,
        showWallet: false,
        actions: <Widget>[
          IconButton(
            tooltip: context.tx('کد دعوت', 'Invite code'),
            onPressed: o.configured ? _enterCode : null,
            icon: const Icon(Icons.vpn_key_rounded),
          ),
          IconButton(
            tooltip: context.tx('اعلان‌ها', 'Notifications'),
            onPressed: () async {
              await context.push('/tournaments/inbox');
              unawaited(_load(silent: true));
            },
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: const Icon(Icons.notifications_rounded),
            ),
          ),
        ],
        floatingActionButton: _organizer
            ? FloatingActionButton.extended(
                backgroundColor: tAccent(context),
                foregroundColor: NxColors.navyDeep,
                onPressed: () async {
                  await context.push('/tournaments/new');
                  unawaited(_load(silent: true));
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tx('تورنمنت جدید', 'New tournament')),
              )
            : null,
        body: !o.configured
            ? Padding(
                padding: const EdgeInsets.all(NxSpace.md),
                child: OnlineOnlyNotice(
                    featureFa: 'تورنمنت‌ها', featureEn: 'Tournaments'),
              )
            : Column(children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Nx2Panel(
                    gold: true,
                    padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                    child: Row(children: <Widget>[
                      Image.asset(Nx2Assets.badgesTrophyGold,
                          width: 46, height: 56, cacheWidth: 140),
                      Image.asset(Nx2Assets.badgesTrophyWings,
                          width: 34, height: 44, cacheWidth: 110),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(context.tx('جام‌های نکسورا', 'NEXORA CUPS'),
                                  style: Nx2.title.copyWith(
                                      fontSize: 15, color: Nx2.gold)),
                              Text(
                                  context.tx('ثبت‌نام کن، بازی کن، جایزه ببر',
                                      'Register, play, win prizes'),
                                  style: const TextStyle(
                                      color: Nx2.muted, fontSize: 11.5)),
                            ]),
                      ),
                    ]),
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: tAccent(context),
                  labelColor: tAccent(context),
                  unselectedLabelColor: NxColors.textDim,
                  dividerColor: Colors.transparent,
                  tabs: <Widget>[
                    for (final (TTab t, String label) in tabs)
                      Tab(
                          text:
                              '$label${_count(t) > 0 ? ' · ${_count(t)}' : ''}'),
                  ],
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(NxSpace.md, 6, NxSpace.md, 2),
                  child: GlassPanel(
                    blur: false,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: tAccent(context).withValues(alpha: 0.14),
                          border: Border.all(
                              color: tAccent(context).withValues(alpha: 0.42)),
                        ),
                        child: Icon(Icons.emoji_events_rounded,
                            color: tAccent(context)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                  context.tx(
                                      'رویدادهای رقابتی', 'Competitive events'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              Text(
                                  context.tx('${_all.length} تورنمنت در دسترس',
                                      '${_all.length} tournaments available'),
                                  style: const TextStyle(
                                      color: NxColors.textDim, fontSize: 12)),
                            ]),
                      ),
                      NxPill(
                        label:
                            '${_all.where((Tournament t) => t.status == 'live').length}',
                        icon: Icons.sensors_rounded,
                        color: tAccentSecondary(context),
                      ),
                    ]),
                  ),
                ),
                _filters(context),
                if (_myMatches.isNotEmpty) _nextMatchBanner(context),
                Expanded(
                  child: _loading && _all.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null && _all.isEmpty
                          ? _errorView(context)
                          : TabBarView(children: <Widget>[
                              for (final (TTab t, String _) in tabs)
                                _list(context, t)
                            ]),
                ),
              ]),
      ),
    );
  }

  int _count(TTab t) => _forTab(t).length;

  Widget _errorView(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.cloud_off_rounded,
              size: 46, color: NxColors.textDim),
          const SizedBox(height: 8),
          Text(context.tx('اتصال برقرار نشد', 'Could not connect')),
          TextButton(
              onPressed: _load,
              child: Text(context.tx('تلاش دوباره', 'Retry'))),
        ]),
      );

  Widget _filters(BuildContext context) {
    Widget chip(String label, bool sel, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: FilterChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: sel,
            onSelected: (_) => onTap(),
            selectedColor: tAccent(context).withValues(alpha: 0.28),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: NxSpace.md, vertical: 4),
        children: <Widget>[
          chip(
              context.tx('همه', 'All'),
              _fee == _FeeFilter.all &&
                  _kind == _KindFilter.all &&
                  _game == null, () {
            setState(() {
              _fee = _FeeFilter.all;
              _kind = _KindFilter.all;
              _game = null;
            });
          }),
          chip(
              context.tx('رایگان', 'Free'),
              _fee == _FeeFilter.free,
              () => setState(() => _fee =
                  _fee == _FeeFilter.free ? _FeeFilter.all : _FeeFilter.free)),
          chip(
              context.tx('ورودی‌دار', 'Entry fee'),
              _fee == _FeeFilter.paid,
              () => setState(() => _fee =
                  _fee == _FeeFilter.paid ? _FeeFilter.all : _FeeFilter.paid)),
          chip(
              context.tx('حذفی', 'Knockout'),
              _kind == _KindFilter.knockout,
              () => setState(() => _kind = _kind == _KindFilter.knockout
                  ? _KindFilter.all
                  : _KindFilter.knockout)),
          chip(
              context.tx('لیگ/گروهی', 'League/groups'),
              _kind == _KindFilter.league,
              () => setState(() => _kind = _kind == _KindFilter.league
                  ? _KindFilter.all
                  : _KindFilter.league)),
          for (final GameInfo g in kGames.where(
              (GameInfo g) => _all.any((Tournament t) => t.game == g.id)))
            chip(context.tx(g.nameFa, g.nameEn), _game == g.id,
                () => setState(() => _game = _game == g.id ? null : g.id)),
        ],
      ),
    );
  }

  Widget _nextMatchBanner(BuildContext context) {
    final TMatch m = _myMatches.firstWhere(
        (TMatch x) => x.status == 'ready_check',
        orElse: () => _myMatches.first);
    final Tournament? t =
        _all.where((Tournament x) => x.id == m.tournamentId).firstOrNull;
    final bool ready = m.status == 'ready_check';
    return Padding(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, 2, NxSpace.md, 6),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tint: (ready ? NxColors.success : tAccent(context))
            .withValues(alpha: 0.14),
        borderColor: (ready ? NxColors.success : tAccent(context))
            .withValues(alpha: 0.7),
        onTap: () =>
            context.push('/tournaments/${m.tournamentId}?match=${m.id}'),
        child: Row(children: <Widget>[
          Icon(ready ? Icons.sports_esports_rounded : Icons.schedule_rounded,
              color: ready ? NxColors.success : tAccent(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      ready
                          ? context.tx('بازی بعدی‌ات آماده است',
                              'Your next match is ready')
                          : context.tx('بازی بعدی من', 'My next match'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(t?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: NxColors.textDim, fontSize: 12)),
                ]),
          ),
          if (ready && m.readyDeadline != null)
            CountdownText(
                to: m.readyDeadline!,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: NxColors.success))
          else if (m.scheduledAt != null &&
              m.scheduledAt!.isAfter(DateTime.now().toUtc()))
            CountdownText(
                to: m.scheduledAt!,
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: tAccent(context))),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }

  Widget _list(BuildContext context, TTab tab) {
    final List<Tournament> items = _forTab(tab);
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(children: <Widget>[
              const SizedBox(height: 80),
              const Icon(Icons.emoji_events_outlined,
                  size: 56, color: NxColors.textDim),
              const SizedBox(height: 10),
              Center(
                child: Text(context.tx('چیزی اینجا نیست', 'Nothing here yet'),
                    style: const TextStyle(color: NxColors.textDim)),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(NxSpace.md, 4, NxSpace.md, 96),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RepaintBoundary(
                    child:
                        TournamentCard(t: items[i], entry: _mine[items[i].id])),
              ),
            ),
    );
  }
}

class TournamentCard extends StatelessWidget {
  const TournamentCard({super.key, required this.t, this.entry});
  final Tournament t;
  final TEntry? entry;

  @override
  Widget build(BuildContext context) {
    final (String st, Color sc) =
        statusLabel(context, t.status, paused: t.paused);
    final (String, DateTime)? next = t.nextMoment;
    final GameInfo? g = gameById(t.game);
    final int pool =
        PrizeSplit.total(PrizeConfig.fromJson(t.prize), t.escrowCoins);
    return GlassPanel(
      blur: false,
      padding: const EdgeInsets.all(14),
      borderColor:
          (t.status == 'live' ? tAccentSecondary(context) : tAccent(context))
              .withValues(alpha: 0.45),
      onTap: () => context.push('/tournaments/${t.id}'),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: <Color>[
                    tAccent(context),
                    tAccentSecondary(context)
                  ]),
                ),
                child: Icon(formatIcon(t.format), color: NxColors.navyDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      Text(
                          '${g == null ? t.game : context.tx(g.nameFa, g.nameEn)} · ${formatName(context, t.format)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NxColors.textDim, fontSize: 12)),
                    ]),
              ),
              NxPill(label: st, color: sc),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              NxPill(
                  label: '${t.capacity}',
                  icon: Icons.groups_rounded,
                  color: NxColors.electricBlue),
              NxPill(
                label: t.isFree
                    ? context.tx('رایگان', 'Free')
                    : '${t.feeCoins > 0 ? '${t.feeCoins}🪙' : ''}${t.feeGems > 0 ? ' ${t.feeGems}💎' : ''}',
                icon: Icons.confirmation_number_rounded,
                color: t.isFree ? NxColors.success : NxColors.gold,
              ),
              if (pool > 0)
                NxPill(
                    label: '$pool',
                    icon: Icons.emoji_events_rounded,
                    color: NxColors.gold),
              if (t.regMode != 'open')
                NxPill(
                    label: regModeName(context, t.regMode),
                    icon: Icons.lock_rounded,
                    color: NxColors.violet),
              if (entry != null && entry!.active)
                NxPill(
                    label: entryStatusName(context, entry!.status),
                    icon: Icons.how_to_reg_rounded,
                    color: NxColors.turquoise),
            ]),
            if (next != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(children: <Widget>[
                const Icon(Icons.timer_outlined,
                    size: 16, color: NxColors.textDim),
                const SizedBox(width: 6),
                Text('${momentLabel(context, next.$1)} ',
                    style:
                        const TextStyle(color: NxColors.textDim, fontSize: 12)),
                CountdownText(
                    to: next.$2,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: tAccent(context),
                        fontSize: 13)),
                const Spacer(),
                Text(fmtWhen(next.$2, withUtc: false),
                    style:
                        const TextStyle(color: NxColors.textDim, fontSize: 11)),
              ]),
            ],
          ]),
    );
  }
}
