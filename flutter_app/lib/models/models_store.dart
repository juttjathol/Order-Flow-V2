import 'package:uuid/uuid.dart';

import '../core/constants.dart';

import 'models_enums.dart';
import 'models_types_a.dart';
import 'models_types_b.dart';

class AppStore {
  AppStore({
    this.schemaVersion = 1,
    this.revision = 0,
    this.model = BusinessModel.restaurant,
    BillProfile? profile,
    List<FloorTable>? tables,
    List<MenuCategory>? categories,
    List<MenuProduct>? products,
    List<StockItem>? stock,
    List<PosOrder>? orders,
    List<Driver>? drivers,
    List<StaffMember>? staff,
    List<ServiceOffering>? services,
    List<Appointment>? appointments,
    PrinterConfig? kitchenPrinter,
    PrinterConfig? receiptPrinter,
    List<PrinterConfig>? printers,
    Map<String, String>? rolePrinters,
    this.ticketSeq = 1000,
    this.seeded = false,
    this.lastDayClose,
    this.shiftCashier = '',
    DateTime? shiftStartedAt,
    this.shiftFloat = 0,
    this.shiftEndCash = 0,
    List<ShopCustomer>? customers,
    this.drawerAuto = false,
    Entitlements? entitlements,
    this.qrOrderOn = false,
    List<WastageEntry>? waste,
    List<Supplier>? suppliers,
    List<PurchaseOrder>? purchases,
    this.poSeq = 500,
  })  : profile = profile ?? BillProfile(),
        entitlements = entitlements ?? Entitlements(),
        tables = tables ?? <FloorTable>[],
        categories = categories ?? <MenuCategory>[],
        products = products ?? <MenuProduct>[],
        stock = stock ?? <StockItem>[],
        orders = orders ?? <PosOrder>[],
        drivers = drivers ?? <Driver>[],
        staff = staff ?? <StaffMember>[],
        services = services ?? <ServiceOffering>[],
        appointments = appointments ?? <Appointment>[],
        kitchenPrinter = kitchenPrinter ?? PrinterConfig(),
        receiptPrinter = receiptPrinter ?? PrinterConfig(),
        printers = printers ?? <PrinterConfig>[],
        rolePrinters = rolePrinters ?? <String, String>{},
        shiftStartedAt = shiftStartedAt,
        customers = customers ?? <ShopCustomer>[],
        waste = waste ?? <WastageEntry>[],
        suppliers = suppliers ?? <Supplier>[],
        purchases = purchases ?? <PurchaseOrder>[];

  int schemaVersion;
  int revision;
  BusinessModel model;
  BillProfile profile;
  List<FloorTable> tables;
  List<MenuCategory> categories;
  List<MenuProduct> products;
  List<StockItem> stock;
  List<PosOrder> orders;
  List<Driver> drivers;
  List<StaffMember> staff;
  List<ServiceOffering> services;
  List<Appointment> appointments;
  PrinterConfig kitchenPrinter;
  PrinterConfig receiptPrinter;
  List<PrinterConfig> printers;
  Map<String, String> rolePrinters;
  int ticketSeq;
  bool seeded;
  DateTime? lastDayClose;
  String shiftCashier;
  DateTime? shiftStartedAt;
  double shiftFloat;
  double shiftEndCash;
  List<ShopCustomer> customers;
  bool drawerAuto;
  /// Plan limits pushed from the license server (v1.1.59).
  Entitlements entitlements;
  /// Master switch for the QR self-order web page (needs the qr_ordering feature).
  bool qrOrderOn;
  List<WastageEntry> waste;
  List<Supplier> suppliers;
  List<PurchaseOrder> purchases;
  int poSeq;

  String get currency => profile.currencySymbol;

  bool canFeature(String key) => entitlements.allowsFeature(key);

  String nextPoNo() {
    poSeq += 1;
    return 'PO-$poSeq';
  }

