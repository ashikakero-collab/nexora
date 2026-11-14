// Port of src/net/supabase.ts: client + rpc helper with Persian error mapping + shared row helpers.
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

const kSupabaseUrl = 'https://eisstodgncimypdawisy.supabase.co';
const kSupabaseAnon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpc3N0b2RnbmNpbXlwZGF3aXN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyMjkwMTAsImV4cCI6MjEwOTgwNTAxMH0.uEPldAQjJdRyZTGXaz_OpFR7WpFXMiPXlW1S34cR3p8';

SupabaseClient get sb => Supabase.instance.client;
bool supaReady = false;

Future<void> initSupabase() async {
  try {
    await Supabase.initialize(
      url: kSupabaseUrl,
      anonKey: kSupabaseAnon,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: true),
      realtimeClientOptions: const RealtimeClientOptions(logLevel: RealtimeLogLevel.error),
    );
    supaReady = true;
  } catch (_) {
    supaReady = false;
  }
}

/// Thin typed view over a JSON row.
class Rec {
  final Map<String, dynamic> m;
  const Rec(this.m);
  factory Rec.of(Object? o) => Rec(o is Map ? Map<String, dynamic>.from(o) : <String, dynamic>{});
  dynamic operator [](String k) => m[k];
  String s(String k, [String d = '']) => m[k]?.toString() ?? d;
  String? str(String k) => m[k]?.toString();
  int i(String k, [int d = 0]) => m[k] is num ? (m[k] as num).toInt() : int.tryParse('${m[k]}') ?? d;
  double d(String k, [double d = 0]) => m[k] is num ? (m[k] as num).toDouble() : double.tryParse('${m[k]}') ?? d;
  bool b(String k) => m[k] == true;
  Rec rec(String k) => Rec.of(m[k]);
  List<Rec> list(String k) => (m[k] is List ? m[k] as List : const []).map(Rec.of).toList();
  Rec merge(Map<String, dynamic> o) => Rec({...m, ...o});
}

List<Rec> recs(Object? data) => (data is List ? data : const []).map(Rec.of).toList();

