import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/online/cloud_profile_sync.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../../games/game_registry.dart';
import '../../../worlds/arcade/online/online_match_page.dart';
import '../data/models.dart';
import '../data/tournament_repository.dart';
import '../domain/bracket.dart';
import '../domain/prize_split.dart';
import 'bracket_view.dart';
import 't_common.dart';

/// Tournament detail: rules, countdowns, prize pool, players, register / code / withdraw, live bracket or
/// league table, my next match with the Ready button, match list and history.
class TournamentDetailPage extends ConsumerStatefulWidget {
  const TournamentDetailPage({super.key, required this.id, this.focusMatch});
  final String id;
  final String? focusMatch;

  @override
  ConsumerState<TournamentDetailPage> createState() =>
      _TournamentDetailPageState();
}

class _TournamentDetailPageState extends ConsumerState<TournamentDetailPage>
    with TClockUser<TournamentDetailPage> {
  Tournament? _t;
  List<TEntry> _entries = <TEntry>[];
  List<TMatch> _matches = <TMatch>[];
  List<StandingRow> _table = <StandingRow>[];
  Map<String, String> _names = <String, String>{};
  bool _loading = true;
  bool _busy = false;
  bool _canManage = false;
  VoidCallback? _unwatch;
  final Set<String> _openedGames = <String>{};

  TournamentRepository get _repo => ref.read(tournamentRepoProvider);
  String? get _me => _repo.uid;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _unwatch?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final Tournament? t = await _repo.get(widget.id);
      if (t == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final List<dynamic> r = await Future.wait<dynamic>(<Future<dynamic>>[
        _repo.entries(t.id),
        _repo.matches(t.id),
        if (t.format.isLeague || t.format == TFormat.groupsKo)
          _repo.standings(t.id)
        else
          Future<List<StandingRow>>.value(<StandingRow>[]),
        _repo.myRole(),
      ]);
      final List<TEntry> entries = r[0] as List<TEntry>;
      final List<TMatch> matches = r[1] as List<TMatch>;
      final ({bool admin, bool organizer}) role =
          r[3] as ({bool admin, bool organizer});
      final Set<String> ids = <String>{
        for (final TEntry e in entries) e.userId,
        for (final TMatch m in matches) ...<String>[
          if (m.p1 != null) m.p1!,
          if (m.p2 != null) m.p2!
        ],
      };
      final Map<String, String> names = <String, String>{
        for (final TEntry e in entries) e.userId: e.username
      };
      final List<String> missing =
          ids.where((String id) => !names.containsKey(id)).toList();
      if (missing.isNotEmpty) names.addAll(await _repo.names(missing));
      bool runner = false;
      if (!role.admin && t.createdBy != _me) {
        try {
          runner =
              (await ref.read(tournamentRepoProvider).logs(t.id))['ok'] == true;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _t = t;
        _entries = entries;
        _matches = matches;
        _table = r[2] as List<StandingRow>;
        _names = names;
        _canManage =
            role.admin || (t.createdBy == _me && role.organizer) || runner;
        _loading = false;
      });
      _unwatch ??= _repo.watchTournament(t.id, () => unawaited(_load()));
      _autoOpenGame();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  TEntry? get _myEntry =>
      _entries.where((TEntry e) => e.userId == _me).firstOrNull;

  List<TMatch> get _myMatches =>
      _matches.where((TMatch m) => m.involves(_me)).toList();

  TMatch? get _myNext {
    final List<TMatch> open =
        _myMatches.where((TMatch m) => !m.isFinal).toList();
    if (open.isEmpty) return null;
    open.sort((TMatch a, TMatch b) {
      int rank(TMatch m) => switch (m.status) {
            'playing' => 0,
            'ready_check' => 1,
            'disputed' => 2,
            'scheduled' => 3,
            _ => 4
          };
      final int c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      return (a.scheduledAt ?? DateTime(2100))
          .compareTo(b.scheduledAt ?? DateTime(2100));
    });
    return open.first;
  }

  void _autoOpenGame() {
    final TMatch? m = _myNext;
    final Tournament? t = _t;
    if (m == null || t == null || m.status != 'playing' || m.gameMatch == null)
      return;
    if (_openedGames.add(m.gameMatch!)) unawaited(_openGame(t, m));
  }

  Future<void> _openGame(Tournament t, TMatch m) async {
    if (m.gameMatch == null) return;
    _openedGames.add(m.gameMatch!);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OnlineMatchPage(
          matchId: m.gameMatch!, gameId: t.game, tournamentMatchId: m.id),
    ));
    unawaited(_load());
  }

  Future<void> _toast(TResult r, {String? okFa, String? okEn}) async {
    if (!mounted) return;
    final bool fa = ref.read(settingsProvider).isFa;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok
          ? (fa ? (okFa ?? 'انجام شد') : (okEn ?? 'Done'))
          : tErrorText(r.error, fa)),
    ));
  }

  Future<void> _register() async {
    final Tournament t = _t!;
    String? code;
    if (t.needsCode) {
      final TextEditingController c = TextEditingController();
      code = await showDialog<String>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(ctx.tx('کد دعوت', 'Invite code')),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 9,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'ABCD2345'),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tx('انصراف', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: Text(ctx.tx('ثبت‌نام', 'Register'))),
          ],
        ),
      );
      c.dispose();
      if (code == null || code.isEmpty) return;
    } else if (!t.isFree) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(ctx.tx('پرداخت ورودیه', 'Pay the entry fee')),
          content: Text(ctx.tx(
              'ورودیه: ${t.feeCoins} سکه${t.feeGems > 0 ? ' و ${t.feeGems} جم' : ''}. تا پایان ثبت‌نام می‌توانی انصراف بدهی و کامل پس بگیری.',
              'Entry: ${t.feeCoins} coins${t.feeGems > 0 ? ' and ${t.feeGems} gems' : ''}. Withdraw before registration closes for a full refund.')),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.tx('انصراف', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.tx('پرداخت و ثبت‌نام', 'Pay & register'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    final TResult r = await _repo.register(t.id, code);
    if (mounted) setState(() => _busy = false);
    await _toast(r,
        okFa: entryStatusName(context, '${r.data['status']}'),
        okEn: entryStatusName(context, '${r.data['status']}'));
    unawaited(ref.read(cloudSyncProvider).refreshWallet());
    unawaited(_load());
  }

  Future<void> _withdraw() async {
    final Tournament t = _t!;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title:
            Text(ctx.tx('انصراف از تورنمنت؟', 'Withdraw from the tournament?')),
        content: Text(t.status == 'registering'
            ? ctx.tx('ورودیه کامل برگشت داده می‌شود.',
                'Your entry fee is refunded in full.')
            : ctx.tx('ثبت‌نام بسته شده؛ ورودیه برگشت داده نمی‌شود.',
                'Registration is closed; the fee is not refunded.')),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('نه', 'No'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tx('انصراف', 'Withdraw')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final TResult r = await _repo.withdraw(t.id);
    await _toast(r);
    unawaited(ref.read(cloudSyncProvider).refreshWallet());
    unawaited(_load());
  }

  Future<void> _ready(TMatch m) async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    final TResult r = await _repo.ready(m.id);
    if (mounted) setState(() => _busy = false);
    if (!r.ok) {
      await _toast(r);
      return;
    }
    if (r.data['status'] == 'playing' &&
        r.data['game_match'] != null &&
        _t != null) {
      final String gm = '${r.data['game_match']}';
      if (_openedGames.add(gm)) {
        await _openGame(
            _t!,
            TMatch(<String, dynamic>{
              'id': m.id,
              'tournament_id': m.tournamentId,
              'bracket': m.bracket,
              'status': 'playing',
              'game_match': gm,
            }));
      }
    } else {
      unawaited(_load());
    }
  }

  Future<void> _dispute(TMatch m) async {
    final TextEditingController c = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('اعتراض به نتیجه', 'Dispute the result')),
        content: TextField(
          controller: c,
          maxLength: 120,
          decoration: InputDecoration(
              hintText: ctx.tx('چه اتفاقی افتاد؟', 'What happened?')),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(ctx.tx('ارسال', 'Send'))),
        ],
      ),
    );
    c.dispose();
    if (reason == null) return;
    await _toast(
        await _repo.dispute(m.id, reason.isEmpty ? 'player_dispute' : reason));
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final Tournament? t = _t;
    if (_loading && t == null) {
      return NxWorldScaffold(
        title: context.tx('تورنمنت', 'TOURNAMENT'),
        palette: WorldPalette.arcade,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (t == null) {
      return NxWorldScaffold(
        title: context.tx('تورنمنت', 'TOURNAMENT'),
        palette: WorldPalette.arcade,
        body: Center(child: Text(context.tx('پیدا نشد', 'Not found'))),
      );
    }
    final bool league = t.format.isLeague || t.format == TFormat.groupsKo;
    final bool elim = !t.format.isLeague;
    final List<(String, Widget)> tabs = <(String, Widget)>[
      (context.tx('خلاصه', 'Overview'), _overview(context, t)),
      if (elim) (context.tx('براکت', 'Bracket'), _bracketTab(context, t)),
      if (league) (context.tx('جدول', 'Table'), _tableTab(context, t)),
      (context.tx('بازی‌ها', 'Matches'), _matchesTab(context, t)),
      (context.tx('بازیکنان', 'Players'), _playersTab(context, t)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: NxWorldScaffold(
        title: t.title.toUpperCase(),
        palette: WorldPalette.arcade,
        actions: <Widget>[
          if (_canManage)
            IconButton(
              tooltip: context.tx('مدیریت', 'Manage'),
              icon: const Icon(Icons.admin_panel_settings_rounded),
              onPressed: () async {
                await context.push('/tournaments/${t.id}/manage');
                unawaited(_load());
              },
            ),
        ],
        body: Column(children: <Widget>[
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: tAccent(context),
            labelColor: tAccent(context),
            unselectedLabelColor: NxColors.textDim,
            dividerColor: Colors.transparent,
            tabs: <Widget>[
              for (final (String l, Widget _) in tabs) Tab(text: l)
            ],
          ),
          Expanded(
              child: TabBarView(children: <Widget>[
            for (final (String _, Widget w) in tabs) w
          ])),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- overview
  Widget _overview(BuildContext context, Tournament t) {
    final (String st, Color sc) =
        statusLabel(context, t.status, paused: t.paused);
    final (String, DateTime)? next = t.nextMoment;
    final GameInfo? g = gameById(t.game);
    final TEntry? me = _myEntry;
    final int approved =
        _entries.where((TEntry e) => e.status == 'approved').length;
    final int waitlist =
        _entries.where((TEntry e) => e.status == 'waitlist').length;
    final TMatch? myNext = _myNext;
    final PrizeConfig pc = PrizeConfig.fromJson(t.prize);
    final PrizeConfig pg = PrizeConfig.fromJson(t.prize, currency: 'gems');
    final int totalC = PrizeSplit.total(pc, t.escrowCoins);
    final int totalG = PrizeSplit.total(pg, t.escrowGems);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding:
            const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96),
        children: <Widget>[
          GlassPanel(
            borderColor: tAccent(context).withValues(alpha: 0.6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t.title,
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.15)),
                  const SizedBox(height: 10),
                  Row(children: <Widget>[
                    Icon(formatIcon(t.format), color: tAccent(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${g == null ? t.game : context.tx(g.nameFa, g.nameEn)} · ${formatName(context, t.format)}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    NxPill(label: st, color: sc),
                  ]),
                  if (t.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(t.description, style: const TextStyle(height: 1.5)),
                  ],
                  const SizedBox(height: 12),
                  if (next != null)
                    Row(children: <Widget>[
                      Text('${momentLabel(context, next.$1)} ',
                          style: const TextStyle(color: NxColors.textDim)),
                      CountdownText(
                          to: next.$2,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: tAccent(context))),
                    ]),
                  if (t.status == 'cancelled' && t.cancelReason != null)
                    Text(
                        '${context.tx('دلیل لغو', 'Reason')}: ${t.cancelReason}',
                        style: const TextStyle(color: NxColors.danger)),
                  if (t.status == 'finished' && t.winner != null)
                    Row(children: <Widget>[
                      const Icon(Icons.emoji_events_rounded,
                          color: NxColors.gold),
                      const SizedBox(width: 6),
                      Text(
                          '${context.tx('قهرمان', 'Champion')}: ${_names[t.winner] ?? '…'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: NxColors.gold)),
                    ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    NxPill(
                        label: '$approved / ${t.capacity}',
                        icon: Icons.groups_rounded),
                    if (waitlist > 0)
                      NxPill(
                          label: '+$waitlist',
                          icon: Icons.hourglass_top_rounded,
                          color: NxColors.violet),
                    NxPill(
                        label: regModeName(context, t.regMode),
                        icon: Icons.how_to_reg_rounded,
                        color: NxColors.turquoise),
                  ]),
                ]),
          ),
          const SizedBox(height: 12),
          if (myNext != null) ...<Widget>[
            _myMatchCard(context, t, myNext),
            const SizedBox(height: 12)
          ],
          _registerPanel(context, t, me),
          const SizedBox(height: 12),
          GlassPanel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    const Icon(Icons.emoji_events_rounded,
                        color: NxColors.gold),
                    const SizedBox(width: 8),
                    Text(context.tx('جوایز', 'Prizes'),
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const Spacer(),
                    if (totalC > 0)
                      NxPill(label: '$totalC 🪙', color: NxColors.gold),
                    if (totalG > 0) ...<Widget>[
                      const SizedBox(width: 6),
                      NxPill(label: '$totalG 💎', color: NxColors.electricBlue)
                    ],
                  ]),
                  const SizedBox(height: 8),
                  if (totalC == 0 && totalG == 0)
                    Text(
                        context.tx('جایزه‌ی سکه‌ای ندارد؛ افتخار و XP!',
                            'No coin prize — glory and XP!'),
                        style: const TextStyle(color: NxColors.textDim))
                  else ...<Widget>[
                    for (int i = 0; i < pc.dist.length; i++)
                      if (pc.dist[i] > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: <Widget>[
                            SizedBox(
                                width: 44,
                                child: Text('#${i + 1}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800))),
                            Expanded(
                                child: Text('${pc.dist[i]}%',
                                    style: const TextStyle(
                                        color: NxColors.textDim))),
                            if (totalC > 0)
                              Text(
                                  '${PrizeSplit.perPlace(totalC, pc.dist)[i]} 🪙'),
                            if (totalG > 0)
                              Text(
                                  '  ${PrizeSplit.perPlace(totalG, pc.dist)[i]} 💎'),
                          ]),
                        ),
                    if (pc.poolPct > 0)
                      Text(
                          context.tx(
                              'شامل ${pc.poolPct}٪ از ورودیه‌ها${pc.feePct > 0 ? ' (کارمزد ${pc.feePct}٪)' : ''}؛ با هر ثبت‌نام بیشتر می‌شود.',
                              'Includes ${pc.poolPct}% of entry fees${pc.feePct > 0 ? ' (${pc.feePct}% fee)' : ''}; grows with every entry.'),
                          style: const TextStyle(
                              color: NxColors.textDim, fontSize: 12)),
                  ],
                ]),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      context.tx('زمان‌بندی (به وقت محلی · UTC)',
                          'Schedule (local · UTC)'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _when(
                      context,
                      context.tx('شروع ثبت‌نام', 'Registration opens'),
                      t.regOpenAt),
                  _when(
                      context,
                      context.tx('پایان ثبت‌نام', 'Registration closes'),
                      t.regCloseAt),
                  _when(context, context.tx('قرعه‌کشی', 'Draw'), t.drawAt),
                  _when(context, context.tx('شروع', 'Start'), t.startAt),
                ]),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.tx('قوانین مسابقه', 'Match rules'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _rule(
                      context,
                      Icons.filter_1_rounded,
                      t.format == TFormat.twoLegs
                          ? context.tx('هر دور رفت و برگشت (مجموع گل‌ها)',
                              'Every tie over two legs (aggregate goals)')
                          : context.tx(
                              'بهترین از: اولیه ${t.cfg('bo_early', 1)} · نیمه‌نهایی ${t.cfg('bo_semi', 1)} · فینال ${t.cfg('bo_final', 1)}',
                              'Best of: early ${t.cfg('bo_early', 1)} · semis ${t.cfg('bo_semi', 1)} · final ${t.cfg('bo_final', 1)}')),
                  _rule(
                      context,
                      Icons.sports_soccer_rounded,
                      context.tx('مساوی در حذفی: گل طلایی (بازی تعیین‌کننده)',
                          'Knockout draws: golden-goal decider game')),
                  if (t.format.isLeague || t.format == TFormat.groupsKo)
                    _rule(
                        context,
                        Icons.table_rows_rounded,
                        context.tx(
                            'امتیاز: برد ${t.cfg('points_win', 3)} · مساوی ${t.cfg('points_draw', 1)}',
                            'Points: win ${t.cfg('points_win', 3)} · draw ${t.cfg('points_draw', 1)}')),
                  if (t.cfgB('third_place', false))
                    _rule(context, Icons.looks_3_rounded,
                        context.tx('بازی رده‌بندی دارد', 'Third-place match')),
                  _rule(
                      context,
                      Icons.how_to_reg_rounded,
                      context.tx(
                          'آمادگی: ${t.cfg('ready_seconds', 300) ~/ 60} دقیقه وقت؛ غیبت = باخت',
                          'Ready check: ${t.cfg('ready_seconds', 300) ~/ 60} min; no-show = walkover')),
                  _rule(
                      context,
                      Icons.wifi_tethering_error_rounded,
                      context.tx('قطعی اینترنت: ۶۰ ثانیه فرصت برگشت',
                          'Disconnect: 60 s to reconnect')),
                  if (t.minLevel > 0 || t.minXp > 0 || t.minRating > 0)
                    _rule(
                        context,
                        Icons.verified_rounded,
                        context.tx(
                            'شرط ورود: سطح ${t.minLevel}+ · XP ${t.minXp}+ · رتبه ${t.minRating}+',
                            'Requirements: level ${t.minLevel}+ · XP ${t.minXp}+ · rating ${t.minRating}+')),
                  if (t.rules.isNotEmpty) ...<Widget>[
                    const Divider(),
                    Text(t.rules, style: const TextStyle(height: 1.5)),
                  ],
                ]),
          ),
        ],
      ),
    );
  }

  Widget _when(BuildContext context, String label, DateTime at) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: NxColors.textDim))),
          Text(fmtWhen(at), style: const TextStyle(fontSize: 12)),
        ]),
      );

  Widget _rule(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 16, color: NxColors.turquoise),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ]),
      );

  Widget _registerPanel(BuildContext context, Tournament t, TEntry? me) {
    final bool active = me != null && me.active;
    Widget body;
    if (active) {
      body = Row(children: <Widget>[
        const Icon(Icons.how_to_reg_rounded, color: NxColors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(entryStatusName(context, me.status),
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: NxColors.success)),
        ),
        if (t.status == 'registering' || t.status == 'closed')
          TextButton(
              onPressed: _busy ? null : _withdraw,
              child: Text(context.tx('انصراف', 'Withdraw'))),
      ]);
    } else if (t.canRegister) {
      body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (me != null && !me.active)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(entryStatusName(context, me.status),
                    style: const TextStyle(color: NxColors.textDim)),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: tAccent(context),
                  minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _register,
              icon: Icon(
                  t.needsCode ? Icons.vpn_key_rounded : Icons.login_rounded),
              label: Text(
                t.needsCode
                    ? context.tx(
                        'ثبت‌نام با کد دعوت', 'Register with invite code')
                    : (t.isFree
                        ? context.tx('ثبت‌نام رایگان', 'Register (free)')
                        : context.tx(
                            'ثبت‌نام · ${t.feeCoins} سکه${t.feeGems > 0 ? ' + ${t.feeGems} جم' : ''}',
                            'Register · ${t.feeCoins} coins${t.feeGems > 0 ? ' + ${t.feeGems} gems' : ''}')),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (t.needsApproval)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    context.tx('ثبت‌نام بعد از تأیید برگزارکننده قطعی می‌شود.',
                        'An organizer approves each registration.'),
                    style:
                        const TextStyle(color: NxColors.textDim, fontSize: 12)),
              ),
          ]);
    } else {
      body = Text(
        t.status == 'scheduled'
            ? context.tx(
                'ثبت‌نام هنوز باز نشده', 'Registration has not opened yet')
            : context.tx('ثبت‌نام بسته است', 'Registration is closed'),
        style: const TextStyle(color: NxColors.textDim),
      );
    }
    return GlassPanel(child: body);
  }

  Widget _myMatchCard(BuildContext context, Tournament t, TMatch m) {
    final String opp = _names[m.p1 == _me ? m.p2 : m.p1] ?? '…';
    final bool iAmP1 = m.p1 == _me;
    final bool meReady = iAmP1 ? m.p1Ready : m.p2Ready;
    final bool oppReady = iAmP1 ? m.p2Ready : m.p1Ready;
    final int lastW = _matches
        .where((TMatch x) => x.bracket == 'W')
        .fold<int>(0, (int a, TMatch x) => x.round > a ? x.round : a);
    final int firstW = _matches
        .where((TMatch x) => x.bracket == 'W')
        .fold<int>(999, (int a, TMatch x) => x.round < a ? x.round : a);
    Widget action;
    switch (m.status) {
      case 'ready_check':
        action = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(children: <Widget>[
                Text(context.tx('وقت آمادگی: ', 'Ready window: '),
                    style: const TextStyle(color: NxColors.textDim)),
                if (m.readyDeadline != null)
                  CountdownText(
                      to: m.readyDeadline!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: NxColors.success)),
                const Spacer(),
                Icon(
                    oppReady
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_empty_rounded,
                    size: 18,
                    color: oppReady ? NxColors.success : NxColors.textDim),
                const SizedBox(width: 4),
                Text(
                    oppReady
                        ? context.tx('حریف آماده', 'Opponent ready')
                        : context.tx('منتظر حریف', 'Waiting'),
                    style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      meReady ? NxColors.navySoft : NxColors.success,
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: meReady || _busy ? null : () => _ready(m),
                icon: Icon(meReady ? Icons.check_rounded : Icons.bolt_rounded),
                label: Text(
                    meReady
                        ? context.tx('آماده‌ای — منتظر حریف',
                            'Ready — waiting for opponent')
                        : context.tx('آماده‌ام!', 'READY!'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ]);
      case 'playing':
        action = FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: tAccentSecondary(context),
              minimumSize: const Size.fromHeight(52)),
          onPressed: () => _openGame(t, m),
          icon: const Icon(Icons.sports_esports_rounded),
          label: Text(context.tx('ورود به بازی', 'Enter the match'),
              style: const TextStyle(fontSize: 16)),
        );
      case 'disputed':
        action = Text(
            context.tx('نتیجه مورد اختلاف است؛ برگزارکننده بررسی می‌کند.',
                'The result is disputed; an organizer will decide.'),
            style: const TextStyle(color: NxColors.gold));
      default:
        action = Row(children: <Widget>[
          Text(context.tx('شروع تا ', 'Starts in '),
              style: const TextStyle(color: NxColors.textDim)),
          if (m.scheduledAt != null && t.status == 'live')
            CountdownText(
                to: m.scheduledAt!,
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: tAccent(context)))
          else if (t.nextMoment != null)
            CountdownText(
                to: t.startAt,
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: tAccent(context))),
        ]);
    }
    return GlassPanel(
      tint: NxColors.success.withValues(alpha: 0.08),
      borderColor:
          (m.status == 'ready_check' ? NxColors.success : tAccent(context))
              .withValues(alpha: 0.8),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: <Widget>[
              Text(context.tx('بازی بعدی من', 'My next match'),
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: tAccent(context))),
              const Spacer(),
              Text(roundName(context, m, lastW, firstW),
                  style:
                      const TextStyle(color: NxColors.textDim, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            Row(children: <Widget>[
              TAvatar(
                  name: _names[_me] ?? 'Me',
                  color: NxColors.turquoise,
                  size: 34),
              const SizedBox(width: 8),
              Text(context.tx('تو', 'You'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              Text(
                  m.bestOf > 1
                      ? (m.aggregate
                          ? context.tx('دو بازی', '2 legs')
                          : 'Bo${m.bestOf}')
                      : 'Bo1',
                  style: const TextStyle(color: NxColors.textDim)),
              if (m.games > 0)
                Text('  ${iAmP1 ? m.w1 : m.w2} - ${iAmP1 ? m.w2 : m.w1}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              Flexible(
                  child: Text(opp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900))),
              const SizedBox(width: 8),
              TAvatar(name: opp, size: 34),
            ]),
            const SizedBox(height: 12),
            action,
            if (m.status == 'playing' || m.status == 'ready_check')
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => _dispute(m),
                  icon: const Icon(Icons.flag_rounded, size: 16),
                  label: Text(context.tx('گزارش مشکل', 'Report a problem'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
          ]),
    );
  }

  // ---------------------------------------------------------------- bracket / table / matches / players
  Widget _bracketTab(BuildContext context, Tournament t) {
    final List<TMatch> elim = _matches
        .where((TMatch m) =>
            m.isElim && (t.format != TFormat.groupsKo || m.stage == 'ko'))
        .toList();
    return BracketView(
        matches: elim,
        names: _names,
        me: _me,
        onTap: (TMatch m) => _matchSheet(context, t, m));
  }

  Widget _tableTab(BuildContext context, Tournament t) {
    if (_table.isEmpty) {
      return Center(
          child: Text(
              context.tx('جدول بعد از قرعه‌کشی ساخته می‌شود',
                  'The table appears after the draw'),
              style: const TextStyle(color: NxColors.textDim)));
    }
    final List<int?> groups = _table
        .map((StandingRow r) => r.groupNo)
        .toSet()
        .toList()
      ..sort((int? a, int? b) => (a ?? 0).compareTo(b ?? 0));
    final int adv = t.format == TFormat.groupsKo ? t.cfg('advance', 2) : 0;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96),
      children: <Widget>[
        for (final int? g in groups) ...<Widget>[
          if (g != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                  context.tx('گروه ${String.fromCharCode(64 + g)}',
                      'Group ${String.fromCharCode(64 + g)}'),
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: tAccent(context))),
            ),
          GlassPanel(
            blur: false,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(children: <Widget>[
              _tableRow(context, null, header: true),
              for (final StandingRow r
                  in _table.where((StandingRow x) => x.groupNo == g))
                _tableRow(context, r, qualifies: adv > 0 && r.rank <= adv),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _tableRow(BuildContext context, StandingRow? r,
      {bool header = false, bool qualifies = false}) {
    TextStyle st(bool bold) => TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
        color: header
            ? NxColors.textDim
            : (r?.userId == _me ? NxColors.turquoise : NxColors.iceWhite));
    Widget c(String s, {double w = 28, bool bold = false}) => SizedBox(
        width: w, child: Text(s, textAlign: TextAlign.center, style: st(bold)));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: header
            ? const Border(bottom: BorderSide(color: NxColors.glassBorder))
            : null,
        color: qualifies ? NxColors.success.withValues(alpha: 0.08) : null,
      ),
      child: Row(children: <Widget>[
        c(header ? '#' : '${r!.rank}', w: 24, bold: true),
        Expanded(
            child: Text(header ? context.tx('بازیکن', 'Player') : r!.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st(!header))),
        c(header ? context.tx('ب', 'P') : '${r!.played}'),
        c(header ? context.tx('بر', 'W') : '${r!.won}'),
        c(header ? context.tx('م', 'D') : '${r!.drawn}'),
        c(header ? context.tx('با', 'L') : '${r!.lost}'),
        c(header ? context.tx('تفاضل', 'GD') : '${r!.gf - r.ga}', w: 38),
        c(header ? context.tx('امتیاز', 'Pts') : '${r!.pts}',
            w: 40, bold: true),
      ]),
    );
  }

  Widget _matchesTab(BuildContext context, Tournament t) {
    if (_matches.isEmpty) {
      return Center(
          child: Text(context.tx('هنوز بازی‌ای ساخته نشده', 'No matches yet'),
              style: const TextStyle(color: NxColors.textDim)));
    }
    final List<TMatch> sorted = List<TMatch>.of(_matches)
      ..sort((TMatch a, TMatch b) {
        int rank(TMatch m) => switch (m.status) {
              'playing' => 0,
              'ready_check' => 1,
              'disputed' => 2,
              'scheduled' => 3,
              'pending' => 4,
              _ => 5
            };
        final int c = rank(a).compareTo(rank(b));
        if (c != 0) return c;
        final int r = a.round.compareTo(b.round);
        return r != 0 ? r : a.idx.compareTo(b.idx);
      });
    final int lastW = _matches
        .where((TMatch x) => x.bracket == 'W')
        .fold<int>(0, (int a, TMatch x) => x.round > a ? x.round : a);
    final int firstW = _matches
        .where((TMatch x) => x.bracket == 'W')
        .fold<int>(999, (int a, TMatch x) => x.round < a ? x.round : a);
    return ListView.builder(
      padding:
          const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96),
      itemCount: sorted.length,
      itemBuilder: (BuildContext context, int i) {
        final TMatch m = sorted[i];
        final (int s1, int s2) = m.shownScore;
        final (String st, Color sc) = _matchStatus(context, m);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            blur: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderColor: m.involves(_me) ? NxColors.turquoise : null,
            onTap: () => _matchSheet(context, t, m),
            child: Row(children: <Widget>[
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(roundName(context, m, lastW, firstW),
                          style: const TextStyle(
                              color: NxColors.textDim, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(
                          '${_pname(m.p1, m.p1Set)}  vs  ${_pname(m.p2, m.p2Set)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
              ),
              if (m.isFinal || m.games > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$s1 - $s2',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              NxPill(label: st, color: sc),
            ]),
          ),
        );
      },
    );
  }

  String _pname(String? uid, bool set) =>
      uid == null ? (set ? 'BYE' : '—') : (_names[uid] ?? '…');

  (String, Color) _matchStatus(BuildContext context, TMatch m) =>
      switch (m.status) {
        'pending' => (context.tx('منتظر', 'Waiting'), NxColors.textDim),
        'scheduled' => (
            context.tx('زمان‌بندی', 'Scheduled'),
            NxColors.electricBlue
          ),
        'ready_check' => (
            context.tx('آمادگی', 'Ready check'),
            NxColors.success
          ),
        'playing' => (
            context.tx('در حال بازی', 'Playing'),
            tAccentSecondary(context)
          ),
        'done' => (
            m.isDraw ? context.tx('مساوی', 'Draw') : context.tx('تمام', 'Done'),
            NxColors.gold
          ),
        'walkover' => (context.tx('واگذار', 'Walkover'), NxColors.violet),
        'bye' => ('BYE', NxColors.textDim),
        'disputed' => (context.tx('اختلاف', 'Disputed'), NxColors.danger),
        'void' => (context.tx('باطل', 'Void'), NxColors.textDim),
        'skipped' => (context.tx('لازم نشد', 'Not needed'), NxColors.textDim),
        _ => (m.status, NxColors.textDim),
      };

  void _matchSheet(BuildContext context, Tournament t, TMatch m) {
    final (int s1, int s2) = m.shownScore;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                  '${_pname(m.p1, m.p1Set)}  ${m.isFinal || m.games > 0 ? '$s1 - $s2' : 'vs'}  ${_pname(m.p2, m.p2Set)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                  'Bo${m.bestOf}${m.aggregate ? ' · ${ctx.tx('مجموع گل', 'aggregate')}' : ''} · ${ctx.tx('بازی‌ها', 'games')} ${m.games} · ${ctx.tx('گل', 'goals')} ${m.g1}-${m.g2}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NxColors.textDim)),
              if (m.scheduledAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(fmtWhen(m.scheduledAt!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                ),
              if (m.resultNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(m.resultNote!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: NxColors.textDim, fontSize: 12)),
                ),
              if (m.involves(_me) && !m.isFinal) ...<Widget>[
                const SizedBox(height: 14),
                _myMatchCard(ctx, t, m),
              ],
            ]),
      ),
    );
  }

  Widget _playersTab(BuildContext context, Tournament t) {
    final List<TEntry> list = _entries
        .where((TEntry e) => e.status == 'approved' || e.status == 'waitlist')
        .toList()
      ..sort((TEntry a, TEntry b) {
        if (a.place != null || b.place != null)
          return (a.place ?? 999).compareTo(b.place ?? 999);
        if (a.seed != null || b.seed != null)
          return (a.seed ?? 999).compareTo(b.seed ?? 999);
        return (a.createdAt ?? DateTime(2000))
            .compareTo(b.createdAt ?? DateTime(2000));
      });
    if (list.isEmpty) {
      return Center(
          child: Text(
              context.tx('هنوز کسی ثبت‌نام نکرده', 'Nobody has registered yet'),
              style: const TextStyle(color: NxColors.textDim)));
    }
    return ListView.builder(
      padding:
          const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96),
      itemCount: list.length,
      itemBuilder: (BuildContext context, int i) {
        final TEntry e = list[i];
        return ListTile(
          dense: true,
          leading: TAvatar(
              name: e.username,
              color: e.userId == _me ? NxColors.turquoise : tAccent(context)),
          title: Text(e.username,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${e.seed != null ? '${context.tx('سید', 'Seed')} ${e.seed} · ' : ''}${context.tx('رتبه', 'Rating')} ${e.rating}${e.groupNo != null ? ' · ${context.tx('گروه', 'Group')} ${String.fromCharCode(64 + e.groupNo!)}' : ''}',
              style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
          trailing: e.place != null
              ? NxPill(
                  label: '#${e.place}',
                  color: e.place == 1 ? NxColors.gold : NxColors.electricBlue)
              : (e.status == 'waitlist'
                  ? NxPill(
                      label: entryStatusName(context, e.status),
                      color: NxColors.violet)
                  : null),
        );
      },
    );
  }
}
