import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import 'models/orbit_models.dart';
import 'state/orbit_controller.dart';
import 'ui/orbit_sheets.dart';
import 'ui/orbit_tabs.dart';

/// ORBIT NETWORK — the messenger world (offline-first).
class OrbitNetworkPage extends ConsumerStatefulWidget {
  const OrbitNetworkPage({super.key});

  @override
  ConsumerState<OrbitNetworkPage> createState() => _OrbitNetworkPageState();
}

class _OrbitNetworkPageState extends ConsumerState<OrbitNetworkPage>
    with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pick up items other worlds shared while this page was closed.
    ref.read(orbitControllerProvider).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      ref.read(orbitControllerProvider).refresh();
  }

  Future<void> _newChat() async {
    final String? kind = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading:
                const Icon(Icons.groups_rounded, color: NxColors.turquoise),
            title: Text(c.tx('گروه تازه', 'New group')),
            subtitle: Text(c.tx('گفت‌وگوی چندنفره با نشان باشگاه',
                'Multi-person chat with a club badge')),
            onTap: () => Navigator.pop(c, 'group'),
          ),
          ListTile(
            leading: const Icon(Icons.campaign_rounded,
                color: NxColors.electricBlue),
            title: Text(c.tx('کانال تازه', 'New channel')),
            subtitle:
                Text(c.tx('فقط مدیران منتشر می‌کنند', 'Only admins publish')),
            onTap: () => Navigator.pop(c, 'channel'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded,
                color: NxColors.textDim),
            title: Text(c.tx('چت خصوصی با دوست', 'Private chat with a friend')),
            subtitle: Text(ref.read(orbitControllerProvider).isOnline
                ? c.tx('از میان دوستانت', 'Pick one of your friends')
                : c.tx('بعد از اتصال آنلاین', 'Once online')),
            onTap: () => Navigator.pop(c, 'dm'),
          ),
        ]),
      ),
    );
    if (!mounted || kind == null) return;
    if (kind == 'dm') {
      setState(() => _tab = 2);
      return;
    }
    final OrbitChat? chat = await showOrbitChatEditor(
      context,
      kind: kind == 'channel' ? OrbitChatKind.channel : OrbitChatKind.group,
    );
    if (chat != null && mounted) openOrbitChat(context, chat.id);
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return const OrbitCallsTab(key: ValueKey<String>('calls'));
      case 2:
        return const OrbitContactsTab(key: ValueKey<String>('contacts'));
      default:
        return const OrbitChatsTab(key: ValueKey<String>('chats'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(orbitControllerProvider);
    final bool reduced = ref.watch(settingsProvider).reducedMotion;
    final NxThemeColors visual = NxThemeColors.of(context);
    final pal = WorldPalette.orbit;
    final int unread = ctrl.totalUnread;
    final List<String> sectionFa = <String>[
      'مدار گفتگوها',
      'تماس‌های واقعی',
      'مخاطبان'
    ];
    final List<String> sectionEn = <String>[
      'Your conversations',
      'Real calls',
      'Contacts'
    ];
    final List<String> subtitleFa = <String>[
      'پیام‌ها و یادداشت‌هایت را در یک جا نگه دار.',
      'تماس‌ها فقط با اتصال آنلاین برقرار می‌شوند.',
      'شناسه و دوستانت را از اینجا مدیریت کن.',
    ];
    final List<String> subtitleEn = <String>[
      'Keep messages and notes together in one place.',
      'Calls connect only while the online service is available.',
      'Manage your explorer ID and friends here.',
    ];
    return NxWorldScaffold(
      title: 'ORBIT NETWORK',
      palette: pal,
      showWallet: false,
      actions: <Widget>[
        IconButton(
          tooltip: context.tx('جستجوی پیام‌ها', 'Search messages'),
          icon: const Icon(Icons.search_rounded),
          onPressed: () =>
              Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext c) =>
                const OrbitMessageListPage(starredOnly: false),
          )),
        ),
        IconButton(
          tooltip: context.tx('ستاره‌دارها', 'Starred'),
          icon: const Icon(Icons.star_rounded),
          onPressed: () =>
              Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext c) =>
                const OrbitMessageListPage(starredOnly: true),
          )),
        ),
        IconButton(
          tooltip: context.tx('صندوق اشتراک', 'Share inbox'),
          icon: Badge(
            isLabelVisible: ctrl.inboxItems.isNotEmpty,
            label: Text('${ctrl.inboxItems.length}'),
            child: const Icon(Icons.move_to_inbox_rounded),
          ),
          onPressed: () => showSharedInbox(context),
        ),
      ],
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              backgroundColor: visual.accent,
              foregroundColor: visual.background,
              tooltip: context.tx('گفت‌وگوی تازه', 'New chat'),
              onPressed: _newChat,
              child: const Icon(Icons.add_comment_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: visual.surfaceRaised.withValues(alpha: 0.98),
        indicatorColor: visual.accent.withValues(alpha: 0.22),
        selectedIndex: _tab,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: <Widget>[
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: context.tx('گفت‌وگوها', 'Chats'),
          ),
          NavigationDestination(
              icon: const Icon(Icons.call_rounded),
              label: context.tx('تماس‌ها', 'Calls')),
          NavigationDestination(
              icon: const Icon(Icons.contacts_rounded),
              label: context.tx('مخاطبان', 'Contacts')),
        ],
      ),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              NxSpace.md, kToolbarHeight + NxSpace.xs, NxSpace.md, NxSpace.sm),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(
                horizontal: NxSpace.md, vertical: NxSpace.sm),
            radius: NxRadius.md,
            child: Row(children: <Widget>[
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                    color: visual.accent,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: NxSpace.sm),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(context.tx(sectionFa[_tab], sectionEn[_tab]),
                          style: TextStyle(
                              color: visual.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(context.tx(subtitleFa[_tab], subtitleEn[_tab]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: visual.muted, fontSize: 12)),
                    ]),
              ),
              Icon(Icons.radar_rounded, color: visual.accent, size: 20),
            ]),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduced ? Duration.zero : NxMotion.normal,
            transitionBuilder: (Widget child, Animation<double> a) =>
                FadeTransition(opacity: a, child: child),
            child: _body(),
          ),
        ),
      ]),
    );
  }
}
