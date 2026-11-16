import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/catalog/catalog.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import 'avatar_view.dart';
import 'po_common.dart';

/// Background gradient (top → bottom) of the room for each orbit theme.
List<Color> orbitThemeColors(String theme) {
  switch (theme) {
    case 'nebula':
      return const <Color>[
        Color(0xFF2A0F55),
        Color(0xFF6B2C9E),
        Color(0xFFE07AC8)
      ];
    case 'crystal':
      return const <Color>[
        Color(0xFFF4FBFF),
        Color(0xFFD5ECFF),
        Color(0xFFBFD8FF)
      ];
    case 'solar':
      return const <Color>[
        Color(0xFF3B1A05),
        Color(0xFFD9641E),
        Color(0xFFFFD27A)
      ];
    case 'aurora':
    default:
      return const <Color>[
        Color(0xFF0B2545),
        Color(0xFF1C7C8C),
        Color(0xFF7CF5D0)
      ];
  }
}

String _themeId(String itemId) =>
    itemId.startsWith('theme_') ? itemId.substring(6) : itemId;

/// My Space: 2.5D room with draggable / scalable decor and theme picker.
class SpaceTab extends ConsumerStatefulWidget {
  const SpaceTab({super.key});

  @override
  ConsumerState<SpaceTab> createState() => _SpaceTabState();
}

class _SpaceTabState extends ConsumerState<SpaceTab> {
  String? _selected;

  /// Live position while dragging (committed to the profile on release).
  final Map<String, Offset> _dragPos = <String, Offset>{};
  double? _liveScale;

  static const double _minX = 0.06;
  static const double _maxX = 0.94;
  static const double _minY = 0.30;
  static const double _maxY = 0.96;

