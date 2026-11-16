import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/backend_gateway.dart';
import '../../core/backend/supabase_backend.dart';
import '../../core/profile/achievements.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/game_registry.dart';
import 'core/oracle_brain.dart';

const String _kChatKey = 'oracle.chat.v1';
const int _kMaxMessages = 100;

/// One chat line (persisted).
class _ChatMsg {
  _ChatMsg({
    required this.fromUser,
    required this.textFa,
    required this.textEn,
    this.actions = const <OracleAction>[],
    this.pose = 'idle',
    this.followUpsFa = const <String>[],
    this.followUpsEn = const <String>[],
    this.ranIndex = -1,
    this.error = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final bool fromUser;
  final String textFa;
  final String textEn;
  final List<OracleAction> actions;
  final String pose;
  final List<String> followUpsFa;
  final List<String> followUpsEn;

  /// Index of the action that was actually executed (-1 = none yet).
  int ranIndex;
  final bool error;
  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'u': fromUser,
        'fa': textFa,
        'en': textEn,
        'a': actions.map((OracleAction a) => a.toJson()).toList(),
        'p': pose,
        'ffa': followUpsFa,
        'fen': followUpsEn,
        'ran': ranIndex,
        'err': error,
        'at': at.millisecondsSinceEpoch,
      };

  static _ChatMsg? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> j = Map<String, dynamic>.from(raw);
    final List<OracleAction> acts = <OracleAction>[];
    final Object? a = j['a'];
    if (a is List) {
      for (final Object? e in a) {
        if (e is Map) {
          acts.add(OracleAction.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    List<String> strs(Object? v) =>
        v is List ? v.map((Object? e) => '$e').toList() : const <String>[];
    final Object? at = j['at'];
    final Object? ran = j['ran'];
    return _ChatMsg(
      fromUser: j['u'] == true,
      textFa: '${j['fa'] ?? ''}',
      textEn: '${j['en'] ?? ''}',
      actions: acts,
      pose: '${j['p'] ?? 'idle'}',
      followUpsFa: strs(j['ffa']),
      followUpsEn: strs(j['fen']),
      ranIndex: ran is int ? ran : -1,
      error: j['err'] == true,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }
}

/// ORACLE CORE (STEP_27): offline assistant that really performs actions.
class OracleCorePage extends ConsumerStatefulWidget {
  const OracleCorePage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  ConsumerState<OracleCorePage> createState() => _OracleCorePageState();
}

class _OracleCorePageState extends ConsumerState<OracleCorePage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final List<_ChatMsg> _msgs = <_ChatMsg>[];
  late final OfflineOracleEngine _engine;
  RemoteOracleEngine? _remote;
  bool _thinking = false;
  bool _initialAsked = false;

  @override
  void initState() {
    super.initState();
    _engine = OfflineOracleEngine(games: <String, OracleGameInfo>{
      for (final GameInfo g in kGames)
        g.id: OracleGameInfo(
            id: g.id,
            nameFa: g.nameFa,
            nameEn: g.nameEn,
            rulesFa: g.rulesFa,
            rulesEn: g.rulesEn),
    });
    final BackendGateway be = ref.read(backendProvider);
    if (be is SupabaseBackend) {
      _remote = RemoteOracleEngine(invoke: be.oracleInvoke, offline: _engine);
    }
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToEnd();
      final String q = (widget.initialQuery ?? '').trim();
      if (!_initialAsked && q.isNotEmpty) {
        _initialAsked = true;
        _ask(q);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ persistence

  void _load() {
    final List<dynamic>? raw = LocalStore.instance.getJsonList(_kChatKey);
    if (raw == null) return;
    for (final Object? e in raw) {
      final _ChatMsg? m = _ChatMsg.fromJson(e);
      if (m != null) _msgs.add(m);
    }
    if (_msgs.length > _kMaxMessages) {
      _msgs.removeRange(0, _msgs.length - _kMaxMessages);
    }
  }

  void _save() {
    if (_msgs.length > _kMaxMessages) {
      _msgs.removeRange(0, _msgs.length - _kMaxMessages);
    }
    LocalStore.instance
        .setJson(_kChatKey, _msgs.map((_ChatMsg m) => m.toJson()).toList());
  }

  Future<void> _clear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('پاک کردن گفتگو', 'Clear conversation')),
        content: Text(ctx.tx('همه‌ی پیام‌های این گفتگو از این دستگاه پاک شود؟',
            'Delete all messages of this conversation from this device?')),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tx('پاک کن', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _msgs.clear());
    LocalStore.instance.remove(_kChatKey);
  }

  // ------------------------------------------------------------ context

  OracleContext _context() {
    final ProfileService p = ref.read(profileProvider);
    final AppSettings s = ref.read(settingsProvider);
    final Map<String, OracleGameStat> stats = <String, OracleGameStat>{};
    p.stats.forEach((String id, GameStats g) {
      stats[id] = OracleGameStat(
          played: g.played,
          won: g.won,
          lost: g.lost,
          draw: g.draw,
          best: g.best);
    });
    final List<OracleAchievementHint> locked = <OracleAchievementHint>[
      for (final AchievementDef a in kAchievements)
        if (!p.achievements.contains(a.id))
          OracleAchievementHint(
              nameFa: a.nameFa,
              nameEn: a.nameEn,
              descFa: a.descFa,
              descEn: a.descEn),
    ];
    return OracleContext(
      username: p.username,
      explorerId: p.explorerId,
      level: p.level,
      xp: p.xp,
      xpIntoLevel: p.xpIntoLevel,
      xpForNextLevel: ProfileService.xpForLevel(p.level),
      rankFa: p.rankTitleFa,
      rankEn: p.rankTitleEn,
      coins: p.coins,
      achievementsUnlocked: p.achievements.length,
      achievementsTotal: kAchievements.length,
      lockedAchievements: locked,
      stats: stats,
      canClaimDaily: p.canClaimDaily,
      streak: p.streak,
      reducedMotion: s.reducedMotion,
      quality: s.quality.name,
      languageCode: s.languageCode,
      now: DateTime.now(),
    );
  }

  // ------------------------------------------------------------ asking

  Future<void> _ask(String text) async {
    final String q = text.trim();
    if (q.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _msgs.add(_ChatMsg(fromUser: true, textFa: q, textEn: q));
      _thinking = true;
    });
    _save();
    _scrollToEnd();

    final ProfileService p = ref.read(profileProvider);
    p.bump('oracle.asked');
    final AwardOutcome outcome = p.award('oracle.ask', xp: 3);

    OracleReply reply;
    try {
      final RemoteOracleEngine? remote = _remote;
      final bool online = ref.read(backendProvider).isOnline;
      reply = remote != null && online
          ? await remote.ask(q, _context())
          : await _engine.ask(q, _context());
    } catch (_) {
      reply = const OracleReply(
        textFa: 'متأسفم، در پردازش این پیام خطایی رخ داد. لطفاً دوباره بپرس.',
        textEn:
            'Sorry, something went wrong while processing that. Please ask again.',
        pose: 'confused',
        intent: 'fallback',
      );
    }
    // A short natural pause so the "thinking" state is visible.
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    final _ChatMsg msg = _ChatMsg(
      fromUser: false,
      textFa: reply.textFa,
      textEn: reply.textEn,
      actions: reply.actions,
      pose: reply.pose,
      followUpsFa: reply.followUpsFa,
      followUpsEn: reply.followUpsEn,
    );
    setState(() {
      _msgs.add(msg);
      _thinking = false;
    });
    _save();
    _scrollToEnd();

    if (outcome.levelUp || outcome.unlocked.isNotEmpty) {
      await showAwardOutcome(context, outcome);
      if (!mounted) return;
    }
    if (reply.autoRun && reply.actions.isNotEmpty) {
      await _run(msg, 0);
    }
  }

  /// Executes [msg.actions[index]] for real and reports the true result.
  Future<void> _run(_ChatMsg msg, int index) async {
    if (index < 0 || index >= msg.actions.length) return;
    final OracleAction a = msg.actions[index];
    bool ok = false;
    try {
      switch (a.type) {
        case OracleActionType.navigate:
          ok = _navigate(a.route);
          break;
        case OracleActionType.setting:
          ok = _applySetting(a.settingKey, a.settingValue);
          break;
        case OracleActionType.none:
          ok = false;
          break;
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() => msg.ranIndex = index);
      _save();
      if (a.type == OracleActionType.setting) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(context.tx('انجام شد: ${a.labelFa}', 'Done: ${a.labelEn}')),
          duration: const Duration(seconds: 2),
        ));
      }
    } else {
      setState(() {
        _msgs.add(_ChatMsg(
          fromUser: false,
          textFa:
              'نتوانستم «${a.labelFa.isEmpty ? 'این کار' : a.labelFa}» را انجام دهم. چیزی تغییر نکرد.',
          textEn:
              'I couldn\'t do "${a.labelEn.isEmpty ? 'that' : a.labelEn}". Nothing was changed.',
          pose: 'confused',
          error: true,
        ));
      });
      _save();
      _scrollToEnd();
    }
  }