const List<(String, String)> _errMap = [
  (r'not enough gems', 'الماس کافی نداری'),
  (r'already owned', 'این دیسک را قبلاً داری'),
  (r'not owned', 'این دیسک را نداری'),
  (r'already in club', 'تو الان عضو یک باشگاه هستی'),
  (r'club full', 'ظرفیت باشگاه پر است'),
  (r'invite only', 'این باشگاه فقط با دعوت عضو می‌گیرد'),
  (r'level too low', 'سطحت برای این کار کافی نیست'),
  (r'officer only', 'فقط افسران باشگاه'),
  (r'leader only', 'فقط رهبر باشگاه'),
  (r'admin only', 'فقط مدیران'),
  (r'already claimed', 'قبلاً دریافت کردی'),
  (r'not completed', 'هنوز کامل نشده'),
  (r'bad size', 'اندازه‌ی نامعتبر'),
  (r'already joined', 'قبلاً ثبت‌نام کردی'),
  (r'\bblocked\b', 'این کاربر تو را مسدود کرده'),
  (r'title required', 'عنوان لازم است'),
  (r'season running', 'فصل هنوز تمام نشده'),
  (r'cannot dm yourself', 'نمی‌توانی به خودت پیام بدهی'),
  (r'not public', 'این گفتگو عمومی نیست'),
  (r'club not found', 'باشگاه پیدا نشد'),
  (r'request not found', 'درخواست پیدا نشد'),
  (r'not allowed|bad action', 'اجازه‌ی این کار را نداری'),
  (r'clubs_name_key|duplicate key.*clubs.*name', 'این نام باشگاه گرفته شده'),
  (r'clubs_tag_key|duplicate key.*tag', 'این تگ گرفته شده'),
  (r'tag.*check|clubs_tag_check', 'تگ باید ۲ تا ۵ حرف/عدد انگلیسی بزرگ باشد'),
  (r'room not found', 'اتاق پیدا نشد'),
  (r'room closed', 'این اتاق بسته شده'),
  (r'teams not full', 'هنوز همه‌ی جایگاه‌ها پر نشده'),
  (r'not all ready', 'همه‌ی بازیکن‌ها آماده نیستند'),
  (r'seat taken', 'این جایگاه گرفته شده'),
  (r'host only', 'فقط میزبان می‌تونه این کار رو بکنه'),
  (r'organizer only', 'فقط برگزارکننده می‌تونه این کار رو بکنه'),
  (r'registration closed', 'ثبت‌نام این تورنمنت بسته شده'),
  (r'\bfull\b', 'ظرفیت تکمیل است'),
  (r'already started', 'از قبل شروع شده'),
  (r'match running', 'بازی در جریان است'),
  (r'match not live', 'این مسابقه دیگر فعال نیست'),
  (r'match not ready|not playable', 'این مسابقه هنوز آماده نیست'),
  (r'not in this match', 'تو در این مسابقه نیستی'),
  (r'need at least 2', 'حداقل ۲ شرکت‌کننده لازم است'),
  (r'bad slot', 'جایگاه نامعتبر'),
  (r'not signed in|JWT|unauthorized', 'اول وارد حساب شو'),
  (r'duplicate key.*username|profiles_username_key', 'این نام کاربری قبلاً گرفته شده'),
  (r'duplicate key.*tournament_entries|tournament_id, captain', 'قبلاً در این تورنمنت ثبت‌نام کردی'),
  (r'username.*check|char_length', 'نام کاربری باید ۳ تا ۲۰ کاراکتر باشد'),
  (r'Invalid login credentials', 'ایمیل یا رمز عبور اشتباه است'),
  (r'Email not confirmed', 'ایمیلت هنوز تأیید نشده؛ صندوق ایمیل را ببین'),
  (r'User already registered|already been registered|email_exists', 'با این ایمیل قبلاً حساب ساخته شده'),
  (r'Password should be at least|weak_password', 'رمز عبور باید حداقل ۶ کاراکتر باشد'),
  (r'rate limit|too many|over_email_send_rate_limit', 'درخواست زیاد بود؛ کمی بعد دوباره امتحان کن'),
  (r'invalid.*email|validate email|email_address_invalid', 'ایمیل معتبر نیست'),
  (r'Anonymous sign-ins are disabled', 'ورود مهمان غیرفعال است'),
  (r'SocketException|Failed host lookup|Network|timeout|Connection', 'اتصال اینترنت برقرار نیست'),
];
final _compiled = [for (final e in _errMap) (RegExp(e.$1, caseSensitive: false), e.$2)];

String errFa(Object? e) {
  String m;
  if (e is PostgrestException) {
    m = e.message;
  } else if (e is AuthException) {
    m = '${e.message} ${e.code ?? ''}';
  } else {
    m = e?.toString() ?? '';
  }
  for (final (re, fa) in _compiled) {
    if (re.hasMatch(m)) return fa;
  }
  return m.isNotEmpty ? 'خطا: ${m.substring(0, math.min(80, m.length))}' : 'خطای ناشناخته؛ دوباره امتحان کن';
}

/// rpc that throws on error (callers map with errFa)
Future<dynamic> rpc(String fn, [Map<String, dynamic>? args]) => sb.rpc(fn, params: args);

// ---- level formula shared with the backend ----
int xpForLevel(int l) => (math.max(1, l) - 1) * (math.max(1, l) - 1) * 100;
int levelOf(int xp) => math.max(1, (math.sqrt(math.max(0, xp) / 100)).floor() + 1);

class LevelProg {
  final int level, cur, need;
  final double frac;
  const LevelProg(this.level, this.cur, this.need, this.frac);
}

LevelProg levelProgress(int xp) {
  final l = levelOf(xp), a = xpForLevel(l), b = xpForLevel(l + 1);
  return LevelProg(l, xp - a, b - a, (xp - a) / (b - a));
}

int teamSize(String m) => m == '1v1' ? 1 : m == '2v2' ? 2 : 3;
