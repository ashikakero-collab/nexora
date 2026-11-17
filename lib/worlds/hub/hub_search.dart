import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/nx_theme.dart';
import '../../games/game_registry.dart';
import '../world_registry.dart';

class _Hit {
  const _Hit(this.title, this.subtitle, this.icon, this.color, this.route);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}

/// Global search across worlds, games and features (STEP_12).
class HubSearchDelegate extends SearchDelegate<void> {
  HubSearchDelegate({required this.isFa})
      : super(searchFieldLabel: isFa ? 'جستجو…' : 'Search…');
  final bool isFa;

  List<_Hit> _all() {
    final hits = <_Hit>[
      for (final w in kWorlds)
        _Hit(isFa ? w.nameFa : w.name, isFa ? w.taglineFa : w.taglineEn, w.icon,
            w.palette.primary, '/world/${w.id}'),
      for (final g in kGames)
        _Hit(isFa ? g.nameFa : g.nameEn, isFa ? g.taglineFa : g.taglineEn,
            Icons.sports_esports_rounded, g.accent, '/arcade/${g.id}'),
      _Hit(
          isFa ? 'تنظیمات' : 'Settings',
          isFa ? 'کیفیت، کاهش حرکت، زبان' : 'Quality, reduced motion, language',
          Icons.settings_rounded,
          NxColors.iceWhite,
          '/settings'),
      _Hit(
          isFa ? 'جایزه‌ی روزانه و چالش‌ها' : 'Daily reward & challenges',
          isFa ? 'در مدار شخصی' : 'In Personal Orbit',
          Icons.card_giftcard_rounded,
          NxColors.gold,
          '/world/personal_orbit'),
      _Hit(
          isFa ? 'دستاوردها' : 'Achievements',
          isFa ? 'نشان‌ها و جام‌ها' : 'Badges & trophies',
          Icons.emoji_events_rounded,
          NxColors.gold,
          '/world/personal_orbit'),
    ];
    return hits;
  }

  List<_Hit> _filter() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _all();
    return _all()
        .where((h) =>
            h.title.toLowerCase().contains(q) ||
            h.subtitle.toLowerCase().contains(q) ||
            h.route.contains(q))
        .toList();
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final t = Theme.of(context);
    final visual = NxThemeColors.of(context);
    return t.copyWith(
      scaffoldBackgroundColor: visual.background,
      appBarTheme: t.appBarTheme.copyWith(
          backgroundColor: visual.backgroundMid, foregroundColor: visual.text),
      inputDecorationTheme:
          t.inputDecorationTheme.copyWith(fillColor: visual.surfaceRaised),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null), icon: const BackButtonIcon());

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final hits = _filter();
    final visual = NxThemeColors.of(context);
    if (hits.isEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: () {
            final q = query;
            close(context, null);
            context.push('/oracle?q=${Uri.encodeComponent(q)}');
          },
          icon: Icon(Icons.blur_circular_rounded, color: visual.accent),
          label:
              Text(isFa ? 'از ORACLE بپرس: «$query»' : 'Ask ORACLE: "$query"'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: hits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final h = hits[i];
        return Material(
          color: visual.surface,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: visual.border.withValues(alpha: 0.48))),
            leading: CircleAvatar(
                backgroundColor: h.color.withValues(alpha: 0.14),
                child: Icon(h.icon, color: h.color)),
            title: Text(h.title,
                style:
                    TextStyle(color: visual.text, fontWeight: FontWeight.w800)),
            subtitle: Text(h.subtitle, style: TextStyle(color: visual.muted)),
            trailing: Icon(Icons.arrow_forward_ios_rounded,
                size: 15, color: visual.muted),
            onTap: () {
              close(context, null);
              context.push(h.route);
            },
          ),
        );
      },
    );
  }
}
