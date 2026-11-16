import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/profile_service.dart';
import '../storage/local_store.dart';
import 'online_service.dart';

/// Keeps the local identity (offline cache) and the server profile in sync.
///
/// * XP / coins: server is the source of truth (public.profiles, shared with the other NEXORA app).
///   Local awards are queued and sent through `nx_award` (idempotent, daily cap server-side).
/// * Inventory, achievements, stats, decor, theme: `nx_profiles.data` (merged on sign-in).
/// * Works offline: the queue survives restarts and flushes on the next connection.
class CloudProfileSync {
  CloudProfileSync(this._online, this._profile, this._store);

  final OnlineService _online;
  final ProfileService _profile;
  final LocalStore _store;

  static const String _kQueue = 'cloud.queue';
  static const String _kUid = 'cloud.uid';

  bool _started = false;
  String? _linkedUid;
  bool _linking = false;
  bool _flushing = false;
  Timer? _uploadDebounce;
  Timer? _retry;

  void start() {
    if (_started || !_online.configured) return;
    _started = true;
    _profile.cloudQueue = _enqueue;
    _profile.onSaved = _scheduleUpload;
    _profile.onNameChanged = (String n) => unawaited(_pushName(n));
    _online.addListener(_onAuthChanged);
    if (_profile.hasIdentity) unawaited(_online.ensureSession());
    _onAuthChanged();
  }

  /// Called after onboarding creates the identity.
  Future<void> identityCreated() async {
    if (!_online.configured) return;
    await _online.ensureSession();
    _onAuthChanged();
  }

  SupabaseClient? get _c => _online.client;

  void _onAuthChanged() {
    final String? uid = _online.isOnline ? _online.uid : null;
    if (uid == null) {
      _linkedUid = null;
      return;
    }
    if (uid != _linkedUid && !_linking) unawaited(_link(uid));
  }

