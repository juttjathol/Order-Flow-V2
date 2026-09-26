import 'package:flutter_test/flutter_test.dart';
import 'package:order_flow/core/role_access.dart';
import 'package:order_flow/models/models.dart';
import 'package:order_flow/models/reducer.dart';
import 'package:order_flow/services/cloud_relay.dart';
import 'package:order_flow/services/print_service.dart';
import 'package:order_flow/state/app_controller.dart';

void main() {
  test('PosOrder split payment round-trips through json', () {
    final order = PosOrder(
      id: 'o1',
      ticketNo: '#1001',
      type: OrderType.dineIn,
      lines: [OrderLine(id: 'l1', productId: 'p1', name: 'Burger', unitPrice: 100)],
    )..splitPayment = PaymentMethod.card;
    order.splitAmount = 40;
    order.loyaltyAwarded = true;

    final copy = PosOrder.fromJson(order.toJson());

    expect(copy.splitPayment, PaymentMethod.card);
    expect(copy.splitAmount, 40);
    expect(copy.loyaltyAwarded, isTrue);
    expect(copy.primaryAmount, 60);
    expect(copy.cashInvolved, isFalse);
  });

  test('paidBy counts both tenders and cashInvolved detects cash', () {
    final order = PosOrder(
      id: 'o1',
      ticketNo: '#1002',
      type: OrderType.retail,
      lines: [OrderLine(id: 'l1', productId: 'p1', name: 'Item', unitPrice: 100)],
    )
      ..payment = PaymentMethod.card
      ..splitPayment = PaymentMethod.cash
      ..splitAmount = 30;

    expect(order.cashInvolved, isTrue);
    expect(order.paidBy(PaymentMethod.cash), 30);
    expect(order.paidBy(PaymentMethod.card), 70);
    expect(order.paidBy(PaymentMethod.wallet), 0);
  });

  test('PrinterConfig drawer flag round-trips', () {
    final cfg = PrinterConfig(
      name: 'Receipt',
      host: '192.168.1.50',
      enabled: true,
      drawer: true,
    );
    final copy = PrinterConfig.fromJson(cfg.toJson());
    expect(copy.drawer, isTrue);
    expect(copy.host, '192.168.1.50');
    expect(copy.isBluetooth, isFalse);
  });

  test('setDrawer command toggles the store flag', () {
    var store = AppStore();
    var res = StoreReducer.apply(
      store,
      NetCommand(name: 'setDrawer', payload: {'on': true}),
    );
    expect(res.store.drawerAuto, isTrue);
    res = StoreReducer.apply(
      res.store,
      NetCommand(name: 'setDrawer', payload: {'on': false}),
    );
    expect(res.store.drawerAuto, isFalse);
  });

  test('setOrderStatus records split payment without breaking payment', () {
    final store = AppStore(orders: [
      PosOrder(
        id: 'o1',
        ticketNo: '#1003',
        type: OrderType.takeaway,
        lines: [OrderLine(id: 'l1', productId: 'p1', name: 'Tea', unitPrice: 50)],
      ),
    ]);
    final res = StoreReducer.apply(
      store,
      NetCommand(name: 'setOrderStatus', payload: {
        'id': 'o1',
        'status': OrderStatus.paid.name,
        'payment': 'card',
        'splitPayment': 'cash',
        'splitAmount': 20,
      }),
    );
    final order = res.store.orderById('o1')!;
    expect(order.status, OrderStatus.paid);
    expect(order.payment, PaymentMethod.card);
    expect(order.splitPayment, PaymentMethod.cash);
    expect(order.splitAmount, 20);
    expect(order.cashInvolved, isTrue);
  });

  // ── v1.1.59: plan entitlements & new store features ────────────────────

  test('legacy license keeps every feature on', () {
    final ent = Entitlements();
    expect(ent.allOn, isTrue);
    expect(ent.allowsFeature('qr_ordering'), isTrue);
    expect(ent.allowsModel('restaurant'), isTrue);
    final fromLic = Entitlements.fromLicense(plan: 'full');
    expect(fromLic.allOn, isTrue, reason: 'no plan data = nothing restricted');
  });

  test('starter license turns gated features off, growth turns them on', () {
    final starter = Entitlements.fromLicense(
      plan: 'starter',
      allowedModels: ['restaurant'],
      allowedFeatures: <String>[],
    );
    expect(starter.allOn, isFalse);
    expect(starter.allowsFeature('loyalty'), isFalse);
    expect(starter.allowsFeature('purchases'), isFalse);
    expect(starter.allowsFeature('some-always-on-thing'), isTrue);
    expect(starter.allowsModel('restaurant'), isTrue);
    expect(starter.allowsModel('retail'), isFalse);

    final growth = Entitlements.fromLicense(
      plan: 'growth',
      allowedModels: ['restaurant', 'retail'],
      allowedFeatures: ['loyalty', 'purchases'],
    );
    expect(growth.allowsFeature('purchases'), isTrue);
    expect(growth.allowsModel('services'), isFalse);
  });

  test('StoreGuard blocks gated commands and allows them when enabled', () {
    final store = AppStore();
    store.entitlements = Entitlements(
      allOn: false,
      plan: 'starter',
      models: const ['restaurant'],
      features: const [],
    );
    final waste = NetCommand(
      name: 'logWastage',
      role: 'main',
      payload: {'stockId': 's1', 'quantity': 2},
    );
    expect(StoreGuard.allow(store, waste), isFalse);

    store.stock.add(StockItem(id: 's1', name: 'Buns', quantity: 10, cost: 1));
    store.entitlements.features = const ['wastage', 'purchases'];
    expect(StoreGuard.allow(store, waste), isTrue);
    final res = StoreReducer.apply(store, waste);
    expect(res.store.stockById('s1')!.quantity, 8);
    expect(res.store.waste.length, 1);
    expect(res.store.waste.first.cost, 2);
  });

  // ── v1.1.82: full-plan heal + empty-list production bug ──────────────

  test('v1.1.82 full plan with explicit empty lists still allows every feature', () {
    // The exact production D1 payload that shipped with the editor bug:
    // plan 'full', all four models ticked, and features: [].
    final full = Entitlements.fromLicense(
      plan: 'full',
      allowedModels: ['restaurant', 'retail', 'fastfood', 'services'],
      allowedFeatures: <String>[],
    );
    expect(full.allOn, isTrue);
    expect(full.allowsFeature('qr_ordering'), isTrue);
    expect(full.allowsFeature('cloud_sync'), isTrue);
    expect(full.allowsFeature('qr_branding'), isTrue);
    expect(full.allowsModel('restaurant'), isTrue);
  });

  test('v1.1.82 starter with empty features really locks extras', () {
    final starter = Entitlements.fromLicense(
      plan: 'starter',
      allowedModels: ['restaurant'],
      allowedFeatures: <String>[],
    );
    expect(starter.allOn, isFalse);
    expect(starter.allowsFeature('loyalty'), isFalse);
    expect(starter.allowsFeature('qr_ordering'), isFalse);
    expect(starter.allowsFeature('some-always-on-thing'), isTrue);
  });

  test('v1.1.82 growth core set locks only cloud extras', () {
    const core13 = [
      'multi_terminal', 'station_printers', 'qr_ordering', 'loyalty',
      'split_payment', 'refunds', 'customer_display', 'reservations',
      'recipe_costing', 'wastage', 'purchases', 'advanced_reports', 'eighty_six',
    ];
    final growth = Entitlements.fromLicense(
      plan: 'growth',
      allowedModels: ['restaurant'],
      allowedFeatures: core13,
    );
    for (final key in core13) {
      expect(growth.allowsFeature(key), isTrue, reason: key);
    }
    expect(growth.allowsFeature('qr_branding'), isFalse);
    expect(growth.allowsFeature('cloud_sync'), isFalse);
  });

  test('setEntitlements only applies from Main role', () {
    final store = AppStore();
    // v1.1.82: start from a restricted store so the allow/deny assertions
    // measure the role gate, not the legacy all-on default.
    store.entitlements = Entitlements(
      allOn: false,
      plan: 'starter',
      features: const [],
    );
    expect(store.entitlements.allOn, isFalse);
    final fromClient = NetCommand(
      name: 'setEntitlements',
      role: 'cashier',
      payload: {'entitlements': Entitlements(allOn: false).toJson()},
    );
    expect(StoreGuard.allow(store, fromClient), isFalse);
    final fromMain = NetCommand(
      name: 'setEntitlements',
      role: 'main',
      payload: {
        'entitlements': Entitlements(
          allOn: false,
          plan: 'starter',
          features: const [],
        ).toJson(),
      },
    );
    expect(StoreGuard.allow(store, fromMain), isTrue);
  });

  test('QR channel and staff attribution survive order patches', () {
    final store = AppStore();
    final order = PosOrder(
      id: 'o9',
      ticketNo: '#9',
      type: OrderType.dineIn,
      channel: 'qr',
      staffId: 'st1',
    );
    StoreReducer.apply(
      store,
      NetCommand(name: 'createOrder', role: 'web', payload: {'order': order.toJson()}),
    );
    final placed = store.orders.first;
    placed.channel = 'qr';
    placed.staffId = 'st1';
    // A patch built without the new fields keeps them intact.
    final stale = PosOrder.fromJson({
      'id': placed.id,
      'ticketNo': placed.ticketNo,
      'type': placed.type.name,
      'status': placed.status.name,
    });
    StoreReducer.apply(
      store,
      NetCommand(name: 'patchOrder', role: 'cashier', payload: {'order': stale.toJson()}),
    );
    final after = store.orders.first;
    expect(after.channel, 'qr');
    expect(after.staffId, 'st1');
    expect(after.isQr, isTrue);
  });

  test('receive purchase restocks and updates cost', () {
    final store = AppStore();
    store.entitlements = Entitlements(allOn: false, features: const ['purchases']);
    store.stock.add(StockItem(id: 's1', name: 'Milk', quantity: 1, cost: 50));
    final po = PurchaseOrder(
      id: 'p1',
      poNo: 'PO-1',
      lines: [PurchaseLine(stockId: 's1', quantity: 4, cost: 60)],
    );
    StoreReducer.apply(
      store,
      NetCommand(name: 'upsertPurchase', role: 'main', payload: {'purchase': po.toJson()}),
    );
    final stored = store.purchases.first;
    StoreReducer.apply(
      store,
      NetCommand(name: 'receivePurchase', role: 'main', payload: {'id': stored.id}),
    );
    expect(store.stockById('s1')!.quantity, 5);
    expect(store.stockById('s1')!.cost, 60);
    expect(store.purchases.first.status, 'received');
  });

  test('v1.1.60 qr fire mode + brand round-trip through store json', () {
    final store = AppStore();
    expect(store.qrFireOn, 'pay');
    StoreReducer.apply(store, NetCommand(name: 'setQrFireOn', payload: {'mode': 'order'}));
    expect(store.qrFireOn, 'order');
    store.qrBrand = QrBrand(
      shopName: 'Biryani House',
      tagline: 'King of tastes',
      whatsapp: '+92 300 1234567',
      accent: '#8b5cf6',
    );
    final copy = AppStore.fromJson(store.toJson());
    expect(copy.qrFireOn, 'order');
    expect(copy.qrBrand.shopName, 'Biryani House');
    expect(copy.qrBrand.whatsapp, '+92 300 1234567');
    expect(copy.qrBrand.accent, '#8b5cf6');
  });

  test('v1.1.60 upsertQrBrand reducer', () {
    final store = AppStore();
    final rev = store.revision;
    StoreReducer.apply(store, NetCommand(name: 'upsertQrBrand', payload: {
      'brand': {'shopName': 'Chatkara', 'hours': '9am to 12am'},
    }));
    expect(store.qrBrand.shopName, 'Chatkara');
    expect(store.qrBrand.hours, '9am to 12am');
    expect(store.revision, greaterThan(rev));
  });

  test('v1.1.60 plan gates: branding is custom-only, fire mode rides qr_ordering', () {
    final growth = AppStore();
    growth.entitlements = Entitlements(
        allOn: false, features: const ['qr_ordering', 'multi_terminal']);
    expect(StoreGuard.denyReason(growth, NetCommand(name: 'setQrFireOn', role: '')), isEmpty);
    expect(StoreGuard.denyReason(growth, NetCommand(name: 'upsertQrBrand', role: '')), isNotEmpty);
    final starter = AppStore();
    starter.entitlements = Entitlements(allOn: false, features: const []);
    expect(StoreGuard.denyReason(starter, NetCommand(name: 'setQrFireOn', role: '')), isNotEmpty);
    expect(growth.canFeature('cloud_sync'), isFalse);
    expect(starter.canFeature('cloud_sync'), isFalse);
    final custom = AppStore();
    custom.entitlements =
        Entitlements(allOn: false, features: const ['cloud_sync', 'qr_branding']);
    expect(custom.canFeature('cloud_sync'), isTrue);
    expect(custom.canFeature('qr_branding'), isTrue);
    expect(AppStore().canFeature('cloud_sync'), isTrue); // legacy keys: all on
  });

  test('v1.1.60 cloud pairing text round-trips', () {
    final txt = CloudRelay.pairing(
        'r3f9', 'AB3K9Z', 'sec123', 'https://order-flow-v2.pages.dev');
    final parts = CloudRelay.parsePairing(txt);
    expect(parts, isNotNull);
    expect(parts![0], 'r3f9');
    expect(parts[1], 'AB3K9Z');
    expect(parts[2], 'sec123');
    expect(parts[3], 'https://order-flow-v2.pages.dev');
    expect(CloudRelay.parsePairing('garbage'), isNull);
    expect(CloudRelay.parsePairing('OF1:a:b:c'), isNull);
  });

  test('deleteCategory reassigns products instead of deleting them', () {
    final store = AppStore();
    store.categories.add(MenuCategory(id: 'c1', name: 'Mains'));
    store.products.add(MenuProduct(id: 'p1', categoryId: 'c1', name: 'Steak', price: 10));
    StoreReducer.apply(store, NetCommand(name: 'deleteCategory', payload: {'id': 'c1'}));
    expect(store.products, hasLength(1));
    expect(store.products.first.name, 'Steak');
    expect(store.products.first.categoryId, isNot('c1'));
    expect(store.categories.any((c) => c.id == 'c1'), isFalse);
    expect(
      store.categories.any((c) => c.id == 'uncat' || c.name.toLowerCase() == 'uncategorized'),
      isTrue,
    );
  });

  test('PrintService.formatQty keeps wholes whole and trims weight decimals', () {
    expect(PrintService.formatQty(2), '2');
    expect(PrintService.formatQty(2.0), '2');
    expect(PrintService.formatQty(1.5), '1.5');
    expect(PrintService.formatQty(0.250), '0.25');
    expect(PrintService.formatQty(1.125), '1.125');
  });

  test('AppSnapshot copyWith clearIp/clearError actually null the fields', () {
    final snap = AppSnapshot(
      ready: true,
      session: SessionPrefs(),
      store: AppStore(),
      gate: LicenseGate.ready,
      serverOn: false,
      connected: false,
      lanIp: '10.0.0.1',
      busy: false,
      error: 'boom',
      notices: const [],
      online: true,
      clients: const [],
      pendingSync: 0,
    );
    final next = snap.copyWith(clearIp: true, clearError: true);
    expect(next.lanIp, isNull);
    expect(next.error, isNull);
    expect(snap.lanIp, '10.0.0.1');
    expect(snap.error, 'boom');
  });

  // ── v1.1.74: QR table on kitchen slip, busy clock, live search, shop shift ─

  test('v1.1.74 kitchenWhere prints table, never TAKEAWAY for a table ticket', () {
    final qr = PosOrder(
      id: 'q1',
      ticketNo: '#1101',
      type: OrderType.dineIn,
      tableName: 'T4',
      channel: 'qr',
    );
    expect(qr.kitchenWhere, '>>> QR TABLE T4 <<<');
    expect(qr.kitchenWhere.contains('TAKEAWAY'), isFalse);

    final dine = PosOrder(
      id: 'd1',
      ticketNo: '#1102',
      type: OrderType.dineIn,
      tableName: 'T2',
    );
    expect(dine.kitchenWhere, 'Table T2');

    final take = PosOrder(
      id: 't1',
      ticketNo: '#1103',
      type: OrderType.takeaway,
    );
    expect(take.kitchenWhere, 'TAKEAWAY');

    final bareDine = PosOrder(
      id: 'd2',
      ticketNo: '#1104',
      type: OrderType.dineIn,
    );
    expect(bareDine.kitchenWhere, 'DINE IN');
  });

  test('v1.1.74 kitchenWhere and shiftNo survive json + stale patch', () {
    final store = AppStore();
    final order = PosOrder(
      id: 'o74',
      ticketNo: '#74',
      type: OrderType.dineIn,
      tableName: 'T8',
      channel: 'qr',
      shiftNo: 3,
    );
    StoreReducer.apply(
      store,
      NetCommand(name: 'createOrder', role: 'web', payload: {'order': order.toJson()}),
    );
    final placed = store.orders.first;
    placed.channel = 'qr';
    placed.tableName = 'T8';
    placed.shiftNo = 3;
    final stale = PosOrder.fromJson({
      'id': placed.id,
      'ticketNo': placed.ticketNo,
      'type': placed.type.name,
      'status': placed.status.name,
      'tableName': 'T8',
    });
    StoreReducer.apply(
      store,
      NetCommand(name: 'patchOrder', role: 'cashier', payload: {'order': stale.toJson()}),
    );
    final after = store.orders.first;
    expect(after.channel, 'qr');
    expect(after.shiftNo, 3);
    expect(after.kitchenWhere, '>>> QR TABLE T8 <<<');
  });

  test('v1.1.74 matchesQuery finds ticket number with or without hash', () {
    final o = PosOrder(
      id: 's1',
      ticketNo: '#2044',
      type: OrderType.dineIn,
      tableName: 'T9',
      customerName: 'Amina',
    );
    expect(o.matchesQuery(''), isTrue);
    expect(o.matchesQuery('2044'), isTrue);
    expect(o.matchesQuery('#2044'), isTrue);
    expect(o.matchesQuery('t9'), isTrue);
    expect(o.matchesQuery('amina'), isTrue);
    expect(o.matchesQuery('missing'), isFalse);
  });

  test('v1.1.74 formatBusyClock is mm:ss then h:mm:ss', () {
    final start = DateTime(2026, 9, 22, 12, 0, 0);
    expect(formatBusyClock(start, start), '00:00');
    expect(formatBusyClock(start, start.add(const Duration(seconds: 65))), '01:05');
    expect(formatBusyClock(start, start.add(const Duration(hours: 1, minutes: 2, seconds: 3))), '1:02:03');
  });

  test('v1.1.74 tableByRef matches id or name; openOrderForTable ignores stale id', () {
    final table = FloorTable(id: 'tbl-1', name: 'T1');
    final live = PosOrder(
      id: 'live',
      ticketNo: '#1',
      type: OrderType.dineIn,
      tableId: 'tbl-1',
      tableName: 'T1',
    );
    final paid = PosOrder(
      id: 'old',
      ticketNo: '#0',
      type: OrderType.dineIn,
      tableId: 'tbl-1',
      status: OrderStatus.paid,
    );
    table.currentOrderId = paid.id;
    final store = AppStore(tables: [table], orders: [paid, live]);
    expect(store.tableByRef('tbl-1')?.name, 'T1');
    expect(store.tableByRef('t1')?.id, 'tbl-1');
    expect(store.tableByRef('gone'), isNull);
    expect(store.openOrderForTable(table)?.id, 'live');
  });

  test('v1.1.74 shop shift lock blocks createOrder until openShift', () {
    final store = AppStore(shiftNo: 2);
    store.tables.add(FloorTable(id: 't1', name: 'T1'));
    expect(StoreGuard.denyReason(store, NetCommand(name: 'createOrder', role: 'web')), isEmpty);

    StoreReducer.apply(store, NetCommand(name: 'closeDay', role: 'manager', payload: {}));
    expect(store.shiftClosed, isTrue);
    expect(StoreGuard.denyReason(store, NetCommand(name: 'createOrder', role: 'main')), 'shift_closed');

    final before = store.orders.length;
    StoreReducer.apply(
      store,
      NetCommand(name: 'createOrder', role: 'web', payload: {
        'order': PosOrder(id: 'blocked', ticketNo: '', type: OrderType.dineIn).toJson(),
      }),
    );
    expect(store.orders.length, before);

    expect(RoleAccess.allow('manager', NetCommand(name: 'openShift')), isTrue);
    expect(RoleAccess.allow('cashier', NetCommand(name: 'openShift')), isFalse);
    expect(RoleAccess.allow('cashier', NetCommand(name: 'closeDay')), isFalse);

    final rev = store.revision;
    StoreReducer.apply(store, NetCommand(name: 'openShift', role: 'manager', payload: {}));
    expect(store.shiftClosed, isFalse);
    expect(store.shiftNo, 3);
    expect(store.revision, greaterThan(rev));

    StoreReducer.apply(store, NetCommand(name: 'openShift', role: 'manager', payload: {}));
    expect(store.shiftNo, 3, reason: 'opening an already-open shift is a no-op');

    StoreReducer.apply(
      store,
      NetCommand(name: 'createOrder', role: 'web', payload: {
        'order': PosOrder(
          id: 'ok',
          ticketNo: '',
          type: OrderType.dineIn,
          tableId: 't1',
          tableName: 'T1',
          channel: 'qr',
        ).toJson(),
      }),
    );
    expect(store.orders, isNotEmpty);
    expect(store.orders.first.shiftNo, 3);
    expect(store.orders.first.kitchenWhere, '>>> QR TABLE T1 <<<');
    expect(store.tableById('t1')!.status, isNot(TableStatus.free));
    expect(store.tableById('t1')!.occupiedAt, isNotNull);
  });

  test('v1.1.74 shiftClosed round-trips on the store', () {
    final store = AppStore(shiftClosed: true, shiftNo: 4);
    final copy = AppStore.fromJson(store.toJson());
    expect(copy.shiftClosed, isTrue);
    expect(copy.shiftNo, 4);
  });

  test('v1.1.76 PrinterConfig spooler transport round-trips through json', () {
    final cfg = PrinterConfig(
      name: '',
      enabled: true,
      transport: 'spooler',
      spoolerName: 'Xprinter XP-58',
      paperMm: 58,
    );
    expect(cfg.isSpooler, isTrue);
    expect(cfg.label, 'Xprinter XP-58'); // falls back to the spooler name
    final copy = PrinterConfig.fromJson(cfg.toJson());
    expect(copy.transport, 'spooler');
    expect(copy.spoolerName, 'Xprinter XP-58');
    expect(copy.isSpooler, isTrue);
    expect(copy.paperMm, 58);
    // Older sessions (no spooler keys) parse with the desktop printer off.
    final old = PrinterConfig.fromJson({
      'id': 'p1',
      'host': '192.168.1.50',
      'port': 9100,
      'enabled': true,
      'transport': 'lan',
    });
    expect(old.isSpooler, isFalse);
    expect(old.spoolerName, '');
  });

  test('v1.1.76 SessionPrefs keeps Windows printer optional and off by default', () {
    final s = SessionPrefs.fromJson({'role': 'main', 'deviceId': 'd1'});
    expect(s.localSpoolerName, '');
    expect(s.localSpoolerEnabled, isFalse);
    expect(s.hasLocalSpoolerPrinter, isFalse);
    s.localSpoolerName = 'XP-58';
    s.localSpoolerEnabled = true;
    expect(s.hasLocalSpoolerPrinter, isTrue);
    final copy = SessionPrefs.fromJson(s.toJson());
    expect(copy.localSpoolerName, 'XP-58');
    expect(copy.hasLocalSpoolerPrinter, isTrue);
  });

  test('v1.1.75 BroadcastItem round-trips through json', () {
    final item = BroadcastItem(
      id: 'b1',
      title: 'Kitchen Timers',
      message: 'New live clock on table map',
      tag: 'feature',
      url: 'floor',
      createdAt: DateTime.utc(2026, 9, 24, 10, 0),
    );
    final copy = BroadcastItem.fromJson(item.toJson());
    expect(copy.id, 'b1');
    expect(copy.title, 'Kitchen Timers');
    expect(copy.message, 'New live clock on table map');
    expect(copy.tag, 'feature');
    expect(copy.url, 'floor');
  });
}
