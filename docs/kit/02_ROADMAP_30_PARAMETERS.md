# نقشه راه NEXORA — ۳۰ پارامتر ثابت

این پارامترها تصمیم‌های پایه‌اند. ایجنت مجاز است با ثبت دلیل در `docs/DECISIONS.md` و **فقط اگر دلیل فنی قوی** وجود داشت، یکی را تغییر دهد (به‌خصوص P03، P09، P14، P24). ستون آخر نشان می‌دهد پارامتر در کدام مرحله نهایی/پیاده می‌شود.

| # | پارامتر | مقدار / تصمیم | مرحله مرتبط |
|---|---|---|---|
| P01 | نام و دامنه محصول | NEXORA؛ جهان کیهانی یکپارچه با ۷ دنیا | STEP_01 |
| P02 | پلتفرم هدف | Android فقط (فاز اول)؛ iOS خارج از دامنه | STEP_01 |
| P03 | حداقل نسخه اندروید | minSdk 24 (Android 7.0) پیشنهادی؛ targetSdk آخرین الزام Google Play | STEP_02 |
| P04 | فریم‌ورک اپ | Flutter + Dart (آخرین stable) | STEP_01 |
| P05 | معماری کد | Clean Architecture، feature-first، یک ماژول برای هر دنیا + core مشترک | STEP_03 |
| P06 | مدیریت state و DI | Riverpod (generator) + get_it فقط در صورت نیاز | STEP_03 |
| P07 | ناوبری | go_router با deep link و انتقال‌های سینمایی سفارشی | STEP_03 |
| P08 | موتور بازی | Flame برای 2D/2.5D؛ هر بازی یک GameModule مستقل | STEP_16 |
| P09 | استراتژی سه‌بعدی | اول spike؛ پیش‌فرض: 2.5D لایه‌ای + shader + Rive/Lottie؛ 3D واقعی فقط پس از اثبات عملکرد | STEP_05 |
| P10 | سیستم طراحی | Design Tokens (رنگ، تایپوگرافی، فاصله، حرکت، سایه، شیشه) + Component Library | STEP_04 |
| P11 | پالت رنگ | Cosmic Navy, Electric Blue, Violet, Ice White, Turquoise + تم‌های روشن/شیشه‌ای هر دنیا | STEP_04 |
| P12 | تایپوگرافی | فونت فارسی و لاتین با پشتیبانی کامل RTL؛ لایسنس آزاد | STEP_04 |
| P13 | سطوح کیفیت گرافیک | Low / Medium / High / Ultra + Auto-detect دستگاه | STEP_05 |
| P14 | بودجه عملکرد | هدف 60fps در High، حداقل 30fps در Low؛ cold start زیر ۳ ثانیه در دستگاه میان‌رده | STEP_05 |
| P15 | بودجه حجم | APK اولیه هدف زیر ~80MB؛ دارایی‌های سنگین به‌صورت دانلود تدریجی | STEP_05 |
| P16 | دسترسی‌پذیری حرکت | Reduced Motion سراسری؛ هر انیمیشن بلند قابل Skip | STEP_12 |
| P17 | بک‌اند اصلی | Supabase (Auth, Postgres, Storage, Realtime, Edge Functions) | STEP_06 |
| P18 | مدل داده | PostgreSQL نرمال‌شده؛ یک جدول profiles مرکزی؛ migration فقط با فایل SQL نسخه‌دار | STEP_06 |
| P19 | امنیت | RLS روی همه جدول‌ها؛ هیچ secret در کلاینت؛ منطق حساس فقط سمت سرور | STEP_07 |
| P20 | احراز هویت | ایمیل/OTP و Google؛ حالت مهمان/آفلاین بدون حساب | STEP_08 |
| P21 | اصالت نتایج | Server-authoritative برای همه بازی‌های آنلاین، XP، رتبه و مسابقه | STEP_17 |
| P22 | همگام‌سازی آفلاین | Local-first برای بازی آفلاین و تنظیمات (Drift/Isar)؛ sync هنگام اتصال | STEP_14 |
| P23 | Realtime و حضور | Supabase Realtime (Presence + Broadcast + Postgres Changes) | STEP_15 |
| P24 | صدا/تصویر | LiveKit (Cloud tier رایگان یا self-host)؛ تأیید هزینه در STEP_24 | STEP_24 |
| P25 | هوش مصنوعی ORACLE | LLM از طریق Edge Function (کلید فقط سمت سرور) + STT/TTS؛ tool-calling واقعی | STEP_27 |
| P26 | اقتصاد و پرداخت | فقط ارز داخلی (سکه/XP) در فاز اول؛ بدون قمار و پاداش تصادفی پولی | STEP_28 |
| P27 | مدیریت محتوا و ایمنی | گزارش، بلاک، moderation، قوانین انتشار، حذف حساب | STEP_25 |
| P28 | زبان‌ها | فارسی (پیش‌فرض، RTL) + انگلیسی؛ ساختار آماده زبان‌های بعدی | STEP_29 |
| P29 | CI/CD و تست | GitHub Actions: analyze، test، build APK/AAB، امضا با secrets؛ تست هر مرحله | STEP_02 |
| P30 | انتشار و پایش | Internal testing → Closed → Production در Google Play؛ Crashlytics/Sentry + تحلیل رفتار با حفظ حریم خصوصی | STEP_30 |

## فازبندی نقشه راه (نمای کلی ۳۰ مرحله)
- **فاز A — پایه (STEP_01–07):** مخزن، CI، معماری، سیستم طراحی، معماری گرافیک، بک‌اند، امنیت.
- **فاز B — هویت و ورود (STEP_08–14):** احراز هویت، آواتار، THE FIRST JOURNEY، Hub، پوسته اصلی، پیشرفت، Personal Orbit.
- **فاز C — بازی (STEP_15–22):** Realtime، موتور بازی، چندنفره سرور-محور، ۹ بازی، مسابقه و لیگ.
- **فاز D — اجتماع و ارتباط (STEP_23–26):** چت، تماس، Nova Gallery، Social Station.
- **فاز E — هوش و اقتصاد (STEP_27–28):** ORACLE، Exchange.
- **فاز F — کیفیت و انتشار (STEP_29–30):** QA، عملکرد، دسترسی‌پذیری، انتشار.

## اصل وابستگی
هر مرحله خروجی‌اش را در `docs/HANDOFF.md` ثبت می‌کند و مرحله بعد از همان شروع می‌کند. ترتیب را تغییر نده.
