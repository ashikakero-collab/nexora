# STEP_22 — مسابقات، لیگ‌ها و رتبه‌بندی

> مرحله 22 از ۳۰ | قبلی: [STEP_21 — Mafia — بازی اجتماعی اطلاعات پنهان](STEP_21.md) | بعدی: [STEP_23 — ORBIT NETWORK — پیام‌رسان (متن و گروه)](STEP_23.md)

## ورودی (آنچه باید از قبل آماده باشد)
همه بازی‌ها (STEP_18–21)، چندنفره (STEP_17)، پیشرفت (STEP_13)، دوستی (STEP_15).
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
سیستم رقابتی واقعی روی بازی‌ها.

## دستورالعمل‌ها
1. جدول‌ها: `tournaments`، `tournament_entries`، `brackets`، `leagues`، `seasons`، `rankings`.
2. فرمت‌ها: جدول حذفی، گروهی، لیگ؛ عمومی و خصوصی (با دعوت)؛ مسابقه جامعه (برای STEP_26).
3. الگوریتم رتبه (مثلاً Elo/Glicko) سمت سرور و بروزرسانی فقط از نتیجه رسمی match.
4. رتبه‌بندی جهانی، دوستان و فصلی با بازنشانی فصل و جوایز دستاوردی.
5. زمان‌بندی خودکار نوبت‌ها، یادآوری و عبور خودکار (walkover).
6. امکان تماشای مسابقه برای بازی‌های پشتیبانی‌شده (spectator با تأخیر کوتاه).

## تأکید گرافیک و معماری
UI رقابتی سینمایی: براکت گرافیکی تعاملی، صحنه جام و تقدیر برنده، تابلوی امتیاز با انیمیشن. حالت ساده‌شده برای دستگاه ضعیف.

## خروجی‌های تحویلی
- سیستم مسابقه و لیگ
- رتبه‌بندی
- Spectator

## معیار پذیرش (Definition of Done)
- [ ] نتیجه فقط از match رسمی سرور وارد رتبه می‌شود
- [ ] یک جام ۸ نفره کامل با کاربران واقعی اجرا می‌شود
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
API ساخت مسابقه (برای Social Station) را در HANDOFF.md بنویس.
بعد از تأیید DoD، فایل `STEP_23.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/progression/achievements/` (15): badge_explorer, badge_gamer, badge_champion, badge_team, badge_legend, badge_idea …
- `assets/progression/club_badges/` (6): badge_club_scorpion, badge_club_wolf, badge_club_yakuza, badge_club_monster, badge_club_bermuda, badge_club_stone
