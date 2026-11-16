import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/nx_theme.dart';
import '../core/mafia_models.dart';
import 'mafia_visuals.dart';

/// Everything a seat on the ring needs to draw itself.
class SeatInfo {
  const SeatInfo({
    required this.id,
    required this.name,
    required this.hue,
    this.emblem,
    this.alive = true,
    this.isYou = false,
    this.role,
    this.votes = 0,
    this.selectable = false,
    this.selected = false,
    this.speaking = false,
    this.defendant = false,
    this.suggested = false,
  });

  final int id;
  final String name;
  final double hue;
  final String? emblem;
  final bool alive;
  final bool isYou;

  /// Role visible to the local viewer (own, teammates, revealed dead).
  final MafiaRole? role;
  final int votes;
  final bool selectable;
  final bool selected;
  final bool speaking;
  final bool defendant;
  final bool suggested;
}

/// Players seated around a holographic table (the local player at the bottom).
class SeatRing extends StatelessWidget {
  const SeatRing(
      {super.key,
      required this.seats,
      required this.center,
      this.onTap,
      required this.isFa});
  final List<SeatInfo> seats;
  final Widget center;
  final ValueChanged<int>? onTap;
  final bool isFa;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth;
        final double h = c.maxHeight;
        final int n = max(1, seats.length);
        final double seat = (min(w, h) / 5.0).clamp(40.0, 70.0).toDouble();
        final double boxW = seat + 26;
        final double boxH = seat + 30;
        final double rx = max(10.0, w / 2 - boxW / 2 - 4);
        final double ry = max(10.0, h / 2 - boxH / 2 - 2);
        final double tableR = min(rx, ry) * 0.62;
        final List<Widget> children = <Widget>[
          Positioned(
            left: w / 2 - tableR,
            top: h / 2 - tableR,
            width: tableR * 2,
            height: tableR * 2,
            child: _Table(child: center),
          ),
        ];
        for (int i = 0; i < seats.length; i++) {
          final double a = pi / 2 + 2 * pi * i / n;
          final double x = w / 2 + rx * cos(a);
          final double y = h / 2 + ry * sin(a);
          final SeatInfo s = seats[i];
          children.add(Positioned(
            left: x - boxW / 2,
            top: y - boxH / 2,
            width: boxW,
            height: boxH,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap:
                  (s.selectable && onTap != null) ? () => onTap!(s.id) : null,
              child: _Seat(info: s, size: seat, isFa: isFa),
            ),
          ));
        }
        return Stack(clipBehavior: Clip.none, children: children);
      }),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: <Color>[
          visual.accentSecondary.withValues(alpha: 0.24),
          visual.accent.withValues(alpha: 0.08),
          Colors.transparent,
        ], stops: const <double>[
          0,
          0.7,
          1
        ]),
        border: Border.all(
            color: visual.accent.withValues(alpha: 0.45), width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: visual.accentSecondary.withValues(alpha: 0.20),
              blurRadius: 30)
        ],
      ),
      child: ClipOval(
          child: Center(
              child: Padding(padding: const EdgeInsets.all(8), child: child))),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.info, required this.size, required this.isFa});
  final SeatInfo info;
  final double size;
  final bool isFa;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    Color? glow;
    if (info.selected) {
      glow = visual.accent;
    } else if (info.speaking) {
      glow = visual.accent;
    } else if (info.defendant) {
      glow = MafiaStyle.blood;
    } else if (info.selectable) {
      glow = NxColors.turquoise;
    } else if (info.isYou) {
      glow = NxColors.violet;
    }
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      SizedBox(
        width: size + 20,
        height: size + 8,
        child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              AnimatedScale(
                scale: info.selected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: CrewAvatar(
                  name: info.name,
                  hue: info.hue,
                  size: size,
                  emblem: info.emblem,
                  dead: !info.alive,
                  glow: info.alive ? glow : null,
                ),
              ),
              if (info.votes > 0)
                Positioned(
                  right: 0,
                  top: -2,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (Widget c, Animation<double> a) =>
                        ScaleTransition(scale: a, child: c),
                    child: Container(
                      key: ValueKey<int>(info.votes),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: MafiaStyle.blood,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                              color: MafiaStyle.blood.withValues(alpha: 0.6),
                              blurRadius: 8)
                        ],
                      ),
                      child: Text('${info.votes}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12)),
                    ),
                  ),
                ),
              if (info.role != null)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF070A22),
                      border:
                          Border.all(color: MafiaStyle.roleColor(info.role!)),
                    ),
                    child: Icon(MafiaStyle.roleIcon(info.role!),
                        size: 12, color: MafiaStyle.roleColor(info.role!)),
                  ),
                ),
              if (info.suggested)
                const Positioned(
                  right: 2,
                  bottom: 0,
                  child:
                      Icon(Icons.gps_fixed, size: 16, color: MafiaStyle.blood),
                ),
              if (info.defendant && info.alive)
                const Positioned(
                  left: 2,
                  top: -2,
                  child: Icon(Icons.gavel, size: 16, color: NxColors.gold),
                ),
            ]),
      ),
      const SizedBox(height: 2),
      Text(
        info.isYou
            ? (isFa ? '${info.name} (تو)' : '${info.name} (you)')
            : info.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: info.alive ? visual.text : visual.muted,
          fontSize: 11,
          fontWeight: info.isYou ? FontWeight.w900 : FontWeight.w600,
          decoration:
              info.alive ? TextDecoration.none : TextDecoration.lineThrough,
        ),
      ),
    ]);
  }
}

