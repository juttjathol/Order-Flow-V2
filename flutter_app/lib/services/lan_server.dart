import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../core/lan_policy.dart';
import '../core/role_access.dart';
import '../core/pin_crypto.dart';
import '../core/sanitize.dart';
import '../models/models.dart';
import '../models/reducer.dart';

class LanDeviceGate {
  LanDeviceGate({
    required this.isApproved,
    required this.inOpenWindow,
    required this.onAutoApprove,
    this.onPending,
  });
  final bool Function(String deviceId) isApproved;
  final bool Function() inOpenWindow;
  final void Function(String deviceId) onAutoApprove;
  final void Function(ClientInfo info)? onPending;
}

typedef StoreReader = AppStore Function();
typedef CommandHandler = ReduceResult Function(NetCommand cmd);

class LanServer {
  LanServer({
    required this.readStore,
    required this.onCommand,
    this.deviceGate,
  });

  final StoreReader readStore;
  final CommandHandler onCommand;
  final LanDeviceGate? deviceGate;

  String get shopName => readStore().profile.businessName;
  String get modelName => readStore().model.name;

  HttpServer? _server;
  final _sockets = <WebSocketChannel>{};
  final clients = <String, ClientInfo>{};
  final pending = <String, ClientInfo>{};
  final _waiting = <String, WebSocketChannel>{};
  final _socketDevice = <WebSocketChannel, String>{};
  final _lanSecret = const Uuid().v4();
  final _qrByTable = <String, List<int>>{};
  final _qrShop = <String, List<int>>{};
  // Phase-2 PIN verify rate limit per device (server-side, Main only)
  final _pinFails = <String, int>{};
  final _pinLockUntil = <String, int>{};
  // Phase-1 QR double-tap guard: same table + same payload hash within 5s returns same ticket
  final _qrLastSubmit = <String, _QrDedup>{};

  // v1.1.83 hardening: hard ceilings so a single LAN client cannot exhaust
  // Main's memory or spam the owner with device-approval prompts. A real shop
  // never comes close (16 paired stations + the owner's browser console).
  static const int _maxSockets = 64;
  static const int _maxWaiting = 24;
  static const int _maxWsFrameBytes = 64 * 1024;

  String _tokenFor(String deviceId, [String? role]) {
    final r = role ?? clients[deviceId]?.role ?? (deviceId == 'web-console' ? 'web' : '');
    final hmac = Hmac(sha256, utf8.encode(_lanSecret));
    return hmac.convert(utf8.encode('$deviceId|$r')).toString();
  }

  String? _bearer(Request req) {
    final h = req.headers['authorization'] ?? req.headers['Authorization'] ?? '';
    if (h.toLowerCase().startsWith('bearer ')) return h.substring(7).trim();
    return null;
  }

  ClientInfo? _clientFromReq(Request req) {
    final device = (req.headers['x-of-device'] ?? req.headers['X-OF-Device'] ?? '').trim();
    final tok = _bearer(req);
    if (device.isEmpty || tok == null || tok.isEmpty) return null;
    // safeEq: constant-time, so a LAN attacker cannot nibble a token byte by
    // byte off the comparison's timing.
    if (!safeEq(tok, _tokenFor(device))) return null;
    if (device == 'web-console') {
      return clients[device] ??
          ClientInfo(deviceId: 'web-console', name: 'Web', role: 'web');
    }
    return clients[device];
  }

  NetCommand _bindRole(NetCommand cmd, String? deviceId) {
    final bound = deviceId != null ? clients[deviceId] : null;
    if (bound != null && bound.role.isNotEmpty) {
      return NetCommand(
        id: cmd.id,
        name: cmd.name,
        payload: cmd.payload,
        actor: cmd.actor.isNotEmpty ? cmd.actor : bound.name,
        role: bound.role,
        at: cmd.at,
      );
    }
    // Never trust a self-reported main/manager from an unidentified station.
    if (cmd.role == 'main' || cmd.role == 'manager') {
      return NetCommand(
        id: cmd.id,
        name: cmd.name,
        payload: cmd.payload,
        actor: cmd.actor,
        role: '',
        at: cmd.at,
      );
    }
    return cmd;
  }

