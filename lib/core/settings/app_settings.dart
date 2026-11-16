import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_store.dart';
import '../theme/nx_theme.dart';

enum GraphicsQuality { low, medium, high, ultra }

/// Global app settings (P13, P16, P28). Persisted locally.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store) {
    final q = _store.getString(_kQuality);
    _quality = GraphicsQuality.values
        .firstWhere((e) => e.name == q, orElse: () => GraphicsQuality.high);
    _reducedMotion = _store.getBool(_kReduced) ?? false;
    _languageCode = _store.getString(_kLang) ?? 'fa';
    _visualTheme = NxVisualTheme.values.firstWhere(
      (e) => e.name == _store.getString(_kVisualTheme),
      orElse: () => NxVisualTheme.neon,
    );
    // NX2 redesign: the cosmic neon skin is the only app skin now.
    _visualTheme = NxVisualTheme.neon;
    _music = _store.getBool(_kMusic) ?? true;
    _musicVolume = (_store.getInt(_kMusicVol) ?? 60).clamp(0, 100) / 100.0;
    _sound = _store.getBool(_kSound) ?? true;
    _haptics = _store.getBool(_kHaptics) ?? true;
    _journeySeen = _store.getBool(_kJourney) ?? false;
    _onboarded = _store.getBool(_kOnboarded) ?? false;
  }

  final LocalStore _store;
  static const _kQuality = 'settings.quality';
  static const _kReduced = 'settings.reduced_motion';
  static const _kLang = 'settings.lang';
  static const _kVisualTheme = 'settings.visual_theme';
  static const _kSound = 'settings.sound';
  static const _kHaptics = 'settings.haptics';
  static const _kJourney = 'settings.journey_seen';
  static const _kOnboarded = 'settings.onboarded';
  static const _kMusic = 'settings.music';
  static const _kMusicVol = 'settings.music_volume';

  late GraphicsQuality _quality;
  late bool _reducedMotion;
  late String _languageCode;
  late NxVisualTheme _visualTheme;
  late bool _sound;
  late bool _haptics;
  late bool _journeySeen;
  late bool _onboarded;
  late bool _music;
  late double _musicVolume;

  /// Background music on menus (default on).
  bool get music => _music;

  /// 0..1 background music volume.
  double get musicVolume => _musicVolume;

  set music(bool v) {
    _music = v;
    _store.setBool(_kMusic, v);
    notifyListeners();
  }

  set musicVolume(double v) {
    _musicVolume = v.clamp(0.0, 1.0);
    _store.setInt(_kMusicVol, (_musicVolume * 100).round());
    notifyListeners();
  }

  GraphicsQuality get quality => _quality;
  bool get reducedMotion => _reducedMotion;
  String get languageCode => _languageCode;
  NxVisualTheme get visualTheme => _visualTheme;
  bool get isFa => _languageCode == 'fa';
  Locale get locale => Locale(_languageCode);
  bool get sound => _sound;
  bool get haptics => _haptics;
  bool get journeySeen => _journeySeen;
  bool get onboarded => _onboarded;

  /// Effects budget helpers used by every world and game.
  bool get fancyEffects =>
      !_reducedMotion && _quality.index >= GraphicsQuality.medium.index;
  int get starCount => switch (_quality) {
        GraphicsQuality.low => 60,
        GraphicsQuality.medium => 140,
        GraphicsQuality.high => 240,
        GraphicsQuality.ultra => 380,
      };

  set quality(GraphicsQuality v) {
    _quality = v;
    _store.setString(_kQuality, v.name);
    notifyListeners();
  }

  set reducedMotion(bool v) {
    _reducedMotion = v;
    _store.setBool(_kReduced, v);
    notifyListeners();
  }

  set languageCode(String v) {
    _languageCode = v;
    _store.setString(_kLang, v);
    notifyListeners();
  }

  set visualTheme(NxVisualTheme v) {
    if (_visualTheme == v) return;
    _visualTheme = v;
    _store.setString(_kVisualTheme, v.name);
    notifyListeners();
  }

  set sound(bool v) {
    _sound = v;
    _store.setBool(_kSound, v);
    notifyListeners();
  }

  set haptics(bool v) {
    _haptics = v;
    _store.setBool(_kHaptics, v);
    notifyListeners();
  }

  void markJourneySeen() {
    _journeySeen = true;
    _store.setBool(_kJourney, true);
    notifyListeners();
  }

  void markOnboarded() {
    _onboarded = true;
    _store.setBool(_kOnboarded, true);
    notifyListeners();
  }
}

final settingsProvider = ChangeNotifierProvider<AppSettings>(
    (ref) => AppSettings(LocalStore.instance));

/// Bilingual text helper: `context.tx('سلام', 'Hello')`.
extension NxTx on BuildContext {
  bool get isFa => Localizations.localeOf(this).languageCode == 'fa';
  String tx(String fa, String en) => isFa ? fa : en;
}
