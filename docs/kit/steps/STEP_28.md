# STEP_28 — NEXORA EXCHANGE — بازار دیجیتال

> مرحله 28 از ۳۰ | قبلی: [STEP_27 — ORACLE CORE — دستیار هوشمند](STEP_27.md) | بعدی: [STEP_29 — QA، عملکرد، دسترسی‌پذیری و بین‌المللی‌سازی](STEP_29.md)

## ورودی (آنچه باید از قبل آماده باشد)
آواتار و کاتالوگ (STEP_09)، Personal Orbit (STEP_14)، پیشرفت (STEP_13)، پارامتر P26.
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
اقتصاد داخلی شفاف و امن برای آیتم‌های ظاهری.

## دستورالعمل‌ها
1. جدول‌ها: `catalog_items`، `inventory`، `wallets`، `transactions`، `creator_submissions`.
2. ارز داخلی (سکه) که از فعالیت و دستاورد به‌دست می‌آید؛ تراکنش‌ها فقط سمت سرور، اتمی (atomic) و قابل ممیزی.
3. فروشگاه: لباس، لوازم، قاب، تم، تزئین فضای شخصی، افکت، آیتم‌های بازی؛ پیش‌نمایش روی آواتار.
4. **ممنوع:** هر مکانیزم قمار، شرط‌بندی یا لوت‌باکس پولی/تصادفی. قیمت و محتوا شفاف.
5. محتوای سازندگان (اولیه): ارسال، بازبینی و انتشار؛ مجوز و ایمنی محتوا.
6. پرداخت پول واقعی را فقط پس از بررسی قوانین فروشگاه و تأیید صاحب پروژه اضافه کن؛ در این مرحله مسیر آماده باشد اما غیرفعال.

## تأکید گرافیک و معماری
ویترین فروشگاه سینمایی و شفاف: پیش‌نمایش چرخشی آیتم روی آواتار، نمایش کیفیت (rarity) فقط بصری. نور و نمایش هر آیتم با RenderProfile.

## خروجی‌های تحویلی
- Exchange کامل با ارز داخلی
- پیش‌نمایش آیتم‌ها

## معیار پذیرش (Definition of Done)
- [ ] خرید اتمی است و موجودی منفی یا دوباره‌خرجی ممکن نیست (تست)
- [ ] هیچ مکانیزم شانس-پول وجود ندارد
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
قوانین اقتصاد و رابط پرداخت (غیرفعال) را در HANDOFF.md ثبت کن.
بعد از تأیید DoD، فایل `STEP_29.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/worlds/personal_orbit/decor/` (16): plant_bowl, ring_sculpture, crystal_cluster, light_pillar, satellite, terrarium_globe …
- `assets/avatar/gear/` (16): helmet, jacket, armor_vest, glove, boots, backpack …
- `assets/games/finger_soccer/pucks/iso/` (11): puck_frost_b_iso, puck_noble_lion_iso, puck_cosmic_crown_iso, puck_eagle_gold_iso, puck_nx_green_iso, puck_royal_lion_iso …
- `assets/games/finger_soccer/pucks/thumb/` (11): puck_frost_b_thumb, puck_noble_lion_thumb, puck_cosmic_crown_thumb, puck_eagle_gold_thumb, puck_nx_green_thumb, puck_royal_lion_thumb …
- `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/iso/` (6): puck_nat_spain_iso, puck_nat_portugal_iso, puck_nat_england_iso, puck_nat_japan_iso, puck_nat_france_iso, puck_nat_netherlands_iso
- `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/thumb/` (6): puck_nat_spain_thumb, puck_nat_portugal_thumb, puck_nat_england_thumb, puck_nat_japan_thumb, puck_nat_france_thumb, puck_nat_netherlands_thumb
