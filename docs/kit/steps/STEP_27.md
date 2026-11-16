# STEP_27 — ORACLE CORE — دستیار هوشمند

> مرحله 27 از ۳۰ | قبلی: [STEP_26 — SOCIAL STATION — اجتماعات](STEP_26.md) | بعدی: [STEP_28 — NEXORA EXCHANGE — بازار دیجیتال](STEP_28.md)

## ورودی (آنچه باید از قبل آماده باشد)
Registry و capabilities (STEP_03)، Hub و گوی (STEP_11)، همه دنیاها (STEP_18–26)، پارامتر P25.
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت دستیار واقعی که کار انجام می‌دهد، نه وانمود.

## دستورالعمل‌ها
1. Edge Function پراکسی LLM (کلید فقط سمت سرور، rate limit، لاگ هزینه).
2. **Tool-calling واقعی:** ابزارها (navigate_to_world، search_feature، start_game_room، invite_friend، show_achievements، explain_game_rules …) که ORACLE می‌تواند فراخوانی کند و **نتیجه واقعی** را گزارش دهد؛ اگر ابزار شکست خورد صادقانه بگوید.
3. آگاهی از زمینه: دنیای فعلی، صفحه فعلی، نقش کاربر؛ بدون ارسال داده خصوصی غیرضروری به مدل.
4. چت متنی، ورودی صوتی (STT)، پاسخ صوتی (TTS)، فارسی و انگلیسی؛ انتخاب فراهم‌کننده کم‌هزینه با ثبت در DECISIONS.md.
5. دستیارهای تخصصی (راهنمای بازی، راهنمای برنامه، مدیر فعالیت‌ها) با system prompt جدا.
6. ایمنی: محدودیت‌ها، حریم خصوصی، تأیید کاربر برای اقدام‌های مهم (خرید، حذف).

## تأکید گرافیک و معماری
گوی سه‌بعدی/نیمه‌سه‌بعدی شناور: انیمیشن حالت‌ها (گوش‌دادن، فکر کردن، صحبت)، واکنش به صدا، تغییر رنگ با دنیای فعلی و حرکت نرم در سراسر برنامه. در Low نسخه ساده 2D با همان حالت‌ها.

## خروجی‌های تحویلی
- ORACLE متنی و صوتی
- ابزارهای واقعی
- گوی بصری

## معیار پذیرش (Definition of Done)
- [ ] درخواست «مرا به آرکید ببر و اتاق Ludo بساز» واقعاً اجرا می‌شود
- [ ] در شکست ابزار پاسخ صادقانه می‌دهد (تست)
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
فهرست ابزارها و راه افزودن ابزار جدید را در HANDOFF.md بنویس.
بعد از تأیید DoD، فایل `STEP_28.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/characters/oracle/poses/` (12): hero_wave, idle, calm, happy, present, confused …
- `assets/characters/oracle/emotes/` (7): hero_front, emote_idle, emote_smile, emote_point, emote_wave, emote_cheer …
- `assets/characters/oracle/` (1): hero_orbit