  Future<void> _link(String uid) async {
    final SupabaseClient? c = _c;
    if (c == null) return;
    _linking = true;
    try {
      final String? lastUid = _store.getString(_kUid);
      final Map<String, dynamic>? prof =
          await c.from('profiles').select('username, xp, coins, avatar').eq('id', uid).maybeSingle();
      final Map<String, dynamic>? nx = await c.from('nx_profiles').select('data, avatar_core').eq('id', uid).maybeSingle();
      final bool otherAccount = lastUid != null && lastUid != uid;
      if (otherAccount) await _store.remove(_kQueue);

      if (nx == null) {
        // First link of this account to NEXORA Flutter.
        if (!otherAccount && _profile.hasIdentity) {
          final dynamic r = await c.rpc('nx_import_local', params: <String, dynamic>{
            'p_xp': _profile.xp,
            'p_coins': _profile.coins,
          });
          _applyWalletJson(r);
        } else if (prof != null) {
          _profile.applyWallet(xp: (prof['xp'] as num?)?.toInt(), coins: (prof['coins'] as num?)?.toInt());
        }
        if (otherAccount) {
          _profile.applyCloudBlob(const <String, dynamic>{}, replace: true, serverName: prof?['username'] as String?);
        }
        await _upload();
        if (_profile.username.isNotEmpty && !otherAccount) await _pushName(_profile.username);
      } else {
        final Map<String, dynamic> data = Map<String, dynamic>.from((nx['data'] as Map?) ?? const <String, dynamic>{});
        _profile.applyCloudBlob(
          data,
          replace: otherAccount,
          serverName: prof?['username'] as String?,
          avatar: nx['avatar_core'] as String?,
        );
        if (prof != null) {
          _profile.applyWallet(xp: (prof['xp'] as num?)?.toInt(), coins: (prof['coins'] as num?)?.toInt());
        }
        await _upload();
      }
      await _store.setString(_kUid, uid);
      _linkedUid = uid;
      await flush();
    } catch (e) {
      debugPrint('cloud link failed: $e');
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 20), _onAuthChanged);
    } finally {
      _linking = false;
    }
  }

  void _applyWalletJson(dynamic r) {
    if (r is Map) {
      _profile.applyWallet(xp: (r['xp'] as num?)?.toInt(), coins: (r['coins'] as num?)?.toInt());
    }
  }

  List<Map<String, dynamic>> _readQueue() => (_store.getJsonList(_kQueue) ?? const <dynamic>[])
      .whereType<Map>()
      .map((Map m) => Map<String, dynamic>.from(m))
      .toList();

  void _enqueue(Map<String, dynamic> op) {
    final List<Map<String, dynamic>> q = _readQueue()..add(op);
    if (q.length > 300) q.removeRange(0, q.length - 300);
    _store.setJson(_kQueue, q);
    unawaited(Future<void>.delayed(const Duration(milliseconds: 400), flush));
  }

  /// Send queued awards / purchases. Stops at the first network error (retried later).
  Future<void> flush() async {
    final SupabaseClient? c = _c;
    if (c == null || _linkedUid == null || _flushing) return;
    _flushing = true;
    try {
      while (true) {
        final List<Map<String, dynamic>> q = _readQueue();
        if (q.isEmpty) break;
        final Map<String, dynamic> op = q.first;
        try {
          if (op['t'] == 'award') {
            final dynamic r = await c.rpc('nx_award', params: <String, dynamic>{
              'p_event': '${op['e']}',
              'p_xp': (op['x'] as num?)?.toInt() ?? 0,
              'p_coins': (op['c'] as num?)?.toInt() ?? 0,
              'p_key': '${op['k']}',
            });
            _applyWalletJson(r);
          } else if (op['t'] == 'buy') {
            final dynamic r = await c.rpc('nx_purchase', params: <String, dynamic>{
              'p_item': '${op['i']}',
              'p_price': (op['p'] as num?)?.toInt() ?? 0,
            });
            if (r is Map && r['ok'] == false) _profile.revertPurchase('${op['i']}');
            _applyWalletJson(r);
          }
        } on PostgrestException catch (e) {
          debugPrint('cloud op rejected: ${e.message}');
        }
        final List<Map<String, dynamic>> rest = _readQueue();
        if (rest.isNotEmpty) rest.removeAt(0);
        await _store.setJson(_kQueue, rest);
      }
    } catch (e) {
      debugPrint('cloud flush paused: $e');
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 30), () => unawaited(flush()));
    } finally {
      _flushing = false;
    }
  }

  void _scheduleUpload() {
    if (_linkedUid == null) return;
    _uploadDebounce?.cancel();
    _uploadDebounce = Timer(const Duration(seconds: 4), () => unawaited(_upload()));
  }

  Future<void> _upload() async {
    final SupabaseClient? c = _c;
    final String? uid = _online.uid;
    if (c == null || uid == null) return;
    try {
      await c.from('nx_profiles').upsert(<String, dynamic>{
        'id': uid,
        'explorer_id': _profile.explorerId,
        'avatar_core': _profile.avatarCore,
        'data': _profile.cloudBlob(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await c.from('profiles').update(<String, dynamic>{'bio': _profile.bio}).eq('id', uid);
    } catch (e) {
      debugPrint('cloud upload failed: $e');
    }
  }

  Future<void> _pushName(String name) async {
    final SupabaseClient? c = _c;
    if (c == null || _online.uid == null || name.trim().length < 2) return;
    try {
      String n = name.trim();
      if (n.length > 24) n = n.substring(0, 24);
      dynamic r = await c.rpc('nx_set_username', params: <String, dynamic>{'p_name': n});
      if (r == 'taken') {
        final String alt = '${n.length > 20 ? n.substring(0, 20) : n}${Random().nextInt(900) + 100}';
        r = await c.rpc('nx_set_username', params: <String, dynamic>{'p_name': alt});
      }
    } catch (e) {
      debugPrint('username sync failed: $e');
    }
  }

  /// Pull the server wallet (e.g. after an online match was settled server-side).
  Future<void> refreshWallet() async {
    final SupabaseClient? c = _c;
    final String? uid = _online.uid;
    if (c == null || uid == null) return;
    try {
      final Map<String, dynamic>? p = await c.from('profiles').select('xp, coins').eq('id', uid).maybeSingle();
      if (p != null) _profile.applyWallet(xp: (p['xp'] as num?)?.toInt(), coins: (p['coins'] as num?)?.toInt());
    } catch (_) {}
  }
}

final cloudSyncProvider = Provider<CloudProfileSync>((ref) {
  final CloudProfileSync s = CloudProfileSync(ref.read(onlineProvider), ref.read(profileProvider), LocalStore.instance);
  return s;
});
