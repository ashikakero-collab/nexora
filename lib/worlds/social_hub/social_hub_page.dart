import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../nova_gallery/nova_gallery_page.dart';
import '../orbit_network/orbit_network_page.dart';
import '../social_station/social_station_page.dart';

/// CHAT + MEDIA: one social hub with tabs — Feed & stories (Nova Gallery), Messages (Orbit Network),
/// Friends (Social Station). Each tab is the existing Supabase-backed screen.
class SocialHubPage extends StatefulWidget {
  const SocialHubPage({super.key, this.initial = 0});
  final int initial;

  @override
  State<SocialHubPage> createState() => _SocialHubPageState();
}

class _SocialHubPageState extends State<SocialHubPage> {
  late int _tab = widget.initial;
  final Set<int> _built = <int>{};

  @override
  Widget build(BuildContext context) {
    _built.add(_tab);
    const List<Widget> pages = <Widget>[NovaGalleryPage(), OrbitNetworkPage(), SocialStationPage()];
    final List<(IconData, String)> tabs = <(IconData, String)>[
      (Icons.dynamic_feed_rounded, context.tx('پست و استوری', 'Feed & stories')),
      (Icons.forum_rounded, context.tx('پیام‌ها', 'Messages')),
      (Icons.group_rounded, context.tx('دوستان', 'Friends')),
    ];
    return Scaffold(
      backgroundColor: Nx2.deep,
      body: IndexedStack(index: _tab, children: <Widget>[
        for (int i = 0; i < pages.length; i++) _built.contains(i) ? pages[i] : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xE6140A36),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Nx2.cyan.withValues(alpha: 0.45)),
          ),
          child: Row(children: <Widget>[
            for (int i = 0; i < tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: i == _tab
                          ? const LinearGradient(colors: <Color>[Color(0xFF7B3CFF), Color(0xFFE040C8)])
                          : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                      Icon(tabs[i].$1, size: 17, color: i == _tab ? Colors.white : Nx2.muted),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(tabs[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: i == _tab ? Colors.white : Nx2.muted)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const Nx2Dock(current: Nx2Tab.social),
      ]),
    );
  }
}
