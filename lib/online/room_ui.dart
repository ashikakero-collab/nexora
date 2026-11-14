// Room widgets shared by the lobby and the online match (port of ChatPanel / VoiceBar / PingBadge in online/ui.tsx).
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'link.dart';
import 'voice.dart';

class PingBadge extends StatelessWidget {
  final RoomLink link;
  const PingBadge({super.key, required this.link});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: link,
        builder: (_, __) {
          final r = link.rtt;
          final col = r == null ? C.dim : r < 80 ? C.green : r < 150 ? C.gold : C.red;
          return Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: const Color(0xd9060a1e), borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withValues(alpha: .53))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              T(r == null ? '— ms' : '$r ms', size: 10, family: F.head, weight: 700, color: col),
            ]),
          );
        },
      );
}

class VoiceBar extends StatelessWidget {
  final RoomLink link;
  final bool enabled, compact;
  const VoiceBar({super.key, required this.link, this.enabled = true, this.compact = false});
  Widget _b(Widget child, VoidCallback? onTap, {Color border = C.line, Color? bg}) => Press(
        onTap: onTap,
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg ?? const Color(0xd9080c22), borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
          child: child,
        ),
      );
  @override
  Widget build(BuildContext context) {
    if (!enabled) return compact ? const SizedBox.shrink() : const T('چت صوتی برای این اتاق خاموش است', size: 11, color: C.dim2, align: TextAlign.right);
    final v = link.voice;
    return ListenableBuilder(
      listenable: v,
      builder: (_, __) {
        final on = v.status == VoiceStatus.on;
        if (on) {
          return Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, textDirection: TextDirection.rtl, children: [
            _b(const Icon(Icons.call_end_rounded, color: C.red, size: 20), () => v.leave(), border: C.red.withValues(alpha: .5)),
            _b(Icon(v.speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: v.speaker ? C.text : C.dim, size: 20), () => v.setSpeaker(!v.speaker)),
            if (v.canPublish)
              _b(Icon(v.mic ? Icons.mic_rounded : Icons.mic_off_rounded, color: v.mic ? C.green : C.dim, size: 20), () => v.setMic(!v.mic),
                  border: v.mic ? C.green : C.line, bg: v.mic ? const Color(0x263dffa8) : null),
            if (!compact) Expanded(child: T(v.canPublish ? (v.mic ? 'میکروفون روشن' : 'میکروفون خاموش') : 'فقط شنونده', size: 11, color: C.dim, lines: 1)),
          ]);
        }
        return Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, textDirection: TextDirection.rtl, children: [
          _b(
              v.status == VoiceStatus.connecting
                  ? const Spinner(size: 18)
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Img(ui2('c_mega'), w: 22, h: 22),
                      if (!compact) ...[const SizedBox(width: 4), tBold('ورود به چت صوتی', size: 12)],
                    ]),
              v.status == VoiceStatus.connecting ? null : () => v.join(),
              border: C.cyan),
          if (!compact && v.status == VoiceStatus.error && v.error != null) Expanded(child: T(v.error!, size: 11, color: C.orange, lines: 2)),
        ]);
      },
    );
  }
}

class ChatPanel extends StatefulWidget {
  final RoomLink link;
  const ChatPanel({super.key, required this.link});
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final ctl = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.link.chatOpen = true;
    widget.link.markRead();
  }

  @override
  void dispose() {
    widget.link.chatOpen = false;
    super.dispose();
  }

  void send() {
    if (ctl.text.trim().isEmpty) return;
    widget.link.sendChat(ctl.text);
    ctl.clear();
    buzz();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(children: [
        Expanded(
          child: ListenableBuilder(
            listenable: l,
            builder: (_, __) {
              final data = l.chat.reversed.toList();
              if (data.isEmpty) return const Center(child: T('هنوز پیامی نیست؛ سلام کن!', size: 12, color: C.dim2));
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: data.length,
                itemBuilder: (_, i) {
                  final c = data[i], mine = c.uid == l.me;
                  return Align(
                    alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                      decoration: BoxDecoration(color: mine ? const Color(0x404fe3ff) : const Color(0xd90e1640), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (!mine) tBold(c.name, size: 10, color: C.cyan),
                        T(c.text, size: 13),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(children: [
            IconBtn(ui2('c_mega'), onTap: send, size: 30),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: ctl,
                maxLength: 200,
                onSubmitted: (_) => send(),
                textInputAction: TextInputAction.send,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: ts(size: 14, family: F.fa),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'پیام…',
                  hintTextDirection: TextDirection.rtl,
                  hintStyle: ts(size: 13, color: C.dim2, family: F.fa),
                  filled: true,
                  fillColor: const Color(0xcc060a22),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: C.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: C.line)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class ChatButton extends StatelessWidget {
  final RoomLink link;
  const ChatButton({super.key, required this.link});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: link,
        builder: (_, __) => IconBtn(ui2('c_bell'), badge: link.unread, onTap: () => showSheet(context, title: 'گفتگوی اتاق', en: 'ROOM CHAT', height: .6, child: (_) => ChatPanel(link: link))),
      );
}

Future<bool> confirmQuit(BuildContext context, bool host) =>
    confirm(context, 'خروج از بازی؟', host ? 'تو میزبانی؛ با خروج تو بازی برای همه لغو می‌شود.' : 'با خروج، هم‌تیمی یا ربات جای تو بازی می‌کند.', yes: 'خروج', no: 'ادامه‌ی بازی');
