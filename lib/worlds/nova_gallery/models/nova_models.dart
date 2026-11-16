// Pure-Dart data models for NOVA GALLERY. Every model is JSON-ready so the
// online sync layer (Supabase tables posts/stories/likes/comments/saves...) can
// mirror them later without changing the UI.

/// Author id used by the seeded official channel.
const String kNovaOfficialId = 'nexora_official';

/// How long a story lives.
const Duration kStoryLifetime = Duration(hours: 24);

DateTime _time(Object? v) {
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) {
    final p = DateTime.tryParse(v);
    if (p != null) return p;
    final n = int.tryParse(v);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _timeOrNull(Object? v) => v == null ? null : _time(v);

/// [photo] = an uploaded image in the Supabase Storage bucket `nx-media` (online only).
enum NovaVisualKind { none, gradient, asset, photo }

/// Optional visual attached to a post: a cosmic gradient card or a built-in art asset.
class NovaVisual {
  const NovaVisual({this.kind = NovaVisualKind.none, this.gradient = 0, this.asset = '', this.url = ''});

  final NovaVisualKind kind;

  /// Public URL of an uploaded photo ([NovaVisualKind.photo]).
  final String url;
  final int gradient; // index into the gradient style list (also used as backdrop for assets)
  final String asset; // ArtAsset ref, e.g. 'gear:helmet'

  static const NovaVisual none = NovaVisual();

  bool get isNone => kind == NovaVisualKind.none;

  Map<String, dynamic> toJson() => <String, dynamic>{'k': kind.name, 'g': gradient, 'a': asset, if (url.isNotEmpty) 'url': url};

  static NovaVisual fromJson(Object? raw) {
    if (raw is! Map) return NovaVisual.none;
    final String k = '${raw['k'] ?? 'none'}';
    NovaVisualKind kind = NovaVisualKind.none;
    for (final v in NovaVisualKind.values) {
      if (v.name == k) kind = v;
    }
    return NovaVisual(
      kind: kind,
      gradient: (raw['g'] as num?)?.toInt() ?? 0,
      asset: '${raw['a'] ?? ''}',
      url: '${raw['url'] ?? ''}',
    );
  }
}

class NovaComment {
  NovaComment({required this.id, required this.authorId, required this.authorName, required this.text, required this.at});

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'at': at.millisecondsSinceEpoch,
      };

  static NovaComment fromJson(Map<String, dynamic> j) => NovaComment(
        id: '${j['id']}',
        authorId: '${j['authorId'] ?? ''}',
        authorName: '${j['authorName'] ?? ''}',
        text: '${j['text'] ?? ''}',
        at: _time(j['at']),
      );
}

