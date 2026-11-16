import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../models/art_asset.dart';
import '../models/nova_models.dart';
import '../state/nova_controller.dart';
import 'nova_visuals.dart';

/// XP for a real published post (the profile's daily cap still applies).
const int kNovaPostXp = 12;

/// Opens the post composer. Pass [editing] to edit an existing post.
Future<void> showNovaComposer(BuildContext context, {NovaPost? editing, bool motion = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => _ComposerSheet(editing: editing, startMotion: motion),
  );
}

class _ComposerSheet extends ConsumerStatefulWidget {
  const _ComposerSheet({this.editing, this.startMotion = false});
  final NovaPost? editing;
  final bool startMotion;

  @override
  ConsumerState<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends ConsumerState<_ComposerSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.editing?.text ?? '');
  late NovaVisualKind _kind = widget.editing?.visual.kind ?? NovaVisualKind.none;
  late int _gradient = widget.editing?.visual.gradient ?? 0;
  late String _asset = widget.editing?.visual.asset ?? '';
  late bool _motion = widget.editing?.motion ?? widget.startMotion;
  late String _url = widget.editing?.visual.url ?? '';
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    if (_motion && _kind == NovaVisualKind.none) _kind = NovaVisualKind.gradient;
    _text.addListener(_onText);
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    super.dispose();
  }

  NovaVisual get _visual {
    if (_kind == NovaVisualKind.photo) {
      return _url.isEmpty ? NovaVisual.none : NovaVisual(kind: NovaVisualKind.photo, gradient: _gradient, url: _url);
    }
    if (_kind == NovaVisualKind.asset && ArtAsset.parse(_asset) == null) {
      return NovaVisual(kind: NovaVisualKind.gradient, gradient: _gradient);
    }
    return NovaVisual(kind: _kind, gradient: _gradient, asset: _kind == NovaVisualKind.asset ? _asset : '');
  }

  bool get _canPublish => !_busy && (_text.text.trim().isNotEmpty || !_visual.isNone);

  /// Real photo: picked from the gallery and uploaded to Supabase Storage (online only).
  Future<void> _pickPhoto() async {
    final repo = ref.read(novaControllerProvider).online;
    if (repo == null) return;
    final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (f == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final String name = f.name;
      final String ext = name.contains('.') ? name.split('.').last : 'jpg';
      final String url = await repo.uploadPhoto(await f.readAsBytes(), ext: ext);
      if (!mounted) return;
      setState(() {
        _url = url;
        _kind = NovaVisualKind.photo;
        _motion = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tx('آپلود عکس ممکن نشد.', 'Photo upload failed.'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickAsset() async {
    final ArtAsset? a = await showArtAssetPicker(context);
    if (a == null) return;
    setState(() {
      _asset = a.ref;
      _kind = NovaVisualKind.asset;
    });
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() => _busy = true);
    final ctrl = ref.read(novaControllerProvider);
    final profile = ref.read(profileProvider);
    final editing = widget.editing;
    final NovaVisual visual =
        _motion && _visual.isNone ? NovaVisual(kind: NovaVisualKind.gradient, gradient: _gradient) : _visual;
    if (editing != null) {
      await ctrl.updatePost(editing.id, text: _text.text, visual: visual, motion: _motion);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    await ctrl.createPost(
      authorId: profile.explorerId,
      authorName: novaMyName(context, profile),
      text: _text.text,
      visual: visual,
      motion: _motion,
    );
    profile.bump('nova.posts');
    final AwardOutcome outcome = profile.award(
      'nova.post',
      xp: kNovaPostXp,
      fa: 'پست جدید در Nova Gallery',
      en: 'New post in Nova Gallery',
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final String msg = context.tx('منتشر شد! +${outcome.xp} XP', 'Published! +${outcome.xp} XP');
    final BuildContext rootCtx = navigator.context;
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    if (rootCtx.mounted) await showAwardOutcome(rootCtx, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.editing != null;
    final pal = WorldPalette.nova;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Icon(editing ? Icons.edit_rounded : Icons.auto_awesome, color: pal.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(editing ? context.tx('ویرایش پست', 'Edit post') : context.tx('پست تازه', 'New post'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: pal.primary),
              onPressed: _canPublish ? _publish : null,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(editing ? context.tx('ذخیره', 'Save') : context.tx('انتشار', 'Publish')),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: context.tx('چه چیزی در مدار تو می‌گذرد؟ #هشتگ و @نام پشتیبانی می‌شود',
                  "What's happening in your orbit? #hashtags and @mentions work"),
            ),
          ),
          const SizedBox(height: 8),
          Text(context.tx('جلوه‌ی تصویری', 'Visual'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            ChoiceChip(
              label: Text(context.tx('بدون تصویر', 'None')),
              selected: _kind == NovaVisualKind.none,
              onSelected: _motion ? null : (_) => setState(() => _kind = NovaVisualKind.none),
            ),
            ChoiceChip(
              label: Text(context.tx('کارت گرادیان', 'Gradient card')),
              selected: _kind == NovaVisualKind.gradient,
              onSelected: (_) => setState(() => _kind = NovaVisualKind.gradient),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.collections_rounded, size: 16),
              label: Text(context.tx('هنر NEXORA', 'NEXORA art')),
              selected: _kind == NovaVisualKind.asset,
              onSelected: (_) => _pickAsset(),
            ),
            if (ref.watch(novaControllerProvider).online != null)
              ChoiceChip(
                avatar: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_rounded, size: 16),
                label: Text(context.tx('عکس', 'Photo')),
                selected: _kind == NovaVisualKind.photo,
                onSelected: _uploading ? null : (_) => _pickPhoto(),
              ),
          ]),
          if (_kind == NovaVisualKind.photo && _url.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            NovaVisualView(visual: _visual, height: 200),
          ],
          if (_kind != NovaVisualKind.none && _kind != NovaVisualKind.photo) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kNovaGradients.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (BuildContext c, int i) {
                  final g = kNovaGradients[i];
                  final bool sel = i == _gradient;
                  return Tooltip(
                    message: c.tx(g.nameFa, g.nameEn),
                    child: GestureDetector(
                      onTap: () => setState(() => _gradient = i),
                      child: AnimatedContainer(
                        duration: NxMotion.fast,
                        width: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: g.colors),
                          border: Border.all(color: sel ? Colors.white : Colors.white24, width: sel ? 3 : 1),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_kind == NovaVisualKind.asset)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _pickAsset,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(context.tx('تغییر تصویر', 'Change art')),
                ),
              ),
            const SizedBox(height: 8),
            NovaVisualView(
              visual: _visual,
              caption: _text.text.trim().isEmpty ? context.tx('پیش‌نمایش', 'Preview') : _text.text.trim(),
              height: 180,
              animated: _motion,
            ),
          ],
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _motion,
            activeColor: pal.primary,
            onChanged: (bool v) => setState(() {
              _motion = v;
              if (v && _kind == NovaVisualKind.none) _kind = NovaVisualKind.gradient;
            }),
            title: Text(context.tx('پست حرکتی (در ریلز)', 'Motion post (shows in Reels)')),
            subtitle: Text(
              context.tx('گرادیان زنده به‌جای ویدئو. آپلود ویدئوی واقعی بعد از اتصال سرور.',
                  'A living gradient instead of video. Real video uploads come with the server.'),
              style: const TextStyle(color: NxColors.textDim, fontSize: 12),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Picker over the app's built-in art library. Returns null if dismissed.
Future<ArtAsset?> showArtAssetPicker(BuildContext context) {
  return showModalBottomSheet<ArtAsset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => SizedBox(
      height: MediaQuery.of(c).size.height * 0.72,
      child: DefaultTabController(
        length: ArtCategory.values.length,
        child: Column(children: <Widget>[
          Text(c.tx('کتابخانه‌ی هنری NEXORA', 'NEXORA art library'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              for (final ArtCategory cat in ArtCategory.values)
                Tab(text: c.tx(ArtAsset.categoryFa(cat), ArtAsset.categoryEn(cat))),
            ],
          ),
          Expanded(
            child: TabBarView(children: <Widget>[
              for (final ArtCategory cat in ArtCategory.values)
                GridView.builder(
                  padding: const EdgeInsets.all(NxSpace.md),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: ArtAsset.all(cat).length,
                  itemBuilder: (BuildContext gc, int i) {
                    final ArtAsset a = ArtAsset.all(cat)[i];
                    return GlassPanel(
                      padding: const EdgeInsets.all(8),
                      radius: NxRadius.md,
                      blur: false,
                      onTap: () => Navigator.of(gc).pop(a),
                      child: Column(children: <Widget>[
                        Expanded(
                          child: Image.asset(
                            a.path,
                            cacheWidth: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(a.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: NxColors.textDim)),
                      ]),
                    );
                  },
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// Story composer (text on a cosmic gradient, lives 24h).
Future<void> showStoryComposer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => const _StoryComposer(),
  );
}

class _StoryComposer extends ConsumerStatefulWidget {
  const _StoryComposer();

  @override
  ConsumerState<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends ConsumerState<_StoryComposer> {
  final TextEditingController _text = TextEditingController();
  int _gradient = 1;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final t = _text.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    final p = ref.read(profileProvider);
    await ref.read(novaControllerProvider).createStory(
          authorId: p.explorerId,
          authorName: novaMyName(context, p),
          text: t,
          gradient: _gradient,
        );
    final outcome = p.award('nova.story', xp: 5, fa: 'استوری تازه در Nova Gallery', en: 'New story in Nova Gallery');
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final BuildContext rootCtx = navigator.context;
    navigator.pop();
    if (rootCtx.mounted) await showAwardOutcome(rootCtx, outcome);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(context.tx('استوری تازه (۲۴ ساعت)', 'New story (24 hours)'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NxRadius.lg),
              child: NovaMotionCanvas(
                gradient: _gradient,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _text,
                      builder: (BuildContext c, TextEditingValue v, Widget? _) => Text(
                        v.text.trim().isEmpty ? c.tx('متن استوری…', 'Story text…') : v.text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLength: 220,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(hintText: context.tx('چه حسی داری؟', 'How are you feeling?')),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kNovaGradients.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (BuildContext c, int i) => GestureDetector(
                onTap: () => setState(() => _gradient = i),
                child: Container(
                  width: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: kNovaGradients[i].colors),
                    border: Border.all(color: i == _gradient ? Colors.white : Colors.white24, width: i == _gradient ? 3 : 1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: WorldPalette.nova.primary),
            onPressed: _busy ? null : _publish,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(context.tx('انتشار استوری', 'Share story')),
          ),
        ]),
      ),
    );
  }
}
