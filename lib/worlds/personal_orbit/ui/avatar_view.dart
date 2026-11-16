import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/catalog/catalog.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';

/// Where each gear slot sits on the figure: alignment + size (fraction of width).
class _SlotPlace {
  const _SlotPlace(this.align, this.size);
  final Alignment align;
  final double size;
}

const Map<String, _SlotPlace> _kSlotPlaces = <String, _SlotPlace>{
  'back': _SlotPlace(Alignment(0, -0.05), 0.62),
  'body': _SlotPlace(Alignment(0, 0.12), 0.40),
  'waist': _SlotPlace(Alignment(0, 0.42), 0.26),
  'feet': _SlotPlace(Alignment(0, 0.98), 0.32),
  'neck': _SlotPlace(Alignment(0, -0.36), 0.22),
  'hands': _SlotPlace(Alignment(-0.78, 0.22), 0.20),
  'wrist': _SlotPlace(Alignment(0.78, 0.16), 0.18),
  'face': _SlotPlace(Alignment(0, -0.62), 0.22),
  'head': _SlotPlace(Alignment(0, -0.95), 0.32),
  'aura': _SlotPlace(Alignment(0.86, -0.78), 0.22),
};

/// Avatar slots in display order for the wardrobe.
const List<String> kAvatarSlots = <String>[
  'head',
  'face',
  'neck',
  'body',
  'hands',
  'wrist',
  'waist',
  'feet',
  'back',
  'aura',
];

String avatarSlotName(BuildContext context, String slot) {
  switch (slot) {
    case 'head':
      return context.tx('سر', 'Head');
    case 'face':
      return context.tx('صورت', 'Face');
    case 'neck':
      return context.tx('گردن', 'Neck');
    case 'body':
      return context.tx('بدن', 'Body');
    case 'hands':
      return context.tx('دست', 'Hands');
    case 'wrist':
      return context.tx('مچ', 'Wrist');
    case 'waist':
      return context.tx('کمر', 'Waist');
    case 'feet':
      return context.tx('پا', 'Feet');
    case 'back':
      return context.tx('پشت', 'Back');
    case 'aura':
      return context.tx('هاله', 'Aura');
    case 'frame':
      return context.tx('قاب هولو', 'Holo frame');
    default:
      return slot;
  }
}

String avatarBaseAsset(String core) =>
    'assets/characters/oracle/emotes/$core.webp';

/// Layered 2.5D avatar: base figure + equipped gear arranged by slot,
/// optional holo frame and aura glow ring. Same look everywhere it is used.
class OrbitAvatar extends ConsumerStatefulWidget {
  const OrbitAvatar({super.key, required this.size, this.animate = true});

  /// Width of the figure; height is 1.25x.
  final double size;
  final bool animate;

  @override
  ConsumerState<OrbitAvatar> createState() => _OrbitAvatarState();
}

class _OrbitAvatarState extends ConsumerState<OrbitAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    if (widget.animate && !ref.read(settingsProvider).reducedMotion)
      _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _img(String asset, double w, {Widget? fallback}) {
    return Image.asset(
      asset,
      width: w,
      height: w,
      cacheWidth: (w * 2.5).round().clamp(32, 1024),
      fit: BoxFit.contain,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
          fallback ??
          Icon(Icons.auto_awesome, size: w * 0.6, color: NxColors.violet),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ProfileService p = ref.watch(profileProvider);
    final AppSettings settings = ref.watch(settingsProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final bool moving =
        widget.animate && !settings.reducedMotion && _c.isAnimating;

    final double w = widget.size;
    final double h = w * 1.25;

    final Map<String, CatalogItem> gear = <String, CatalogItem>{};
    for (final String slot in kAvatarSlots) {
      final String? id = p.equipped[slot];
      if (id == null) continue;
      final CatalogItem? item = catalogItem(id);
      if (item != null &&
          item.category == ItemCategory.avatarGear &&
          item.asset.isNotEmpty) gear[slot] = item;
    }
    final String? frameId = p.equipped['frame'];
    final CatalogItem? frame = frameId == null ? null : catalogItem(frameId);
    final bool hasAura = gear.containsKey('aura');

    Widget placed(String slot) {
      final CatalogItem? item = gear[slot];
      final _SlotPlace? place = _kSlotPlaces[slot];
      if (item == null || place == null) return const SizedBox.shrink();
      return Align(
        alignment: place.align,
        child: _img(item.asset, w * place.size),
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) {
        final double t = _c.value * 2 * math.pi;
        final double bob = moving ? math.sin(t) * w * 0.018 : 0;
        final double glow = moving ? 0.5 + 0.5 * math.sin(t * 2) : 0.7;
        return SizedBox(
          width: w,
          height: h,
          child: Stack(clipBehavior: Clip.none, children: <Widget>[
            // Floor shadow.
            Align(
              alignment: const Alignment(0, 1.02),
              child: Container(
                width: w * 0.55,
                height: w * 0.08,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w),
                  gradient: const RadialGradient(
                      colors: <Color>[Color(0x553A2C80), Color(0x003A2C80)]),
                ),
              ),
            ),
            if (frame != null && frame.asset.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.95,
                  child: Image.asset(
                    frame.asset,
                    fit: BoxFit.contain,
                    cacheWidth: (w * 2.5).round().clamp(32, 1024),
                    errorBuilder:
                        (BuildContext _, Object __, StackTrace? ___) =>
                            const SizedBox.shrink(),
                  ),
                ),
              ),
            if (hasAura)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: w * 0.92,
                  height: w * 0.92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            visual.accent.withValues(alpha: 0.35 + 0.4 * glow),
                        width: 3),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: visual.accentSecondary
                              .withValues(alpha: 0.25 + 0.3 * glow),
                          blurRadius: 30,
                          spreadRadius: 4),
                      BoxShadow(
                          color: visual.accent.withValues(alpha: 0.2 * glow),
                          blurRadius: 60,
                          spreadRadius: 10),
                    ],
                  ),
                ),
              ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, bob),
                child: Stack(clipBehavior: Clip.none, children: <Widget>[
                  placed('back'),
                  Align(
                    alignment: Alignment.center,
                    child: _img(
                      avatarBaseAsset(p.avatarCore),
                      w * 0.86,
                      fallback: _img(
                          AppAssets.charactersOracleEmotesHeroFront, w * 0.86),
                    ),
                  ),
                  placed('body'),
                  placed('waist'),
                  placed('feet'),
                  placed('neck'),
                  placed('hands'),
                  placed('wrist'),
                  placed('face'),
                  placed('head'),
                  if (hasAura)
                    Transform.translate(
                      offset: Offset(0, moving ? math.cos(t) * w * 0.03 : 0),
                      child: placed('aura'),
                    ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}