  /// Store JSON for one specific audience.
  ///
  /// v1.1.83 security: the browser console at `http://<main-ip>:8787/` is
  /// served — token included — to ANYONE on the shop Wi-Fi, so it must never
  /// receive the manager PIN hash. (A 4-digit PIN behind a single round of
  /// SHA-256 is a few milliseconds of offline brute force, and a legacy
  /// plaintext PIN would be handed over verbatim.) Paired stations still
  /// receive it: their local PIN gate verifies against that hash, and removing
  /// it there would silently disable void/refund/close-day prompts on stations
  /// until server-side PIN verification ships.
  // Phase-2 10k: hash never leaves Main. All LAN clients (stations + web-console)
  // receive store without managerPin — verification is server-side via /verify-pin.
  Map<String, dynamic> _storeJsonFor(String deviceId) {
    final json = readStore().toJson();
    final profile = json['profile'];
    if (profile is Map) {
      final copy = Map<String, dynamic>.from(profile);
      copy['managerPin'] = '';
      json['profile'] = copy;
    }
    return json;
  }

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
      ..post('/verify-pin', _verifyPin)
      ..post('/driver/status', _driverStatus)
      ..get('/order', _qrPage)
      ..get('/order.html', _qrPage)
      ..get('/order/menu', _qrMenu)
      ..get('/order/status', _qrStatus)
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
    pending.clear();
    _waiting.clear();
    _socketDevice.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void broadcastState() {
    // Two audiences, two payloads: paired stations get the full store, the
    // browser console gets the same store minus profile.managerPin.
    String? stations;
    String? console;
    for (final s in _sockets.toList()) {
      try {
        final dev = _socketDevice[s] ?? '';
        if (dev == 'web-console') {
          console ??= jsonEncode({
            'type': 'state',
            'store': _storeJsonFor('web-console'),
          });
          s.sink.add(console);
        } else {
          stations ??= jsonEncode({
            'type': 'state',
            'store': _storeJsonFor(dev),
          });
          s.sink.add(stations);
        }
      } catch (_) {
        _sockets.remove(s);
      }
    }
  }

  void broadcastNotice(AppNotice notice) {
    final msg = jsonEncode({'type': 'notify', 'notice': notice.toJson()});
    for (final s in _sockets.toList()) {
      try {
        s.sink.add(msg);
      } catch (_) {
        _sockets.remove(s);
      }
    }
  }

  Map<String, String> _corsFor(Request request) {
    final origin = request.headers['origin'];
    final host = request.headers['host'];
    if (!corsOriginOk(origin, host)) return {};
    if (origin == null || origin.isEmpty) {
      return {
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-OF-Device',
      };
    }
    return {
      'Access-Control-Allow-Origin': origin,
      'Vary': 'Origin',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-OF-Device',
    };
  }

