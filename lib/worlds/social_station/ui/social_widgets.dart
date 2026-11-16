import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../orbit_network/models/arcade_refs.dart';
import '../models/social_models.dart';

const WorldPalette kSocialPalette = WorldPalette.social;

/// The current explorer acting in SOCIAL STATION.
class SocialMe {
  const SocialMe(this.id, this.name);
  final String id;
  final String name;
}

SocialMe socialMe(WidgetRef ref) {
  final ProfileService p = ref.read(profileProvider);
  final String n = p.username.trim();
  return SocialMe(p.explorerId, n.isEmpty ? 'Explorer' : n);
}

String kindLabel(BuildContext context, CommunityKind k) {
  switch (k) {
    case CommunityKind.public:
      return context.tx('عمومی', 'Public');
    case CommunityKind.private:
      return context.tx('خصوصی', 'Private');
    case CommunityKind.topic:
      return context.tx('موضوعی', 'Topic');
    case CommunityKind.game:
      return context.tx('بازی', 'Game');
    case CommunityKind.tournament:
      return context.tx('مسابقه', 'Tournament');
  }
}

IconData kindIcon(CommunityKind k) {
  switch (k) {
    case CommunityKind.public:
      return Icons.public_rounded;
    case CommunityKind.private:
      return Icons.lock_rounded;
    case CommunityKind.topic:
      return Icons.tag_rounded;
    case CommunityKind.game:
      return Icons.sports_esports_rounded;
    case CommunityKind.tournament:
      return Icons.emoji_events_rounded;
  }
}

Color kindColor(CommunityKind k) {
  switch (k) {
    case CommunityKind.public:
      return kSocialPalette.primary;
    case CommunityKind.private:
      return NxColors.violet;
    case CommunityKind.topic:
      return NxColors.turquoise;
    case CommunityKind.game:
      return kSocialPalette.secondary;
    case CommunityKind.tournament:
      return NxColors.gold;
  }
}

String roleLabel(BuildContext context, CommunityRole r) {
  switch (r) {
    case CommunityRole.owner:
      return context.tx('مالک', 'Owner');
    case CommunityRole.admin:
      return context.tx('مدیر', 'Admin');
    case CommunityRole.moderator:
      return context.tx('ناظر', 'Moderator');
    case CommunityRole.member:
      return context.tx('عضو', 'Member');
  }
}

Color roleColor(CommunityRole r) {
  switch (r) {
    case CommunityRole.owner:
      return NxColors.gold;
    case CommunityRole.admin:
      return NxColors.pink;
    case CommunityRole.moderator:
      return NxColors.turquoise;
    case CommunityRole.member:
      return NxColors.textDim;
  }
}

String gameLabel(BuildContext context, String? gameId) {
  final ArcadeGameRef? g = arcadeGame(gameId);
  if (g == null) return context.tx('بدون بازی', 'No game');
  return context.tx(g.nameFa, g.nameEn);
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String formatDateTime(DateTime d) => '${d.year}/${_two(d.month)}/${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';

String formatCountdown(BuildContext context, Duration d) {
  final int days = d.inDays;
  final int h = d.inHours % 24;
  final int m = d.inMinutes % 60;
  final int s = d.inSeconds % 60;
  if (days > 0) return context.tx('$days روز و $h ساعت', '${days}d ${h}h');
  return '${_two(d.inHours)}:${_two(m)}:${_two(s)}';
}

/// Club badge with a soft glow ring.
class CommunityBadge extends StatelessWidget {
  const CommunityBadge({super.key, required this.badgeId, this.size = 56, this.glow = kSocialPaletteGlow});
  final String badgeId;
  final double size;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: <Color>[glow.withValues(alpha: 0.35), Colors.transparent]),
        boxShadow: <BoxShadow>[BoxShadow(color: glow.withValues(alpha: 0.30), blurRadius: size * 0.35)],
      ),
      padding: EdgeInsets.all(size * 0.06),
      child: Image.asset(
        AppAssets.clubBadge(badgeId),
        width: size,
        height: size,
        cacheWidth: (size * 2.5).round(),
        fit: BoxFit.contain,
        errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
            Icon(Icons.shield_rounded, size: size * 0.8, color: glow),
      ),
    );
  }
}

const Color kSocialPaletteGlow = Color(0xFF4FD1FF);

class RolePill extends StatelessWidget {
  const RolePill({super.key, required this.role});
  final CommunityRole role;

  @override
  Widget build(BuildContext context) => NxPill(
        label: roleLabel(context, role),
        color: roleColor(role),
        icon: role == CommunityRole.owner
            ? Icons.workspace_premium_rounded
            : (role == CommunityRole.admin
                ? Icons.admin_panel_settings_rounded
                : (role == CommunityRole.moderator ? Icons.shield_moon_rounded : Icons.person_rounded)),
      );
}

class SocialEmpty extends StatelessWidget {
  const SocialEmpty({super.key, required this.icon, required this.fa, required this.en, this.action});
  final IconData icon;
  final String fa;
  final String en;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NxSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 56, color: kSocialPalette.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(context.tx(fa, en), textAlign: TextAlign.center, style: const TextStyle(color: NxColors.textDim, height: 1.5)),
          if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}

/// Live countdown that ticks every second until [target].
class CountdownText extends StatefulWidget {
  const CountdownText({super.key, required this.target, this.style});
  final DateTime target;
  final TextStyle? style;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!DateTime.now().isBefore(widget.target)) _t?.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Duration d = widget.target.difference(DateTime.now());
    final String text = d.isNegative ? context.tx('شروع شده', 'Started') : formatCountdown(context, d);
    return Text(text, style: widget.style ?? const TextStyle(fontWeight: FontWeight.w900));
  }
}

/// Section title used inside tabs.
class SocialSectionTitle extends StatelessWidget {
  const SocialSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, NxSpace.md, 4, NxSpace.sm),
      child: Row(children: <Widget>[
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: <Color>[kSocialPalette.primary, kSocialPalette.secondary]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

void socialSnack(BuildContext context, String fa, String en) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tx(fa, en))));
}

/// Asks for a single line of text.
Future<String?> askText(BuildContext context,
    {required String titleFa, required String titleEn, String hintFa = '', String hintEn = '', int maxLength = 40, int maxLines = 1}) {
  final TextEditingController ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      title: Text(c.tx(titleFa, titleEn)),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        decoration: InputDecoration(hintText: c.tx(hintFa, hintEn)),
        onSubmitted: maxLines == 1 ? (String v) => Navigator.pop(c, v) : null,
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(c), child: Text(c.tx('انصراف', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(c.tx('تأیید', 'OK'))),
      ],
    ),
  );
}

Future<bool> confirmAction(BuildContext context, {required String fa, required String en}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      content: Text(c.tx(fa, en)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tx('انصراف', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: NxColors.danger),
          onPressed: () => Navigator.pop(c, true),
          child: Text(c.tx('بله', 'Yes')),
        ),
      ],
    ),
  );
  return ok == true;
}
