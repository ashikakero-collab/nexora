// Port of src/online/ui.tsx helpers: avatar, badge, text field, leagues cache, tabs, time-ago, image upload.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../core/assets.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/supabase.dart';
import '../ui/kit.dart';

Team teamOfAvatar(String? key) => kTeams.firstWhere((t) => t.id == key || teamKey(t) == key, orElse: () => kTeams[0]);
String discImg(String? key) => teamImg(teamOfAvatar(key));

const kLeagueImg = {'bronze': 'medal_bronze', 'silver': 'medal_silver', 'gold': 'medal_gold', 'platinum': 'medal_epic', 'diamond': 'shield_epic', 'master': 'shield_star', 'legend': 'shield_crown'};
const kReasonFa = {'match': 'مسابقه‌ی آنلاین', 'tournament': 'جایزه‌ی تورنمنت', 'challenge': 'چالش روزانه', 'offline': 'برد مقابل ربات'};
const kKindLabel = {'dm': 'گفتگو', 'group': 'گروه', 'channel': 'کانال', 'club': 'باشگاه'};

String timeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t).inSeconds;
  return d < 60 ? 'الان' : d < 3600 ? '${fa(d ~/ 60)} دقیقه' : d < 86400 ? '${fa(d ~/ 3600)} ساعت' : '${fa(d ~/ 86400)} روز';
}

bool isOnline(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  return t != null && DateTime.now().difference(t).inMinutes < 3;
}

class Avatar extends StatelessWidget {
  final String? avatar, url;
  final double size;
  final Color ring;
  final bool dim;
  const Avatar({super.key, this.avatar, this.url, this.size = 40, this.ring = C.cyan, this.dim = false});
  @override
  Widget build(BuildContext context) => Opacity(opacity: dim ? .5 : 1, child: Disc(url ?? discImg(avatar), size: size, ring: ring));
}

class Badge2 extends StatelessWidget {
  final String label;
  final Color color;
  final bool live;
  const Badge2(this.label, {super.key, this.color = C.cyan, this.live = false});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: .5))),
        child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
          if (live) Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          T(label, size: 10, color: color),
        ]),
      );
}

class Field2 extends StatelessWidget {
  final TextEditingController ctl;
  final String? hint, label;
  final bool secure, ltr;
  final int maxLength;
  final int lines;
  final TextInputType? kb;
  final ValueChanged<String>? onSubmit;
  const Field2(this.ctl, {super.key, this.hint, this.label, this.secure = false, this.ltr = false, this.maxLength = 200, this.lines = 1, this.kb, this.onSubmit});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (label != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: T(label!, size: 11, color: C.dim, align: TextAlign.right)),
          TextField(
            controller: ctl,
            obscureText: secure,
            maxLength: maxLength,
            maxLines: lines,
            keyboardType: kb,
            onSubmitted: onSubmit,
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            textAlign: ltr ? TextAlign.left : TextAlign.right,
            style: ts(size: 14, family: ltr ? F.body : F.fa),
            decoration: InputDecoration(
              counterText: '',
              hintText: hint,
              hintTextDirection: TextDirection.rtl,
              hintStyle: ts(size: 13, color: C.dim2, family: F.fa),
              filled: true,
              fillColor: const Color(0xcc060a22),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.cyan)),
            ),
          ),
        ]),
      );
}

class Tabs2<K> extends StatelessWidget {
  final List<(K, String)> items;
  final K value;
  final ValueChanged<K> onChange;
  const Tabs2({super.key, required this.items, required this.value, required this.onChange});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Segment<K>(items: items, value: value, onChange: onChange));
}

List<Rec>? _leagues;
Future<List<Rec>> leagues() async {
  if (_leagues != null) return _leagues!;
  try {
    _leagues = recs(await sb.from('leagues').select().order('sort'));
  } catch (_) {
    _leagues = [];
  }
  return _leagues!;
}

Rec? leagueFor(List<Rec> ls, int rating) {
  Rec? cur;
  for (final l in ls) {
    if (l.i('min_rating') <= rating) cur = l;
  }
  return cur;
}

/// Pick an image, resize/compress on device to <= size px JPEG and upload to Supabase Storage (media.ts).
Future<(String?, String?)> pickAndUpload(String bucket, String uid, {required int size, bool square = false}) async {
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: size.toDouble(), maxHeight: size.toDouble(), imageQuality: 82, requestFullMetadata: false);
    if (x == null) return (null, null);
    Uint8List bytes = await x.readAsBytes();
    if (square) {
      // centre-crop to a square (pickImage already capped the size)
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      final s = img.width < img.height ? img.width : img.height;
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(img, Rect.fromLTWH((img.width - s) / 2, (img.height - s) / 2, s.toDouble(), s.toDouble()), Rect.fromLTWH(0, 0, s.toDouble(), s.toDouble()), Paint());
      final out = await rec.endRecording().toImage(s, s);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      if (png != null) bytes = png.buffer.asUint8List();
    }
    final ext = square ? 'png' : 'jpg';
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}.$ext';
    await sb.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: square ? 'image/png' : 'image/jpeg', upsert: false));
    return (sb.storage.from(bucket).getPublicUrl(path), null);
  } catch (e) {
    return (null, 'انتخاب یا آپلود عکس ناموفق بود');
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(32), child: Center(child: Spinner()));
}