  Middleware get _cors => (inner) {
        return (request) async {
          final origin = request.headers['origin'];
          final host = request.headers['host'];
          if (!corsOriginOk(origin, host)) {
            return Response.forbidden(
              jsonEncode({'ok': false, 'error': 'origin'}),
              headers: {'Content-Type': 'application/json'},
            );
          }
          final h = _corsFor(request);
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: h);
          }
          final res = await inner(request);
          return res.change(headers: {...h, ...res.headers});
        };
      };

  static const _headers = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  String? _dashboardHtml;

  Future<Response> _dashboard(Request req) async {
    _dashboardHtml ??= await rootBundle.loadString('assets/web/index.html');
    final html = _dashboardHtml!.replaceFirst(
      '/*OF_AUTH*/',
      'window.OF_TOKEN="${_tokenFor('web-console', 'web')}";window.OF_DEVICE="web-console";',
    );
    return Response.ok(
      html,
      headers: {
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

  Response _state(Request req) {
    final who = _clientFromReq(req);
    if (who == null) {
      return _json({'ok': false, 'error': 'unauthorized'}, status: 401);
    }
    return _json({'ok': true, 'store': _storeJsonFor(who.deviceId)});
  }

  Future<Response> _command(Request req) async {
    try {
      final raw = await req.readAsString();
      if (raw.length > 32 * 1024) {
        return _json({'ok': false, 'error': 'too_large'}, status: 413);
      }
      final body = jsonDecode(raw);
      if (body is! Map) {
        return _json({'ok': false, 'error': 'invalid'}, status: 400);
      }
      var cmd = NetCommand.fromJson(Map<String, dynamic>.from(body));
      if (cmd.role.isEmpty && cmd.actor == 'web') {
        cmd = NetCommand(
          id: cmd.id,
          name: cmd.name,
          payload: cmd.payload,
          actor: cmd.actor,
          role: 'web',
          at: cmd.at,
        );
      }
      final who = _clientFromReq(req);
      if (who == null) {
        return _json({'ok': false, 'error': 'unauthorized'}, status: 401);
      }
      cmd = _bindRole(cmd, who.deviceId);
      if (isPrivileged(cmd.name, cmd.role)) {
        return _json({'ok': false, 'error': 'forbidden'}, status: 403);
      }
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
      return _json({'ok': false, 'error': 'server_error'}, status: 500);
    }
  }

  // Phase-2: server-side PIN verification — hash never leaves Main
  Future<Response> _verifyPin(Request req) async {
    final who = _clientFromReq(req);
    if (who == null) return _json({'ok': false, 'error': 'unauthorized'}, status: 401);
    final deviceId = who.deviceId;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lockedUntil = _pinLockUntil[deviceId] ?? 0;
    if (nowMs < lockedUntil) {
      return _json({'ok': false, 'error': 'locked', 'until': lockedUntil}, status: 403);
    }
    try {
      final body = jsonDecode(await req.readAsString());
      final pin = (body is Map ? (body['pin'] ?? '').toString() : '').trim();
      final stored = readStore().profile.managerPin;
      if (stored.isEmpty) return _json({'ok': true, 'valid': true});
      final valid = PinCrypto.verify(stored, pin);
      if (!valid) {
        final fails = (_pinFails[deviceId] ?? 0) + 1;
        _pinFails[deviceId] = fails;
        if (fails >= 5) {
          _pinFails[deviceId] = 0;
          _pinLockUntil[deviceId] = nowMs + 5 * 60 * 1000;
          return _json({'ok': false, 'error': 'locked', 'until': _pinLockUntil[deviceId]}, status: 403);
        }
        return _json({'ok': false, 'error': 'invalid', 'fails': fails}, status: 403);
      }
      _pinFails.remove(deviceId);
      _pinLockUntil.remove(deviceId);
      return _json({'ok': true, 'valid': true});
    } catch (_) {
      return _json({'ok': false, 'error': 'server_error'}, status: 500);
    }
  }

  Future<Response> _driverStatus(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      if (body is! Map) {
        return _json({'ok': false}, status: 400);
      }
      final map = Map<String, dynamic>.from(body);
      final who = _clientFromReq(req);
      if (who == null) {
        return _json({'ok': false, 'error': 'unauthorized'}, status: 401);
      }
      final callerRole = clients[who.deviceId]?.role ?? '';
      if (map['name'] == 'pairDriver') {
        if (!readStore().entitlements.allowsFeature('multi_terminal')) {
          return _json({'ok': false, 'error': 'plan_stations'}, status: 403);
        }
        // v1.1.83: pairing a driver used to be open to any authenticated
        // client — a kitchen or cashier station could mint driver records.
        if (callerRole != 'main' && callerRole != 'manager') {
          return _json({'ok': false, 'error': 'forbidden'}, status: 403);
        }
      } else {
        final paired = readStore().drivers.any((d) => d.deviceId == who.deviceId);
        if (!paired) {
          return _json({'ok': false, 'error': 'unpaired'}, status: 403);
        }
        // A driver may only flip its OWN status: deviceId came from the
        // request body, so driver A could set driver B free/busy/offline.
        map['deviceId'] = who.deviceId;
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
      return _json({'ok': false, 'error': 'server_error'}, status: 500);
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
      'shiftClosed': store.shiftClosed,
    });
  }

  /// QR self-order flood control.
  ///
  /// v1.1.83 fix — this used to be broken in two directions:
  ///  * the "per IP" bucket keyed on the `x-real-ip` header, which the guest's
  ///    browser controls, so any script could rotate it and bypass the limit;
  ///  * when that header was absent it fell back to `req.requestedUri.host`,
  ///    which is *this server's* address — so every guest in the shop shared a
  ///    single 60-orders-per-hour bucket and QR ordering locked the whole shop
  ///    out mid-service. Takeaway-only shops were worse: with no table id the
  ///    table bucket collapsed to one shared 12-per-hour key.
  /// Now: a per-table limit for seated service, no per-table limit for
  /// takeaway/queue shops, and one generous shop-wide flood cap.
  static const int _qrPerTableHour = 24;
  static const int _qrShopHour = 900;

  bool _qrLimited(String tableId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    List<int> bucket(Map<String, List<int>> map, String key) {
      final a = map.putIfAbsent(key, () => <int>[]);
      a.removeWhere((t) => now - t > 3600000);
      return a;
    }

    // Memory guard: keys are attacker-chosen strings, so never let the maps
    // grow without bound.
    if (_qrByTable.length > 400) {
      _qrByTable.removeWhere((_, v) => v.isEmpty);
    }
    final shop = bucket(_qrShop, 'shop');
    final table =
        tableId.isEmpty ? null : bucket(_qrByTable, tableId);
    if (shop.length >= _qrShopHour) return true;
    if (table != null && table.length >= _qrPerTableHour) return true;
    table?.add(now);
    shop.add(now);
    return false;
  }

  Future<Response> _qrSubmit(Request req) async {
    if (!qrEnabled) return _json({'ok': false, 'error': 'disabled'}, status: 403);
    try {
      final rawBody = await req.readAsString();
      if (rawBody.length > 16 * 1024) {
        return _json({'ok': false, 'error': 'too_large'}, status: 413);
      }
      final body = jsonDecode(rawBody);
      if (body is! Map) return _json({'ok': false}, status: 400);
      final store = readStore();
      final rawItems = body['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        return _json({'ok': false, 'error': 'empty'}, status: 400);
      }
      if (store.shiftClosed) {
        return _json({'ok': false, 'error': 'shift_closed'}, status: 403);
      }
      FloorTable? table;
      final tableId =
          sanitizeText((body['tableId'] ?? body['table'] ?? '').toString());
      if (tableId.isNotEmpty) {
        table = store.tableByRef(tableId);
        if (table == null) {
          return _json({'ok': false, 'error': 'table_gone'}, status: 400);
        }
      } else if (store.tables.isNotEmpty) {
        // Floor map is live — never silently default a guest order to TAKEAWAY.
        return _json({'ok': false, 'error': 'need_table'}, status: 400);
      }
      if (_qrLimited(table?.id ?? tableId)) {
        return _json({'ok': false, 'error': 'rate_limited'}, status: 429);
      }
      // Idempotency: same QR payload within 5s (double-tap) returns previous ticket
      final dedupKey = '${table?.id ?? tableId}|${rawBody.hashCode}';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final last = _qrLastSubmit[dedupKey];
      if (last != null && nowMs - last.at < 5000 && last.hash == rawBody.hashCode.toString()) {
        return _json({
          'ok': true,
          'ticket': last.ticket,
          'total': 0,
          'fireOn': readStore().qrFireOn,
          'status': 'received',
          'table': table?.name ?? '',
          'dedup': true,
        });
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
        final note = sanitizeText((raw['note'] ?? '').toString().trim());
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
        customerName: sanitizeText((body['name'] ?? '').toString().trim()),
        customerPhone: sanitizeText((body['phone'] ?? '').toString().trim()),
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
      final deny = StoreGuard.denyReason(store, createCmd);
      if (deny.isNotEmpty) {
        return _json({'ok': false, 'error': deny}, status: 403);
      }
      final created = onCommand(createCmd);
      PosOrder? placed;
      for (final o in created.store.orders) {
        if (o.id == order.id) {
          placed = o;
          break;
        }
      }
      if (placed == null) {
        return _json({'ok': false, 'error': 'shift_closed'}, status: 403);
      }
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
      _qrLastSubmit[dedupKey] = _QrDedup(rawBody.hashCode.toString(), placed.ticketNo, nowMs);
      // prune map
      if (_qrLastSubmit.length > 200) {
        _qrLastSubmit.removeWhere((_, v) => nowMs - v.at > 30000);
      }
      return _json({
        'ok': true,
        'ticket': placed.ticketNo,
        'total': placed.total,
        'fireOn': created.store.qrFireOn,
        'status': created.store.qrFireOn == 'order' ? 'preparing' : 'received',
        'table': placed.tableName ?? '',
      });
    } catch (e) {
      return _json({'ok': false, 'error': 'server_error'}, status: 500);
    }
  }

  Response _qrStatus(Request req) {
    if (!qrEnabled) return _json({'ok': false, 'error': 'disabled'}, status: 403);
    final ticket = (req.url.queryParameters['ticket'] ?? '').trim();
    if (ticket.isEmpty) {
      return _json({'ok': false, 'error': 'missing'}, status: 400);
    }
    final needle = ticket.startsWith('#') ? ticket : '#$ticket';
    PosOrder? order;
    for (final o in readStore().orders) {
      if (o.ticketNo == ticket || o.ticketNo == needle || o.id == ticket) {
        order = o;
        break;
      }
    }
    if (order == null || order.channel != 'qr') {
      return _json({'ok': false, 'error': 'not_found'}, status: 404);
    }
    String stage;
    switch (order.status) {
      case OrderStatus.preparing:
        stage = 'preparing';
        break;
      case OrderStatus.ready:
      case OrderStatus.served:
        stage = 'ready';
        break;
      case OrderStatus.paid:
        stage = 'paid';
        break;
      case OrderStatus.cancelled:
        stage = 'cancelled';
        break;
      default:
        stage = order.sentAt != null ? 'preparing' : 'received';
    }
    return _json({
      'ok': true,
      'ticket': order.ticketNo,
      'status': stage,
      'table': order.tableName ?? '',
    });
  }

  bool _deviceAllowed(String deviceId, String name, String role) {
    if (deviceId == 'web-console') return true;
    final gate = deviceGate;
    if (gate == null) return true;
    if (gate.isApproved(deviceId)) return true;
    if (gate.inOpenWindow()) {
      gate.onAutoApprove(deviceId);
      return true;
    }
    // v1.1.83: cap the approval queue. Every unknown hello used to add a
    // pending entry AND fire a notification on Main, so a laptop looping
    // fresh device ids on the shop Wi-Fi could spam the owner endlessly and
    // grow two unbounded maps.
    if (pending.length >= _maxWaiting || _waiting.length >= _maxWaiting) {
      return false;
    }
    final info = ClientInfo(deviceId: deviceId, name: name, role: role);
    pending[deviceId] = info;
    gate.onPending?.call(info);
    return false;
  }

  void approveDevice(String deviceId) {
    deviceGate?.onAutoApprove(deviceId);
    final socket = _waiting.remove(deviceId);
    final info = pending.remove(deviceId);
    if (socket == null || info == null) return;
    _admit(socket, info);
  }

  void denyDevice(String deviceId) {
    final socket = _waiting.remove(deviceId);
    pending.remove(deviceId);
    try {
      socket?.sink.add(jsonEncode({'type': 'error', 'error': 'denied'}));
      socket?.sink.close();
    } catch (_) {}
  }

  void revokeDevice(String deviceId) {
    pending.remove(deviceId);
    denyDevice(deviceId);
    final drop = <WebSocketChannel>[];
    for (final e in _socketDevice.entries) {
      if (e.value == deviceId) drop.add(e.key);
    }
    for (final s in drop) {
      try {
        s.sink.add(jsonEncode({'type': 'error', 'error': 'revoked'}));
        s.sink.close();
      } catch (_) {}
      _sockets.remove(s);
      _socketDevice.remove(s);
    }
    clients.remove(deviceId);
  }

  void _admit(WebSocketChannel socket, ClientInfo info) {
    _sockets.add(socket);
    _socketDevice[socket] = info.deviceId;
    clients[info.deviceId] = info;
    try {
      socket.sink.add(jsonEncode({
        'type': 'hello',
        'token': _tokenFor(info.deviceId, info.role),
        'store': _storeJsonFor(info.deviceId),
        'name': shopName,
        'model': modelName,
      }));
    } catch (_) {}
  }

  void _onWs(WebSocketChannel socket, String? _) {
    // v1.1.83: refuse connections past the ceiling instead of accepting them
    // all — an unbounded socket set is a memory-exhaustion DoS on the device
    // that runs the whole shop.
    if (_sockets.length >= _maxSockets) {
      try {
        socket.sink.add(jsonEncode({'type': 'error', 'error': 'server_full'}));
        unawaited(socket.sink.close());
      } catch (_) {}
      return;
    }
    socket.stream.listen(
      (event) {
        try {
          // Frame cap: /command already rejects bodies over 32KB, but the
          // websocket path had no limit at all, so one client could push an
          // arbitrarily large frame into memory before JSON parsing.
          final raw = event.toString();
          if (raw.length > _maxWsFrameBytes) return;
          final data = jsonDecode(raw);
          if (data is! Map) return;
          final type = data['type'];
          if (type == 'hello') {
            final id = (data['deviceId'] ?? '').toString();
            final roleName = (data['role'] ?? '').toString();
            final name = sanitizeText((data['name'] ?? '').toString());
            if (!helloRoleOk(roleName) || id.isEmpty) {
              socket.sink.add(jsonEncode({'type': 'error', 'error': 'bad_role'}));
              return;
            }
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
              return;
            }
            final info = ClientInfo(deviceId: id, name: name, role: roleName);
            if (!_deviceAllowed(id, name, roleName)) {
              _waiting[id] = socket;
              try {
                socket.sink.add(jsonEncode({'type': 'pending', 'error': 'pending_approval'}));
              } catch (_) {}
              return;
            }
            _admit(socket, info);
          } else if (type == 'command') {
            final raw = data['command'];
            if (raw is Map) {
              final deviceId = _socketDevice[socket];
              if (deviceId == null) return;
              var cmd = NetCommand.fromJson(Map<String, dynamic>.from(raw));
              cmd = _bindRole(cmd, deviceId);
              if (isPrivileged(cmd.name, cmd.role)) return;
              if (!RoleAccess.allow(cmd.role, cmd)) return;
              if (StoreGuard.denyReason(readStore(), cmd).isNotEmpty) return;
              StoreGuard.sanitize(readStore(), cmd);
              final result = onCommand(cmd);
              broadcastState();
              if (result.notice != null) broadcastNotice(result.notice!);
            }
          }
        } catch (_) {}
      },
      onDone: () {
        final id = _socketDevice.remove(socket);
        _sockets.remove(socket);
        if (id != null) {
          clients.remove(id);
          _waiting.remove(id);
        }
      },
      onError: (_) {
        final id = _socketDevice.remove(socket);
        _sockets.remove(socket);
        if (id != null) {
          clients.remove(id);
          _waiting.remove(id);
        }
      },
      cancelOnError: true,
    );
  }

}

class _QrDedup {
  _QrDedup(this.hash, this.ticket, this.at);
  final String hash;
  final String ticket;
  final int at;
}
