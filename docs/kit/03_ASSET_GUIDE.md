# راهنمای دارایی‌ها (Assets) — NEXORA

همه تصاویری که صاحب پروژه فرستاده برش داده، نام‌گذاری و به ساختار اپ تبدیل شده‌اند. **229 فایل** در `assets/` و فهرست کامل با ابعاد، منبع و مرحله مصرف در `assets_manifest.json`.

## قوانین
- فرمت: **WebP با آلفا** (Flutter/Android پشتیبانی می‌کند). نام‌ها `snake_case`، بدون فاصله.
- ابعاد فایل‌ها حدود **۳× ابعاد منطقی** هستند (`suggested_logical_dp` در manifest). هیچ‌جا اندازه‌ی منبع را مستقیم استفاده نکن؛ با `Image` و `cacheWidth/cacheHeight` به اندازه‌ی نمایش دیکد کن تا حافظه نسوزد.
- دارایی‌های سنگین (Hub، سفینه، پورتال‌ها، تخته‌ها) را در STEP_05 به Asset Pack دانلودی ببر؛ دارایی‌های کوچک UI در APK بمانند.
- هر دارایی جدید باید در `assets_manifest.json` ثبت شود (path, size_px, source, category, used_in_steps).
- مسیرها را فقط از طریق یک کلاس ثابت `AppAssets` (تولید شده از manifest) استفاده کن؛ رشته‌ی خام مسیر در کد ممنوع.

## ساختار پوشه‌ها
| پوشه | تعداد | محتوا |
|---|---|---|
| `assets/characters/oracle/poses/` | 12 | ORACLE mascot, 12 poses (hero_wave, idle, calm, happy, present, confused, power, cheer, spin, sleep, craft, alert) |
| `assets/characters/oracle/emotes/` | 7 | ORACLE, front hero + 6 emotes (idle, smile, point, wave, cheer, alert) |
| `assets/characters/oracle/` | 1 |  |
| `assets/worlds/hub/ship/` | 1 | NEXORA CRUISER NX-01 spaceship |
| `assets/worlds/hub/props/` | 6 | Hub furniture/props: command platforms, desk, captain chairs, podium, gate |
| `assets/worlds/hub/portals/` | 8 | 7 world portals + Arcade gate (nova_gallery, orbit_network, nexora_arcade, oracle_core, personal_orbit, social_station, nexora_exchange) |
| `assets/worlds/hub/props/set/` | 13 | 13 Hub props (desk, holo chamber, globe, projector, terminal, door, seat, rack, core, pod, floor pad, crate, kiosk) |
| `assets/ui/holo_frames/` | 10 | Hologram frames/panels (+ luminance-keyed glow sheets) |
| `assets/ui/kit/` | 16 | UI kit pieces (auto-named by kind: icon/bar/panel/element) |
| `assets/worlds/personal_orbit/decor/` | 16 | 16 Personal Orbit decor items |
| `assets/avatar/gear/` | 16 | 16 avatar gear items (helmet, jacket, vest, glove, boots, backpack, watch...) |
| `assets/progression/achievements/` | 15 | 10 achievement badges + 5 trophies |
| `assets/arcade/pedestals/` | 9 | 9 Arcade game pedestals (carrom, finger_soccer, snakes_ladders, quiz, backgammon, billiards, uno, ludo, mafia) |
| `assets/progression/club_badges/` | 6 | 6 club/community badges (scorpion, wolf, yakuza, monster, bermuda, stone) |
| `assets/games/carrom/` | 2 | Carrom boards (NX black-gold, classic wood) |
| `assets/games/backgammon/` | 5 | Backgammon NX board, checkers, dice |
| `assets/games/billiards/` | 1 | Billiards table (portrait) |
| `assets/games/shared/discs/` | 32 | 32 shared discs: carrom men, suit discs, strikers, emblems |
| `assets/games/finger_soccer/pucks/iso/` | 11 | Pucks, isometric (shop/preview) |
| `assets/games/finger_soccer/pucks/top/` | 11 | Pucks, top-down derived faces (gameplay) |
| `assets/games/finger_soccer/pucks/thumb/` | 11 | Pucks, 96px thumbnails |
| `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/iso/` | 6 | National-team pucks - LICENSED MARKS, placeholder only |
| `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/top/` | 6 | National-team pucks top - LICENSED MARKS, placeholder only |
| `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/thumb/` | 6 | National-team pucks thumb - LICENSED MARKS, placeholder only |
| `assets/games/finger_soccer/` | 2 | Finger Soccer pitch + ball (generated) |


