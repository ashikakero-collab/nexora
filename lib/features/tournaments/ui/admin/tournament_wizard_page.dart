import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../../core/theme/nx_theme.dart';
import '../../../../core/widgets/nx_widgets.dart';
import '../../../../games/game_registry.dart';
import '../../data/models.dart';
import '../../data/tournament_repository.dart';
import '../../domain/bracket.dart';
import '../../domain/prize_split.dart';
import '../t_common.dart';

/// Organizer wizard: info → format/capacity → times → match rules → prizes → registration/codes → review/publish.
/// Every value is validated again on the server (nx_t_save); this page only guides.
class TournamentWizardPage extends ConsumerStatefulWidget {
  const TournamentWizardPage({super.key, this.editId});
  final String? editId;

  @override
  ConsumerState<TournamentWizardPage> createState() =>
      _TournamentWizardPageState();
}

/// Games that can run a 1-vs-1 tournament match online.
const List<String> kTournamentGames = <String>[
  'finger_soccer',
  'carrom',
  'billiards',
  'backgammon',
  'quiz'
];

class _TournamentWizardPageState extends ConsumerState<TournamentWizardPage> {
  int _step = 0;
  bool _busy = false;
  bool _admin = false;
  Tournament? _editing;

  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _rules = TextEditingController();
  String _game = 'finger_soccer';
  TFormat _format = TFormat.singleElim;
  double _capacity = 16;
  int _minPlayers = 2;
  bool _thirdPlace = false;
  bool _rrDouble = false;
  int _groups = 4;
  int _advance = 2;
  int _swissRounds = 0;
  String _seeding = 'random';

  late DateTime _regOpen =
      _roundUp(DateTime.now().add(const Duration(minutes: 10)));
  late DateTime _regClose = _regOpen.add(const Duration(days: 1));
  late DateTime _draw = _regClose.add(const Duration(minutes: 10));
  late DateTime _start = _draw.add(const Duration(minutes: 20));
  int _roundMinutes = 20;
  int _readyMinutes = 5;
  int _maxGameMinutes = 30;

  int _boEarly = 1;
  int _boSemi = 1;
  int _boFinal = 3;
  bool _finalOneLeg = false;
  int _ptsWin = 3;
  int _ptsDraw = 1;

  int _fixedCoins = 0;
  int _fixedGems = 0;
  int _poolPct = 90;
  int _feePct = 10;
  List<int> _dist = <int>[60, 30, 10];

  String _regMode = 'open';
  int _feeCoins = 0;
  int _feeGems = 0;
  int _minLevel = 0;
  int _minXp = 0;
  int _minRating = 0;
  int _codesCount = 0;
  int _codeUses = 1;
  int _codeDays = 7;
  bool _codeApproval = false;

