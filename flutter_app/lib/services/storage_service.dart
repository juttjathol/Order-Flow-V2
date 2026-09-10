import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

class StorageService {
  StorageService(this.prefs, this._docs);

  final SharedPreferences prefs;
  final Directory _docs;

  static const _sessionKey = 'of_session_v1';
  static const _queueKey = 'of_cmd_queue_v1';
  static const _seenKey = 'of_cmd_seen_v1';
  static const _stateName = 'app_state.json';

  static Future<StorageService> open() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    return StorageService(prefs, docs);
  }

  File get _stateFile => File(p.join(_docs.path, _stateName));

  SessionPrefs loadSession() {
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      final session = SessionPrefs(deviceId: const Uuid().v4());
      saveSession(session);
      return session;
    }
    try {
      final session = SessionPrefs.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (session.deviceId.isEmpty) {
        session.deviceId = const Uuid().v4();
        saveSession(session);
      }
      return session;
    } catch (_) {
      final session = SessionPrefs(deviceId: const Uuid().v4());
      saveSession(session);
      return session;
    }
  }

  Future<void> saveSession(SessionPrefs session) async {
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<AppStore> loadStore() async {
    try {
      if (await _stateFile.exists()) {
        final raw = await _stateFile.readAsString();
        if (raw.isNotEmpty) {
          return AppStore.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    // Main file missing or corrupt — fall back to the last good copy, then
    // heal it back into place so a crash mid-write never wipes the shop.
    try {
      final bak = File('${_stateFile.path}.bak');
      if (await bak.exists()) {
        final raw = await bak.readAsString();
        if (raw.isNotEmpty) {
          final store =
              AppStore.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          await _stateFile.writeAsString(raw);
          return store;
        }
      }
    } catch (_) {}
    final legacy = prefs.getString('of_store_v1');
    if (legacy != null && legacy.isNotEmpty) {
      try {
        return AppStore.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
      } catch (_) {}
    }
    return AppStore();
  }

  List<NetCommand> loadQueue() {
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => NetCommand.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQueue(List<NetCommand> cmds) async {
    await prefs.setString(
      _queueKey,
      jsonEncode(cmds.map((c) => c.toJson()).toList()),
    );
  }

  List<String> loadSeenIds() {
    final raw = prefs.getString(_seenKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSeenIds(Iterable<String> ids) async {
    await prefs.setString(_seenKey, jsonEncode(ids.toList()));
  }

  Future<void> saveStore(AppStore store) async {
    final encoded = jsonEncode(store.toJson());
    // Crash-safe write: keep the previous good state in .bak, write a temp
    // file, then rename over — an atomic replace on Android. A kill in the
    // middle can never leave a half-written app_state.json behind.
    try {
      if (await _stateFile.exists()) {
        await _stateFile.copy('${_stateFile.path}.bak');
      }
    } catch (_) {}
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(_stateFile.path);
    // Mirror a compact revision stamp in SharedPreferences.
    await prefs.setInt('of_store_rev', store.revision);
    await prefs.setString('of_store_saved_at', DateTime.now().toIso8601String());
  }

  Future<String> exportPath(AppStore store) async {
    final file = File(
      p.join(
        _docs.path,
        'order_flow_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(store.toJson()));
    return file.path;
  }
}
