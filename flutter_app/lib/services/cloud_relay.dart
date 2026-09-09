import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as cr;
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;

/// Default relay home — the Jathol dashboard project doubles as the
/// transport. The relay only forwards live messages; nothing is kept as a
/// shop backup (rows die within minutes server-side).
const kCloudRelayBase = 'https://order-flow-v2.pages.dev';

/// One relay room = one shop. The room id is a random 256-bit token and every
/// payload is AES-GCM encrypted with a key derived from the room secret, so
/// rooms cannot read each other and the server only ever sees ciphertext.
class CloudRoom {
  CloudRoom(this.room, this.secret, this.code);
  final String room;
  final String secret;
  final String code;
}

class CloudRelay {
  CloudRelay({
    required this.roomId,
    required this.secret,
    required this.deviceId,
    required this.isMain,
    required this.revision,
    required this.getStateJson,
    this.onPeerState,
    this.onPeerCommand,
    this.onLost,
    this.onOk,
    String? baseUrl,
  }) : _base = (baseUrl == null || baseUrl.isEmpty) ? kCloudRelayBase : baseUrl {
    final keyBytes = cr.sha256.convert(utf8.encode('orderflow-cloud|v1|$secret')).bytes;
    _aes = Encrypter(AES(Key(Uint8List.fromList(keyBytes)), mode: AESMode.gcm));
  }

  final String roomId;
  final String secret;
  final String deviceId;
  final bool isMain;
  final String _base;
  late final Encrypter _aes;

  /// Main: current store revision — a change triggers a state push.
  final int Function() revision;
  /// Main: full store JSON shared with the room.
  final String Function() getStateJson;
  /// Stations: Main pushed a store snapshot.
  final void Function(Map<String, dynamic> storeJson)? onPeerState;
  /// Main: a station sent a command.
  final void Function(Map<String, dynamic> cmdJson)? onPeerCommand;
  final void Function()? onLost;
  final void Function()? onOk;

  Timer? _pullTimer;
  int _cursor = 0;
  // Relay sleep/wake: `hot` means "my LAN side is degraded, keep the cloud
  // channel fast (1.2s)". In idle mode we patrol every 30s and the server
  // writes nothing for us. Main also honors the room's peersHot signal so a
  // single station losing Wi-Fi wakes the whole room back to fast mode.
  bool _hot = true;
  DateTime? _peersHotAt;
  int _fails = 0;
  int _lastPushedRev = -1;
  bool _running = false;
  bool _pushing = false;
  // Chunk assembly: store snapshots can be large, so the server relays them
  // as pieces that are stitched back together here.
  List<String>? _chunkParts;
  final Random _rnd = Random.secure();

  bool get active => _running;
  bool get healthy => _fails < 20;
  bool get hot => _hot;

  set hot(bool v) {
    if (v == _hot) return;
    _hot = v;
    if (v) {
      // Waking up: force a fresh snapshot push so any late device
      // re-baselines immediately instead of waiting for the heartbeat.
      _lastPushedRev = -1;
      _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
      _fails = 0;
    }
    _restartTimer();
  }

  bool get _fast =>
      _hot ||
      (_peersHotAt != null &&
          DateTime.now().difference(_peersHotAt!) < const Duration(seconds: 90));

  void _restartTimer() {
    _pullTimer?.cancel();
    _pullTimer = null;
    if (!_running) return;
    _pullTimer = Timer.periodic(
      _fast ? const Duration(milliseconds: 1200) : const Duration(seconds: 30),
      (_) => _tick(),
    );
  }

  static const _chunkSize = 480000;

  // ── Room lifecycle ───────────────────────────────────────────────────

  static Future<CloudOpenResult> openRoom({
    required String licenseKey,
    required String deviceId,
    required String shopName,
    String? baseUrl,
  }) async {
    Map<String, dynamic>? res;
    for (var attempt = 0; attempt < 2; attempt++) {
      res = await _post(
        '${baseUrl ?? kCloudRelayBase}/api/cloud/open',
        {'licenseKey': licenseKey, 'deviceId': deviceId, 'shopName': shopName},
      );
      if (res != null) break; // any parsed answer beats a retry
    }
    if (res == null) return const CloudOpenResult.fail('cloud_unreachable');
    if (res['ok'] == true) {
      return CloudOpenResult.ok(
          CloudRoom('${res['room']}', '${res['secret']}', '${res['code']}'));
    }
    final e = '${res['error'] ?? ''}';
    if (e == 'plan') return const CloudOpenResult.fail('plan');
    return const CloudOpenResult.fail('server');
  }

