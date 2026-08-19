import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../models/models.dart';

class LanClient {
  LanClient({
    required this.host,
    this.port = kLanPort,
    required this.onStore,
    required this.onNotice,
    required this.onStatus,
  });

  final String host;
  final int port;
  final void Function(AppStore store) onStore;
  final void Function(AppNotice notice) onNotice;
  final void Function(bool connected) onStatus;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _ping;
  bool _closed = false;

  String get base => 'http://$host:$port';

  static Future<Map<String, dynamic>> probe(String host, {int port = kLanPort}) async {
    final res = await http
        .get(Uri.parse('http://$host:$port/health'))
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body);
    if (body is Map) return Map<String, dynamic>.from(body);
    throw Exception('Unexpected health response');
  }

  Future<void> connect({
    required String deviceId,
    required String name,
    required String role,
  }) async {
    _closed = false;
    final health = await probe(host, port: port);
    if (health['ok'] != true) {
      throw Exception('Main device refused the connection');
    }
    await _openWs(deviceId: deviceId, name: name, role: role);
  }

  Future<void> _openWs({
    required String deviceId,
    required String name,
    required String role,
  }) async {
    await _sub?.cancel();
    await _ws?.sink.close();
    _ws = IOWebSocketChannel.connect(Uri.parse('ws://$host:$port/ws'));
    _sub = _ws!.stream.listen(
      (event) {
        try {
          final data = jsonDecode(event.toString());
          if (data is! Map) return;
          final map = Map<String, dynamic>.from(data);
          final type = map['type'];
          if (type == 'hello' || type == 'state') {
            if (map['store'] is Map) {
              onStore(AppStore.fromJson(Map<String, dynamic>.from(map['store'] as Map)));
            }
            onStatus(true);
          } else if (type == 'notify' && map['notice'] is Map) {
            onNotice(
              AppNotice.fromJson(Map<String, dynamic>.from(map['notice'] as Map)),
            );
          }
        } catch (_) {}
      },
      onDone: () {
        onStatus(false);
        if (!_closed) _reconnect(deviceId: deviceId, name: name, role: role);
      },
      onError: (_) {
        onStatus(false);
        if (!_closed) _reconnect(deviceId: deviceId, name: name, role: role);
      },
      cancelOnError: true,
    );
    _ws!.sink.add(jsonEncode({
      'type': 'hello',
      'deviceId': deviceId,
      'name': name,
      'role': role,
    }));
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 20), (_) {
      try {
        _ws?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _reconnect({
    required String deviceId,
    required String name,
    required String role,
  }) {
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (_closed) return;
      try {
        await _openWs(deviceId: deviceId, name: name, role: role);
      } catch (_) {
        if (!_closed) {
          _reconnect(deviceId: deviceId, name: name, role: role);
        }
      }
    });
  }

  Future<Map<String, dynamic>> send(NetCommand cmd) async {
    final res = await http
        .post(
          Uri.parse('$base/command'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(cmd.toJson()),
        )
        .timeout(const Duration(seconds: 8));
    final body = jsonDecode(res.body);
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      if (map['store'] is Map) {
        onStore(AppStore.fromJson(Map<String, dynamic>.from(map['store'] as Map)));
      }
      return map;
    }
    throw Exception('Bad command response');
  }

  Future<Map<String, dynamic>> driverCall(Map<String, dynamic> payload) async {
    final res = await http
        .post(
          Uri.parse('$base/driver/status'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 6));
    final body = jsonDecode(res.body);
    if (body is Map) return Map<String, dynamic>.from(body);
    throw Exception('Bad driver response');
  }

  Future<void> close() async {
    _closed = true;
    _ping?.cancel();
    await _sub?.cancel();
    await _ws?.sink.close();
    _ws = null;
  }
}
