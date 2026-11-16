# STEP_16 — معماری موتور بازی (Flame) و چارچوب مشترک بازی‌ها

> مرحله 16 از ۳۰ | قبلی: [STEP_15 — Realtime، حضور و دوستی](STEP_15.md) | بعدی: [STEP_17 — چندنفره سرور-محور: اتاق، Matchmaking، ضد تقلب](STEP_17.md)

## ورودی (آنچه باید از قبل آماده باشد)
معماری (STEP_03)، کیفیت و RenderProfile (STEP_05)، آواتار (STEP_09)، پیشرفت (STEP_13) و پارامتر P08.
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت یک چارچوب واحد که ۹ بازی روی آن ساخته شوند، با تأکید قوی بر گرافیک و کیفیت حس بازی.

## دستورالعمل‌ها
1. اینترفیس `GameModule` (id، نام، تعداد بازیکن، حالت‌ها، `createGame()`، `rulesEngine`، `assets`) و ثبت در `GameRegistry`.
2. پایه مشترک: `NexoraGame extends FlameGame` با چرخه عمر، مدیریت صحنه، دوربین، ورودی لمسی/ژست، سیستم صدا، و بارگذاری دارایی.
3. **جداسازی قوانین از رندر:** `RulesEngine` (Dart خالص، بدون Flame) که هم کلاینت و هم سرور (Edge Function یا کپی منطق) از آن استفاده کنند؛ این پایه اصالت نتایج است.
4. ماژول‌های مشترک: Turn Manager، Timer، Dice، Card Deck، Physics wrapper (برای بازی‌های فیزیکی)، Replay/Recorder، Hint/Tutorial.
5. UI بازی: HUD، پنل بازیکنان با آواتار، چت سریع/ایموجی، منوی توقف، صفحه نتیجه با XP.
6. ساخت یک بازی نمونه حداقلی برای اثبات چارچوب (مثلاً Tic-Tac-Toe موقت که بعداً حذف می‌شود).

## تأکید گرافیک و معماری
هویت بصری هر بازی: Theme اختصاصی (`GameTheme`)، سیستم ذرات، نور و سایه، انیمیشن‌های حس‌دار (juice): لرزش دوربین، ردپا، impact effect، ریزانیمیشن UI. رزولوشن رندر و تعداد افکت‌ها از RenderProfile. هر بازی باید تفاوت چشمگیر با نسخه ساده داشته باشد.

## خروجی‌های تحویلی
- Game framework
- GameRegistry
- RulesEngine مشترک
- docs/GAME_ARCHITECTURE.md

## معیار پذیرش (Definition of Done)
- [ ] بازی نمونه روی Low حداقل 30fps و روی High 60fps
- [ ] RulesEngine بدون وابستگی به Flame تست واحد دارد
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
قرارداد GameModule/RulesEngine و پوشه‌بندی را دقیق در HANDOFF.md بنویس؛ STEP_17 تا STEP_22 به آن وابسته‌اند.
بعد از تأیید DoD، فایل `STEP_17.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/games/shared/discs/` (32): disc_cream, disc_black, disc_red, disc_cream_crown, disc_black_crown, disc_red_crown …
