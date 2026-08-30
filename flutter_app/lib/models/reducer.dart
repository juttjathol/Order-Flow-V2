import 'models.dart';
import 'seed.dart';

class ReduceResult {
  ReduceResult(this.store, {this.notice});
  final AppStore store;
  final AppNotice? notice;
}

class StoreReducer {
  static ReduceResult apply(AppStore store, NetCommand cmd) {
    AppNotice? notice;
    final p = cmd.payload;

    void bump() {
      store.revision += 1;
    }

    Map<String, dynamic> mapOf(Object? raw) =>
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    switch (cmd.name) {
      case 'replaceState':
        store = AppStore.fromJson(mapOf(p['store']));
        bump();
        break;
      case 'seedModel':
        final model = enumParse(
          BusinessModel.values,
          p['model'],
          BusinessModel.restaurant,
        );
        seedFor(model, store);
        bump();
        break;
      case 'setModel':
        store.model = enumParse(
          BusinessModel.values,
          p['model'],
          store.model,
        );
        bump();
        break;
      case 'setProfile':
        store.profile = BillProfile.fromJson(mapOf(p['profile']));
        bump();
        break;
      case 'setPrinters':
        if (p['printers'] is List) {
          store.printers = (p['printers'] as List)
              .whereType<Map>()
              .map((e) => PrinterConfig.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        if (p['rolePrinters'] is Map) {
          store.rolePrinters = Map<String, dynamic>.from(p['rolePrinters'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()));
        }
        if (p['kitchen'] is Map) {
          store.kitchenPrinter =
              PrinterConfig.fromJson(Map<String, dynamic>.from(p['kitchen'] as Map));
        } else {
          store.kitchenPrinter = store.kitchenTarget();
        }
        if (p['receipt'] is Map) {
          store.receiptPrinter =
              PrinterConfig.fromJson(Map<String, dynamic>.from(p['receipt'] as Map));
        } else {
          store.receiptPrinter = store.receiptTarget();
        }
        bump();
        break;
      case 'upsertTable':
        final t = FloorTable.fromJson(mapOf(p['table']));
        final i = store.tables.indexWhere((e) => e.id == t.id);
        if (i >= 0) {
          store.tables[i] = t;
        } else {
          store.tables.add(t);
        }
        bump();
        break;
      case 'deleteTable':
        store.tables.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'upsertCategory':
        final c = MenuCategory.fromJson(mapOf(p['category']));
        final i = store.categories.indexWhere((e) => e.id == c.id);
        if (i >= 0) {
          store.categories[i] = c;
        } else {
          store.categories.add(c);
        }
        bump();
        break;
      case 'deleteCategory':
        store.categories.removeWhere((e) => e.id == p['id']);
        store.products.removeWhere((e) => e.categoryId == p['id']);
        bump();
        break;
      case 'upsertProduct':
        final prod = MenuProduct.fromJson(mapOf(p['product']));
        final i = store.products.indexWhere((e) => e.id == prod.id);
        if (i >= 0) {
          store.products[i] = prod;
        } else {
          store.products.add(prod);
        }
        bump();
        break;
      case 'deleteProduct':
        store.products.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'upsertStock':
        final s = StockItem.fromJson(mapOf(p['stock']));
        final i = store.stock.indexWhere((e) => e.id == s.id);
        if (i >= 0) {
          store.stock[i] = s;
        } else {
          store.stock.add(s);
        }
        bump();
        break;
      case 'adjustStock':
        final item = store.stockById(parseStr(p['id']));
        if (item != null) {
          item.quantity += parseNum(p['delta']);
          if (item.quantity < 0) item.quantity = 0;
        }
        bump();
        break;
      case 'deleteStock':
        store.stock.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'createOrder':
        final order = PosOrder.fromJson(mapOf(p['order']));
        order.ticketNo = store.nextTicket();
        order.taxRate = store.profile.taxRate;
        order.serviceRate = store.profile.serviceRate;
        store.orders.insert(0, order);
        _syncTable(store, order);
        bump();
        break;
      case 'patchOrder':
        final incoming = PosOrder.fromJson(mapOf(p['order']));
        final i = store.orders.indexWhere((e) => e.id == incoming.id);
        if (i >= 0) {
          incoming.stockDeducted = store.orders[i].stockDeducted;
          store.orders[i] = incoming;
          _syncTable(store, incoming);
        }
        bump();
        break;
      case 'closeDay':
        store.lastDayClose = DateTime.now();
        bump();
        break;
      case 'startShift':
        store.shiftCashier = parseStr(p['name']) ?? '';
        store.shiftStartedAt = DateTime.now();
        store.shiftFloat = parseNum(p['float']);
        store.shiftEndCash = 0;
        bump();
        break;
      case 'endShift':
        store.shiftEndCash = parseNum(p['endCash']);
        store.shiftCashier = '';
        store.shiftStartedAt = null;
        bump();
        break;
      case 'upsertCustomer':
        final c = ShopCustomer.fromJson(mapOf(p['customer']));
        final i = store.customers.indexWhere((e) => e.id == c.id);
        if (i >= 0) {
          store.customers[i] = c;
        } else {
          final byPhone = store.customers.indexWhere(
            (e) => e.phone.isNotEmpty && e.phone == c.phone,
          );
          if (byPhone >= 0) {
            store.customers[byPhone] = c..id = store.customers[byPhone].id;
          } else {
            store.customers.add(c);
          }
        }
        bump();
        break;
      case 'deleteCustomer':
        store.customers.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'moveOrder':
        final order = store.orderById(parseStr(p['orderId']));
        final table = store.tableById(parseStr(p['tableId']));
        if (order != null && table != null) {
          final old = store.tableById(order.tableId);
          if (old != null && old.currentOrderId == order.id) {
            old.currentOrderId = null;
            old.status = TableStatus.free;
          }
          order.tableId = table.id;
          order.tableName = table.name;
          table.currentOrderId = order.id;
          table.status = order.status == OrderStatus.ready ? TableStatus.ready : TableStatus.ordered;
        }
        bump();
        break;
      case 'mergeOrders':
        final keep = store.orderById(parseStr(p['keepId']));
        final drop = store.orderById(parseStr(p['dropId']));
        if (keep != null && drop != null && keep.id != drop.id) {
          keep.lines.addAll(drop.lines);
          drop.status = OrderStatus.cancelled;
          drop.voidReason = 'merged into ${keep.ticketNo}';
          _syncTable(store, drop);
          _syncTable(store, keep);
        }
        bump();
        break;
      case 'fireCourse':
        final order = store.orderById(parseStr(p['orderId']));
        final course = parseStr(p['course']) ?? '';
        if (order != null) {
          for (final l in order.lines) {
            if (course.isEmpty || l.course == course) l.fired = true;
          }
          order.sentAt ??= DateTime.now();
          if (order.status == OrderStatus.open) order.status = OrderStatus.preparing;
          final label = order.tableName?.isNotEmpty == true
              ? 'Table ${order.tableName}'
              : 'Ticket ${order.ticketNo}';
          notice = AppNotice(
            id: newId(),
            title: 'Kitchen order',
            body: '$label sent to kitchen',
            tableId: order.tableId,
            orderId: order.id,
            kind: 'kitchen',
          );
        }
        bump();
        break;
      case 'setOrderStatus':
        final order = store.orderById(parseStr(p['id']));
        if (order != null) {
          final next =
              enumParse(OrderStatus.values, p['status'], order.status);
          final prev = order.status;
          order.status = next;
          order.updatedAt = DateTime.now();
          if (next == OrderStatus.preparing && order.sentAt == null) {
            order.sentAt = DateTime.now();
          }
          if (p['voidReason'] != null) {
            order.voidReason = parseStr(p['voidReason']) ?? '';
          }
          if (p['payment'] != null) {
            order.payment =
                enumParse(PaymentMethod.values, p['payment'], PaymentMethod.cash);
          }
          if (p['tip'] != null) {
            order.tip = parseNum(p['tip']);
          }
          if (p['driverId'] != null) {
            order.driverId = parseStr(p['driverId']);
          }
          if (next == OrderStatus.paid && !order.stockDeducted) {
            _deductStock(store, order);
            order.stockDeducted = true;
          }
          if (next == OrderStatus.cancelled && order.stockDeducted) {
            _restoreStock(store, order);
            order.stockDeducted = false;
          }
          _syncTable(store, order);
          if (next == OrderStatus.preparing && prev != OrderStatus.preparing) {
            final label = order.tableName?.isNotEmpty == true
                ? 'Table ${order.tableName}'
                : 'Ticket ${order.ticketNo}';
            notice = AppNotice(
              id: newId(),
              title: 'Kitchen order',
              body: '$label sent to kitchen',
              tableId: order.tableId,
              orderId: order.id,
              kind: 'kitchen',
            );
          }
          if (next == OrderStatus.ready && prev != OrderStatus.ready) {
            final label = order.tableName?.isNotEmpty == true
                ? 'Table ${order.tableName}'
                : 'Ticket ${order.ticketNo}';
            notice = AppNotice(
              id: newId(),
              title: 'Ready to serve',
              body: '$label order is ready to serve',
              tableId: order.tableId,
              orderId: order.id,
              kind: 'ready',
            );
          }
        }
        bump();
        break;
      case 'addLine':
        final order = store.orderById(parseStr(p['orderId']));
        if (order != null) {
          order.lines.add(OrderLine.fromJson(mapOf(p['line'])));
          order.updatedAt = DateTime.now();
          if (order.status == OrderStatus.ready || order.status == OrderStatus.served) {
            order.status = OrderStatus.preparing;
            final label = order.tableName?.isNotEmpty == true
                ? 'Table ${order.tableName}'
                : 'Ticket ${order.ticketNo}';
            notice = AppNotice(
              id: newId(),
              title: 'Kitchen order',
              body: '$label extra items sent to kitchen',
              tableId: order.tableId,
              orderId: order.id,
              kind: 'kitchen',
            );
          }
          _syncTable(store, order);
        }
        bump();
        break;
      case 'updateLine':
        final order = store.orderById(parseStr(p['orderId']));
        if (order != null) {
          final line = OrderLine.fromJson(mapOf(p['line']));
          final i = order.lines.indexWhere((e) => e.id == line.id);
          if (i >= 0) order.lines[i] = line;
          order.updatedAt = DateTime.now();
        }
        bump();
        break;
      case 'removeLine':
        final order = store.orderById(parseStr(p['orderId']));
        if (order != null) {
          order.lines.removeWhere((e) => e.id == p['lineId']);
          order.updatedAt = DateTime.now();
        }
        bump();
        break;
      case 'upsertDriver':
        final d = Driver.fromJson(mapOf(p['driver']));
        final i = store.drivers.indexWhere((e) => e.id == d.id);
        if (i >= 0) {
          store.drivers[i] = d;
        } else {
          store.drivers.add(d);
        }
        bump();
        break;
      case 'setDriverStatus':
        Driver? d = store.driverById(parseStr(p['id']));
        d ??= store.drivers.cast<Driver?>().firstWhere(
              (e) => e?.deviceId == p['deviceId'],
              orElse: () => null,
            );
        if (d != null) {
          d.status = enumParse(DriverStatus.values, p['status'], d.status);
          d.lastSeen = DateTime.now();
          if (p['deviceId'] != null) d.deviceId = parseStr(p['deviceId']);
          if (p['name'] != null && parseStr(p['name'])!.isNotEmpty) {
            d.name = parseStr(p['name'])!;
          }
        }
        bump();
        break;
      case 'pairDriver':
        final deviceId = parseStr(p['deviceId']) ?? '';
        final name = parseStr(p['name']) ?? 'Driver';
        var d = store.drivers.cast<Driver?>().firstWhere(
              (e) => e?.deviceId == deviceId,
              orElse: () => null,
            );
        d ??= store.drivers.cast<Driver?>().firstWhere(
              (e) => e?.name.toLowerCase() == name.toLowerCase() && e?.deviceId == null,
              orElse: () => null,
            );
        if (d == null) {
          d = Driver(
            id: parseStr(p['id']) ?? newId(),
            name: name,
            phone: parseStr(p['phone']) ?? '',
            status: DriverStatus.free,
            deviceId: deviceId,
            lastSeen: DateTime.now(),
          );
          store.drivers.add(d);
        } else {
          d.deviceId = deviceId;
          d.name = name;
          d.status = DriverStatus.free;
          d.lastSeen = DateTime.now();
        }
        p['pairedId'] = d.id;
        bump();
        break;
      case 'deleteDriver':
        store.drivers.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'upsertStaff':
        final s = StaffMember.fromJson(mapOf(p['staff']));
        final i = store.staff.indexWhere((e) => e.id == s.id);
        if (i >= 0) {
          store.staff[i] = s;
        } else {
          store.staff.add(s);
        }
        bump();
        break;
      case 'deleteStaff':
        store.staff.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'setStaffDuty':
        final st = store.staffById(parseStr(p['id']));
        if (st != null) {
          st.duty = enumParse(StaffDuty.values, p['duty'], st.duty);
          st.lastSeen = DateTime.now();
        }
        bump();
        break;
      case 'upsertService':
        final s = ServiceOffering.fromJson(mapOf(p['service']));
        final i = store.services.indexWhere((e) => e.id == s.id);
        if (i >= 0) {
          store.services[i] = s;
        } else {
          store.services.add(s);
        }
        bump();
        break;
      case 'deleteService':
        store.services.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      case 'upsertAppointment':
        final a = Appointment.fromJson(mapOf(p['appointment']));
        final i = store.appointments.indexWhere((e) => e.id == a.id);
        if (i >= 0) {
          store.appointments[i] = a;
        } else {
          store.appointments.add(a);
        }
        bump();
        break;
      case 'deleteAppointment':
        store.appointments.removeWhere((e) => e.id == p['id']);
        bump();
        break;
      default:
        break;
    }
    return ReduceResult(store, notice: notice);
  }

  static void _syncTable(AppStore store, PosOrder order) {
    if (order.tableId == null) return;
    final table = store.tableById(order.tableId);
    if (table == null) return;
    if (order.status == OrderStatus.paid ||
        order.status == OrderStatus.cancelled) {
      if (table.currentOrderId == order.id) {
        table.currentOrderId = null;
        table.status = TableStatus.free;
      }
      return;
    }
    table.currentOrderId = order.id;
    table.status =
        order.status == OrderStatus.ready ? TableStatus.ready : TableStatus.ordered;
  }

  static void _deductStock(AppStore store, PosOrder order) {
    for (final line in order.lines) {
      final invId = line.inventoryId ?? store.productById(line.productId)?.inventoryId;
      if (invId == null) continue;
      final item = store.stockById(invId);
      if (item == null) continue;
      final qty = (line.deductQty > 0 ? line.deductQty : 1) * line.qty;
      item.quantity -= qty;
      if (item.quantity < 0) item.quantity = 0;
    }
  }

  static void _restoreStock(AppStore store, PosOrder order) {
    for (final line in order.lines) {
      final invId = line.inventoryId ?? store.productById(line.productId)?.inventoryId;
      if (invId == null) continue;
      final item = store.stockById(invId);
      if (item == null) continue;
      final qty = (line.deductQty > 0 ? line.deductQty : 1) * line.qty;
      item.quantity += qty;
    }
  }
}
