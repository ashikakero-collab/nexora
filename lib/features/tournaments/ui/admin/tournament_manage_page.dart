import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../../core/theme/nx_theme.dart';
import '../../../../core/widgets/nx_widgets.dart';
import '../../data/models.dart';
import '../../data/tournament_repository.dart';
import '../../domain/bracket.dart';
import '../t_common.dart';

/// Organizer panel: controls (publish / draw / start / pause / cancel / finish), approval queue, players
/// and seeds, invite codes, manual match tools (result / correction / replay / edit / add for custom), logs, staff.
/// The UI only hides; every action is role-checked by the RPCs in Postgres.
class TournamentManagePage extends ConsumerStatefulWidget {
  const TournamentManagePage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<TournamentManagePage> createState() =>
      _TournamentManagePageState();
}

class _TournamentManagePageState extends ConsumerState<TournamentManagePage>
    with TClockUser<TournamentManagePage> {
  Tournament? _t;
  List<TEntry> _entries = <TEntry>[];
  List<TMatch> _matches = <TMatch>[];
  List<TCode> _codes = <TCode>[];
  Map<String, dynamic> _logs = <String, dynamic>{};
  Map<String, String> _names = <String, String>{};
  bool _admin = false;
  bool _loading = true;
  bool _busy = false;
  VoidCallback? _unwatch;

  TournamentRepository get _repo => ref.read(tournamentRepoProvider);

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
        _repo.codes(t.id),
        _repo.logs(t.id),
        _repo.myRole(),
      ]);
      final List<TEntry> entries = r[0] as List<TEntry>;
      final List<TMatch> matches = r[1] as List<TMatch>;
      final Map<String, String> names = <String, String>{
        for (final TEntry e in entries) e.userId: e.username
      };
      if (!mounted) return;
      setState(() {
        _t = t;
        _entries = entries;
        _matches = matches;
        _codes = r[2] as List<TCode>;
        _logs = r[3] as Map<String, dynamic>;
        _admin = (r[4] as ({bool admin, bool organizer})).admin;
        _names = names;
        _loading = false;
      });
      _unwatch ??= _repo.watchTournament(t.id, () => unawaited(_load()));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<TResult> Function() f,
      {String? okFa, String? okEn}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final TResult r = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    final bool fa = ref.read(settingsProvider).isFa;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok
          ? (fa ? (okFa ?? 'انجام شد') : (okEn ?? 'Done'))
          : tErrorText(r.error, fa)),
    ));
    unawaited(_load());
  }

  Future<bool> _confirm(String title, String body,
      {bool danger = false}) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('نه', 'No'))),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: NxColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tx('بله', 'Yes')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _ask(String title, {String hint = ''}) async {
    final TextEditingController c = TextEditingController();
    final String? v = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(hintText: hint)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(ctx.tx('تأیید', 'OK'))),
        ],
      ),
    );
    c.dispose();
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final Tournament? t = _t;
    if (t == null) {
      return NxWorldScaffold(
        title: context.tx('مدیریت', 'MANAGE'),
        palette: WorldPalette.arcade,
        showWallet: false,
        body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Text(context.tx('دسترسی نداری', 'No access'))),
      );
    }
    final int pending =
        _entries.where((TEntry e) => e.status == 'pending').length;
    final int disputes =
        _matches.where((TMatch m) => m.status == 'disputed').length;
    final List<(String, Widget)> tabs = <(String, Widget)>[
      (context.tx('کنترل', 'Control'), _controlTab(context, t)),
      (
        context.tx('تأیید${pending > 0 ? ' ($pending)' : ''}',
            'Approvals${pending > 0 ? ' ($pending)' : ''}'),
        _approvalsTab(context, t)
      ),
      (context.tx('بازیکنان', 'Players'), _playersTab(context, t)),
      (context.tx('کدها', 'Codes'), _codesTab(context, t)),
      (
        context.tx('بازی‌ها${disputes > 0 ? ' ⚠$disputes' : ''}',
            'Matches${disputes > 0 ? ' ⚠$disputes' : ''}'),
        _matchesTab(context, t)
      ),
      (context.tx('گزارش‌ها', 'Logs'), _logsTab(context, t)),
      if (_admin) (context.tx('نقش‌ها', 'Staff'), _staffTab(context, t)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: NxWorldScaffold(
        title: context.tx('مدیریت · ${t.title}', 'MANAGE · ${t.title}'),
        palette: WorldPalette.arcade,
        showWallet: false,
        actions: <Widget>[
          IconButton(
            tooltip: context.tx('صفحه‌ی تورنمنت', 'Tournament page'),
            onPressed: () => context.push('/tournaments/${t.id}'),
            icon: const Icon(Icons.visibility_rounded),
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
          if (_busy) LinearProgressIndicator(color: tAccent(context)),
          Expanded(
              child: TabBarView(children: <Widget>[
            for (final (String _, Widget w) in tabs) w
          ])),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ control
  Widget _controlTab(BuildContext context, Tournament t) {
    final (String st, Color sc) =
        statusLabel(context, t.status, paused: t.paused);
    final (String, DateTime)? next = t.nextMoment;
    Widget act(IconData icon, String label, VoidCallback? onTap,
            {Color? color}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: color ?? tAccent(context),
                minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : onTap,
            icon: Icon(icon),
            label: Text(label),
          ),
        );
    final bool preDraw =
        <String>['scheduled', 'registering', 'closed'].contains(t.status);
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: <Widget>[
        GlassPanel(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                      child: Text(t.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18))),
                  NxPill(label: st, color: sc),
                ]),
                const SizedBox(height: 8),
                if (next != null)
                  Row(children: <Widget>[
                    Text('${momentLabel(context, next.$1)} ',
                        style: const TextStyle(color: NxColors.textDim)),
                    CountdownText(
                        to: next.$2,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: tAccent(context))),
                  ]),
                Text(
                    '${context.tx('امانت', 'Escrow')}: ${t.escrowCoins}🪙 ${t.escrowGems}💎 · ${context.tx('پرداخت شد', 'paid out')}: ${t.paidOut ? '✓' : '—'}',
                    style:
                        const TextStyle(color: NxColors.textDim, fontSize: 12)),
              ]),
        ),
        const SizedBox(height: 12),
        if (t.status == 'draft')
          act(Icons.rocket_launch_rounded, context.tx('انتشار', 'Publish'),
              () => _run(() => _repo.admin(t.id, 'publish'))),
        if (!t.isOver)
          act(Icons.edit_rounded,
              context.tx('ویرایش جزئیات و زمان‌ها', 'Edit details & times'),
              () async {
            await context.push('/tournaments/${t.id}/edit');
            unawaited(_load());
          }, color: tAccentSecondary(context)),
        if (t.status == 'scheduled')
          act(
              Icons.lock_open_rounded,
              context.tx('باز کردن ثبت‌نام الان', 'Open registration now'),
              () => _run(() => _repo.admin(t.id, 'open_reg'))),
        if (t.status == 'registering')
          act(
              Icons.lock_rounded,
              context.tx('بستن ثبت‌نام الان', 'Close registration now'),
              () => _run(() => _repo.admin(t.id, 'close_reg'))),
        if (t.status == 'registering' || t.status == 'closed')
          act(Icons.shuffle_rounded, context.tx('قرعه‌کشی الان', 'Draw now'),
              () async {
            if (await _confirm(
                context.tx('قرعه‌کشی؟', 'Draw now?'),
                context.tx('ثبت‌نام بسته می‌شود و براکت ساخته می‌شود.',
                    'Registration closes and the bracket is generated.'))) {
              await _run(() => _repo.admin(t.id, 'draw'));
            }
          }),
        if (t.status == 'drawn')
          act(Icons.refresh_rounded, context.tx('قرعه‌کشی دوباره', 'Redraw'),
              () async {
            if (await _confirm(
                context.tx('قرعه‌ی دوباره؟', 'Redraw?'),
                context.tx('براکت فعلی پاک می‌شود.',
                    'The current bracket is discarded.'))) {
              await _run(() => _repo.admin(t.id, 'redraw'));
            }
          }, color: tAccentSecondary(context)),
        if (preDraw || t.status == 'drawn')
          act(Icons.play_arrow_rounded, context.tx('شروع الان', 'Start now'),
              () async {
            if (await _confirm(
                context.tx('شروع تورنمنت؟', 'Start the tournament?'),
                context.tx('اگر قرعه انجام نشده، اول قرعه‌کشی می‌شود.',
                    'If not drawn yet, the draw runs first.'))) {
              await _run(() => _repo.admin(t.id, 'start'));
            }
          }, color: NxColors.success),
        if (!t.isOver && t.status != 'draft')
          act(
              t.paused ? Icons.play_circle_rounded : Icons.pause_circle_rounded,
              t.paused
                  ? context.tx('ادامه', 'Resume')
                  : context.tx('توقف موقت', 'Pause'),
              () =>
                  _run(() => _repo.admin(t.id, t.paused ? 'resume' : 'pause')),
              color: tAccent(context)),
        if (t.status == 'live')
          act(
              Icons.flag_rounded,
              context.tx('پایان دادن (بازی‌های باز باطل)',
                  'Finish now (void open matches)'), () async {
            if (await _confirm(
                context.tx('پایان تورنمنت؟', 'Finish the tournament?'),
                context.tx(
                    'بازی‌های باز باطل می‌شوند و جوایز طبق جدول فعلی پرداخت می‌شوند.',
                    'Open matches are voided and prizes are paid from the current standings.'),
                danger: true)) {
              await _run(() => _repo.admin(t.id, 'finish'));
            }
          }, color: tAccentSecondary(context)),
        if (!t.isOver)
          act(Icons.cancel_rounded,
              context.tx('لغو و بازپرداخت کامل', 'Cancel & refund everyone'),
              () async {
            final String? reason =
                await _ask(context.tx('دلیل لغو', 'Reason for cancelling'));
            if (reason == null) return;
            await _run(() => _repo.admin(t.id, 'cancel', reason));
          }, color: NxColors.danger),
        if (t.status == 'draft')
          act(Icons.delete_forever_rounded,
              context.tx('حذف پیش‌نویس', 'Delete draft'), () async {
            if (await _confirm(context.tx('حذف شود؟', 'Delete?'), t.title,
                danger: true)) {
              final TResult r = await _repo.admin(t.id, 'delete');
              if (r.ok && mounted) context.pop();
            }
          }, color: NxColors.danger),
      ],
    );
  }

  // ---------------------------------------------------------------- approvals
  Widget _approvalsTab(BuildContext context, Tournament t) {
    final List<TEntry> queue = _entries
        .where((TEntry e) => e.status == 'pending' || e.status == 'waitlist')
        .toList();
    if (queue.isEmpty) {
      return Center(
          child: Text(context.tx('کسی در صف نیست', 'Nobody is waiting'),
              style: const TextStyle(color: NxColors.textDim)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(NxSpace.md),
      itemCount: queue.length,
      itemBuilder: (BuildContext context, int i) {
        final TEntry e = queue[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            blur: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: <Widget>[
              TAvatar(name: e.username),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(e.username,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                          '${entryStatusName(context, e.status)} · ${context.tx('رتبه', 'rating')} ${e.rating}'
                          '${e.paidCoins > 0 ? ' · ${e.paidCoins}🪙' : ''}',
                          style: const TextStyle(
                              color: NxColors.textDim, fontSize: 12)),
                    ]),
              ),
              IconButton(
                tooltip: context.tx('رد', 'Reject'),
                icon: const Icon(Icons.close_rounded, color: NxColors.danger),
                onPressed: () async {
                  final String? note = await _ask(
                      context.tx('دلیل (اختیاری)', 'Reason (optional)'));
                  if (note == null) return;
                  await _run(() => _repo.decide(t.id, e.userId, false, note));
                },
              ),
              IconButton(
                tooltip: context.tx('تأیید', 'Approve'),
                icon: const Icon(Icons.check_rounded, color: NxColors.success),
                onPressed: () => _run(() => _repo.decide(t.id, e.userId, true)),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ players
  Widget _playersTab(BuildContext context, Tournament t) {
    final List<TEntry> list = _entries
        .where((TEntry e) => e.status == 'approved')
        .toList()
      ..sort((TEntry a, TEntry b) => (a.seed ?? 999).compareTo(b.seed ?? 999));
    final bool preDraw = <String>['draft', 'scheduled', 'registering', 'closed']
        .contains(t.status);
    return ListView.builder(
      padding: const EdgeInsets.all(NxSpace.md),
      itemCount: list.length + 1,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                '${list.length} / ${t.capacity} ${context.tx('تأیید شده', 'approved')}'
                '${t.seeding == 'manual' && preDraw ? ' · ${context.tx('سید دستی: روی بازیکن بزن', 'manual seeding: tap a player')}' : ''}',
                style: const TextStyle(color: NxColors.textDim)),
          );
        }
        final TEntry e = list[i - 1];
        return ListTile(
          dense: true,
          leading: TAvatar(name: e.username),
          title: Text(e.username,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${e.seed != null ? '${context.tx('سید', 'Seed')} ${e.seed} · ' : ''}${context.tx('رتبه', 'Rating')} ${e.rating}',
              style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
          onTap: preDraw
              ? () async {
                  final String? v = await _ask(
                      context.tx('سید (۱ = بهترین)', 'Seed (1 = best)'),
                      hint: '1');
                  final int? s = int.tryParse(v ?? '');
                  if (s != null)
                    await _run(() => _repo.setSeed(t.id, e.userId, s));
                }
              : null,
          trailing: preDraw
              ? IconButton(
                  icon: const Icon(Icons.person_remove_rounded,
                      color: NxColors.danger),
                  onPressed: () async {
                    final String? note = await _ask(context.tx(
                        'حذف ${e.username}؟ دلیل:',
                        'Remove ${e.username}? Reason:'));
                    if (note == null) return;
                    await _run(() => _repo.removeEntry(t.id, e.userId, note));
                  },
                )
              : (e.place != null
                  ? NxPill(label: '#${e.place}', color: NxColors.gold)
                  : null),
        );
      },
    );
  }

  // -------------------------------------------------------------------- codes
  Widget _codesTab(BuildContext context, Tournament t) {
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: <Widget>[
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: tAccent(context),
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy || t.isOver ? null : () => _newCodes(t),
          icon: const Icon(Icons.vpn_key_rounded),
          label: Text(context.tx('ساخت کد دعوت', 'Create invite codes')),
        ),
        const SizedBox(height: 12),
        for (final TCode c in _codes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassPanel(
              blur: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              borderColor:
                  c.usable ? NxColors.success.withValues(alpha: 0.6) : null,
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SelectableText(c.code,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 2,
                                decoration: c.revoked
                                    ? TextDecoration.lineThrough
                                    : null)),
                        Text(
                            '${c.uses}/${c.maxUses}${c.expiresAt != null ? ' · ${context.tx('تا', 'until')} ${fmtWhen(c.expiresAt!, withUtc: false)}' : ''}'
                            '${c.requiresApproval ? ' · ${context.tx('با تأیید', 'needs approval')}' : ''}${c.revoked ? ' · ${context.tx('باطل', 'revoked')}' : ''}',
                            style: const TextStyle(
                                color: NxColors.textDim, fontSize: 12)),
                      ]),
                ),
                IconButton(
                  tooltip: context.tx('کپی لینک', 'Copy link'),
                  icon: const Icon(Icons.link_rounded),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: 'nexora://t/${c.code}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('nexora://t/${c.code}')));
                  },
                ),
                if (!c.revoked)
                  IconButton(
                    tooltip: context.tx('باطل کردن', 'Revoke'),
                    icon:
                        const Icon(Icons.block_rounded, color: NxColors.danger),
                    onPressed: () => _run(() => _repo.revokeCode(c.id)),
                  ),
              ]),
            ),
          ),
      ],
    );
  }

  Future<void> _newCodes(Tournament t) async {
    int count = 1;
    int uses = 1;
    int days = 7;
    bool approval = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) {
          Widget row(
                  String label, int v, int min, int max, ValueChanged<int> f) =>
              Row(children: <Widget>[
                Expanded(child: Text(label)),
                IconButton(
                    onPressed: v > min ? () => set(() => f(v - 1)) : null,
                    icon: const Icon(Icons.remove_rounded)),
                Text('$v', style: const TextStyle(fontWeight: FontWeight.w900)),
                IconButton(
                    onPressed: v < max ? () => set(() => f(v + 1)) : null,
                    icon: const Icon(Icons.add_rounded)),
              ]);
          return AlertDialog(
            title: Text(ctx.tx('کد دعوت جدید', 'New invite codes')),
            content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              row(ctx.tx('تعداد', 'Count'), count, 1, 50, (int v) => count = v),
              row(ctx.tx('دفعات استفاده', 'Max uses'), uses, 1, 1000,
                  (int v) => uses = v),
              row(ctx.tx('اعتبار (روز)', 'Valid (days)'), days, 1, 365,
                  (int v) => days = v),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: approval,
                title: Text(ctx.tx('نیاز به تأیید', 'Requires approval')),
                onChanged: (bool v) => set(() => approval = v),
              ),
            ]),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.tx('انصراف', 'Cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tx('ساخت', 'Create'))),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.createCodes(t.id,
        maxUses: uses,
        expiresAt: DateTime.now().add(Duration(days: days)),
        requiresApproval: approval,
        count: count));
  }

  // ------------------------------------------------------------------ matches
  Widget _matchesTab(BuildContext context, Tournament t) {
    final List<TMatch> list = List<TMatch>.of(_matches)
      ..sort((TMatch a, TMatch b) {
        int rank(TMatch m) => switch (m.status) {
              'disputed' => 0,
              'playing' => 1,
              'ready_check' => 2,
              'scheduled' => 3,
              'pending' => 4,
              _ => 5
            };
        final int c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.round.compareTo(b.round);
      });
    final int lastW = _matches
        .where((TMatch x) => x.bracket == 'W')
        .fold<int>(0, (int a, TMatch x) => x.round > a ? x.round : a);
    final int firstW = _matches
        .where((TMatch x) => x.bracket == 'W')
        .fold<int>(999, (int a, TMatch x) => x.round < a ? x.round : a);
    return ListView.builder(
      padding: const EdgeInsets.all(NxSpace.md),
      itemCount: list.length + (t.format == TFormat.custom ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (t.format == TFormat.custom && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: tAccent(context)),
              onPressed: t.status == 'drawn' || t.status == 'live'
                  ? () => _addCustomMatch(t)
                  : null,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tx(
                  'افزودن بازی (براکت دستی)', 'Add match (custom bracket)')),
            ),
          );
        }
        final TMatch m = list[i - (t.format == TFormat.custom ? 1 : 0)];
        final (int s1, int s2) = m.shownScore;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            blur: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            borderColor: m.status == 'disputed' ? NxColors.danger : null,
            onTap: () => _matchTools(t, m),
            child: Row(children: <Widget>[
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                          '${roundName(context, m, lastW, firstW)} · ${m.status}${m.resultNote != null ? ' · ${m.resultNote}' : ''}',
                          style: const TextStyle(
                              color: NxColors.textDim, fontSize: 11)),
                      Text(
                          '${_names[m.p1] ?? (m.p1Set ? 'BYE' : '—')}  vs  ${_names[m.p2] ?? (m.p2Set ? 'BYE' : '—')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
              ),
              if (m.isFinal || m.games > 0)
                Text('$s1 - $s2',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              const Icon(Icons.more_vert_rounded),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _matchTools(Tournament t, TMatch m) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (m.p1 != null &&
              m.p2 != null &&
              m.status != 'bye' &&
              m.status != 'skipped')
            ListTile(
              leading: Icon(Icons.gavel_rounded, color: tAccent(context)),
              title: Text(m.isFinal
                  ? ctx.tx('اصلاح نتیجه', 'Correct the result')
                  : ctx.tx('ثبت نتیجه', 'Set the result')),
              onTap: () => Navigator.pop(ctx, 'result'),
            ),
          if (<String>['disputed', 'playing', 'ready_check', 'scheduled']
              .contains(m.status))
            ListTile(
              leading: const Icon(Icons.replay_rounded,
                  color: NxColors.electricBlue),
              title: Text(ctx.tx('بازی دوباره (بازی فعلی باطل)',
                  'Replay (void the current game)')),
              onTap: () => Navigator.pop(ctx, 'replay'),
            ),
          if (<String>['pending', 'scheduled', 'ready_check']
                  .contains(m.status) &&
              m.games == 0)
            ListTile(
              leading:
                  const Icon(Icons.edit_rounded, color: NxColors.turquoise),
              title: Text(
                  ctx.tx('تغییر بازیکن/زمان/Bo', 'Edit players / time / Bo')),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          if (t.format == TFormat.custom &&
              m.games == 0 &&
              <String>['pending', 'scheduled', 'ready_check']
                  .contains(m.status))
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: NxColors.danger),
              title: Text(ctx.tx('حذف بازی', 'Delete match')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'result':
        await _resultDialog(t, m);
      case 'replay':
        await _run(
            () => _repo.adminMatch(m.id, 'replay', const <String, dynamic>{}));
      case 'edit':
        await _editMatch(t, m);
      case 'delete':
        await _run(
            () => _repo.adminMatch(m.id, 'delete', const <String, dynamic>{}));
    }
  }

  Future<void> _resultDialog(Tournament t, TMatch m) async {
    String? winner = m.winner ?? m.p1;
    bool draw = false;
    final TextEditingController g1 = TextEditingController(text: '${m.g1}');
    final TextEditingController g2 = TextEditingController(text: '${m.g2}');
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: Text(ctx.tx('نتیجه‌ی دستی', 'Manual result')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              RadioListTile<String?>(
                value: m.p1,
                groupValue: draw ? null : winner,
                title: Text(_names[m.p1] ?? 'P1'),
                onChanged: (String? v) => set(() {
                  draw = false;
                  winner = v;
                }),
              ),
              RadioListTile<String?>(
                value: m.p2,
                groupValue: draw ? null : winner,
                title: Text(_names[m.p2] ?? 'P2'),
                onChanged: (String? v) => set(() {
                  draw = false;
                  winner = v;
                }),
              ),
              if (!m.isElim)
                CheckboxListTile(
                  value: draw,
                  title: Text(ctx.tx('مساوی', 'Draw')),
                  onChanged: (bool? v) => set(() => draw = v ?? false),
                ),
              Row(children: <Widget>[
                Expanded(
                    child: TextField(
                        controller: g1,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'G1'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: g2,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'G2'))),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: note,
                  decoration: InputDecoration(
                      labelText:
                          ctx.tx('یادداشت (در لاگ)', 'Note (audit log)'))),
            ]),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.tx('انصراف', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.tx('ثبت', 'Save'))),
          ],
        ),
      ),
    );
    final Map<String, dynamic> p = <String, dynamic>{
      'winner': draw ? null : winner,
      'draw': draw,
      'g1': int.tryParse(g1.text) ?? m.g1,
      'g2': int.tryParse(g2.text) ?? m.g2,
      'w1': draw
          ? m.w1
          : (winner == m.p1 ? (m.w1 > m.w2 ? m.w1 : m.w2 + 1) : m.w1),
      'w2': draw
          ? m.w2
          : (winner == m.p2 ? (m.w2 > m.w1 ? m.w2 : m.w1 + 1) : m.w2),
      'note': note.text.trim(),
    };
    g1.dispose();
    g2.dispose();
    note.dispose();
    if (ok != true) return;
    await _run(() => _repo.adminMatch(m.id, 'result', p));
  }

  Future<String?> _pickPlayer(String title, {String? exclude}) async {
    final List<TEntry> list = _entries
        .where((TEntry e) => e.status == 'approved' && e.userId != exclude)
        .toList();
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (BuildContext c, int i) => ListTile(
                leading: TAvatar(name: list[i].username),
                title: Text(list[i].username),
                onTap: () => Navigator.pop(ctx, list[i].userId),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _editMatch(Tournament t, TMatch m) async {
    final bool fa = ref.read(settingsProvider).isFa;
    final String? p1 = await _pickPlayer(fa ? 'بازیکن اول' : 'Player 1');
    if (p1 == null || !mounted) return;
    final String? p2 =
        await _pickPlayer(fa ? 'بازیکن دوم' : 'Player 2', exclude: p1);
    if (p2 == null) return;
    await _run(() =>
        _repo.adminMatch(m.id, 'edit', <String, dynamic>{'p1': p1, 'p2': p2}));
  }

  Future<void> _addCustomMatch(Tournament t) async {
    final bool fa = ref.read(settingsProvider).isFa;
    final String? p1 = await _pickPlayer(fa ? 'بازیکن اول' : 'Player 1');
    if (p1 == null || !mounted) return;
    final String? p2 =
        await _pickPlayer(fa ? 'بازیکن دوم' : 'Player 2', exclude: p1);
    if (p2 == null || !mounted) return;
    final String? round =
        await _ask(fa ? 'شماره‌ی دور' : 'Round number', hint: '1');
    final String? label =
        await _ask(fa ? 'عنوان (اختیاری)' : 'Label (optional)');
    await _run(() => _repo.adminMatch(null, 'add', <String, dynamic>{
          'tournament_id': t.id,
          'p1': p1,
          'p2': p2,
          'round': int.tryParse(round ?? '') ?? 1,
          'best_of': t.cfg('bo_early', 1),
          'label': label ?? '',
        }));
  }

  // --------------------------------------------------------------------- logs
  Widget _logsTab(BuildContext context, Tournament t) {
    final List<dynamic> audit =
        (_logs['audit'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> jobs =
        (_logs['jobs'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> ledger =
        (_logs['ledger'] as List<dynamic>?) ?? const <dynamic>[];
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: <Widget>[
        Text(context.tx('کارهای زمان‌بندی‌شده', 'Scheduled jobs'),
            style: TextStyle(
                fontWeight: FontWeight.w900, color: tAccent(context))),
        for (final dynamic j in jobs)
          ListTile(
            dense: true,
            leading: Icon(
                (j as Map)['done_at'] != null
                    ? Icons.check_circle_rounded
                    : Icons.schedule_rounded,
                color:
                    j['done_at'] != null ? NxColors.success : NxColors.textDim,
                size: 18),
            title: Text('${j['kind']}'),
            subtitle: Text(
                '${fmtWhen(DateTime.tryParse('${j['run_at']}') ?? DateTime.now())}${j['last_error'] != null ? '\n⚠ ${j['last_error']}' : ''}',
                style: const TextStyle(fontSize: 11)),
          ),
        const Divider(),
        Text(context.tx('دفتر مالی (تغییرناپذیر)', 'Ledger (append-only)'),
            style: TextStyle(
                fontWeight: FontWeight.w900, color: tAccent(context))),
        for (final dynamic l in ledger)
          ListTile(
            dense: true,
            title: Text(
                '${(l as Map)['kind']} · ${l['amount']} ${l['currency']}${l['place'] != null ? ' · #${l['place']}' : ''}'),
            subtitle: Text(
                '${_names[l['user_id']] ?? l['user_id'] ?? 'house'} · ${l['idem_key']}',
                style: const TextStyle(fontSize: 10)),
          ),
        const Divider(),
        Text(context.tx('گزارش عملیات', 'Audit log'),
            style: TextStyle(
                fontWeight: FontWeight.w900, color: tAccent(context))),
        for (final dynamic a in audit)
          ListTile(
            dense: true,
            title: Text(
                '${(a as Map)['action']}${a['actor_name'] != null ? ' · ${a['actor_name']}' : ''}'),
            subtitle: Text(
                '${fmtWhen(DateTime.tryParse('${a['created_at']}') ?? DateTime.now(), withUtc: false)}  ${a['data']}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------- staff
  Widget _staffTab(BuildContext context, Tournament t) {
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: <Widget>[
        Text(
            context.tx(
                'ادمین: همه‌چیز. برگزارکننده: ساخت و اجرای تورنمنت خودش. همکار: اجرای همین تورنمنت.',
                'Admin: everything. Organizer: creates and runs own tournaments. Runner: runs this tournament.'),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: tAccent(context)),
          onPressed: () => _staffAction(t, 'runner'),
          icon: const Icon(Icons.person_add_rounded),
          label: Text(context.tx(
              'افزودن همکار این تورنمنت', 'Add a runner to this tournament')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _staffAction(t, 'organizer'),
          icon: const Icon(Icons.badge_rounded),
          label:
              Text(context.tx('دادن نقش برگزارکننده', 'Grant organizer role')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _staffAction(t, 'player'),
          icon: const Icon(Icons.person_off_rounded),
          label: Text(context.tx('گرفتن نقش', 'Revoke role')),
        ),
      ],
    );
  }

  Future<void> _staffAction(Tournament t, String what) async {
    final bool fa = ref.read(settingsProvider).isFa;
    final String? q = await _ask(fa ? 'نام کاربری' : 'Username');
    if (q == null || q.isEmpty || !mounted) return;
    final List<Map<String, dynamic>> users = await _repo.searchUsers(q);
    if (!mounted) return;
    final String? uid = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: <Widget>[
          for (final Map<String, dynamic> u in users)
            ListTile(
              leading: TAvatar(name: '${u['username']}'),
              title: Text('${u['username']}'),
              onTap: () => Navigator.pop(ctx, '${u['id']}'),
            ),
          if (users.isEmpty)
            ListTile(title: Text(fa ? 'پیدا نشد' : 'No match')),
        ]),
      ),
    );
    if (uid == null) return;
    if (what == 'runner') {
      await _run(() => _repo.setRunner(t.id, uid, true));
    } else {
      await _run(() => _repo.setStaff(uid, what == 'player' ? null : what));
    }
  }
}