  static Future<bool> joinRoom({
    required String roomId,
    required String code,
    required String deviceId,
    required String role,
    String? baseUrl,
  }) async {
    final res = await _post(
      '${baseUrl ?? kCloudRelayBase}/api/cloud/join',
      {'room': roomId, 'code': code, 'deviceId': deviceId, 'role': role},
    );
    return res != null && res['ok'] == true;
  }

  static Future<void> leaveRoom({
    required String roomId,
    required String deviceId,
    String? baseUrl,
  }) async {
    await _post(
      '${baseUrl ?? kCloudRelayBase}/api/cloud/leave',
      {'room': roomId, 'deviceId': deviceId},
    );
  }

  /// Pairing text shown on Main (QR / typed):
  /// OF1:room:code:secret:base64url(baseUrl)
  static String pairing(String room, String code, String secret, String baseUrl) {
    final u = base64Url.encode(utf8.encode(baseUrl));
    return 'OF1:$room:$code:$secret:$u';
  }

  static List<String>? parsePairing(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 5 || parts[0] != 'OF1') return null;
    try {
      final url = utf8.decode(base64Url.decode(base64Url.normalize(parts[4])));
      return [parts[1], parts[2], parts[3], url];
    } catch (_) {
      return null;
    }
  }

  // ── Runtime ──────────────────────────────────────────────────────────

  Future<void> start() async {
    _running = true;
    _restartTimer();
    unawaited(_tick());
  }

  void stop() {
    _running = false;
    _pullTimer?.cancel();
    _pullTimer = null;
  }

  Future<void> _tick() async {
    if (!_running) return;
    final wasFast = _fast;
    try {
      await _pull();
      await _pushCheck();
      if (_fails > 0) {
        _fails = 0;
        onOk?.call();
      }
    } catch (_) {
      _fails += 1;
      // Idle mode checks every 30s — lose the room after ~3 quiet minutes,
      // hot mode keeps the old ~48s alarm.
      if (_fails == (_fast ? 40 : 6)) onLost?.call();
    }
    if (_fast != wasFast) _restartTimer();
  }

  Future<void> _pull() async {
    final res = await _apiPost('/api/cloud/pull', {'after': _cursor, 'hot': _hot ? 1 : 0});
    if (res == null) throw const SocketErrorRelay();
    if (res['ok'] != true) throw const SocketErrorRelay();
    final c = int.tryParse('${res['cursor']}');
    if (c != null) _cursor = c;
    final peersHot = int.tryParse('${res['peersHot']}') ?? 0;
    if (isMain && peersHot > 0) _peersHotAt = DateTime.now();
    final msgs = res['msgs'];
    if (msgs is List) _handleMsgs(msgs);
  }

  Future<Map<String, dynamic>?> _apiPost(String path, Map<String, dynamic> body) {
    return _post('$_base$path', {...body, 'room': roomId, 'device': deviceId});
  }

  /// Queue a command from a station. False = send failed; the caller keeps
  /// the command in its offline queue.
  Future<bool> sendCommand(Map<String, dynamic> cmdJson) async {
    return _sendEnvelope({'t': 'cmd', 'c': cmdJson});
  }

  Future<bool> _sendEnvelope(Map<String, dynamic> env) async {
    final blob = _encrypt(jsonEncode(env));
    if (blob == null) return false;
    final res = await _apiPost('/api/cloud/send', {'msg': blob});
    return res != null && res['ok'] == true;
  }

  DateTime _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _pushCheck() async {
    if (!isMain || _pushing) return;
    final rev = revision();
    // Heartbeat: even with no change, re-share so a station that was offline
    // past the message TTL catches up. Fast mode = every 2 min (as before);
    // idle mode = every 10 min, because whoever needs freshness will flip the
    // room hot via the peersHot handshake and then changes push instantly.
    final stale =
        DateTime.now().difference(_lastPushAt).inSeconds > (_fast ? 120 : 600);
    if (rev == _lastPushedRev && !stale) return;
    if (!_fast && !stale) return;
    _pushing = true;
    try {
      if (await _pushState()) {
        _lastPushedRev = rev;
        _lastPushAt = DateTime.now();
      }
    } finally {
      _pushing = false;
    }
  }

  Future<bool> _pushState() async {
    final s = getStateJson();
    if (s.length <= _chunkSize) {
      return _sendEnvelope({'t': 'state', 's': s});
    }
    final chunks = <String>[];
    for (var i = 0; i < s.length; i += _chunkSize) {
      final end = i + _chunkSize > s.length ? s.length : i + _chunkSize;
      chunks.add(s.substring(i, end));
    }
    for (var i = 0; i < chunks.length; i++) {
      final ok = await _sendEnvelope({
        't': 'state_part',
        'part': i,
        'parts': chunks.length,
        's': chunks[i],
      });
      if (!ok) return false;
    }
    return true;
  }

  String? _encrypt(String plain) {
    try {
      final ivBytes = List<int>.generate(12, (_) => _rnd.nextInt(256));
      final iv = IV(Uint8List.fromList(ivBytes));
      final result = _aes.encrypt(plain, iv: iv);
      return '${base64Url.encode(ivBytes)}.${result.base64}';
    } catch (_) {
      return null;
    }
  }

  String? _decrypt(String blob) {
    try {
      final dot = blob.indexOf('.');
      if (dot <= 0) return null;
      final iv = IV(base64Url.decode(base64Url.normalize(blob.substring(0, dot))));
      final enc = Encrypted.fromBase64(blob.substring(dot + 1));
      return _aes.decrypt(enc, iv: iv);
    } catch (_) {
      return null;
    }
  }

  void _handleMsgs(List msgs) {
    for (final raw in msgs) {
      if (raw is! Map) continue;
      final sender = '${raw['sender']}';
      if (sender == deviceId) continue;
      final plain = _decrypt('${raw['msg']}');
      if (plain == null) continue;
      Map<String, dynamic> env;
      try {
        final j = jsonDecode(plain);
        if (j is! Map) continue;
        env = Map<String, dynamic>.from(j);
      } catch (_) {
        continue;
      }
      final t = env['t'];
      if (t == 'state_part') {
        final k = int.tryParse('${env['parts']}') ?? 1;
        final i = int.tryParse('${env['part']}') ?? -1;
        if (k <= 1 || i < 0) {
          _applyState('${env['s']}');
          continue;
        }
        final buf = _chunkParts ??= List<String>.filled(k, '');
        if (i < buf.length) buf[i] = '${env['s']}';
        var done = true;
        for (final part in buf) {
          if (part.isEmpty) done = false;
        }
        if (done) {
          _applyState(buf.join());
          _chunkParts = null;
        }
      } else if (t == 'state') {
        _applyState('${env['s']}');
      } else if (t == 'cmd' && isMain) {
        final c = env['c'];
        if (c is Map) onPeerCommand?.call(Map<String, dynamic>.from(c));
      }
    }
  }

  void _applyState(String storeJson) {
    if (storeJson.isEmpty) return;
    try {
      final j = jsonDecode(storeJson);
      if (j is Map) onPeerState?.call(Map<String, dynamic>.from(j));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _post(String url, Map<String, dynamic> body) async {
    try {
      final client = http.Client();
      try {
        final res = await client
            .post(Uri.parse(url),
                headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));
        // Relay errors ride JSON bodies on non-200 responses — parse them at
        // every status so the UI can name the real cause (plan / relay /
        // quota) instead of blaming the network. (v1.1.66)
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        return j is Map ? Map<String, dynamic>.from(j) : null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// Outcome of a room-open attempt: the room itself, or an error token the
/// sheet translates via 'cloud_err_<token>'. (v1.1.66 — honest errors.)
class CloudOpenResult {
  const CloudOpenResult.ok(this.room) : error = '';
  const CloudOpenResult.fail(this.error) : room = null;

  final CloudRoom? room;
  final String error;

  bool get ok => room != null;
}

/// Internal marker used to count relay failures (no socket is involved).
class SocketErrorRelay implements Exception {
  const SocketErrorRelay();
}
