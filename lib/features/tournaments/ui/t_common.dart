import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../data/models.dart';
import '../domain/bracket.dart';

/// Tournament accent (same arcade palette as the rest of the app).
const Color kTAccent = Color(0xFFFFB020);
const Color kTAccent2 = Color(0xFFFF4F6E);

/// Theme-aware NEXORA accents for tournament chrome.
Color tAccent(BuildContext context) => NxThemeColors.of(context).accent;
Color tAccentSecondary(BuildContext context) =>
    NxThemeColors.of(context).accentSecondary;

/// One shared 1 Hz clock for every countdown on screen (cheap: only listeners rebuild).
class TClock {
  TClock._();
  static final ValueNotifier<DateTime> now =
      ValueNotifier<DateTime>(DateTime.now().toUtc());
  static Timer? _timer;
  static int _users = 0;

  static void retain() {
    _users++;
    _timer ??= Timer.periodic(
        const Duration(seconds: 1), (_) => now.value = DateTime.now().toUtc());
  }

  static void release() {
    _users = _users > 0 ? _users - 1 : 0;
    if (_users == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// Mixin for pages that show countdowns.
mixin TClockUser<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    TClock.retain();
  }

  @override
  void dispose() {
    TClock.release();
    super.dispose();
  }
}

String _two(int v) => v < 10 ? '0$v' : '$v';

/// "2d 04:12:09" / "04:12" style countdown.
String fmtLeft(Duration d) {
  if (d.isNegative) return '00:00';
  final int days = d.inDays;
  final int h = d.inHours % 24;
  final int m = d.inMinutes % 60;
  final int s = d.inSeconds % 60;
  if (days > 0) return '${days}d ${_two(h)}:${_two(m)}:${_two(s)}';
  if (h > 0) return '${_two(h)}:${_two(m)}:${_two(s)}';
  return '${_two(m)}:${_two(s)}';
}

/// Local date + time with the UTC time beside it (all schedules are stored in UTC).
String fmtWhen(DateTime utc, {bool withUtc = true}) {
  final DateTime l = utc.toLocal();
  final DateTime u = utc.toUtc();
  final String local =
      '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
  return withUtc ? '$local  ·  ${_two(u.hour)}:${_two(u.minute)} UTC' : local;
}

class CountdownText extends StatelessWidget {
  const CountdownText(
      {super.key, required this.to, this.style, this.prefix = ''});
  final DateTime to;
  final TextStyle? style;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: TClock.now,
      builder: (BuildContext context, DateTime now, _) => Text(
          '$prefix${fmtLeft(to.difference(now))}',
          style: style ??
              const TextStyle(
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
    );
  }
}

String formatName(BuildContext context, TFormat f) => switch (f) {
      TFormat.singleElim => context.tx('حذفی تک‌باخت', 'Single elimination'),
      TFormat.doubleElim => context.tx('حذفی دوباخت', 'Double elimination'),
      TFormat.twoLegs => context.tx('رفت و برگشت', 'Two legs (aggregate)'),
      TFormat.roundRobin => context.tx('دوره‌ای (لیگ)', 'Round robin (league)'),
      TFormat.groupsKo => context.tx('گروهی + حذفی', 'Groups → knockout'),
      TFormat.swiss => context.tx('سوئیسی', 'Swiss'),
      TFormat.custom => context.tx('براکت دستی', 'Custom bracket'),
    };

IconData formatIcon(TFormat f) => switch (f) {
      TFormat.singleElim || TFormat.twoLegs => Icons.account_tree_rounded,
      TFormat.doubleElim => Icons.call_split_rounded,
      TFormat.roundRobin => Icons.table_chart_rounded,
      TFormat.groupsKo => Icons.grid_view_rounded,
      TFormat.swiss => Icons.swap_horiz_rounded,
      TFormat.custom => Icons.edit_note_rounded,
    };

(String, Color) statusLabel(BuildContext context, String status,
    {bool paused = false}) {
  if (paused) return (context.tx('متوقف', 'Paused'), tAccent(context));
  return switch (status) {
    'draft' => (context.tx('پیش‌نویس', 'Draft'), NxColors.textDim),
    'scheduled' => (context.tx('به‌زودی', 'Scheduled'), tAccent(context)),
    'registering' => (
        context.tx('ثبت‌نام باز', 'Registering'),
        NxColors.success
      ),
    'closed' => (
        context.tx('ثبت‌نام بسته', 'Registration closed'),
        tAccentSecondary(context)
      ),
    'drawn' => (context.tx('قرعه انجام شد', 'Drawn'), tAccent(context)),
    'live' => (context.tx('زنده', 'Live'), tAccentSecondary(context)),
    'finished' => (context.tx('پایان‌یافته', 'Finished'), tAccent(context)),
    'cancelled' => (context.tx('لغو شد', 'Cancelled'), NxColors.danger),
    _ => (status, NxColors.textDim),
  };
}

String momentLabel(BuildContext context, String code) => switch (code) {
      'reg_opens' => context.tx('شروع ثبت‌نام تا', 'Registration opens in'),
      'reg_closes' => context.tx('پایان ثبت‌نام تا', 'Registration closes in'),
      'draw' => context.tx('قرعه‌کشی تا', 'Draw in'),
      'start' => context.tx('شروع تا', 'Starts in'),
      _ => '',
    };

String regModeName(BuildContext context, String m) => switch (m) {
      'approval' => context.tx('با تأیید برگزارکننده', 'Manual approval'),
      'code' => context.tx('فقط با کد دعوت', 'Invite code only'),
      'code_approval' => context.tx('کد دعوت + تأیید', 'Code + approval'),
      _ => context.tx('آزاد', 'Open'),
    };

String entryStatusName(BuildContext context, String s) => switch (s) {
      'approved' => context.tx('تأیید شده', 'Approved'),
      'pending' => context.tx('در انتظار تأیید', 'Pending approval'),
      'waitlist' => context.tx('لیست انتظار', 'Waitlist'),
      'rejected' => context.tx('رد شده', 'Rejected'),
      'withdrawn' => context.tx('انصراف', 'Withdrawn'),
      'removed' => context.tx('حذف شده', 'Removed'),
      _ => s,
    };

/// Round name for a match of an elimination bracket.
String roundName(BuildContext context, TMatch m, int lastWinnersRound,
    int firstWinnersRound) {
  switch (m.bracket) {
    case 'GF':
      return context.tx('فینال بزرگ', 'Grand final');
    case 'GF2':
      return context.tx('فینال بزرگ (ریست)', 'Grand final reset');
    case 'P3':
      return context.tx('رده‌بندی', '3rd place');
    case 'L':
      return context.tx(
          'براکت بازنده‌ها · دور ${m.round}', 'Losers · round ${m.round}');
    case 'W':
      final int fromEnd = lastWinnersRound - m.round;
      if (fromEnd == 0) return context.tx('فینال', 'Final');
      if (fromEnd == 1) return context.tx('نیمه‌نهایی', 'Semi-finals');
      if (fromEnd == 2) return context.tx('یک‌چهارم', 'Quarter-finals');
      return context.tx('دور ${m.round - firstWinnersRound + 1}',
          'Round ${m.round - firstWinnersRound + 1}');
    case 'G':
      return context.tx(
          'گروه ${String.fromCharCode(64 + (m.groupNo ?? 1))} · دور ${m.round}',
          'Group ${String.fromCharCode(64 + (m.groupNo ?? 1))} · round ${m.round}');
    default:
      return m.label ?? context.tx('دور ${m.round}', 'Round ${m.round}');
  }
}

String notifText(BuildContext context, TNotification n) {
  final Map<String, dynamic> d = n.data;
  return switch (n.kind) {
    'approved' =>
      context.tx('ثبت‌نامت تأیید شد', 'You are in! Registration approved'),
    'registered' => context.tx('ثبت‌نامت ثبت شد و منتظر تأیید است',
        'Registered — waiting for approval'),
    'waitlisted' => context.tx(
        'ظرفیت پر است؛ در لیست انتظاری', 'Full — you are on the waitlist'),
    'promoted' => context.tx(
        'از لیست انتظار وارد تورنمنت شدی', 'A place opened up — you are in'),
    'rejected' =>
      context.tx('ثبت‌نامت رد شد', 'Your registration was declined'),
    'refund' => context.tx('ورودیه برگشت داده شد (${d['coins'] ?? 0} سکه)',
        'Entry fee refunded (${d['coins'] ?? 0} coins)'),
    'drawn' => context.tx('قرعه‌کشی انجام شد؛ براکت را ببین',
        'The draw is done — check the bracket'),
    'starting_soon' => context.tx('تورنمنت ۱۰ دقیقه‌ی دیگر شروع می‌شود',
        'The tournament starts in 10 minutes'),
    'started' => context.tx('تورنمنت شروع شد', 'The tournament has started'),
    'match_soon' =>
      context.tx('بازی‌ات ۱۰ دقیقه‌ی دیگر است', 'Your match is in 10 minutes'),
    'match_ready' => context.tx('بازی‌ات آماده است — دکمه‌ی آماده را بزن',
        'Your match is ready — tap Ready'),
    'result' => d['draw'] == true
        ? context.tx('بازی مساوی شد', 'Match drawn')
        : (d['won'] == true
            ? context.tx('بردی!', 'You won!')
            : context.tx('باختی', 'You lost')),
    'advanced' =>
      context.tx('به دور بعد رفتی', 'You advanced to the next round'),
    'eliminated' => context.tx('حذف شدی', 'You were eliminated'),
    'bye' => context.tx(
        'استراحت (bye) گرفتی و بالا رفتی', 'You got a bye and advance'),
    'walkover' => context.tx('به‌خاطر غیبت، بازی واگذار شد',
        'Walkover: the match was forfeited for not showing up'),
    'dispute' => context.tx('اختلاف در نتیجه؛ برگزارکننده بررسی می‌کند',
        'Result disputed — an organizer will review'),
    'result_corrected' => context.tx(
        'نتیجه توسط برگزارکننده اصلاح شد', 'An organizer corrected the result'),
    'prize' => context.tx('جایزه‌ات واریز شد: ${d['coins'] ?? d['gems'] ?? 0}',
        'Prize paid: ${d['coins'] ?? d['gems'] ?? 0}'),
    'time_changed' =>
      context.tx('زمان تورنمنت تغییر کرد', 'The tournament schedule changed'),
    'cancelled' => context.tx('تورنمنت لغو شد؛ ورودیه‌ها برگشت داده شد',
        'The tournament was cancelled — fees refunded'),
    'finished' => context.tx(
        'تورنمنت تمام شد. قهرمان: ${d['winner_name'] ?? '-'}',
        'Tournament finished. Champion: ${d['winner_name'] ?? '-'}'),
    'approval_needed' => context.tx(
        'ثبت‌نام جدید منتظر تأیید است', 'A new registration needs approval'),
    _ => n.kind,
  };
}

/// Small avatar circle with the first letter.
class TAvatar extends StatelessWidget {
  const TAvatar({super.key, required this.name, this.size = 26, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color avatarColor = color ?? tAccent(context);
    final String l = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: <Color>[avatarColor, avatarColor.withValues(alpha: 0.45)]),
      ),
      child: Text(l,
          style: TextStyle(
              fontSize: size * 0.48,
              fontWeight: FontWeight.w900,
              color: NxColors.navyDeep)),
    );
  }
}