## تنظیم pubspec.yaml (پوشه‌ها غیربازگشتی‌اند)
```yaml
flutter:
  assets:
    - assets/characters/oracle/poses/
    - assets/characters/oracle/emotes/
    - assets/characters/oracle/
    - assets/worlds/hub/ship/
    - assets/worlds/hub/props/
    - assets/worlds/hub/portals/
    - assets/worlds/hub/props/set/
    - assets/ui/holo_frames/
    - assets/ui/kit/
    - assets/worlds/personal_orbit/decor/
    - assets/avatar/gear/
    - assets/progression/achievements/
    - assets/arcade/pedestals/
    - assets/progression/club_badges/
    - assets/games/carrom/
    - assets/games/backgammon/
    - assets/games/billiards/
    - assets/games/shared/discs/
    - assets/games/finger_soccer/pucks/iso/
    - assets/games/finger_soccer/pucks/top/
    - assets/games/finger_soccer/pucks/thumb/
    - assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/iso/
    - assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/top/
    - assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/thumb/
    - assets/games/finger_soccer/
```
در Flame: `images.prefix = 'assets/'` و مسیر مثل `games/finger_soccer/pucks/top/puck_nx_green_top.webp`.

## هشدارهای مهم (حتماً بخوان)
1. **نشان‌های ملی (اسپانیا، پرتغال، انگلیس، ژاپن، فرانسه، هلند — JFA/FFF/KNVB/FPF…)** لوگوی ثبت‌شده‌ی فدراسیون‌ها هستند. در `pucks_PLACEHOLDER_LICENSED/` گذاشته شده‌اند و **فقط برای نمونه/نمایش داخلی**‌اند. قبل از انتشار در Google Play یا باید مجوز بگیری یا طرح اورجینال جایگزین کنی (ایجنت: در STEP_28/30 این را بررسی و جایگزین کن، پیش‌فرض بازی باید از پاک‌های غیرمجوزی استفاده کند).
2. **پاک‌های top-down** (`pucks/top`) از روی نمای مایل (iso) استخراج و دایره‌ای شده‌اند؛ تقریب قابل‌قبول‌اند ولی برای کیفیت نهایی بهتر است نسخه‌ی واقعاً top-down تولید شود (پرامپت در `06_PROMPTS.md`).
3. برش‌ها خودکارند: لبه‌ی بعضی تصاویر (به‌خصوص نشان‌های باشگاه که روی پس‌زمینه تیره بودند و دیسک‌های مشکی) ممکن است هاله‌ی نازک داشته باشد؛ در صورت دیده شدن، با ابزار `tools/` یا مات دستی اصلاح کن.
4. `ui/kit/ui_*` به‌صورت خودکار بر اساس اندازه نام‌گذاری شده‌اند (icon/bar/panel/element). در STEP_04 به نام معنایی تغییر بده و در manifest به‌روز کن.
5. تخته‌ها (کارم، بیلیارد، تخته‌نرد) تصویر کامل با قاب‌اند؛ مستطیل میدان بازی در `note`‌ها تقریبی است. قبل از استفاده، ناحیه‌ی بازی را با پیکسل‌سنجی دقیق کن و در `GameModule` ثبت کن.
6. پیکسل‌های «شیت glow» (`holo_sheet_a/b`) با کلید روشنایی ساخته شده‌اند؛ با `BlendMode.plus` یا `screen` استفاده شوند.
7. ORACLE: ۱۲ ژست + ۷ ایموت → نگاشت پیشنهادی به حالت‌ها: idle→idle، listening→calm، thinking→confused/craft، speaking→present/happy، success→cheer، alert→alert، sleep→sleep، power-up→power/spin.
