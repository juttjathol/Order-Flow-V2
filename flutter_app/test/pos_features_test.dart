import 'package:flutter_test/flutter_test.dart';
import 'package:order_flow/core/role_access.dart';
import 'package:order_flow/models/models.dart';
import 'package:order_flow/models/reducer.dart';

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

  test('setEntitlements only applies from Main role', () {
    final store = AppStore();
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
}
