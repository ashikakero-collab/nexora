import '../models/nova_models.dart';

/// Genuine welcome / tips posts from the NEXORA Official channel.
/// They describe real features of this build; they carry no fake likes or comments.
List<NovaPost> buildOfficialSeed(DateTime now) {
  NovaPost p(int i, int hoursAgo, String fa, String en, NovaVisual v, {bool motion = false}) => NovaPost(
        id: 'official_$i',
        authorId: kNovaOfficialId,
        authorName: 'NEXORA Official',
        official: true,
        text: fa,
        textEn: en,
        visual: v,
        motion: motion,
        createdAt: now.subtract(Duration(hours: hoursAgo)),
      );

  return <NovaPost>[
    p(
      1,
      1,
      'به NOVA GALLERY خوش آمدی ✨ اینجا گالری کیهانی توست: پست بگذار، استوری بساز و لحظه‌هایت را با دنیاهای دیگر NEXORA به اشتراک بگذار. #خوش_آمدید #NEXORA',
      'Welcome to NOVA GALLERY ✨ This is your cosmic gallery: post, create stories and share moments with the other NEXORA worlds. #welcome #NEXORA',
      const NovaVisual(kind: NovaVisualKind.gradient, gradient: 0),
      motion: true,
    ),
    p(
      2,
      3,
      'نکته: با # هشتگ بساز و با @ از کسی نام ببر. روی هر هشتگ بزن تا همه‌ی پست‌های آن را در اکتشاف ببینی. #نکته #هشتگ',
      'Tip: use # for hashtags and @ to mention someone. Tap any hashtag to see every post with it in Explore. #tips #hashtags',
      const NovaVisual(kind: NovaVisualKind.gradient, gradient: 3),
    ),
    p(
      3,
      6,
      'استوری‌ها ۲۴ ساعت می‌مانند و بعد خودبه‌خود محو می‌شوند. دایره‌ی + بالای فید را بزن. #استوری #نکته',
      'Stories last 24 hours and then fade away on their own. Tap the + circle above the feed. #stories #tips',
      const NovaVisual(kind: NovaVisualKind.asset, gradient: 5, asset: 'decor:orb_rings'),
    ),
    p(
      4,
      10,
      'پست حرکتی بساز تا در ریلز با گرادیان زنده پخش شود. ویدئو و تصویر واقعی بعد از اتصال سرور اضافه می‌شوند. #ریلز #نکته',
      'Make a motion post and it plays in Reels as a living gradient. Real video and photo uploads arrive once the server is connected. #reels #tips',
      const NovaVisual(kind: NovaVisualKind.gradient, gradient: 6),
      motion: true,
    ),
    p(
      5,
      20,
      'هر پست را با یک لمس به ORBIT NETWORK بفرست و در چت به اشتراک بگذار. دنیاها به هم وصل‌اند. #اوربیت #NEXORA',
      'Send any post to ORBIT NETWORK with one tap and share it in a chat. The worlds are connected. #orbit #NEXORA',
      const NovaVisual(kind: NovaVisualKind.asset, gradient: 2, asset: 'gear:planet_orb'),
    ),
    p(
      6,
      30,
      'آماده‌ی رقابتی؟ در NEXORA ARCADE نه بازی منتظر توست؛ از کرم تا مافیا. نتیجه‌هایت در مدار شخصی‌ات ثبت می‌شوند. #آرکید #بازی',
      'Ready to compete? Nine games wait in NEXORA ARCADE, from Carrom to Mafia. Your results are recorded in your Personal Orbit. #arcade #games',
      const NovaVisual(kind: NovaVisualKind.asset, gradient: 4, asset: 'pedestal:carrom'),
    ),
  ];
}

NovaNotification buildWelcomeNotification(DateTime now) => NovaNotification(
      id: 'notif_welcome',
      kind: NovaNotifKind.system,
      textFa: 'به NOVA GALLERY خوش آمدی. اولین پستت را منتشر کن!',
      textEn: 'Welcome to NOVA GALLERY. Publish your first post!',
      at: now,
    );