  static DateTime _roundUp(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, (d.minute ~/ 5 + 1) * 5);

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final TournamentRepository repo = ref.read(tournamentRepoProvider);
    final ({bool admin, bool organizer}) role = await repo.myRole();
    Tournament? t;
    if (widget.editId != null) t = await repo.get(widget.editId!);
    if (!mounted) return;
    setState(() {
      _admin = role.admin;
      if (t != null) _fill(t);
    });
  }

  void _fill(Tournament t) {
    _editing = t;
    _title.text = t.title;
    _desc.text = t.description;
    _rules.text = t.rules;
    _game = t.game;
    _format = t.format;
    _capacity = t.capacity.toDouble();
    _minPlayers = t.minPlayers;
    _thirdPlace = t.cfgB('third_place', false);
    _rrDouble = t.cfgB('rr_double', false);
    _groups = t.cfg('groups', 4);
    _advance = t.cfg('advance', 2);
    _swissRounds = t.cfg('swiss_rounds', 0);
    _seeding = t.seeding;
    _regOpen = t.regOpenAt.toLocal();
    _regClose = t.regCloseAt.toLocal();
    _draw = t.drawAt.toLocal();
    _start = t.startAt.toLocal();
    _roundMinutes = t.cfg('round_minutes', 20);
    _readyMinutes = (t.cfg('ready_seconds', 300) / 60).round();
    _maxGameMinutes = t.cfg('max_game_minutes', 30);
    _boEarly = t.cfg('bo_early', 1);
    _boSemi = t.cfg('bo_semi', 1);
    _boFinal = t.cfg('bo_final', 1);
    _finalOneLeg = t.cfgB('final_one_leg', false);
    _ptsWin = t.cfg('points_win', 3);
    _ptsDraw = t.cfg('points_draw', 1);
    final PrizeConfig pc = PrizeConfig.fromJson(t.prize);
    _fixedCoins = pc.fixed;
    _fixedGems = PrizeConfig.fromJson(t.prize, currency: 'gems').fixed;
    _poolPct = pc.poolPct;
    _feePct = pc.feePct;
    _dist = List<int>.of(pc.dist);
    _regMode = t.regMode;
    _feeCoins = t.feeCoins;
    _feeGems = t.feeGems;
    _minLevel = t.minLevel;
    _minXp = t.minXp;
    _minRating = t.minRating;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _rules.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() => <String, dynamic>{
        if (_editing != null) 'id': _editing!.id,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'rules': _rules.text.trim(),
        'game': _game,
        'format': _format.code,
        'capacity': _capacity.round(),
        'min_players': _minPlayers,
        'seeding': _seeding,
        'reg_mode': _regMode,
        'fee_coins': _feeCoins,
        'fee_gems': _feeGems,
        'min_level': _minLevel,
        'min_xp': _minXp,
        'min_rating': _minRating,
        'reg_open_at': _regOpen.toUtc().toIso8601String(),
        'reg_close_at': _regClose.toUtc().toIso8601String(),
        'draw_at': _draw.toUtc().toIso8601String(),
        'start_at': _start.toUtc().toIso8601String(),
        'config': <String, dynamic>{
          'bo_early': _boEarly,
          'bo_semi': _boSemi,
          'bo_final': _boFinal,
          'third_place': _thirdPlace,
          'rr_double': _rrDouble,
          'groups': _groups,
          'advance': _advance,
          'swiss_rounds': _swissRounds,
          'points_win': _ptsWin,
          'points_draw': _ptsDraw,
          'ready_seconds': _readyMinutes * 60,
          'round_minutes': _roundMinutes,
          'max_game_minutes': _maxGameMinutes,
          'final_one_leg': _finalOneLeg,
        },
        'prize': <String, dynamic>{
          'fixed_coins': _fixedCoins,
          'fixed_gems': _fixedGems,
          'pool_pct': _poolPct,
          'fee_pct': _feePct,
          'dist': _dist,
        },
      };

  String? _validate(BuildContext context) {
    if (_title.text.trim().length < 3)
      return context.tx('عنوان حداقل ۳ حرف', 'Title needs at least 3 letters');
    if (!_regOpen.isBefore(_regClose) ||
        _draw.isBefore(_regClose) ||
        _start.isBefore(_draw)) {
      return context.tx(
          'ترتیب زمان‌ها: شروع ثبت‌نام < پایان ثبت‌نام ≤ قرعه ≤ شروع',
          'Order: reg open < reg close ≤ draw ≤ start');
    }
    if (_format == TFormat.groupsKo && _capacity < 4)
      return context.tx(
          'حالت گروهی حداقل ۴ نفر', 'Groups need at least 4 players');
    if (_dist.fold<int>(0, (int a, int b) => a + b) > 100)
      return context.tx(
          'جمع درصدها بیشتر از ۱۰۰', 'Prize % adds up to more than 100');
    return null;
  }

  Future<void> _save({required bool publish}) async {
    final String? err = _validate(context);
    final bool fa = ref.read(settingsProvider).isFa;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _busy = true);
    final TournamentRepository repo = ref.read(tournamentRepoProvider);
    final TResult r = await repo.save(_payload());
    if (!r.ok) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tErrorText(r.error, fa))));
      }
      return;
    }
    final String id = '${r.data['id']}';
    if (_codesCount > 0 && _editing == null) {
      await repo.createCodes(id,
          maxUses: _codeUses,
          expiresAt: DateTime.now().add(Duration(days: _codeDays)),
          requiresApproval: _codeApproval,
          count: _codesCount);
    }
    if (publish && (_editing == null || _editing!.status == 'draft')) {
      final TResult p = await repo.admin(id, 'publish');
      if (!p.ok && mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tErrorText(p.error, fa))));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(publish
            ? (fa ? 'منتشر شد' : 'Published')
            : (fa ? 'ذخیره شد' : 'Saved'))));
    if (_editing == null) {
      context.pushReplacement('/tournaments/$id/manage');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, IconData, Widget Function(BuildContext))> steps =
        <(String, IconData, Widget Function(BuildContext))>[
      (context.tx('اطلاعات', 'Info'), Icons.info_rounded, _stepInfo),
      (context.tx('فرمت', 'Format'), Icons.account_tree_rounded, _stepFormat),
      (context.tx('زمان‌ها', 'Times'), Icons.schedule_rounded, _stepTimes),
      (
        context.tx('قوانین بازی', 'Match rules'),
        Icons.rule_rounded,
        _stepRules
      ),
      (context.tx('جوایز', 'Prizes'), Icons.emoji_events_rounded, _stepPrizes),
      (
        context.tx('ثبت‌نام', 'Registration'),
        Icons.how_to_reg_rounded,
        _stepRegistration
      ),
      (context.tx('بازبینی', 'Review'), Icons.fact_check_rounded, _stepReview),
    ];
    final bool locked = _editing != null &&
        !<String>['draft', 'scheduled', 'registering', 'closed']
            .contains(_editing!.status);
    return NxWorldScaffold(
      title: _editing == null
          ? context.tx('تورنمنت جدید', 'NEW TOURNAMENT')
          : context.tx('ویرایش تورنمنت', 'EDIT TOURNAMENT'),
      palette: WorldPalette.arcade,
      showWallet: false,
      body: Column(children: <Widget>[
        SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: NxSpace.md, vertical: 10),
            itemCount: steps.length,
            itemBuilder: (BuildContext context, int i) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                avatar: Icon(steps[i].$2,
                    size: 16,
                    color: i == _step ? NxColors.navyDeep : tAccent(context)),
                label: Text('${i + 1}. ${steps[i].$1}'),
                selected: i == _step,
                selectedColor: tAccent(context),
                labelStyle: TextStyle(
                    color: i == _step ? NxColors.navyDeep : NxColors.iceWhite,
                    fontWeight: FontWeight.w700),
                showCheckmark: false,
                onSelected: (_) => setState(() => _step = i),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              NxSpace.md, 0, NxSpace.md, 6),
          child: Row(children: <Widget>[
            Expanded(
                child: Text(steps[_step].$1,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(
                context.tx('مرحله ${_step + 1} از ${steps.length}',
                    'STEP ${_step + 1} OF ${steps.length}'),
                style: TextStyle(
                    color: NxThemeColors.of(context).muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        LinearProgressIndicator(
            value: (_step + 1) / steps.length,
            color: tAccent(context),
            backgroundColor:
                NxThemeColors.of(context).border.withValues(alpha: 0.35)),
        if (locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(NxSpace.md, 8, NxSpace.md, 0),
            child: Text(
                context.tx(
                    'بعد از قرعه فقط عنوان، توضیحات و زمان‌ها قابل تغییرند.',
                    'After the draw only text and times can change.'),
                style: const TextStyle(color: NxColors.gold, fontSize: 12)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                NxSpace.md, NxSpace.md, NxSpace.md, NxSpace.lg),
            children: <Widget>[steps[_step].$3(context)],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                NxSpace.md, 0, NxSpace.md, NxSpace.sm),
            child: Row(children: <Widget>[
              if (_step > 0)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _step--),
                  icon: Icon(Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded),
                  label: Text(context.tx('قبلی', 'Back')),
                ),
              const Spacer(),
              if (_step < steps.length - 1)
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: tAccent(context)),
                  onPressed: () => setState(() => _step++),
                  icon: Icon(Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_back_rounded
                      : Icons.arrow_forward_rounded),
                  label: Text(context.tx('بعدی', 'Next')),
                )
              else ...<Widget>[
                OutlinedButton(
                  onPressed: _busy ? null : () => _save(publish: false),
                  child: Text(_editing == null
                      ? context.tx('ذخیره‌ی پیش‌نویس', 'Save draft')
                      : context.tx('ذخیره', 'Save')),
                ),
                const SizedBox(width: 8),
                if (_editing == null || _editing!.status == 'draft')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: tAccent(context)),
                    onPressed: _busy ? null : () => _save(publish: true),
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: Text(context.tx('انتشار', 'Publish')),
                  ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  // ----------------------------------------------------------------- helpers
  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassPanel(
          blur: false,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: tAccent(context))),
                const SizedBox(height: 10),
                ...children,
              ]),
        ),
      );

  Widget _stepper(String label, int value, int min, int max,
          ValueChanged<int> onChanged,
          {int step = 1, String suffix = ''}) =>
      Row(children: <Widget>[
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value - step >= min
              ? () => setState(() => onChanged(value - step))
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 64,
          child: Text('$value$suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        IconButton(
          onPressed: value + step <= max
              ? () => setState(() => onChanged(value + step))
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);

  Widget _bo(String label, int value, ValueChanged<int> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: <Widget>[
          Expanded(child: Text(label)),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 1, label: Text('1')),
              ButtonSegment<int>(value: 2, label: Text('2')),
              ButtonSegment<int>(value: 3, label: Text('3')),
              ButtonSegment<int>(value: 5, label: Text('5')),
            ],
            selected: <int>{value},
            onSelectionChanged: (Set<int> v) =>
                setState(() => onChanged(v.first)),
          ),
        ]),
      );

  Future<void> _pick(DateTime current, ValueChanged<DateTime> onPicked) async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return;
    final TimeOfDay? t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (t == null) return;
    setState(
        () => onPicked(DateTime(d.year, d.month, d.day, t.hour, t.minute)));
  }

  Widget _timeRow(
          String label, DateTime value, ValueChanged<DateTime> onPicked) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.event_rounded, color: tAccent(context)),
        title: Text(label),
        subtitle: Text(fmtWhen(value.toUtc())),
        trailing: const Icon(Icons.edit_calendar_rounded),
        onTap: () => _pick(value, onPicked),
      );

  // ----------------------------------------------------------------- steps
  Widget _stepInfo(BuildContext context) =>
      _section(context.tx('اطلاعات پایه', 'Basics'), <Widget>[
        TextField(
            controller: _title,
            maxLength: 80,
            decoration:
                InputDecoration(labelText: context.tx('عنوان', 'Title'))),
        const SizedBox(height: 8),
        TextField(
          controller: _desc,
          maxLines: 3,
          maxLength: 4000,
          decoration:
              InputDecoration(labelText: context.tx('توضیحات', 'Description')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _rules,
          maxLines: 4,
          maxLength: 4000,
          decoration: InputDecoration(
              labelText: context.tx('قوانین اضافه', 'Extra rules')),
        ),
        const SizedBox(height: 8),
        Text(context.tx('بازی', 'Game'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final String id in kTournamentGames)
            if (gameById(id) != null)
              ChoiceChip(
                label: Text(
                    context.tx(gameById(id)!.nameFa, gameById(id)!.nameEn)),
                selected: _game == id,
                selectedColor: gameById(id)!.accent.withValues(alpha: 0.4),
                onSelected: (_) => setState(() => _game = id),
              ),
        ]),
      ]);

  Widget _stepFormat(BuildContext context) => Column(children: <Widget>[
        _section(context.tx('فرمت', 'Format'), <Widget>[
          for (final TFormat f in TFormat.values)
            RadioListTile<TFormat>(
              contentPadding: EdgeInsets.zero,
              value: f,
              groupValue: _format,
              activeColor: tAccent(context),
              secondary: Icon(formatIcon(f), color: tAccent(context)),
              title: Text(formatName(context, f)),
              onChanged: (TFormat? v) => setState(() => _format = v ?? _format),
            ),
        ]),
        _section(context.tx('ظرفیت', 'Capacity'), <Widget>[
          Row(children: <Widget>[
            Text(context.tx('حداکثر بازیکن', 'Max players')),
            Expanded(
              child: Slider(
                value: _capacity,
                min: 2,
                max: 64,
                divisions: 62,
                activeColor: tAccent(context),
                label: '${_capacity.round()}',
                onChanged: (double v) => setState(() {
                  _capacity = v;
                  if (_minPlayers > v.round()) _minPlayers = v.round();
                }),
              ),
            ),
            Text('${_capacity.round()}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
          _stepper(context.tx('حداقل برای برگزاری', 'Minimum to run'),
              _minPlayers, 2, _capacity.round(), (int v) => _minPlayers = v),
          Text(
              context.tx(
                  'کمتر از توان ۲ = استراحت (bye) خودکار برای سیدهای بالا.',
                  'Not a power of 2 → automatic byes for the top seeds.'),
              style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
          if (_format == TFormat.singleElim ||
              _format == TFormat.twoLegs ||
              _format == TFormat.groupsKo)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _thirdPlace,
              activeColor: tAccent(context),
              title: Text(
                  context.tx('بازی رده‌بندی (سوم و چهارم)', '3rd-place match')),
              onChanged: (bool v) => setState(() => _thirdPlace = v),
            ),
          if (_format == TFormat.roundRobin || _format == TFormat.groupsKo)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _rrDouble,
              activeColor: tAccent(context),
              title:
                  Text(context.tx('دوره‌ای رفت و برگشت', 'Double round robin')),
              onChanged: (bool v) => setState(() => _rrDouble = v),
            ),
          if (_format == TFormat.groupsKo) ...<Widget>[
            _stepper(context.tx('تعداد گروه', 'Groups'), _groups, 1, 16,
                (int v) => _groups = v),
            _stepper(context.tx('صعودی از هر گروه', 'Advance per group'),
                _advance, 1, 8, (int v) => _advance = v),
          ],
          if (_format == TFormat.swiss)
            _stepper(context.tx('تعداد دور (۰ = خودکار)', 'Rounds (0 = auto)'),
                _swissRounds, 0, 12, (int v) => _swissRounds = v),
          const SizedBox(height: 8),
          Text(context.tx('سیدبندی', 'Seeding'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                  value: 'random', label: Text(context.tx('تصادفی', 'Random'))),
              ButtonSegment<String>(
                  value: 'rating',
                  label: Text(context.tx('بر اساس رتبه', 'By rating'))),
              ButtonSegment<String>(
                  value: 'manual', label: Text(context.tx('دستی', 'Manual'))),
            ],
            selected: <String>{_seeding},
            onSelectionChanged: (Set<String> v) =>
                setState(() => _seeding = v.first),
          ),
        ]),
      ]);

  Widget _stepTimes(BuildContext context) => _section(
          context.tx('زمان‌بندی (ذخیره به UTC)', 'Schedule (stored in UTC)'),
          <Widget>[
            _timeRow(context.tx('شروع ثبت‌نام', 'Registration opens'), _regOpen,
                (DateTime d) => _regOpen = d),
            _timeRow(context.tx('پایان ثبت‌نام', 'Registration closes'),
                _regClose, (DateTime d) => _regClose = d),
            _timeRow(context.tx('قرعه‌کشی خودکار', 'Automatic draw'), _draw,
                (DateTime d) => _draw = d),
            _timeRow(context.tx('شروع مسابقات', 'Start'), _start,
                (DateTime d) => _start = d),
            const Divider(),
            _stepper(context.tx('فاصله‌ی دورها', 'Minutes between rounds'),
                _roundMinutes, 1, 10080, (int v) => _roundMinutes = v,
                step: _roundMinutes >= 60 ? 30 : 5, suffix: "'"),
            _stepper(context.tx('مهلت آمادگی', 'Ready window'), _readyMinutes,
                1, 60, (int v) => _readyMinutes = v,
                suffix: "'"),
            _stepper(context.tx('حداکثر زمان هر بازی', 'Max game length'),
                _maxGameMinutes, 5, 240, (int v) => _maxGameMinutes = v,
                step: 5, suffix: "'"),
            Text(
                context.tx(
                    'می‌توانی ماه‌ها جلوتر برنامه بریزی. تغییر زمان‌ها به همه‌ی شرکت‌کننده‌ها اعلام می‌شود.',
                    'You can schedule months ahead. Time changes notify every participant.'),
                style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
          ]);

  Widget _stepRules(BuildContext context) =>
      _section(context.tx('قوانین بازی', 'Match rules'), <Widget>[
        if (_format == TFormat.twoLegs)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _finalOneLeg,
            activeColor: tAccent(context),
            title: Text(context.tx('فینال تک‌بازی', 'Single-game final')),
            onChanged: (bool v) => setState(() => _finalOneLeg = v),
          )
        else ...<Widget>[
          Text(context.tx('بهترین از (Bo)', 'Best of'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          _bo(context.tx('دورهای اولیه', 'Early rounds'), _boEarly,
              (int v) => _boEarly = v),
          _bo(context.tx('نیمه‌نهایی', 'Semi-finals'), _boSemi,
              (int v) => _boSemi = v),
          _bo(context.tx('فینال', 'Final'), _boFinal, (int v) => _boFinal = v),
        ],
        const Divider(),
        Text(
            context.tx('مساوی در حذفی ← بازی گل طلایی',
                'Knockout draw → golden-goal decider'),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        if (_format.isLeague || _format == TFormat.groupsKo) ...<Widget>[
          _stepper(context.tx('امتیاز برد', 'Points for a win'), _ptsWin, 0, 10,
              (int v) => _ptsWin = v),
          _stepper(context.tx('امتیاز مساوی', 'Points for a draw'), _ptsDraw, 0,
              10, (int v) => _ptsDraw = v),
        ],
      ]);

  Widget _stepPrizes(BuildContext context) {
    final int expectedEscrow = _feeCoins * _capacity.round();
    final PrizeConfig pc = PrizeConfig(
        fixed: _fixedCoins, poolPct: _poolPct, feePct: _feePct, dist: _dist);
    final int total = PrizeSplit.total(pc, expectedEscrow);
    final List<int> per = PrizeSplit.perPlace(total, _dist);
    return Column(children: <Widget>[
      _section(context.tx('منبع جایزه', 'Prize source'), <Widget>[
        if (_admin) ...<Widget>[
          _stepper(context.tx('جایزه‌ی ثابت (سکه)', 'Fixed prize (coins)'),
              _fixedCoins, 0, 1000000, (int v) => _fixedCoins = v,
              step: 100),
          _stepper(context.tx('جایزه‌ی ثابت (جم)', 'Fixed prize (gems)'),
              _fixedGems, 0, 100000, (int v) => _fixedGems = v,
              step: 10),
        ] else
          Text(
              context.tx('جایزه‌ی ثابت فقط توسط ادمین تعیین می‌شود.',
                  'Fixed prizes are set by admins only.'),
              style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        _stepper(
            context.tx('سهم ورودیه‌ها در جایزه', 'Entry fees into the pool'),
            _poolPct,
            0,
            100,
            (int v) => _poolPct = v,
            step: 5,
            suffix: '%'),
        _stepper(context.tx('کارمزد', 'House fee'), _feePct, 0, 50,
            (int v) => _feePct = v,
            suffix: '%'),
        Text(
            context.tx(
                'ورودیه‌ها تا پایان تورنمنت امانت می‌مانند؛ لغو = بازپرداخت کامل.',
                'Entry fees are held in escrow until the end; cancel = full refund.'),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
      ]),
      _section(context.tx('تقسیم بین رتبه‌ها', 'Split by place'), <Widget>[
        for (int i = 0; i < _dist.length; i++)
          _stepper('#${i + 1}', _dist[i], 0, 100, (int v) => _dist[i] = v,
              suffix: '%'),
        Row(children: <Widget>[
          TextButton.icon(
            onPressed: _dist.length < 16
                ? () => setState(() => _dist = <int>[..._dist, 0])
                : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.tx('رتبه‌ی بعدی', 'Add place')),
          ),
          TextButton.icon(
            onPressed: _dist.length > 1
                ? () =>
                    setState(() => _dist = _dist.sublist(0, _dist.length - 1))
                : null,
            icon: const Icon(Icons.remove_rounded),
            label: Text(context.tx('حذف', 'Remove')),
          ),
          const Spacer(),
          Text('Σ ${_dist.fold<int>(0, (int a, int b) => a + b)}%',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _dist.fold<int>(0, (int a, int b) => a + b) > 100
                      ? NxColors.danger
                      : NxColors.success)),
        ]),
        const Divider(),
        Text(
            context.tx('پیش‌نمایش با ظرفیت کامل: $total سکه',
                'Preview at full capacity: $total coins'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (int i = 0; i < per.length; i++)
            NxPill(label: '#${i + 1}: ${per[i]}', color: NxColors.gold),
        ]),
      ]),
    ]);
  }

  Widget _stepRegistration(BuildContext context) => Column(children: <Widget>[
        _section(context.tx('نحوه‌ی ثبت‌نام', 'Registration mode'), <Widget>[
          for (final String m in <String>[
            'open',
            'approval',
            'code',
            'code_approval'
          ])
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: m,
              groupValue: _regMode,
              activeColor: tAccent(context),
              title: Text(regModeName(context, m)),
              onChanged: (String? v) =>
                  setState(() => _regMode = v ?? _regMode),
            ),
        ]),
        _section(context.tx('ورودیه و شرایط', 'Fee & requirements'), <Widget>[
          _stepper(context.tx('ورودیه (سکه)', 'Entry fee (coins)'), _feeCoins,
              0, 100000, (int v) => _feeCoins = v,
              step: _feeCoins >= 1000 ? 100 : 10),
          _stepper(context.tx('ورودیه (جم)', 'Entry fee (gems)'), _feeGems, 0,
              10000, (int v) => _feeGems = v,
              step: 5),
          _stepper(context.tx('حداقل سطح', 'Min level'), _minLevel, 0, 100,
              (int v) => _minLevel = v),
          _stepper(context.tx('حداقل XP', 'Min XP'), _minXp, 0, 1000000,
              (int v) => _minXp = v,
              step: 100),
          _stepper(context.tx('حداقل رتبه (تروفی)', 'Min rating (trophies)'),
              _minRating, 0, 5000, (int v) => _minRating = v,
              step: 50),
          Text(
              context.tx(
                  'هر حساب فقط یک‌بار؛ ظرفیت پر = لیست انتظار با جایگزینی خودکار.',
                  'One registration per account; full = waitlist with automatic replacement.'),
              style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        ]),
        if (_editing == null &&
            (_regMode == 'code' ||
                _regMode == 'code_approval' ||
                _regMode == 'approval' ||
                _regMode == 'open'))
          _section(
              context.tx('کدهای دعوت (اختیاری)', 'Invite codes (optional)'),
              <Widget>[
                _stepper(context.tx('تعداد کد', 'How many codes'), _codesCount,
                    0, 50, (int v) => _codesCount = v),
                if (_codesCount > 0) ...<Widget>[
                  _stepper(context.tx('دفعات استفاده‌ی هر کد', 'Uses per code'),
                      _codeUses, 1, 1000, (int v) => _codeUses = v),
                  _stepper(context.tx('اعتبار (روز)', 'Valid for (days)'),
                      _codeDays, 1, 365, (int v) => _codeDays = v),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _codeApproval,
                    activeColor: tAccent(context),
                    title: Text(context.tx('ورود با کد هم تأیید لازم دارد',
                        'Code entries also need approval')),
                    onChanged: (bool v) => setState(() => _codeApproval = v),
                  ),
                ],
                Text(
                    context.tx(
                        'کدها ۸ حرفی‌اند، بدون 0/O/1/I، با لینک nexora://t/<code>. بعداً در مدیریت هم می‌سازی یا باطل می‌کنی.',
                        '8-character codes without 0/O/1/I, deep link nexora://t/<code>. Create or revoke more later in Manage.'),
                    style:
                        const TextStyle(color: NxColors.textDim, fontSize: 12)),
              ]),
      ]);

  Widget _stepReview(BuildContext context) {
    final int n = _capacity.round();
    final int matches = BracketGen.matchCount(_format, n,
        thirdPlace: _thirdPlace,
        rrDouble: _rrDouble,
        groups: _groups,
        advance: _advance,
        swissRoundsCfg: _swissRounds);
    final String? err = _validate(context);
    return _section(context.tx('بازبینی', 'Review'), <Widget>[
      if (err != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(err,
              style: const TextStyle(
                  color: NxColors.danger, fontWeight: FontWeight.w800)),
        ),
      _kv(context.tx('عنوان', 'Title'), _title.text),
      _kv(
          context.tx('بازی', 'Game'),
          context.tx(gameById(_game)?.nameFa ?? _game,
              gameById(_game)?.nameEn ?? _game)),
      _kv(context.tx('فرمت', 'Format'), formatName(context, _format)),
      _kv(context.tx('ظرفیت', 'Capacity'), '$_minPlayers – $n'),
      _kv(
          context.tx('تعداد بازی‌ها (ظرفیت کامل)', 'Matches at full capacity'),
          _format == TFormat.custom
              ? context.tx('دستی', 'manual')
              : '$matches'),
      _kv(context.tx('ثبت‌نام', 'Registration'),
          '${regModeName(context, _regMode)} · ${_feeCoins}🪙 ${_feeGems}💎'),
      _kv(context.tx('شروع ثبت‌نام', 'Reg opens'), fmtWhen(_regOpen.toUtc())),
      _kv(context.tx('پایان ثبت‌نام', 'Reg closes'),
          fmtWhen(_regClose.toUtc())),
      _kv(context.tx('قرعه', 'Draw'), fmtWhen(_draw.toUtc())),
      _kv(context.tx('شروع', 'Start'), fmtWhen(_start.toUtc())),
      _kv(
          'Bo',
          _format == TFormat.twoLegs
              ? context.tx('رفت و برگشت', 'two legs')
              : '$_boEarly / $_boSemi / $_boFinal'),
      _kv(context.tx('جوایز', 'Prizes'),
          '${_fixedCoins > 0 ? '$_fixedCoins🪙 + ' : ''}$_poolPct% ${context.tx('ورودیه', 'fees')} · ${_dist.join('/')}'),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                  width: 150,
                  child:
                      Text(k, style: const TextStyle(color: NxColors.textDim))),
              Expanded(
                  child: Text(v,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
      );
}
