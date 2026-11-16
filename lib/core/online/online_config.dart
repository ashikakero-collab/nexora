/// Online configuration injected at build time (never hard-coded secrets).
///
/// CI passes the public project URL + publishable (anon) key:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Without them the app runs fully offline exactly like before.
class OnlineConfig {
  const OnlineConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String liveKitUrl =
      String.fromEnvironment('LIVEKIT_URL', defaultValue: 'wss://nexora-space-xzjzlfyl.livekit.cloud');

  static bool get enabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