  double _num(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

  Offset _posOf(ProfileService p, String id) {
    final Offset? live = _dragPos[id];
    if (live != null) return live;
    final Map<String, dynamic>? m = p.decorLayout[id];
    return Offset(_num(m?['x'], 0.5), _num(m?['y'], 0.65));
  }

  double _scaleOf(ProfileService p, String id) {
    if (id == _selected && _liveScale != null) return _liveScale!;
    return _num(p.decorLayout[id]?['s'], 1.0);
  }

  void _commit(ProfileService p, String id) {
    final Offset pos = _posOf(p, id);
    final double s = _scaleOf(p, id);
    p.placeDecor(id, pos.dx, pos.dy, s);
    setState(() => _dragPos.remove(id));
  }

  Future<void> _addDecor(ProfileService p) async {
    final List<CatalogItem> candidates = kCatalog
        .where((CatalogItem c) =>
            c.category == ItemCategory.decor &&
            p.owns(c.id) &&
            !p.decorLayout.containsKey(c.id))
        .toList();
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: NxThemeColors.of(context).backgroundMid,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final NxThemeColors sheetVisual = NxThemeColors.of(ctx);
        if (candidates.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(NxSpace.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(Icons.inventory_2_outlined,
                  size: 40, color: PoColors.inkDim(ctx)),
              const SizedBox(height: 10),
              Text(
                ctx.tx(
                    'دکور آزادی نداری. همه‌ی دکورهایت در اتاق‌اند یا هنوز دکوری نخریده‌ای.',
                    'No free decor. Everything you own is placed, or you have not bought any yet.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: sheetVisual.text),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/world/nexora_exchange');
                },
                icon: const Icon(Icons.storefront_rounded),
                label: Text(ctx.tx(
                    'خرید دکور در Exchange', 'Buy decor in the Exchange')),
              ),
            ]),
          );
        }
        return SizedBox(
          height: 260,
          child: GridView.count(
            crossAxisCount: 4,
            padding: const EdgeInsets.all(NxSpace.md),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: <Widget>[
              for (final CatalogItem c in candidates)
                InkWell(
                  borderRadius: BorderRadius.circular(NxRadius.md),
                  onTap: () => Navigator.pop(ctx, c.id),
                  child: Column(children: <Widget>[
                    Expanded(
                      child: Image.asset(c.asset,
                          cacheWidth: 160,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (BuildContext _, Object __, StackTrace? ___) =>
                                  Icon(Icons.chair_rounded,
                                      color: PoColors.lilac(ctx))),
                    ),
                    Text(ctx.tx(c.nameFa, c.nameEn),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: PoColors.ink(ctx))),
                  ]),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    final int n = p.decorLayout.length;
    final double x = (0.25 + (n % 3) * 0.25).clamp(_minX, _maxX);
    final double y = (0.62 + ((n ~/ 3) % 3) * 0.1).clamp(_minY, _maxY);
    p.placeDecor(picked, x, y, 1.0);
    setState(() {
      _selected = picked;
      _liveScale = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ProfileService p = ref.watch(profileProvider);
    final bool fancy = ref.watch(settingsProvider).fancyEffects;
    if (_selected != null && !p.decorLayout.containsKey(_selected)) {
      _selected = null;
    }
    final List<Color> bg = orbitThemeColors(p.orbitTheme);
    final List<CatalogItem> ownedThemes = kCatalog
        .where(
            (CatalogItem c) => c.category == ItemCategory.theme && p.owns(c.id))
        .toList();
    final List<CatalogItem> allThemes = kCatalog
        .where((CatalogItem c) => c.category == ItemCategory.theme)
        .toList();
    final CatalogItem? sel = _selected == null ? null : catalogItem(_selected!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
      children: <Widget>[
        AspectRatio(
          aspectRatio: 0.92,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NxRadius.lg),
            child:
                LayoutBuilder(builder: (BuildContext ctx, BoxConstraints box) {
              final double w = box.maxWidth;
              final double h = box.maxHeight;
              final List<String> ids = p.decorLayout.keys.toList()
                ..sort((String a, String b) =>
                    _posOf(p, a).dy.compareTo(_posOf(p, b).dy));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _selected = null;
                  _liveScale = null;
                }),
                child: Stack(children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: bg),
                      ),
                    ),
                  ),
                  if (fancy)
                    Positioned.fill(
                        child: CustomPaint(
                            painter: _RoomStarsPainter(
                                seed: p.orbitTheme.hashCode))),
                  // Back wall horizon glow.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: h * 0.26,
                    height: h * 0.08,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.25)
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Floor plane with perspective grid.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: h * 0.34,
                    bottom: 0,
                    child: CustomPaint(
                        painter: _FloorPainter(color: Colors.white)),
                  ),
                  // Platform asset under the avatar.
                  Positioned(
                    left: w * 0.18,
                    right: w * 0.18,
                    top: h * 0.50,
                    height: h * 0.34,
                    child: Image.asset(
                      AppAssets.worldsHubPropsCommandPlatformWide,
                      fit: BoxFit.contain,
                      cacheWidth: (w * 2).round().clamp(64, 1400),
                      errorBuilder:
                          (BuildContext _, Object __, StackTrace? ___) =>
                              const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    left: w * 0.5 - w * 0.17,
                    top: h * 0.30,
                    child: OrbitAvatar(size: w * 0.34),
                  ),
                  for (final String id in ids) _decorWidget(p, id, w, h),
                  if (ids.isEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: NxSpace.md,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0x99000000),
                              borderRadius: BorderRadius.circular(30)),
                          child: Text(
                              ctx.tx('دکوری اضافه کن تا اتاقت جان بگیرد',
                                  'Add decor to bring your room to life'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    ),
                ]),
              );
            }),
          ),
        ),
        const SizedBox(height: NxSpace.sm),
        Row(children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _addDecor(p),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tx('افزودن دکور', 'Add decor')),
            ),
          ),
          const SizedBox(width: NxSpace.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: sel == null
                  ? null
                  : () {
                      p.removeDecor(sel.id);
                      setState(() {
                        _selected = null;
                        _liveScale = null;
                      });
                    },
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(context.tx('برداشتن', 'Remove')),
            ),
          ),
        ]),
        if (sel != null)
          PoCard(
            padding: const EdgeInsets.fromLTRB(
                NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.sm),
            child: Row(children: <Widget>[
              Icon(Icons.open_in_full_rounded,
                  size: 18, color: PoColors.lilac(context)),
              const SizedBox(width: 8),
              Text(context.tx(sel.nameFa, sel.nameEn),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PoColors.ink(context))),
              Expanded(
                child: Slider(
                  min: 0.5,
                  max: 2.0,
                  value: _scaleOf(p, sel.id).clamp(0.5, 2.0),
                  onChanged: (double v) => setState(() => _liveScale = v),
                  onChangeEnd: (double v) {
                    final Offset pos = _posOf(p, sel.id);
                    p.placeDecor(sel.id, pos.dx, pos.dy, v);
                    setState(() => _liveScale = null);
                  },
                ),
              ),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NxSpace.sm),
            child: Text(
              context.tx('روی یک دکور بزن تا انتخاب شود؛ بکش تا جابه‌جا شود.',
                  'Tap a decor item to select it; drag to move it.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: PoColors.inkDim(context), fontSize: 12),
            ),
          ),
        PoSectionTitle(context.tx('تم مدار', 'Orbit theme'),
            icon: Icons.palette_rounded),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final CatalogItem t in allThemes)
            _ThemeChip(
              item: t,
              owned: ownedThemes.contains(t),
              active: p.orbitTheme == _themeId(t.id),
              onTap: () {
                if (ownedThemes.contains(t)) {
                  p.setOrbitTheme(_themeId(t.id));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(poDigits(
                        context,
                        context.tx(
                            'این تم را با ${t.price} سکه از Exchange بگیر.',
                            'Get this theme in the Exchange for ${t.price} coins.'))),
                    action: SnackBarAction(
                      label: context.tx('Exchange', 'Exchange'),
                      onPressed: () => context.push('/world/nexora_exchange'),
                    ),
                  ));
                }
              },
            ),
        ]),
      ],
    );
  }

  Widget _decorWidget(ProfileService p, String id, double w, double h) {
    final CatalogItem? item = catalogItem(id);
    final Offset pos = _posOf(p, id);
    // 2.5D: items further back (smaller y) are drawn smaller.
    final double depth =
        0.65 + 0.55 * ((pos.dy - _minY) / (_maxY - _minY)).clamp(0.0, 1.0);
    final double size = w * 0.2 * _scaleOf(p, id) * depth;
    final bool selected = id == _selected;
    return Positioned(
      left: pos.dx * w - size / 2,
      top: pos.dy * h - size,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selected = id;
          _liveScale = null;
        }),
        onPanStart: (DragStartDetails _) => setState(() {
          _selected = id;
          _liveScale = null;
          _dragPos[id] = _posOf(p, id);
        }),
        onPanUpdate: (DragUpdateDetails d) {
          final Offset cur = _posOf(p, id);
          setState(() {
            _dragPos[id] = Offset(
              (cur.dx + d.delta.dx / w).clamp(_minX, _maxX),
              (cur.dy + d.delta.dy / h).clamp(_minY, _maxY),
            );
          });
        },
        onPanEnd: (DragEndDetails _) => _commit(p, id),
        child: Stack(clipBehavior: Clip.none, children: <Widget>[
          // Contact shadow on the floor.
          Positioned(
            left: size * 0.15,
            right: size * 0.15,
            bottom: -size * 0.04,
            height: size * 0.12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: const RadialGradient(
                    colors: <Color>[Color(0x66000000), Color(0x00000000)]),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(NxRadius.md),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x887CF5D0), blurRadius: 16)
                  ],
                ),
              ),
            ),
          Positioned.fill(
            child: item == null || item.asset.isEmpty
                ? const Icon(Icons.chair_rounded, color: Colors.white)
                : Image.asset(
                    item.asset,
                    fit: BoxFit.contain,
                    cacheWidth: (size * 2.5).round().clamp(32, 600),
                    errorBuilder: (BuildContext _, Object __,
                            StackTrace? ___) =>
                        const Icon(Icons.chair_rounded, color: Colors.white),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip(
      {required this.item,
      required this.owned,
      required this.active,
      required this.onTap});
  final CatalogItem item;
  final bool owned;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final List<Color> c = orbitThemeColors(_themeId(item.id));
    return InkWell(
      borderRadius: BorderRadius.circular(NxRadius.md),
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: NxThemeColors.of(context).surface,
          borderRadius: BorderRadius.circular(NxRadius.md),
          border: Border.all(
              color: active
                  ? PoColors.mint(context)
                  : PoColors.cardBorder(context),
              width: active ? 2 : 1),
        ),
        child: Column(children: <Widget>[
          Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NxRadius.sm),
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: c),
            ),
            child: Center(
              child: Icon(
                active
                    ? Icons.check_circle_rounded
                    : (owned
                        ? Icons.radio_button_unchecked
                        : Icons.lock_rounded),
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(context.tx(item.nameFa, item.nameEn),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: owned
                      ? PoColors.ink(context)
                      : PoColors.inkDim(context))),
        ]),
      ),
    );
  }
}

/// Perspective floor grid (the 2.5D ground plane).
class _FloorPainter extends CustomPainter {
  _FloorPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.05),
            color.withValues(alpha: 0.22)
          ],
        ).createShader(r),
    );
    final Paint line = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final double cx = size.width / 2;
    for (int i = -8; i <= 8; i++) {
      final double bottomX = cx + i * size.width / 6;
      canvas.drawLine(Offset(cx + i * size.width / 30, 0),
          Offset(bottomX, size.height), line);
    }
    for (int j = 1; j <= 7; j++) {
      final double t = j / 7;
      final double y = size.height * t * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPainter old) => old.color != color;
}

/// Static sparkles on the back wall (deterministic per theme).
class _RoomStarsPainter extends CustomPainter {
  _RoomStarsPainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random r = math.Random(seed);
    final Paint p = Paint();
    for (int i = 0; i < 46; i++) {
      final double x = r.nextDouble() * size.width;
      final double y = r.nextDouble() * size.height * 0.34;
      final double s = 0.6 + r.nextDouble() * 1.6;
      p.color = Colors.white.withValues(alpha: 0.25 + r.nextDouble() * 0.6);
      canvas.drawCircle(Offset(x, y), s, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RoomStarsPainter old) => old.seed != seed;
}