class NovaPost {
  NovaPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.textEn,
    this.official = false,
    this.visual = NovaVisual.none,
    this.motion = false,
    this.editedAt,
    Set<String>? likedBy,
    List<NovaComment>? comments,
  })  : likedBy = likedBy ?? <String>{},
        comments = comments ?? <NovaComment>[];

  final String id;
  final String authorId;
  final String authorName;
  String text;

  /// English text (official posts are bilingual). Null for user posts.
  final String? textEn;
  final bool official;
  NovaVisual visual;

  /// Motion post: rendered as an animated gradient in Reels (no video files offline).
  bool motion;
  final DateTime createdAt;
  DateTime? editedAt;
  final Set<String> likedBy;
  final List<NovaComment> comments;

  int get likeCount => likedBy.length;
  bool likedByUser(String userId) => likedBy.contains(userId);

  String textFor(bool fa) => (!fa && textEn != null && textEn!.isNotEmpty) ? textEn! : text;

  /// All hashtags in both language versions (lower-case, without '#').
  Set<String> get hashtags => <String>{...NovaText.hashtags(text), ...NovaText.hashtags(textEn ?? '')};
  Set<String> get mentions => <String>{...NovaText.mentions(text), ...NovaText.mentions(textEn ?? '')};

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        if (textEn != null) 'textEn': textEn,
        'official': official,
        'visual': visual.toJson(),
        'motion': motion,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (editedAt != null) 'editedAt': editedAt!.millisecondsSinceEpoch,
        'likedBy': likedBy.toList(),
        'comments': comments.map((NovaComment c) => c.toJson()).toList(),
      };

  static NovaPost fromJson(Map<String, dynamic> j) => NovaPost(
        id: '${j['id']}',
        authorId: '${j['authorId'] ?? ''}',
        authorName: '${j['authorName'] ?? ''}',
        text: '${j['text'] ?? ''}',
        textEn: j['textEn'] as String?,
        official: j['official'] == true,
        visual: NovaVisual.fromJson(j['visual']),
        motion: j['motion'] == true,
        createdAt: _time(j['createdAt']),
        editedAt: _timeOrNull(j['editedAt']),
        likedBy: ((j['likedBy'] as List?) ?? const <dynamic>[]).map((dynamic e) => '$e').toSet(),
        comments: ((j['comments'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map e) => NovaComment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class NovaStory {
  NovaStory({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.gradient,
    required this.createdAt,
    this.viewed = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final int gradient;
  final DateTime createdAt;
  bool viewed;

  DateTime get expiresAt => createdAt.add(kStoryLifetime);
  bool isActive(DateTime now) => now.isBefore(expiresAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'gradient': gradient,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'viewed': viewed,
      };

  static NovaStory fromJson(Map<String, dynamic> j) => NovaStory(
        id: '${j['id']}',
        authorId: '${j['authorId'] ?? ''}',
        authorName: '${j['authorName'] ?? ''}',
        text: '${j['text'] ?? ''}',
        gradient: (j['gradient'] as num?)?.toInt() ?? 0,
        createdAt: _time(j['createdAt']),
        viewed: j['viewed'] == true,
      );
}

/// Notification kinds shown in the Nova notifications tab.
class NovaNotifKind {
  NovaNotifKind._();
  static const String like = 'like';
  static const String comment = 'comment';
  static const String system = 'system';
  static const String share = 'share';
  static const String story = 'story';
  static const String post = 'post';
}

class NovaNotification {
  NovaNotification({
    required this.id,
    required this.kind,
    required this.textFa,
    required this.textEn,
    required this.at,
    this.postId,
    this.read = false,
  });

  final String id;
  final String kind;
  final String textFa;
  final String textEn;
  final DateTime at;
  final String? postId;
  bool read;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'fa': textFa,
        'en': textEn,
        'at': at.millisecondsSinceEpoch,
        if (postId != null) 'postId': postId,
        'read': read,
      };

  static NovaNotification fromJson(Map<String, dynamic> j) => NovaNotification(
        id: '${j['id']}',
        kind: '${j['kind'] ?? NovaNotifKind.system}',
        textFa: '${j['fa'] ?? ''}',
        textEn: '${j['en'] ?? ''}',
        at: _time(j['at']),
        postId: j['postId'] as String?,
        read: j['read'] == true,
      );
}

enum NovaTokenKind { text, hashtag, mention }

class NovaToken {
  const NovaToken(this.kind, this.value);
  final NovaTokenKind kind;

  /// For hashtag/mention: the word WITHOUT the leading symbol.
  final String value;

  String get display {
    switch (kind) {
      case NovaTokenKind.text:
        return value;
      case NovaTokenKind.hashtag:
        return '#$value';
      case NovaTokenKind.mention:
        return '@$value';
    }
  }
}

/// Hashtag / mention parser (supports Persian letters, digits, underscore and ZWNJ).
class NovaText {
  NovaText._();

  static final RegExp _re = RegExp(r'([#@])([\p{L}\p{M}\p{N}_\u200C.]+)', unicode: true);

  static String _clean(String word) {
    var w = word;
    while (w.endsWith('.')) {
      w = w.substring(0, w.length - 1);
    }
    return w;
  }

  static List<NovaToken> parse(String text) {
    final out = <NovaToken>[];
    var last = 0;
    for (final RegExpMatch m in _re.allMatches(text)) {
      // A symbol glued to a previous word (e.g. "mail@host") is not a tag.
      if (m.start > 0) {
        final prev = text.substring(m.start - 1, m.start);
        if (RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(prev)) continue;
      }
      final sym = m.group(1) ?? '#';
      final word = _clean(m.group(2) ?? '');
      if (word.isEmpty) continue;
      if (m.start > last) out.add(NovaToken(NovaTokenKind.text, text.substring(last, m.start)));
      out.add(NovaToken(sym == '#' ? NovaTokenKind.hashtag : NovaTokenKind.mention, word));
      last = m.start + 1 + word.length;
    }
    if (last < text.length) out.add(NovaToken(NovaTokenKind.text, text.substring(last)));
    return out;
  }

  static Set<String> hashtags(String text) =>
      parse(text).where((NovaToken t) => t.kind == NovaTokenKind.hashtag).map((NovaToken t) => t.value.toLowerCase()).toSet();

  static Set<String> mentions(String text) =>
      parse(text).where((NovaToken t) => t.kind == NovaTokenKind.mention).map((NovaToken t) => t.value.toLowerCase()).toSet();
}
