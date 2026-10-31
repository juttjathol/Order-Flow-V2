import 'package:flutter_test/flutter_test.dart';
import 'package:order_flow/core/lan_policy.dart';
import 'package:order_flow/core/pin_crypto.dart';
import 'package:order_flow/core/role_access.dart';
import 'package:order_flow/core/sanitize.dart';
import 'package:order_flow/models/models.dart';
import 'package:order_flow/services/cloud_relay.dart';

void main() {
  test('helloRoleOk allows AppRole names and web, rejects main/empty', () {
    expect(helloRoleOk('web'), isTrue);
    expect(helloRoleOk('cashier'), isTrue);
    expect(helloRoleOk('orderTaker'), isTrue);
    expect(helloRoleOk('main'), isFalse);
    expect(helloRoleOk(''), isFalse);
    expect(helloRoleOk('none'), isFalse);
    expect(helloRoleOk('admin'), isFalse);
  });

  test('corsOriginOk matches http://Host only', () {
    expect(corsOriginOk(null, '10.0.0.1:8787'), isTrue);
    expect(corsOriginOk('', '10.0.0.1:8787'), isTrue);
    expect(corsOriginOk('http://10.0.0.1:8787', '10.0.0.1:8787'), isTrue);
    expect(corsOriginOk('http://evil.example', '10.0.0.1:8787'), isFalse);
    expect(corsOriginOk('https://10.0.0.1:8787', '10.0.0.1:8787'), isFalse);
  });

  test('corsOriginOk blocks DNS rebinding (v1.1.83)', () {
    // A rebinding page makes Origin and Host agree with each other while the
    // authority is a hostname that resolves to the shop's LAN IP. That must
    // never be treated as same-origin.
    expect(corsOriginOk('http://shop.evil:8787', 'shop.evil:8787'), isFalse);
    expect(corsOriginOk('http://10.0.0.1.evil', '10.0.0.1.evil'), isFalse);
    expect(corsOriginOk('http://orderflow.local:8787', 'orderflow.local:8787'), isFalse);
    // Real guests and the owner console always arrive by IP literal.
    expect(corsOriginOk('http://192.168.1.50:8787', '192.168.1.50:8787'), isTrue);
    expect(corsOriginOk('http://10.0.0.1:8787', '10.0.0.1:8787'), isTrue);
    expect(corsOriginOk('http://localhost:8787', 'localhost:8787'), isTrue);
    expect(corsOriginOk('http://[::1]:8787', '[::1]:8787'), isTrue);
    // Native apps send no Origin at all and stay unaffected.
    expect(corsOriginOk(null, 'shop.evil:8787'), isTrue);
  });

  test('authorityIsIpLiteral only accepts IP-shaped authorities', () {
    expect(authorityIsIpLiteral('192.168.0.7'), isTrue);
    expect(authorityIsIpLiteral('192.168.0.7:8787'), isTrue);
    expect(authorityIsIpLiteral('localhost:8787'), isTrue);
    expect(authorityIsIpLiteral('[fe80::1]:8787'), isTrue);
    expect(authorityIsIpLiteral('main.local'), isFalse);
    expect(authorityIsIpLiteral('shop.evil:8787'), isFalse);
    expect(authorityIsIpLiteral('10.0.0'), isFalse);
    expect(authorityIsIpLiteral('10.0.0.1x'), isFalse);
    expect(authorityIsIpLiteral(''), isFalse);
  });

  test('web RoleAccess cannot replaceState or setEntitlements', () {
    expect(RoleAccess.allow('web', NetCommand(name: 'createOrder')), isTrue);
    expect(RoleAccess.allow('web', NetCommand(name: 'setModel')), isTrue);
    expect(RoleAccess.allow('web', NetCommand(name: 'replaceState')), isFalse);
    expect(RoleAccess.allow('web', NetCommand(name: 'setEntitlements')), isFalse);
    expect(RoleAccess.allow('web', NetCommand(name: 'seedModel')), isFalse);
  });

  test('paid and cancelled tickets cannot be reopened or rewritten', () {
    final paid = PosOrder(
      id: 'paid-1', ticketNo: '1001', type: OrderType.takeaway,
      status: OrderStatus.paid,
    );
    final cancelled = PosOrder(
      id: 'cancelled-1', ticketNo: '1002', type: OrderType.takeaway,
      status: OrderStatus.cancelled,
    );
    final store = AppStore(orders: [paid, cancelled]);
    expect(StoreGuard.denyReason(store, NetCommand(
      name: 'setOrderStatus', payload: {'id': paid.id, 'status': 'paid'},
    )), 'ticket_closed');
    expect(StoreGuard.denyReason(store, NetCommand(
      name: 'setOrderStatus', payload: {'orderId': cancelled.id, 'status': 'paid'},
    )), 'ticket_closed');
    expect(StoreGuard.denyReason(store, NetCommand(
      name: 'setOrderStatus', payload: {'id': paid.id, 'status': 'cancelled'},
    )), ''); // controller enforces the manager PIN and reducer reversals
    expect(StoreGuard.denyReason(store, NetCommand(
      name: 'mergeOrders', payload: {'keepId': cancelled.id, 'dropId': paid.id},
    )), 'ticket_closed');
  });

  test('driver relay commands bind to paired device and legal transition', () {
    final driver = Driver(id: 'driver-1', name: 'A', deviceId: 'paired-device');
    final order = PosOrder(
      id: 'delivery-1', ticketNo: '2001', type: OrderType.delivery,
      status: OrderStatus.preparing, driverId: driver.id, deliveryState: 'queued',
    );
    final store = AppStore(drivers: [driver], orders: [order]);
    final cmd = NetCommand(name: 'setDelivery', payload: {
      'orderId': order.id, 'state': 'out', 'driverId': 'spoofed',
    });
    expect(RoleAccess.bindDriverCommand(store, cmd, 'other-device'), isFalse);
    expect(RoleAccess.bindDriverCommand(store, cmd, 'paired-device'), isTrue);
    expect(cmd.payload['driverId'], driver.id);
  });

  test('station cannot send privileged commands', () {
    expect(isPrivileged('replaceState', 'cashier'), isTrue);
    expect(isPrivileged('setEntitlements', 'manager'), isTrue);
    expect(isPrivileged('setModel', 'cashier'), isTrue);
    expect(isPrivileged('setModel', 'web'), isFalse);
    expect(isPrivileged('setModel', 'main'), isFalse);
    expect(isPrivileged('createOrder', 'cashier'), isFalse);
  });

  test('sanitizeText strips control characters except tab/newline', () {
    expect(sanitizeText('ok\tline\n'), 'ok\tline\n');
    expect(sanitizeText('bad\u0000x\u0007y'), 'badxy');
    expect(sanitizeText('hi\u001b[31m'), 'hi[31m');
  });

  test('PinCrypto hashes and verifies; plaintext still matches once', () {
    const pin = '1234';
    final hashed = PinCrypto.hash(pin);
    expect(PinCrypto.isHashed(hashed), isTrue);
    expect(PinCrypto.verify(hashed, pin), isTrue);
    expect(PinCrypto.verify(hashed, '0000'), isFalse);
    expect(PinCrypto.verify('1234', '1234'), isTrue);
    expect(PinCrypto.verify('1234', '0000'), isFalse);
  });

  test('parsePairing rejects non-https origins', () {
    final good = CloudRelay.pairing('r1', 'CODE12', 'sec', 'https://order-flow-v2.pages.dev');
    expect(CloudRelay.parsePairing(good), isNotNull);
    final http = CloudRelay.pairing('r1', 'CODE12', 'sec', 'http://evil.example');
    expect(CloudRelay.parsePairing(http), isNull);
    expect(CloudRelay.parsePairing('garbage'), isNull);
  });

  test('safeEq is length-aware', () {
    expect(safeEq('abcd', 'abcd'), isTrue);
    expect(safeEq('abcd', 'abce'), isFalse);
    expect(safeEq('abc', 'abcd'), isFalse);
  });
}
