import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../core/game_contract.dart';
import '../core/uno_bot.dart';
import '../core/uno_engine.dart';
import '../core/uno_models.dart';
import 'uno_card_widget.dart';
import 'uno_overlays.dart';
import 'uno_table_widgets.dart';

class _Flight {
  _Flight({
    required this.ctrl,
    required this.from,
    required this.to,
    required this.faceUp,
    required this.toDiscard,
    required this.width,
    this.card,
    this.spin = 0,
  });

  final AnimationController ctrl;
  final Offset from;
  final Offset to;
  final bool faceUp;
  final bool toDiscard;
  final double width;
  final UnoCard? card;
  final double spin;
  bool started = false;
}

/// NX Cards table: hand fan, opponents, piles, bots and pass-and-play.
class UnoGameView extends StatefulWidget {
  const UnoGameView({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<UnoGameView> createState() => _UnoGameViewState();
}

class _UnoGameViewState extends State<UnoGameView>
    with TickerProviderStateMixin {
  late UnoGame _game;
  late math.Random _rng;
  late UnoBotLevel _level;
  late AnimationController _spin;
  late AnimationController _pulse;

  int _cursor = 0;
  int _viewer = 0;
  bool _revealed = true;
  bool _dealt = false;
  bool _finished = false;
  int _pendingDiscard = 0;
  UnoCard? _pickingWild;
  int? _dragId;
  Offset _drag = Offset.zero;
  String? _toast;
  Color _toastColor = NxColors.electricBlue;
  int _toastSerial = 0;

  final List<_Flight> _flights = <_Flight>[];
  final Set<AnimationController> _liveCtrls = <AnimationController>{};
  final GlobalKey _rootKey = GlobalKey();
  final GlobalKey _deckKey = GlobalKey();
  final GlobalKey _discardKey = GlobalKey();
  final GlobalKey _handKey = GlobalKey();
  final Map<int, GlobalKey> _seatKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _cardKeys = <int, GlobalKey>{};

  Timer? _botTimer;
  Timer? _catchTimer;
  Timer? _finishTimer;
  Timer? _toastTimer;
  Timer? _dealTimer;

  GameLaunch get _l => widget.launch;
  bool get _motion => !_l.reducedMotion;

  // ------------------------------------------------------------- online
  NetInbox? _inbox;
  final Set<int> _out = <int>{};
  bool _isRemote(int seat) => _l.isRemoteSeat(seat);
  String _hash() {
    final StringBuffer b = StringBuffer(
        '${_game.current}|${_game.activeColor.index}|${_game.drawnCardId}|');
    for (int p = 0; p < _game.playerCount; p++) {
      b.write('${_game.hands[p].map((UnoCard c) => c.id).join(',')};');
    }
    return hashOf(b.toString());
  }

  void _send(Map<String, dynamic> d) {
    if (_l.online) _l.net!.send(d);
  }

  /// Apply one player's logged action to the engine (same calls the UI makes).
  bool _applyAction(int seat, Map<String, dynamic> d) {
    switch ('${d['a']}') {
      case 'play':
        final int? col = (d['col'] as num?)?.toInt();
        return _game.play(seat, (d['c'] as num).toInt(),
            chosenColor: col == null || col < 0 || col >= UnoColor.values.length
                ? null
                : UnoColor.values[col]);
      case 'draw':
        return _game.draw(seat) != null || true;
      case 'pass':
        return _game.pass(seat);
      case 'nx':
        return _game.callNx(seat);
      case 'catch':
        return _game.catchNx(seat);
    }
    return false;
  }

  /// A player who left: when their turn comes, every phone draws and passes for them (deterministic).
  void _autoOut() {
    int guard = 0;
    while (!_game.isOver && _out.contains(_game.current) && guard < 12) {
      final int cur = _game.current;
      _game.draw(cur);
      if (!_game.isOver && _game.current == cur) _game.pass(cur);
      guard++;
    }
  }

  int? _lastStanding() {
    final List<int> alive = <int>[
      for (int i = 0; i < _game.playerCount; i++)
        if (!_out.contains(i)) i
    ];
    return alive.length == 1 ? alive.first : null;
  }

  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      _cursor = _game.events.length;
      if (_lastStanding() != null) {
        _finishOnline(_lastStanding()!);
        return;
      }
      setState(() {});
      if (!_dealt) {
        _deal();
      } else {
        _afterChange();
      }
      return;
    }
    if (m.isForfeit) {
      _out.add((m.data['seat'] as num?)?.toInt() ?? m.seat);
      if (_lastStanding() != null) {
        if (!m.replay) _finishOnline(_lastStanding()!);
        return;
      }
      _autoOut();
      if (!m.replay) _afterChange();
      return;
    }
    if (m.kind != 'move') return;
    if (m.replay) {
      _dealt = true;
      _applyAction(m.seat, m.data);
      _autoOut();
      return;
    }
    _l.net?.verify(m.seq, m.data['h'] as String?, _hash());
    if (_applyAction(m.seat, m.data)) {
      if ('${m.data['a']}' == 'play' && m.seat != _l.mySeat) {
        _pickingWild = null;
      }
      _autoOut();
      _afterChange();
    }
  }

