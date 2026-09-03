import 'package:flutter_test/flutter_test.dart';
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
}