  bool _navigate(String? route) {
    if (route == null || route.isEmpty || !route.startsWith('/')) return false;
    if (route == '/hub') {
      context.go('/hub');
    } else {
      context.push(route);
    }
    return true;
  }

  bool _applySetting(String? key, String? value) {
    if (key == null || value == null) return false;
    final AppSettings s = ref.read(settingsProvider);
    switch (key) {
      case OracleSettingKeys.reducedMotion:
        if (value != 'true' && value != 'false') return false;
        s.reducedMotion = value == 'true';
        return true;
      case OracleSettingKeys.quality:
        for (final GraphicsQuality q in GraphicsQuality.values) {
          if (q.name == value) {
            s.quality = q;
            return true;
          }
        }
        return false;
      case OracleSettingKeys.language:
        if (value != 'fa' && value != 'en') return false;
        s.languageCode = value;
        return true;
      default:
        return false;
    }
  }

  // ------------------------------------------------------------ scrolling

  void _jumpToEnd() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final bool reduced = ref.read(settingsProvider).reducedMotion;
      if (reduced) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: NxMotion.normal, curve: NxMotion.curve);
      }
    });
  }

  void _showVoiceNotice() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF20B0A24),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NxRadius.lg))),
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NxSpace.lg),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Icon(Icons.mic_off_rounded,
                    color: NxColors.gold, size: 40),
                const SizedBox(height: NxSpace.md),
                const OnlineOnlyNotice(
                    featureFa: 'گفتگوی صوتی با ORACLE',
                    featureEn: 'Voice chat with ORACLE'),
                const SizedBox(height: NxSpace.md),
                Text(
                  ctx.tx(
                      'تا آن موقع می‌توانی سؤالت را تایپ کنی؛ ORACLE همه‌ی کارها را آفلاین انجام می‌دهد.',
                      'Until then, type your question; ORACLE does everything else offline.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NxColors.textDim),
                ),
                const SizedBox(height: NxSpace.md),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _focus.requestFocus();
                  },
                  child: Text(ctx.tx('تایپ می‌کنم', 'I\'ll type')),
                ),
              ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ build

  String get _pose {
    if (_thinking) return 'focus';
    for (int i = _msgs.length - 1; i >= 0; i--) {
      if (!_msgs[i].fromUser) return _msgs[i].pose;
    }
    return 'hero_wave';
  }

  List<String> _chips(BuildContext context) {
    final bool fa = context.isFa;
    for (int i = _msgs.length - 1; i >= 0; i--) {
      final _ChatMsg m = _msgs[i];
      if (m.fromUser) break;
      final List<String> f = fa ? m.followUpsFa : m.followUpsEn;
      if (f.isNotEmpty) return f;
    }
    return fa
        ? const <String>[
            'چی بازی کنم؟',
            'سطح من چنده؟',
            'قوانین لودو',
            'منو ببر به آرکید',
            'چطور سکه بگیرم؟'
          ]
        : const <String>[
            'What should I play?',
            'What\'s my level?',
            'Ludo rules',
            'Take me to the Arcade',
            'How do I earn coins?'
          ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final bool keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final double avatarSize = keyboard ? 74 : 140;
    final List<String> chips = _chips(context);
    return NxWorldScaffold(
      title: 'ORACLE CORE',
      palette: WorldPalette.oracle,
      actions: <Widget>[
        if (_msgs.isNotEmpty)
          IconButton(
            tooltip: context.tx('پاک کردن گفتگو', 'Clear conversation'),
            onPressed: _clear,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
      ],
      body: Column(children: <Widget>[
        SizedBox(height: kToolbarHeight),
        // Floating ORACLE with a glow halo that follows the reply pose.
        AnimatedContainer(
          duration: NxMotion.normal,
          curve: NxMotion.curve,
          height: avatarSize + 34,
          child: Stack(alignment: Alignment.center, children: <Widget>[
            AnimatedContainer(
              duration: NxMotion.slow,
              width: avatarSize * 1.1,
              height: avatarSize * 1.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  (_thinking ? NxColors.turquoise : WorldPalette.oracle.primary)
                      .withValues(alpha: 0.45),
                  Colors.transparent,
                ]),
              ),
            ),
            AnimatedSwitcher(
              duration: NxMotion.normal,
              child: OracleAvatar(
                  key: ValueKey<String>('pose_$_pose$avatarSize'),
                  pose: _pose,
                  size: avatarSize),
            ),
            PositionedDirectional(
              bottom: 2,
              child: NxPill(
                label: _thinking
                    ? context.tx('در حال فکر کردن…', 'Thinking…')
                    : context.tx('آفلاین · روی دستگاه', 'Offline · on device'),
                icon: _thinking
                    ? Icons.psychology_rounded
                    : Icons.offline_bolt_rounded,
                color: _thinking ? visual.accent : visual.accentSecondary,
              ),
            ),
          ]),
        ),
        Expanded(
          child: _msgs.isEmpty
              ? _EmptyIntro(onAsk: _ask)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                      NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.md),
                  itemCount: _msgs.length + (_thinking ? 1 : 0),
                  itemBuilder: (BuildContext c, int i) {
                    if (i >= _msgs.length) return const _TypingBubble();
                    final _ChatMsg m = _msgs[i];
                    return _Bubble(msg: m, onAction: (int idx) => _run(m, idx));
                  },
                ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: NxSpace.sm),
            itemBuilder: (BuildContext c, int i) => ActionChip(
              label: Text(chips[i]),
              labelStyle: TextStyle(color: visual.text, fontSize: 12.5),
              backgroundColor: visual.surfaceRaised,
              side: BorderSide(color: visual.border.withValues(alpha: 0.72)),
              onPressed: _thinking ? null : () => _ask(chips[i]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              NxSpace.sm, NxSpace.xs, NxSpace.sm, NxSpace.sm),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            radius: 28,
            child: Row(children: <Widget>[
              IconButton(
                tooltip: context.tx('ورودی صوتی', 'Voice input'),
                onPressed: _showVoiceNotice,
                icon: Icon(Icons.mic_none_rounded, color: visual.accent),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  style: TextStyle(color: visual.text),
                  decoration: InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    hintText: context.tx('از ORACLE بپرس…', 'Ask ORACLE…'),
                    hintStyle: TextStyle(color: visual.muted),
                  ),
                  onSubmitted: _ask,
                ),
              ),
              IconButton.filled(
                tooltip: context.tx('ارسال', 'Send'),
                style: IconButton.styleFrom(
                    backgroundColor: visual.accent,
                    foregroundColor: visual.background),
                onPressed: _thinking ? null : () => _ask(_input.text),
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EmptyIntro extends StatelessWidget {
  const _EmptyIntro({required this.onAsk});
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: <Widget>[
          GlassPanel(
            borderColor: visual.border.withValues(alpha: 0.72),
            child: Column(children: <Widget>[
              Icon(Icons.auto_awesome_rounded, color: visual.accent, size: 24),
              const SizedBox(height: NxSpace.sm),
              Text(
                context.tx('سلام! من ORACLE هستم.', 'Hi! I\'m ORACLE.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: visual.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: NxSpace.sm),
              Text(
                context.tx(
                    'می‌توانم تو را به هر دنیا ببرم، بازی را برایت باز کنم، قوانین را توضیح بدهم، پیشرفتت را بگویم و تنظیمات را عوض کنم. همه‌چیز آفلاین روی همین دستگاه.',
                    'I can take you to any world, open a game, explain rules, report your progress and change settings — all offline on this device.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: visual.muted, height: 1.5),
              ),
            ]),
          ),
        ]);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: NxSpace.sm),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: visual.surfaceRaised,
          border: Border.all(color: visual.border.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: SizedBox(
          width: 36,
          height: 12,
          child: LinearProgressIndicator(
              color: visual.accent, backgroundColor: Colors.transparent),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.onAction});
  final _ChatMsg msg;
  final ValueChanged<int> onAction;

  @override
  Widget build(BuildContext context) {
    final bool user = msg.fromUser;
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color accent = msg.error ? NxColors.danger : visual.accent;
    final String text = user ? msg.textFa : context.tx(msg.textFa, msg.textEn);
    return Align(
      alignment: user
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.only(bottom: NxSpace.sm),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: user
                ? LinearGradient(
                    colors: <Color>[visual.accentSecondary, visual.accent])
                : LinearGradient(colors: <Color>[
                    accent.withValues(alpha: 0.18),
                    visual.surfaceRaised
                  ]),
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(user ? 18 : 4),
              bottomEnd: Radius.circular(user ? 4 : 18),
            ),
            border:
                user ? null : Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(text,
                    style: TextStyle(
                        color: visual.text, height: 1.45, fontSize: 14.5)),
                if (msg.actions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    for (int i = 0; i < msg.actions.length; i++)
                      _actionButton(context, msg.actions[i], i),
                  ]),
                ],
              ]),
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context, OracleAction a, int i) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final bool done = msg.ranIndex == i;
    final String label = context.tx(a.labelFa, a.labelEn);
    final IconData icon = done
        ? Icons.check_circle_rounded
        : a.type == OracleActionType.setting
            ? Icons.tune_rounded
            : Icons.arrow_forward_rounded;
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: done
            ? NxColors.success.withValues(alpha: 0.25)
            : visual.accent.withValues(alpha: 0.18),
        foregroundColor: done ? NxColors.success : visual.accent,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: a.type == OracleActionType.none ? null : () => onAction(i),
      icon: Icon(icon, size: 16),
      label: Text(label.isEmpty ? context.tx('انجام بده', 'Do it') : label),
    );
  }
}