  void _finishOnline(int winner) {
    if (_finished || !mounted) return;
    _finished = true;
    _l.onFinish(GameResult(
      outcome: winner == _l.mySeat ? GameOutcome.win : GameOutcome.loss,
      winnerSeats: <int>[winner],
      summaryFa: '${_name(winner)} آخرین بازیکن باقی‌مانده بود.',
      summaryEn: '${_name(winner)} was the last player standing.',
    ));
  }

  static const List<String> _botFa = <String>[
    'ربات نوا',
    'ربات اوریون',
    'ربات لیرا',
    'ربات وگا',
    'ربات آلتایر'
  ];
  static const List<String> _botEn = <String>[
    'Nova Bot',
    'Orion Bot',
    'Lyra Bot',
    'Vega Bot',
    'Altair Bot'
  ];
  static const List<Color> _seatColors = <Color>[
    NxColors.electricBlue,
    NxColors.pink,
    NxColors.turquoise,
    NxColors.gold,
    NxColors.violet,
    NxColors.success,
  ];

  @override
  void initState() {
    super.initState();
    final int seed = _l.seed ?? DateTime.now().millisecondsSinceEpoch;
    final int players = math.max(2, math.min(4, _l.playerCount));
    _game = UnoGame(playerCount: players, seed: seed);
    _rng = math.Random(seed ^ 0x5eed);
    switch (_l.difficulty) {
      case BotDifficulty.easy:
        _level = UnoBotLevel.easy;
        break;
      case BotDifficulty.normal:
        _level = UnoBotLevel.normal;
        break;
      case BotDifficulty.hard:
        _level = UnoBotLevel.hard;
        break;
    }
    _spin =
        AnimationController(vsync: this, duration: const Duration(seconds: 14));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    if (_motion) {
      _spin.repeat();
      _pulse.repeat();
    }
    _cursor = _game.events.length;
    _revealed = _l.vsBot; // local: first player taps to reveal their hand
    final NetLink? net = _l.net;
    if (net != null) {
      _viewer = net.mySeat;
      _revealed = true;
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      net.listen(inbox.add,
          onReplayDone: () => inbox.add(const NetMove(
              seq: -1,
              seat: -1,
              kind: 'replayDone',
              data: <String, dynamic>{})));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _deal());
    }
  }

  @override
  void dispose() {
    _inbox?.close();
    _botTimer?.cancel();
    _catchTimer?.cancel();
    _finishTimer?.cancel();
    _toastTimer?.cancel();
    _dealTimer?.cancel();
    for (final AnimationController c in _liveCtrls) {
      c.dispose();
    }
    _liveCtrls.clear();
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- helpers

  String _tx(String fa, String en) => _l.tx(fa, en);

  String _num(int n) {
    if (!_l.isFa) return '$n';
    const String digits = '۰۱۲۳۴۵۶۷۸۹';
    return '$n'.split('').map((String ch) {
      final int? d = int.tryParse(ch);
      return d == null ? ch : digits[d];
    }).join();
  }

  bool _isBot(int seat) => _l.vsBot && seat != 0;

  String _name(int seat) {
    final String? online = _l.netName(seat);
    if (online != null) return online;
    if (seat == 0) {
      final String n = _l.playerName.trim();
      return n.isEmpty ? _tx('شما', 'You') : n;
    }
    if (_l.vsBot) {
      return _tx(_botFa[(seat - 1) % _botFa.length],
          _botEn[(seat - 1) % _botEn.length]);
    }
    return _tx('بازیکن ${_num(seat + 1)}', 'Player ${seat + 1}');
  }

  GlobalKey _seatKey(int seat) =>
      _seatKeys.putIfAbsent(seat, () => GlobalKey());
  GlobalKey _cardKey(int id) => _cardKeys.putIfAbsent(id, () => GlobalKey());

  Offset? _centerOf(GlobalKey key) {
    final BuildContext? ctx = key.currentContext;
    final BuildContext? rootCtx = _rootKey.currentContext;
    if (ctx == null || rootCtx == null) return null;
    final RenderObject? ro = ctx.findRenderObject();
    final RenderObject? rootRo = rootCtx.findRenderObject();
    if (ro is! RenderBox ||
        rootRo is! RenderBox ||
        !ro.hasSize ||
        !ro.attached) {
      return null;
    }
    final Offset g = ro.localToGlobal(ro.size.center(Offset.zero));
    return rootRo.globalToLocal(g);
  }

  Offset _seatCenter(int seat) {
    final Offset? o =
        seat == _viewer ? _centerOf(_handKey) : _centerOf(_seatKey(seat));
    if (o != null) return o;
    final Size s = MediaQuery.of(context).size;
    return Offset(s.width / 2, seat == _viewer ? s.height - 80 : 120);
  }

  Offset _deckCenter() =>
      _centerOf(_deckKey) ??
      Offset(MediaQuery.of(context).size.width * 0.35, 300);
  Offset _discardCenter() =>
      _centerOf(_discardKey) ??
      Offset(MediaQuery.of(context).size.width * 0.6, 300);

  double get _pileCardWidth =>
      math.min(84.0, MediaQuery.of(context).size.width / 4.8);

  void _haptic() {
    if (_l.soundOn) HapticFeedback.selectionClick();
  }

  // ------------------------------------------------------------- flights

  void _fly({
    required Offset from,
    required Offset to,
    required double width,
    UnoCard? card,
    bool faceUp = true,
    bool toDiscard = false,
    int delayMs = 0,
  }) {
    if (!_motion) return;
    final AnimationController ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _l.fancyEffects ? 420 : 260),
    );
    _liveCtrls.add(ctrl);
    final _Flight f = _Flight(
      ctrl: ctrl,
      from: from,
      to: to,
      faceUp: faceUp,
      toDiscard: toDiscard,
      width: width,
      card: card,
      spin: (_rng.nextDouble() - 0.5) * 0.9,
    );
    _flights.add(f);
    if (toDiscard) _pendingDiscard++;
    ctrl.addStatusListener((AnimationStatus s) {
      if (s != AnimationStatus.completed) return;
      _liveCtrls.remove(ctrl);
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      if (!mounted) return;
      setState(() {
        _flights.remove(f);
        if (f.toDiscard && _pendingDiscard > 0) _pendingDiscard--;
      });
    });
    void start() {
      if (!mounted || !_liveCtrls.contains(ctrl)) return;
      setState(() => f.started = true);
      ctrl.forward();
    }

    if (delayMs <= 0) {
      f.started = true;
      ctrl.forward();
    } else {
      Future<void>.delayed(Duration(milliseconds: delayMs), start);
    }
  }

  void _deal() {
    if (!mounted) return;
    if (!_motion || !_l.fancyEffects) {
      setState(() => _dealt = true);
      _afterChange();
      return;
    }
    final Offset deck = _deckCenter();
    int k = 0;
    for (int r = 0; r < 7; r++) {
      for (int p = 0; p < _game.playerCount; p++) {
        _fly(
            from: deck,
            to: _seatCenter(p),
            width: 46,
            faceUp: false,
            delayMs: k * 38);
        k++;
      }
    }
    _dealTimer = Timer(Duration(milliseconds: k * 38 + 450), () {
      if (!mounted) return;
      setState(() => _dealt = true);
      _afterChange();
    });
  }

  // ------------------------------------------------------------- events

  void _showToast(String text, Color color) {
    _toastTimer?.cancel();
    setState(() {
      _toast = text;
      _toastColor = color;
      _toastSerial++;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  /// Animates every engine event since the last call.
  void _consume() {
    final List<UnoEvent> evs = _game.events;
    final List<String> notes = <String>[];
    Color noteColor = NxColors.electricBlue;
    int drawDelay = 0;
    while (_cursor < evs.length) {
      final UnoEvent e = evs[_cursor++];
      switch (e.type) {
        case UnoEventType.play:
          final UnoCard card = e.card!;
          Offset from = _seatCenter(e.player);
          if (e.player == _viewer && _revealed) {
            from = _centerOf(_cardKey(card.id)) ?? from;
          }
          _fly(
              from: from,
              to: _discardCenter(),
              width: _pileCardWidth,
              card: card,
              toDiscard: true);
          drawDelay = 260;
          _haptic();
          break;
        case UnoEventType.draw:
          final Offset deck = _deckCenter();
          final Offset to = _seatCenter(e.player);
          final int visual = math.min(e.count, 4);
          for (int i = 0; i < visual; i++) {
            _fly(
                from: deck,
                to: to,
                width: 50,
                faceUp: false,
                delayMs: drawDelay + i * 110);
          }
          drawDelay += visual * 110;
          if (e.count >= 2) {
            notes.add(_tx('${_name(e.player)} +${_num(e.count)} کارت',
                '${_name(e.player)} draws ${e.count}'));
          }
          break;
        case UnoEventType.skip:
          notes.add(_tx(
              'نوبت ${_name(e.player)} پرید', '${_name(e.player)} is skipped'));
          noteColor = NxColors.pink;
          break;
        case UnoEventType.reverse:
          notes.add(_tx('جهت بازی برعکس شد', 'Direction reversed'));
          noteColor = NxColors.turquoise;
          break;
        case UnoEventType.colorChosen:
          final UnoColor c = e.color!;
          notes.add(_tx('رنگ: ${unoColorName(c, true)}',
              'Colour: ${unoColorName(c, false)}'));
          noteColor = unoColorValue(c);
          break;
        case UnoEventType.nxCall:
          notes.add(_tx('${_name(e.player)}: NX!', '${_name(e.player)}: NX!'));
          noteColor = NxColors.gold;
          if (_l.soundOn) HapticFeedback.mediumImpact();
          break;
        case UnoEventType.nxCaught:
          notes.add(_tx('${_name(e.player)} NX نگفت! +۲ جریمه',
              '${_name(e.player)} forgot NX! +2 penalty'));
          noteColor = NxColors.danger;
          if (_l.soundOn) HapticFeedback.heavyImpact();
          break;
        case UnoEventType.reshuffle:
          notes.add(_tx('دسته بُر خورد', 'Discard pile reshuffled'));
          break;
        case UnoEventType.win:
          notes.add(_tx('${_name(e.player)} برد!', '${_name(e.player)} wins!'));
          noteColor = NxColors.gold;
          break;
        case UnoEventType.deal:
        case UnoEventType.pass:
          break;
      }
    }
    if (notes.isNotEmpty) _showToast(notes.join('  ·  '), noteColor);
  }

  void _afterChange() {
    if (!mounted) return;
    if (_l.online) _autoOut();
    _consume();
    setState(() {});
    if (_game.isOver) {
      _botTimer?.cancel();
      _catchTimer?.cancel();
      _finishTimer ??= Timer(const Duration(milliseconds: 2200), _finish);
      return;
    }
    if (!_dealt) return;
    _maybeBotCatchesHuman();
    final int cur = _game.current;
    _l.net?.turnSeat = cur;
    if (_isBot(cur)) {
      _scheduleBot();
      return;
    }
    if (_l.online) return;
    if (!_l.vsBot && cur != _viewer) {
      setState(() {
        _viewer = cur;
        _revealed = false;
        _dragId = null;
      });
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    final int w = _game.winner ?? 0;
    final int pts = _game.scoreFor(w);
    final bool iWon = w == _l.mySeat;
    _l.onFinish(GameResult(
      outcome: iWon ? GameOutcome.win : GameOutcome.loss,
      score: iWon ? pts : 0,
      opponentScore: iWon ? 0 : pts,
      winnerSeats: <int>[w],
      scores: <int>[
        for (int p = 0; p < _game.playerCount; p++) p == w ? pts : 0
      ],
      summaryFa:
          '${_name(w)} همه کارت‌ها را زمین گذاشت و ${_num(pts)} امتیاز گرفت.',
      summaryEn: '${_name(w)} emptied their hand and scored $pts points.',
    ));
  }

  // ------------------------------------------------------------- bots

  void _scheduleBot() {
    _botTimer?.cancel();
    final int ms = (_motion ? 800 : 450) + _rng.nextInt(_motion ? 700 : 300);
    _botTimer = Timer(Duration(milliseconds: ms), _botTurn);
  }

  void _maybeBotCatchesHuman() {
    if (!_l.vsBot || _game.vulnerable != 0) return;
    if (_catchTimer != null && _catchTimer!.isActive) return;
    _catchTimer = Timer(Duration(milliseconds: 1400 + _rng.nextInt(900)), () {
      if (!mounted || _game.isOver || _game.vulnerable != 0) return;
      if (_rng.nextDouble() < UnoBot.catchChance(_level)) {
        final int catcher = 1 + _rng.nextInt(_game.playerCount - 1);
        _game.catchNx(catcher);
        _afterChange();
      }
    });
  }

  void _botTurn() {
    if (!mounted || _game.isOver) return;
    final int seat = _game.current;
    if (!_isBot(seat)) return;
    final int? v = _game.vulnerable;
    if (v != null &&
        v != seat &&
        _rng.nextDouble() < UnoBot.catchChance(_level)) {
      _game.catchNx(seat);
    }
    if (_game.drawnCardId != null) {
      _botResolveDrawn(seat);
      return;
    }
    final UnoBotMove move = UnoBot.decide(_game, seat, _level, _rng);
    if (move.draw) {
      _game.draw(seat);
      if (_game.drawnCardId != null && _game.current == seat) {
        _consume();
        setState(() {});
        _botTimer = Timer(Duration(milliseconds: _motion ? 650 : 300),
            () => _botResolveDrawn(seat));
        return;
      }
    } else {
      if (_game.hands[seat].length == 2 &&
          _rng.nextDouble() < UnoBot.nxCallChance(_level)) {
        _game.callNx(seat);
      }
      _game.play(seat, move.cardId!, chosenColor: move.color);
    }
    _afterChange();
  }

  void _botResolveDrawn(int seat) {
    if (!mounted || _game.isOver || _game.current != seat) return;
    final int? id = _game.drawnCardId;
    if (id == null) {
      _afterChange();
      return;
    }
    final UnoCard? c = _game.cardInHand(seat, id);
    if (c != null && UnoBot.playDrawn(_game, seat, _level, _rng)) {
      if (_game.hands[seat].length == 2 &&
          _rng.nextDouble() < UnoBot.nxCallChance(_level)) {
        _game.callNx(seat);
      }
      final UnoColor? color = c.isWild
          ? UnoBot.bestColor(_game, seat, _rng, excludingCardId: c.id)
          : null;
      _game.play(seat, c.id, chosenColor: color);
    } else {
      _game.pass(seat);
    }
    _afterChange();
  }

  // ------------------------------------------------------------- human

  bool get _canAct =>
      _dealt &&
      !_game.isOver &&
      _revealed &&
      _pickingWild == null &&
      _game.current == _viewer &&
      !_isBot(_viewer) &&
      !_isRemote(_viewer);

  void _tapCard(UnoCard c) {
    if (!_canAct) return;
    if (!_game.legalCards(_viewer).contains(c)) {
      if (c.kind == UnoKind.wildDrawFour && _game.drawnCardId == null) {
        _showToast(
            _tx('+۴ فقط وقتی مجاز است که کارت هم‌رنگ نداشته باشی',
                '+4 is only allowed when you hold no card of the active colour'),
            NxColors.danger);
      } else {
        _showToast(_tx('این کارت قابل بازی نیست', "That card can't be played"),
            NxColors.danger);
      }
      return;
    }
    if (c.isWild) {
      setState(() => _pickingWild = c);
      return;
    }
    final String h = _hash();
    if (_game.play(_viewer, c.id)) {
      _send(<String, dynamic>{'a': 'play', 'c': c.id, 'h': h});
    }
    _afterChange();
  }

  void _pickColor(UnoColor color) {
    final UnoCard? c = _pickingWild;
    setState(() => _pickingWild = null);
    if (c == null) return;
    final String h = _hash();
    if (_game.play(_viewer, c.id, chosenColor: color)) {
      _send(<String, dynamic>{
        'a': 'play',
        'c': c.id,
        'col': color.index,
        'h': h
      });
    }
    _afterChange();
  }

  void _tapDeck() {
    if (!_canAct || !_game.canDraw(_viewer)) return;
    final String h = _hash();
    _game.draw(_viewer);
    _send(<String, dynamic>{'a': 'draw', 'h': h});
    _afterChange();
  }

  void _pass() {
    if (!_canAct) return;
    final String h = _hash();
    if (_game.pass(_viewer)) _send(<String, dynamic>{'a': 'pass', 'h': h});
    _afterChange();
  }

  void _callNx() {
    final String h = _hash();
    if (_game.callNx(_viewer)) {
      _send(<String, dynamic>{'a': 'nx', 'h': h});
      _afterChange();
    }
  }

  void _catch() {
    final String h = _hash();
    if (_game.catchNx(_viewer)) {
      _send(<String, dynamic>{'a': 'catch', 'h': h});
      _afterChange();
    }
  }

  List<UnoCard> _sortedHand(int seat) {
    final List<UnoCard> h = List<UnoCard>.of(_game.hands[seat]);
    int colorIdx(UnoCard c) => c.color == null ? 9 : c.color!.index;
    h.sort((UnoCard a, UnoCard b) {
      final int ca = colorIdx(a).compareTo(colorIdx(b));
      if (ca != 0) return ca;
      final int k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      return a.number.compareTo(b.number);
    });
    return h;
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        key: _rootKey,
        fit: StackFit.expand,
        children: <Widget>[
          UnoTableBackground(
              fancy: _l.fancyEffects, accent: unoColorValue(_game.activeColor)),
          SafeArea(
            child: Column(
              children: <Widget>[
                _buildHud(),
                _buildOpponents(),
                Expanded(child: _buildCenter()),
                _buildActionBar(),
                _buildHand(),
              ],
            ),
          ),
          _buildToast(),
          for (final _Flight f in _flights)
            if (f.started) _buildFlight(f),
          if (_pickingWild != null)
            Positioned.fill(
              child: UnoColorPicker(
                isFa: _l.isFa,
                onPick: _pickColor,
                onCancel: () => setState(() => _pickingWild = null),
              ),
            ),
          if (!_revealed && !_game.isOver)
            Positioned.fill(child: _buildPassScreen()),
          if (_game.isOver) Positioned.fill(child: _buildWinOverlay()),
        ],
      ),
    );
  }

  Widget _buildHud() {
    final NxThemeColors visual = NxThemeColors.of(context);
    final bool myTurn = _game.current == _viewer && !_game.isOver;
    final Color activeColor = unoColorValue(_game.activeColor);
    final String turn = _game.isOver
        ? _tx('پایان بازی', 'Game complete')
        : myTurn
            ? _tx('نوبت تو', 'Your turn')
            : _tx('نوبت ${_name(_game.current)}',
                "${_name(_game.current)}'s turn");
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: GlassPanel(
        blur: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        radius: NxRadius.md,
        borderColor: myTurn ? visual.accent : visual.border,
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (myTurn ? visual.accent : visual.accentSecondary)
                    .withValues(alpha: 0.16),
                border: Border.all(
                    color: myTurn ? visual.accent : visual.accentSecondary),
              ),
              child: Icon(
                  myTurn
                      ? Icons.play_arrow_rounded
                      : Icons.hourglass_top_rounded,
                  color: myTurn ? visual.accent : visual.accentSecondary,
                  size: 21),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(turn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection:
                          _l.isFa ? TextDirection.rtl : TextDirection.ltr,
                      style: TextStyle(
                          color: visual.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                  Text(
                      _tx(
                          'جهت ${_game.direction == 1 ? 'ساعت‌گرد' : 'پادساعت‌گرد'}',
                          _game.direction == 1
                              ? 'Clockwise'
                              : 'Counter-clockwise'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: visual.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(9, 5, 9, 5),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: activeColor.withValues(alpha: 0.72)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(Icons.style_rounded, size: 14, color: visual.text),
                const SizedBox(width: 5),
                Text(_num(_game.hands[_viewer].length),
                    style: TextStyle(
                        color: visual.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 6),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: activeColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8), width: 1.2),
              ),
              child: Icon(Icons.palette_rounded,
                  size: 14,
                  color: activeColor.computeLuminance() > 0.55
                      ? Colors.black87
                      : Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponents() {
    final List<int> seats = <int>[];
    for (int i = 1; i < _game.playerCount; i++) {
      seats.add((_viewer + i) % _game.playerCount);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          for (final int s in seats)
            UnoSeatView(
              key: _seatKey(s),
              name: _name(s),
              cardCount: _game.hands[s].length,
              active: _game.current == s && !_game.isOver,
              isBot: _isBot(s),
              nxSafe: _game.vulnerable != s,
              pulse: _pulse,
              seatColor: _seatColors[s % _seatColors.length],
              visible: _dealt,
            ),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    final double cw = _pileCardWidth;
    final int topIndex =
        math.max(0, _game.discard.length - 1 - _pendingDiscard);
    final List<Widget> pile = <Widget>[];
    for (int i = math.max(0, topIndex - 2); i <= topIndex; i++) {
      final UnoCard c = _game.discard[i];
      final double ang = (((c.id * 37) % 21) - 10) * math.pi / 180;
      pile.add(Transform.rotate(
        angle: ang,
        child: UnoCardView(
          width: cw,
          card: c,
          wildColor: i == topIndex && c.isWild ? _game.activeColor : null,
          glow: i == topIndex && _l.fancyEffects,
        ),
      ));
    }
    final Color active = unoColorValue(_game.activeColor);
    final bool myDrawTurn = _canAct && _game.canDraw(_viewer);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double ringW = math.min(box.maxWidth * 0.92, 420.0);
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            UnoDirectionRing(
                animation: _spin,
                direction: _game.direction,
                color: active,
                size: ringW),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  GestureDetector(
                    onTap: _tapDeck,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          key: _deckKey,
                          width: cw + 6,
                          height: cw / kUnoCardAspect + 6,
                          child: Stack(
                            children: <Widget>[
                              Positioned(
                                  left: 6,
                                  top: 6,
                                  child: UnoCardView(width: cw, faceUp: false)),
                              Positioned(
                                  left: 3,
                                  top: 3,
                                  child: UnoCardView(width: cw, faceUp: false)),
                              Positioned(
                                  left: 0,
                                  top: 0,
                                  child: UnoCardView(
                                      width: cw,
                                      faceUp: false,
                                      glow: myDrawTurn)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          myDrawTurn
                              ? _tx('برداشتن (${_num(_game.drawPile.length)})',
                                  'Draw (${_game.drawPile.length})')
                              : _num(_game.drawPile.length),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: myDrawTurn
                                ? NxColors.iceWhite
                                : NxColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: math.min(48.0, box.maxWidth * 0.1)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        key: _discardKey,
                        width: cw + 10,
                        height: cw / kUnoCardAspect + 10,
                        child:
                            Stack(alignment: Alignment.center, children: pile),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: NxMotion.normal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: active.withValues(alpha: 0.25),
                          border: Border.all(color: active),
                        ),
                        child: Text(
                          unoColorName(_game.activeColor, _l.isFa),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: NxColors.iceWhite),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionBar() {
    final List<Widget> buttons = <Widget>[];
    if (_revealed && _dealt && !_game.isOver) {
      if (_game.canCallNx(_viewer)) {
        buttons.add(UnoActionButton(
            label: 'NX!',
            color: NxColors.gold,
            icon: Icons.campaign_rounded,
            onTap: _callNx));
      }
      final int? v = _game.vulnerable;
      if (v != null && v != _viewer) {
        buttons.add(UnoActionButton(
          label: _tx('گرفتمت! (${_name(v)})', 'Catch ${_name(v)}!'),
          color: NxColors.danger,
          icon: Icons.back_hand_rounded,
          onTap: _catch,
        ));
      }
      if (_canAct && _game.drawnCardId != null) {
        buttons.add(UnoActionButton(
          label: _tx('نگه دار و رد کن', 'Keep & pass'),
          color: NxColors.turquoise,
          icon: Icons.skip_next_rounded,
          onTap: _pass,
        ));
      }
    }
    String status = '';
    if (_dealt && !_game.isOver) {
      if (_game.current == _viewer && _revealed) {
        status = _game.drawnCardId != null
            ? _tx('کارت کشیده‌شده را بازی کن یا نگه دار',
                'Play the drawn card or keep it')
            : (_game.hasLegalPlay(_viewer)
                ? _tx('نوبت توست — کارت را بزن یا به بالا بکش',
                    'Your turn — tap or swipe a card up')
                : _tx('کارت مناسب نداری — از دسته بردار',
                    'No match — draw from the deck'));
      } else {
        status = _tx(
            'نوبت ${_name(_game.current)}…', "${_name(_game.current)}'s turn…");
      }
    }
    return SizedBox(
      height: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedSwitcher(
            duration: NxMotion.fast,
            child: Text(
              status,
              key: ValueKey<String>(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: _l.isFa ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                  fontSize: 12,
                  color: NxColors.textDim,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < buttons.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 10),
                  buttons[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHand() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double width = box.maxWidth;
        final List<UnoCard> hand = _sortedHand(_viewer);
        final int n = hand.length;
        final double cw = math.min(88.0, width / 5.0);
        final double ch = cw / kUnoCardAspect;
        final double avail = width - 36 - cw;
        final double step = n <= 1 ? 0 : math.min(cw * 0.7, avail / (n - 1));
        final double total = step * (n - 1) + cw;
        final double startX = (width - total) / 2;
        final Set<int> legal = _canAct
            ? _game.legalCards(_viewer).map((UnoCard c) => c.id).toSet()
            : <int>{};
        final double spread = math.min(0.36, 0.04 * n);
        final bool show = _revealed && _dealt;
        final List<Widget> cards = <Widget>[];
        for (int i = 0; i < n; i++) {
          final UnoCard c = hand[i];
          final double t = n <= 1 ? 0 : (i / (n - 1)) * 2 - 1;
          final bool isLegal = legal.contains(c.id);
          final bool dragging = _dragId == c.id;
          final double lift =
              isLegal ? (_game.drawnCardId == c.id ? 30 : 16) : 0;
          final Offset d = dragging ? _drag : Offset.zero;
          cards.add(AnimatedPositioned(
            key: ValueKey<int>(c.id),
            duration: dragging || !_motion ? Duration.zero : NxMotion.normal,
            curve: NxMotion.curve,
            left: startX + i * step + d.dx,
            top: 28 + t * t * 16 - lift + d.dy,
            child: GestureDetector(
              onTap: () => _tapCard(c),
              onPanStart: (_) {
                if (!_canAct) return;
                setState(() {
                  _dragId = c.id;
                  _drag = Offset.zero;
                });
              },
              onPanUpdate: (DragUpdateDetails u) {
                if (_dragId != c.id) return;
                setState(() => _drag += u.delta);
              },
              onPanEnd: (DragEndDetails e) {
                if (_dragId != c.id) return;
                final bool up =
                    _drag.dy < -60 || e.velocity.pixelsPerSecond.dy < -700;
                setState(() {
                  _dragId = null;
                  _drag = Offset.zero;
                });
                if (up) _tapCard(c);
              },
              onPanCancel: () {
                if (_dragId == c.id) {
                  setState(() {
                    _dragId = null;
                    _drag = Offset.zero;
                  });
                }
              },
              child: Transform.rotate(
                angle: dragging ? 0 : t * spread / 2,
                alignment: Alignment.bottomCenter,
                child: UnoCardView(
                  key: _cardKey(c.id),
                  width: cw,
                  card: c,
                  faceUp: show,
                  glow: isLegal && show,
                  dim: _canAct && !isLegal,
                ),
              ),
            ),
          ));
        }
        return AnimatedOpacity(
          opacity: _dealt ? 1 : 0,
          duration: NxMotion.normal,
          child: SizedBox(
            key: _handKey,
            width: width,
            height: ch + 56,
            child: Stack(clipBehavior: Clip.none, children: cards),
          ),
        );
      },
    );
  }

  Widget _buildFlight(_Flight f) {
    final double h = f.width / kUnoCardAspect;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: f.ctrl,
          builder: (BuildContext context, Widget? child) {
            final double t = Curves.easeInOutCubic.transform(f.ctrl.value);
            final Offset base = Offset.lerp(f.from, f.to, t)!;
            final double arc = math.sin(math.pi * t) * -40;
            final Offset p = base + Offset(0, arc);
            final double scale = 1.0 + math.sin(math.pi * t) * 0.12;
            return Stack(
              children: <Widget>[
                Positioned(
                  left: p.dx - f.width / 2,
                  top: p.dy - h / 2,
                  child: Transform.rotate(
                    angle: f.spin * (1 - t) + (f.toDiscard ? 0 : f.spin * t),
                    child: Transform.scale(scale: scale, child: child),
                  ),
                ),
              ],
            );
          },
          child: UnoCardView(
              width: f.width,
              card: f.card,
              faceUp: f.faceUp,
              glow: f.faceUp && _l.fancyEffects),
        ),
      ),
    );
  }

  Widget _buildToast() {
    return Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(context).padding.top + 196,
      child: UnoToast(
          text: _toast,
          color: _toastColor,
          serial: _toastSerial,
          isFa: _l.isFa),
    );
  }

  Widget _buildPassScreen() {
    return UnoPassScreen(
      isFa: _l.isFa,
      color: _seatColors[_viewer % _seatColors.length],
      title: _tx('دستگاه را به ${_name(_viewer)} بده',
          'Pass the device to ${_name(_viewer)}'),
      subtitle: _tx('بقیه نگاه نکنند! کارت‌ها مخفی هستند.',
          'Others look away — hands are hidden.'),
      button: _tx('من ${_name(_viewer)} هستم — نمایش کارت‌ها',
          "I'm ${_name(_viewer)} — show my hand"),
      onReveal: () {
        setState(() => _revealed = true);
        _afterChange();
      },
    );
  }

  Widget _buildWinOverlay() {
    final int w = _game.winner ?? 0;
    final int pts = _game.scoreFor(w);
    return UnoWinOverlay(
      isFa: _l.isFa,
      title: _tx('${_name(w)} برنده شد!', '${_name(w)} wins!'),
      subtitle: _tx('${_num(pts)} امتیاز از کارت‌های حریفان',
          "$pts points from opponents' cards"),
    );
  }
}
