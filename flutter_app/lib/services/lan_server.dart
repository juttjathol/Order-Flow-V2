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
import '../core/role_access.dart';
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
      ..get('/order', _qrPage)
      ..get('/order.html', _qrPage)
      ..get('/order/menu', _qrMenu)
      ..post('/order/submit', _qrSubmit)
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
    for (final s in _sockets.toList()) {
      try {
        s.sink.add(msg);
      } catch (_) {
        _sockets.remove(s);
      }
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
      if (!RoleAccess.allow(cmd.role, cmd)) {
        return _json({'ok': false, 'error': 'forbidden'}, status: 403);
      }
      final deny = StoreGuard.denyReason(readStore(), cmd);
      if (deny.isNotEmpty) {
        return _json({'ok': false, 'error': deny}, status: 403);
      }
      StoreGuard.sanitize(readStore(), cmd);
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
      if (map['name'] == 'pairDriver' &&
          !readStore().entitlements.allowsFeature('multi_terminal')) {
        return _json({'ok': false, 'error': 'plan_stations'}, status: 403);
      }
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

  // ── QR table ordering & self-order (v1.1.59) ──────────────────────────
  //
  // Customers on the shop Wi-Fi open http://<main-ip>:8787/order, tap menu
  // items and submit. Orders land as normal tickets with channel 'qr' and
  // auto-fire to the kitchen. Both endpoints stay closed unless the license
  // plan allows the feature AND Main turned the switch on (More → QR ordering).

  bool get qrEnabled {
    final store = readStore();
    return store.qrOrderOn &&
        store.entitlements.allowsFeature('qr_ordering');
  }

  String? _qrHtml;

  Future<Response> _qrPage(Request req) async {
    if (!qrEnabled) return _qrDisabledPage();
    _qrHtml ??= await rootBundle.loadString('assets/web/order.html');
    return Response.ok(
      _qrHtml,
      headers: {
        ..._corsHeaders,
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  Response _qrDisabledPage() => Response.ok(
        '<!doctype html><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">'
        '<body style=\"margin:0;font-family:system-ui;background:#051912;color:#eafff6;'
        'display:flex;align-items:center;justify-content:center;min-height:100vh\">'
        '<div style=\"text-align:center;padding:28px\"><h2>Order Flow</h2>'
        '<p style=\"color:#9bb5a8\">QR ordering is not enabled on this shop.<br>'
        'Ask the cashier to take your order.</p></div>',
        headers: {
          ..._corsHeaders,
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        },
      );

  Response _qrMenu(Request req) {
    if (!qrEnabled) return _json({'ok': false, 'error': 'disabled'}, status: 403);
    final store = readStore();
    final categories = store.categories
        .map((c) => {'id': c.id, 'name': c.name, 'nameUr': c.nameUr})
        .toList();
    final products = store.products
        .where((p) => p.available)
        .map((p) => {
              'id': p.id,
              'categoryId': p.categoryId,
              'name': p.name,
              'nameUr': p.nameUr,
              'desc': p.description,
              'price': p.price,
              'image': p.imageBase64,
              'mods': p.mods
                  .map((m) => {
                        'id': m.id,
                        'name': m.name,
                        'group': m.group,
                        'price': m.price,
                      })
                  .toList(),
            })
        .toList();
    final b = store.qrBrand;
    return _json({
      'ok': true,
      'shop': b.shopName.trim().isNotEmpty ? b.shopName : store.profile.businessName,
      'brand': {
        'tagline': b.tagline,
        'address': b.address,
        'phone': b.phone.trim().isNotEmpty ? b.phone : store.profile.phone,
        'whatsapp': b.whatsapp,
        'hours': b.hours,
        'welcome': b.welcome,
        'accent': b.accent,
      },
      'fireOn': store.qrFireOn,
      'model': store.model.name,
      'currency': store.profile.currencySymbol,
      'currencyPrefix': store.profile.currencyPrefix,
      'taxRate': store.profile.taxRate,
      'serviceRate': store.profile.serviceRate,
      'categories': categories,
      'products': products,
      'tables': store.tables
          .map((t) => {'id': t.id, 'name': t.name})
          .toList(),
    });
  }

  Future<Response> _qrSubmit(Request req) async {
    if (!qrEnabled) return _json({'ok': false, 'error': 'disabled'}, status: 403);
    try {
      final body = jsonDecode(await req.readAsString());
      if (body is! Map) return _json({'ok': false}, status: 400);
      final store = readStore();
      final rawItems = body['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        return _json({'ok': false, 'error': 'empty'}, status: 400);
      }
      FloorTable? table;
      final tableId = (body['tableId'] ?? '').toString();
      if (tableId.isNotEmpty) {
        table = store.tableById(tableId);
        if (table == null) {
          return _json({'ok': false, 'error': 'table_gone'}, status: 400);
        }
      }
      final lines = <Map<String, dynamic>>[];
      for (final raw in rawItems.take(40)) {
        if (raw is! Map) continue;
        final product = store.productById((raw['productId'] ?? '').toString());
        if (product == null || !product.available) continue;
        var qty = double.tryParse('${raw['qty']}') ?? 1;
        if (qty < 1) qty = 1;
        if (qty > 99) qty = 99;
        double price = product.price;
        final modNames = <String>[];
        final rawMods = raw['mods'];
        if (rawMods is List) {
          for (final mid in rawMods.take(12)) {
            ItemMod? mod;
            for (final m in product.mods) {
              if (m.id == '$mid') {
                mod = m;
                break;
              }
            }
            if (mod != null) {
              price += mod.price;
              modNames.add(mod.name);
            }
          }
        }
        final note = (raw['note'] ?? '').toString().trim();
        final label = modNames.isEmpty
            ? product.name
            : '${product.name} (${modNames.join(', ')})';
        lines.add(OrderLine(
          id: newId(),
          productId: product.id,
          name: label,
          unitPrice: price,
          qty: qty,
          notes: note.length > 120 ? note.substring(0, 120) : note,
          inventoryId: product.inventoryId,
          deductQty: product.deductQty,
          course: product.course,
        ).toJson());
      }
      if (lines.isEmpty) {
        return _json({'ok': false, 'error': 'empty'}, status: 400);
      }
      final order = PosOrder(
        id: newId(),
        ticketNo: '',
        type: table != null ? OrderType.dineIn : OrderType.takeaway,
        tableId: table?.id,
        tableName: table?.name,
        customerName: (body['name'] ?? '').toString().trim(),
        customerPhone: (body['phone'] ?? '').toString().trim(),
        notes: 'QR self-order',
        channel: 'qr',
      );
      final createCmd = NetCommand(
        name: 'createOrder',
        role: 'web',
        actor: order.customerName.isEmpty ? 'QR' : order.customerName,
        payload: {
          'order': {...order.toJson(), 'lines': lines},
        },
      );
      final created = onCommand(createCmd);
      final placed = created.store.orders.first;
      // 'order' mode fires straight away; 'pay' mode (v1.1.60 default) waits
      // for the counter — Main then fires it with the table number.
      AppNotice? notice;
      if (created.store.qrFireOn == 'order') {
        final fire = onCommand(NetCommand(
          name: 'fireCourse',
          role: 'web',
          actor: createCmd.actor,
          payload: {'orderId': placed.id},
        ));
        notice = fire.notice;
      }
      broadcastState();
      if (notice != null) broadcastNotice(notice);
      return _json({
        'ok': true,
        'ticket': placed.ticketNo,
        'total': placed.total,
        'fireOn': created.store.qrFireOn,
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
            final roleName = (data['role'] ?? '').toString();
            final isStation = roleName.isNotEmpty &&
                roleName != 'web' &&
                roleName != 'main';
            if (isStation &&
                !readStore().entitlements.allowsFeature('multi_terminal')) {
              try {
                socket.sink.add(jsonEncode(
                    {'type': 'rejected', 'reason': 'plan_stations'}));
                unawaited(socket.sink.close());
              } catch (_) {}
              _sockets.remove(socket);
              return;
            }
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
              if (StoreGuard.denyReason(readStore(), cmd).isNotEmpty) return;
              StoreGuard.sanitize(readStore(), cmd);
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
