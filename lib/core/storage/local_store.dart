import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local-first key/value JSON store (P22). Every offline feature persists here.
/// When the app goes online later, the sync layer reads/writes the same keys.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static LocalStore? _instance;
  static LocalStore get instance {
    final i = _instance;
    if (i == null) throw StateError('LocalStore.init() not called');
    return i;
  }

  static Future<LocalStore> init() async {
    final prefs = await SharedPreferences.getInstance();
    return _instance = LocalStore(prefs);
  }

  /// For tests.
  static void setForTest(LocalStore store) => _instance = store;

  SharedPreferences get prefs => _prefs;

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
  Future<void> remove(String key) => _prefs.remove(key);

  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? getJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Object value) => _prefs.setString(key, jsonEncode(value));
}
