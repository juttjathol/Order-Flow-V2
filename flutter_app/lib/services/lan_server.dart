import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../models/models.dart';
import '../models/reducer.dart';

typedef StoreReader = AppStore Function();
typedef CommandHandler = ReduceResult Function(NetCommand cmd);

class LanServer {
  LanServer({
    required this.readStore,
    required this.onCommand,
  });

  final StoreReader readStore;
  final CommandHandler onCommand;

  String get shopName => readStore().profile.businessName;
  String get modelName => readStore().model.name;

  HttpServer? _server;
  final _sockets = <WebSocketChannel>{};
  final clients = <String, ClientInfo>{};

  bool get running => _server != null;
  int get port => _server?.port ?? kLanPort;

  Future<void> start({int port = kLanPort}) async {
    if (_server != null) return;
    final router = Router()
      ..get('/', _dashboard)
      ..get('/index.html', _dashboard)
      ..get('/health', _health)
      ..get('/join', _join)
      ..get('/state', _state)
      ..post('/command', _command)
      ..post('/driver/status', _driverStatus)
      ..get('/ws', webSocketHandler(_onWs));

    final handler = const Pipeline()
        .addMiddleware(_cors)
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    for (final s in _sockets.toList()) {
      await s.sink.close();
    }
    _sockets.clear();
    clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void broadcastState() {
    final msg = jsonEncode({
      'type': 'state',
      'store': readStore().toJson(),
    });
    for (final s in _sockets) {
      s.sink.add(msg);
    }
  }

  void broadcastNotice(AppNotice notice) {
    final msg = jsonEncode({'type': 'notify', 'notice': notice.toJson()});
    for (final s in _sockets) {
      s.sink.add(msg);
    }
  }

  Middleware get _cors => (inner) {
        return (request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: _corsHeaders);
          }
          final res = await inner(request);
          return res.change(headers: _corsHeaders);
        };
      };

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  static const _headers = {
    ..._corsHeaders,
    'Content-Type': 'application/json; charset=utf-8',
  };

  String? _dashboardHtml;

  Future<Response> _dashboard(Request req) async {
    _dashboardHtml ??= await rootBundle.loadString('assets/web/index.html');
    return Response.ok(
      _dashboardHtml,
      headers: {
        ..._corsHeaders,
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  Response _json(Map<String, dynamic> body, {int status = 200}) =>
      Response(status, body: jsonEncode(body), headers: _headers);

  Response _health(Request req) {
    return _json({
      'ok': true,
      'app': kAppName,
      'version': kAppVersion,
      'name': shopName,
      'model': modelName,
      'port': port,
      'revision': readStore().revision,
    });
  }

  Response _join(Request req) => _health(req);

  Response _state(Request req) =>
      _json({'ok': true, 'store': readStore().toJson()});

  Future<Response> _command(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      if (body is! Map) {
        return _json({'ok': false, 'error': 'invalid'}, status: 400);
      }
      final cmd = NetCommand.fromJson(Map<String, dynamic>.from(body));
      final result = onCommand(cmd);
      broadcastState();
      if (result.notice != null) broadcastNotice(result.notice!);
      return _json({
        'ok': true,
        'store': result.store.toJson(),
        'notice': result.notice?.toJson(),
        'payload': cmd.payload,
      });
    } catch (e) {
      return _json({'ok': false, 'error': e.toString()}, status: 500);
    }
  }

  Future<Response> _driverStatus(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      if (body is! Map) {
        return _json({'ok': false}, status: 400);
      }
      final map = Map<String, dynamic>.from(body);
      final cmd = NetCommand(
        name: map['name'] == 'pairDriver' ? 'pairDriver' : 'setDriverStatus',
        payload: map,
        actor: (map['name'] ?? 'driver').toString(),
      );
      final result = onCommand(cmd);
      broadcastState();
      Driver? paired;
      final pairedId = cmd.payload['pairedId']?.toString();
      if (pairedId != null) paired = result.store.driverById(pairedId);
      paired ??= result.store.drivers.cast<Driver?>().firstWhere(
            (d) => d?.deviceId == map['deviceId'],
            orElse: () => null,
          );
      return _json({
        'ok': true,
        'driver': paired?.toJson(),
        'store': result.store.toJson(),
      });
    } catch (e) {
      return _json({'ok': false, 'error': e.toString()}, status: 500);
    }
  }

  void _onWs(WebSocketChannel socket, String? _) {
    _sockets.add(socket);
    socket.sink.add(jsonEncode({
      'type': 'hello',
      'store': readStore().toJson(),
      'name': shopName,
      'model': modelName,
    }));
    socket.stream.listen(
      (event) {
        try {
          final data = jsonDecode(event.toString());
          if (data is! Map) return;
          final type = data['type'];
          if (type == 'hello') {
            final id = (data['deviceId'] ?? '').toString();
            if (id.isNotEmpty) {
              clients[id] = ClientInfo(
                deviceId: id,
                name: (data['name'] ?? '').toString(),
                role: (data['role'] ?? '').toString(),
              );
            }
          } else if (type == 'command') {
            final raw = data['command'];
            if (raw is Map) {
              final cmd = NetCommand.fromJson(Map<String, dynamic>.from(raw));
              final result = onCommand(cmd);
              broadcastState();
              if (result.notice != null) broadcastNotice(result.notice!);
            }
          }
        } catch (_) {}
      },
      onDone: () => _sockets.remove(socket),
      onError: (_) => _sockets.remove(socket),
      cancelOnError: true,
    );
  }
}