/// One chat bubble.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.name,
    required this.text,
    required this.hue,
    this.emblem,
    this.mine = false,
    this.accent,
  });

  final String name;
  final String text;
  final double hue;
  final String? emblem;
  final bool mine;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color a = accent ?? (mine ? visual.accentSecondary : visual.accent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child:
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        CrewAvatar(name: name, hue: hue, size: 28, emblem: emblem),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: a.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: a.withValues(alpha: 0.35)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name,
                      style: TextStyle(
                          color: a, fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(text,
                      style: TextStyle(
                          color: visual.text, fontSize: 13, height: 1.3)),
                ]),
          ),
        ),
      ]),
    );
  }
}

/// Bottom sheet listing the game log the viewer may see.
Future<void> showMafiaLog(
    BuildContext context, List<GameLogEntry> entries, bool isFa) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xF0070A22),
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(isFa ? 'گزارش بازی' : 'Game log',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                          isFa
                              ? 'هنوز چیزی ثبت نشده.'
                              : 'Nothing recorded yet.',
                          style: const TextStyle(color: NxColors.textDim)))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      itemCount: entries.length,
                      itemBuilder: (BuildContext c, int i) {
                        final GameLogEntry e = entries[entries.length - 1 - i];
                        final bool priv = e.visibleTo != null;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(_logIcon(e),
                                    size: 16,
                                    color: priv
                                        ? NxColors.gold
                                        : (e.night
                                            ? NxColors.violet
                                            : NxColors.turquoise)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${isFa ? (e.night ? 'شب' : 'روز') : (e.night ? 'N' : 'D')}${e.day} · ${isFa ? e.fa : e.en}${priv ? (isFa ? '  (خصوصی)' : '  (private)') : ''}',
                                    style: TextStyle(
                                        color:
                                            priv ? NxColors.gold : Colors.white,
                                        fontSize: 13,
                                        height: 1.3),
                                  ),
                                ),
                              ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
    },
  );
}

IconData _logIcon(GameLogEntry e) {
  switch (e.kind) {
    case LogKind.death:
      return Icons.dangerous;
    case LogKind.save:
      return Icons.health_and_safety;
    case LogKind.vote:
      return Icons.how_to_vote;
    case LogKind.speech:
      return Icons.chat_bubble_outline;
    case LogKind.check:
      return Icons.search;
    case LogKind.phase:
      return Icons.nightlight_round;
    case LogKind.info:
      return Icons.info_outline;
  }
}

/// Lets the user pick one player from [options]. Returns null if dismissed.
Future<int?> pickPlayer(
  BuildContext context, {
  required String title,
  required List<int> options,
  required String Function(int id) nameOf,
  required double Function(int id) hueOf,
  required String? Function(int id) emblemOf,
}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: const Color(0xF0070A22),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (final int id in options)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(ctx).pop(id),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0x1AFFFFFF),
                        border: Border.all(color: NxColors.glassBorder),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CrewAvatar(
                                name: nameOf(id),
                                hue: hueOf(id),
                                size: 30,
                                emblem: emblemOf(id)),
                            const SizedBox(width: 8),
                            Text(nameOf(id),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      );
    },
  );
}

/// Pick a role to claim.
Future<MafiaRole?> pickRole(BuildContext context,
    {required String title,
    required bool isFa,
    required List<MafiaRole> roles}) {
  return showModalBottomSheet<MafiaRole>(
    context: context,
    backgroundColor: const Color(0xF0070A22),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final MafiaRole r in roles)
                    GhostButton(
                      label: isFa ? r.labelFa : r.labelEn,
                      icon: MafiaStyle.roleIcon(r),
                      color: MafiaStyle.roleColor(r),
                      onTap: () => Navigator.of(ctx).pop(r),
                    ),
                ]),
          ]),
        ),
      );
    },
  );
}

/// Pick yes/no style choice (e.g. claimed investigation result).
Future<bool?> pickBool(BuildContext context,
    {required String title,
    required String yes,
    required String no,
    Color yesColor = MafiaStyle.blood}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: const Color(0xF0070A22),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              GhostButton(
                  label: yes,
                  color: yesColor,
                  onTap: () => Navigator.of(ctx).pop(true)),
              const SizedBox(width: 12),
              GhostButton(
                  label: no,
                  color: NxColors.turquoise,
                  onTap: () => Navigator.of(ctx).pop(false)),
            ]),
          ]),
        ),
      );
    },
  );
}