  Supplier? supplierById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final s in suppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  PurchaseOrder? purchaseById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in purchases) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Estimated ingredient cost of one sale of [product] (recipe lines first,
  /// then the linked stock item's own deduction cost).
  double productCost(MenuProduct product) {
    double total = 0;
    if (product.recipe.isNotEmpty) {
      for (final r in product.recipe) {
        final item = stockById(r.stockId);
        if (item != null) total += item.cost * r.quantity;
      }
      return total;
    }
    final inv = product.inventoryId == null ? null : stockById(product.inventoryId);
    if (inv != null) total += inv.cost * (product.deductQty > 0 ? product.deductQty : 1);
    return total;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'revision': revision,
        'model': model.name,
        'profile': profile.toJson(),
        'tables': tables.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'products': products.map((e) => e.toJson()).toList(),
        'stock': stock.map((e) => e.toJson()).toList(),
        'orders': orders.map((e) => e.toJson()).toList(),
        'drivers': drivers.map((e) => e.toJson()).toList(),
        'staff': staff.map((e) => e.toJson()).toList(),
        'services': services.map((e) => e.toJson()).toList(),
        'appointments': appointments.map((e) => e.toJson()).toList(),
        'kitchenPrinter': kitchenPrinter.toJson(),
        'receiptPrinter': receiptPrinter.toJson(),
        'printers': printers.map((e) => e.toJson()).toList(),
        'rolePrinters': rolePrinters,
        'ticketSeq': ticketSeq,
        'seeded': seeded,
        'lastDayClose': lastDayClose?.toIso8601String(),
        'shiftCashier': shiftCashier,
        'shiftStartedAt': shiftStartedAt?.toIso8601String(),
        'shiftFloat': shiftFloat,
        'shiftEndCash': shiftEndCash,
        'customers': customers.map((e) => e.toJson()).toList(),
        'drawerAuto': drawerAuto,
        'entitlements': entitlements.toJson(),
        'qrOrderOn': qrOrderOn,
        'waste': waste.map((e) => e.toJson()).toList(),
        'suppliers': suppliers.map((e) => e.toJson()).toList(),
        'purchases': purchases.map((e) => e.toJson()).toList(),
        'poSeq': poSeq,
      };

  factory AppStore.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    List<T> list<T>(String key, T Function(Map<String, dynamic>) map) =>
        ((m[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => map(Map<String, dynamic>.from(e)))
            .toList();
    return AppStore(
      schemaVersion: parseInt(m['schemaVersion'], 1),
      revision: parseInt(m['revision']),
      model: enumParse(BusinessModel.values, m['model'], BusinessModel.restaurant),
      profile: BillProfile.fromJson(
        m['profile'] is Map ? Map<String, dynamic>.from(m['profile'] as Map) : null,
      ),
      tables: list('tables', FloorTable.fromJson),
      categories: list('categories', MenuCategory.fromJson),
      products: list('products', MenuProduct.fromJson),
      stock: list('stock', StockItem.fromJson),
      orders: list('orders', PosOrder.fromJson),
      drivers: list('drivers', Driver.fromJson),
      staff: list('staff', StaffMember.fromJson),
      services: list('services', ServiceOffering.fromJson),
      appointments: list('appointments', Appointment.fromJson),
      kitchenPrinter: PrinterConfig.fromJson(
        m['kitchenPrinter'] is Map
            ? Map<String, dynamic>.from(m['kitchenPrinter'] as Map)
            : null,
      ),
      receiptPrinter: PrinterConfig.fromJson(
        m['receiptPrinter'] is Map
            ? Map<String, dynamic>.from(m['receiptPrinter'] as Map)
            : null,
      ),
      printers: list('printers', PrinterConfig.fromJson),
      rolePrinters: () {
        final raw = m['rolePrinters'];
        if (raw is! Map) return <String, String>{};
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }(),
      ticketSeq: parseInt(m['ticketSeq'], 1000),
      seeded: parseBool(m['seeded']),
      lastDayClose: m['lastDayClose'] == null ? null : parseTime(m['lastDayClose']),
      shiftCashier: parseStr(m['shiftCashier']) ?? '',
      shiftStartedAt: m['shiftStartedAt'] == null ? null : parseTime(m['shiftStartedAt']),
      shiftFloat: parseNum(m['shiftFloat']),
      shiftEndCash: parseNum(m['shiftEndCash']),
      customers: list('customers', ShopCustomer.fromJson),
      drawerAuto: parseBool(m['drawerAuto']),
      entitlements: Entitlements.fromJson(
        m['entitlements'] is Map
            ? Map<String, dynamic>.from(m['entitlements'] as Map)
            : null,
      ),
      qrOrderOn: parseBool(m['qrOrderOn']),
      waste: list('waste', WastageEntry.fromJson),
      suppliers: list('suppliers', Supplier.fromJson),
      purchases: list('purchases', PurchaseOrder.fromJson),
      poSeq: parseInt(m['poSeq'], 500),
    );
  }

  void ensurePrinters() {
    if (printers.isNotEmpty) return;
    if (kitchenPrinter.enabled ||
        kitchenPrinter.host.isNotEmpty ||
        kitchenPrinter.btAddress.isNotEmpty) {
      kitchenPrinter.id = kitchenPrinter.id.isEmpty ? newId() : kitchenPrinter.id;
      if (kitchenPrinter.name.isEmpty) kitchenPrinter.name = 'Kitchen';
      printers.add(kitchenPrinter.copy());
      rolePrinters.putIfAbsent(AppRole.kitchen.name, () => printers.last.id);
    }
    if (receiptPrinter.enabled ||
        receiptPrinter.host.isNotEmpty ||
        receiptPrinter.btAddress.isNotEmpty) {
      receiptPrinter.id = receiptPrinter.id.isEmpty ? newId() : receiptPrinter.id;
      if (receiptPrinter.name.isEmpty) receiptPrinter.name = 'Receipt';
      printers.add(receiptPrinter.copy());
      rolePrinters.putIfAbsent(AppRole.cashier.name, () => printers.last.id);
      rolePrinters.putIfAbsent(AppRole.main.name, () => printers.last.id);
    }
  }

  PrinterConfig? printerById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in printers) {
      if (p.id == id) return p;
    }
    return null;
  }

  PrinterConfig? printerForRole(AppRole? role) {
    if (role == null || role == AppRole.none) return null;
    return printerById(rolePrinters[role.name]);
  }

  PrinterConfig kitchenTarget() {
    ensurePrinters();
    return printerForRole(AppRole.kitchen) ?? kitchenPrinter;
  }

  PrinterConfig receiptTarget([AppRole? role]) {
    ensurePrinters();
    return printerForRole(role) ??
        printerForRole(AppRole.cashier) ??
        printerForRole(AppRole.main) ??
        receiptPrinter;
  }

  String nextTicket() {
    ticketSeq += 1;
    return '#$ticketSeq';
  }

  FloorTable? tableById(String? id) {
    if (id == null) return null;
    for (final t in tables) {
      if (t.id == id) return t;
    }
    return null;
  }

  PosOrder? orderById(String? id) {
    if (id == null) return null;
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  StockItem? stockById(String? id) {
    if (id == null) return null;
    for (final s in stock) {
      if (s.id == id) return s;
    }
    return null;
  }

  MenuProduct? productById(String? id) {
    if (id == null) return null;
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  StaffMember? staffById(String? id) {
    if (id == null) return null;
    for (final s in staff) {
      if (s.id == id) return s;
    }
    return null;
  }

  Driver? driverById(String? id) {
    if (id == null) return null;
    for (final d in drivers) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<PosOrder> get openOrders => orders
      .where((o) =>
          o.status != OrderStatus.paid && o.status != OrderStatus.cancelled)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<StockItem> get lowStock =>
      stock.where((s) => s.level != StockLevel.ok).toList();

  double salesOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return orders
        .where((o) =>
            o.status == OrderStatus.paid &&
            !o.updatedAt.isBefore(start) &&
            o.updatedAt.isBefore(end))
        .fold<double>(0, (s, o) => s + o.total);
  }
}
