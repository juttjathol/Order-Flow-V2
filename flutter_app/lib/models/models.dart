import 'package:uuid/uuid.dart';

import '../core/constants.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

enum BusinessModel { restaurant, retail, fastfood, services }

enum AppRole {
  none,
  main,
  orderTaker,
  kitchen,
  cashier,
  driver,
  stockClerk,
  frontDesk,
  specialist,
}

enum TableStatus { free, ordered, ready }

enum OrderType { dineIn, takeaway, delivery, retail, service }

enum OrderStatus { open, preparing, ready, served, paid, cancelled }

enum PaymentMethod { cash, card, wallet, other, complimentary }

enum DriverStatus { free, busy, offline }

enum ThemeChoice { system, light, dark }

enum LicenseGate { boot, license, locked, setup, ready }

enum StockLevel { ok, low, out }

T enumParse<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw == null) return fallback;
  final name = raw.toString();
  for (final v in values) {
    if (v.name == name || v.toString() == name) return v;
  }
  return fallback;
}

DateTime parseTime(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw) ?? DateTime.now();
  }
  return DateTime.now();
}

String? parseStr(Object? raw) => raw?.toString();

double parseNum(Object? raw, [double fallback = 0]) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

int parseInt(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

bool parseBool(Object? raw, [bool fallback = false]) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final v = raw.toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return fallback;
}

class BillProfile {
  BillProfile({
    this.businessName = 'My Shop',
    this.address = '',
    this.phone = '',
    this.taxId = '',
    this.footer = 'Thank you for your visit',
    this.currencySymbol = kDefaultCurrency,
    this.currencyPrefix = true,
    this.taxRate = 0,
    this.serviceRate = 0,
    this.logoBase64,
    this.managerPin = '',
  });

  String businessName;
  String address;
  String phone;
  String taxId;
  String footer;
  String currencySymbol;
  bool currencyPrefix;
  double taxRate;
  double serviceRate;
  String? logoBase64;
  String managerPin;

  BillProfile copy() => BillProfile(
        businessName: businessName,
        address: address,
        phone: phone,
        taxId: taxId,
        footer: footer,
        currencySymbol: currencySymbol,
        currencyPrefix: currencyPrefix,
        taxRate: taxRate,
        serviceRate: serviceRate,
        logoBase64: logoBase64,
        managerPin: managerPin,
      );

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'address': address,
        'phone': phone,
        'taxId': taxId,
        'footer': footer,
        'currencySymbol': currencySymbol,
        'currencyPrefix': currencyPrefix,
        'taxRate': taxRate,
        'serviceRate': serviceRate,
        'logoBase64': logoBase64,
        'managerPin': managerPin,
      };

  factory BillProfile.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return BillProfile(
      businessName: parseStr(m['businessName']) ?? 'My Shop',
      address: parseStr(m['address']) ?? '',
      phone: parseStr(m['phone']) ?? '',
      taxId: parseStr(m['taxId']) ?? '',
      footer: parseStr(m['footer']) ?? 'Thank you for your visit',
      currencySymbol: parseStr(m['currencySymbol']) ?? kDefaultCurrency,
      currencyPrefix: parseBool(m['currencyPrefix'], true),
      taxRate: parseNum(m['taxRate']),
      serviceRate: parseNum(m['serviceRate']),
      logoBase64: parseStr(m['logoBase64']),
      managerPin: parseStr(m['managerPin']) ?? '',
    );
  }
}

class FloorTable {
  FloorTable({
    required this.id,
    required this.name,
    this.seats = 4,
    this.status = TableStatus.free,
    this.currentOrderId,
  });

  String id;
  String name;
  int seats;
  TableStatus status;
  String? currentOrderId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'seats': seats,
        'status': status.name,
        'currentOrderId': currentOrderId,
      };

  factory FloorTable.fromJson(Map<String, dynamic> j) => FloorTable(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? 'T',
        seats: parseInt(j['seats'], 4),
        status: enumParse(TableStatus.values, j['status'], TableStatus.free),
        currentOrderId: parseStr(j['currentOrderId']),
      );
}

class MenuCategory {
  MenuCategory({
    required this.id,
    required this.name,
    this.nameUr = '',
    this.sort = 0,
  });

  String id;
  String name;
  String nameUr;
  int sort;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameUr': nameUr,
        'sort': sort,
      };

  factory MenuCategory.fromJson(Map<String, dynamic> j) => MenuCategory(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        nameUr: parseStr(j['nameUr']) ?? '',
        sort: parseInt(j['sort']),
      );
}

class ItemMod {
  ItemMod({
    required this.id,
    required this.name,
    this.group = 'extra',
    this.price = 0,
  });

  String id;
  String name;
  /// size | spice | extra — size/spice pick one, extra can stack.
  String group;
  double price;

  bool get exclusive => group == 'size' || group == 'spice';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'group': group,
        'price': price,
      };

  factory ItemMod.fromJson(Map<String, dynamic> j) => ItemMod(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        group: parseStr(j['group']) ?? 'extra',
        price: parseNum(j['price']),
      );
}

class MenuProduct {
  MenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    this.nameUr = '',
    this.description = '',
    this.price = 0,
    this.imageBase64,
    this.available = true,
    this.sku = '',
    this.inventoryId,
    this.deductQty = 1,
    this.course = 'main',
    List<ItemMod>? mods,
  }) : mods = mods ?? <ItemMod>[];

  String id;
  String categoryId;
  String name;
  String nameUr;
  String description;
  double price;
  String? imageBase64;
  bool available;
  String sku;
  String? inventoryId;
  double deductQty;
  String course;
  List<ItemMod> mods;

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'name': name,
        'nameUr': nameUr,
        'description': description,
        'price': price,
        'imageBase64': imageBase64,
        'available': available,
        'sku': sku,
        'inventoryId': inventoryId,
        'deductQty': deductQty,
        'course': course,
        'mods': mods.map((e) => e.toJson()).toList(),
      };

  factory MenuProduct.fromJson(Map<String, dynamic> j) => MenuProduct(
        id: parseStr(j['id']) ?? newId(),
        categoryId: parseStr(j['categoryId']) ?? '',
        name: parseStr(j['name']) ?? '',
        nameUr: parseStr(j['nameUr']) ?? '',
        description: parseStr(j['description']) ?? '',
        price: parseNum(j['price']),
        imageBase64: parseStr(j['imageBase64']),
        available: parseBool(j['available'], true),
        sku: parseStr(j['sku']) ?? '',
        inventoryId: parseStr(j['inventoryId']),
        deductQty: parseNum(j['deductQty'], 1),
        course: parseStr(j['course']) ?? 'main',
        mods: ((j['mods'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ItemMod.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class StockItem {
  StockItem({
    required this.id,
    required this.name,
    this.sku = '',
    this.quantity = 0,
    this.lowStockAt = 5,
    this.unit = 'pcs',
    this.cost = 0,
    this.sellPrice,
  });

  String id;
  String name;
  String sku;
  double quantity;
  double lowStockAt;
  String unit;
  double cost;
  double? sellPrice;

  StockLevel get level {
    if (quantity <= 0) return StockLevel.out;
    if (quantity <= lowStockAt) return StockLevel.low;
    return StockLevel.ok;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'quantity': quantity,
        'lowStockAt': lowStockAt,
        'unit': unit,
        'cost': cost,
        'sellPrice': sellPrice,
      };

  factory StockItem.fromJson(Map<String, dynamic> j) => StockItem(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        sku: parseStr(j['sku']) ?? '',
        quantity: parseNum(j['quantity']),
        lowStockAt: parseNum(j['lowStockAt'], 5),
        unit: parseStr(j['unit']) ?? 'pcs',
        cost: parseNum(j['cost']),
        sellPrice: j['sellPrice'] == null ? null : parseNum(j['sellPrice']),
      );
}

class OrderLine {
  OrderLine({
    required this.id,
    required this.productId,
    required this.name,
    required this.unitPrice,
    this.qty = 1,
    this.notes = '',
    this.inventoryId,
    this.deductQty = 0,
    this.course = 'main',
    this.fired = false,
  });

  String id;
  String productId;
  String name;
  double unitPrice;
  double qty;
  String notes;
  String? inventoryId;
  double deductQty;
  String course;
  bool fired;

  double get lineTotal => unitPrice * qty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'name': name,
        'unitPrice': unitPrice,
        'qty': qty,
        'notes': notes,
        'inventoryId': inventoryId,
        'deductQty': deductQty,
        'course': course,
        'fired': fired,
      };

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        id: parseStr(j['id']) ?? newId(),
        productId: parseStr(j['productId']) ?? '',
        name: parseStr(j['name']) ?? '',
        unitPrice: parseNum(j['unitPrice']),
        qty: parseNum(j['qty'], 1),
        notes: parseStr(j['notes']) ?? '',
        inventoryId: parseStr(j['inventoryId']),
        deductQty: parseNum(j['deductQty']),
        course: parseStr(j['course']) ?? 'main',
        fired: parseBool(j['fired']),
      );
}

class PosOrder {
  PosOrder({
    required this.id,
    required this.ticketNo,
    required this.type,
    this.status = OrderStatus.open,
    this.tableId,
    this.tableName,
    this.customerName = '',
    this.customerPhone = '',
    this.address = '',
    this.driverId,
    List<OrderLine>? lines,
    this.discount = 0,
    this.taxRate = 0,
    this.serviceRate = 0,
    this.tip = 0,
    this.payment,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.createdBy = '',
    this.stockDeducted = false,
    this.held = false,
    this.voidReason = '',
    this.sentAt,
  })  : lines = lines ?? <OrderLine>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String id;
  String ticketNo;
  OrderType type;
  OrderStatus status;
  String? tableId;
  String? tableName;
  String customerName;
  String customerPhone;
  String address;
  String? driverId;
  List<OrderLine> lines;
  double discount;
  double taxRate;
  double serviceRate;
  double tip;
  PaymentMethod? payment;
  String notes;
  DateTime createdAt;
  DateTime updatedAt;
  String createdBy;
  bool stockDeducted;
  bool held;
  String voidReason;
  DateTime? sentAt;

  double get subtotal =>
      lines.fold<double>(0, (s, l) => s + l.lineTotal) - discount;
  double get service => (subtotal * (serviceRate / 100.0)).clamp(0, double.infinity);
  double get tax => subtotal * (taxRate / 100.0);
  double get total => (subtotal + service + tax + tip).clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticketNo': ticketNo,
        'type': type.name,
        'status': status.name,
        'tableId': tableId,
        'tableName': tableName,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'address': address,
        'driverId': driverId,
        'lines': lines.map((e) => e.toJson()).toList(),
        'discount': discount,
        'taxRate': taxRate,
        'serviceRate': serviceRate,
        'tip': tip,
        'payment': payment?.name,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'createdBy': createdBy,
        'stockDeducted': stockDeducted,
        'held': held,
        'voidReason': voidReason,
        'sentAt': sentAt?.toIso8601String(),
      };

  factory PosOrder.fromJson(Map<String, dynamic> j) => PosOrder(
        id: parseStr(j['id']) ?? newId(),
        ticketNo: parseStr(j['ticketNo']) ?? '',
        type: enumParse(OrderType.values, j['type'], OrderType.dineIn),
        status: enumParse(OrderStatus.values, j['status'], OrderStatus.open),
        tableId: parseStr(j['tableId']),
        tableName: parseStr(j['tableName']),
        customerName: parseStr(j['customerName']) ?? '',
        customerPhone: parseStr(j['customerPhone']) ?? '',
        address: parseStr(j['address']) ?? '',
        driverId: parseStr(j['driverId']),
        lines: ((j['lines'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => OrderLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        discount: parseNum(j['discount']),
        taxRate: parseNum(j['taxRate']),
        serviceRate: parseNum(j['serviceRate']),
        tip: parseNum(j['tip']),
        payment: j['payment'] == null
            ? null
            : enumParse(PaymentMethod.values, j['payment'], PaymentMethod.cash),
        notes: parseStr(j['notes']) ?? '',
        createdAt: parseTime(j['createdAt']),
        updatedAt: parseTime(j['updatedAt']),
        createdBy: parseStr(j['createdBy']) ?? '',
        stockDeducted: parseBool(j['stockDeducted']),
        held: parseBool(j['held']),
        voidReason: parseStr(j['voidReason']) ?? '',
        sentAt: j['sentAt'] == null ? null : parseTime(j['sentAt']),
      );
}

class Driver {
  Driver({
    required this.id,
    required this.name,
    this.phone = '',
    this.status = DriverStatus.offline,
    this.deviceId,
    this.lastSeen,
  });

  String id;
  String name;
  String phone;
  DriverStatus status;
  String? deviceId;
  DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'status': status.name,
        'deviceId': deviceId,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        phone: parseStr(j['phone']) ?? '',
        status: enumParse(DriverStatus.values, j['status'], DriverStatus.offline),
        deviceId: parseStr(j['deviceId']),
        lastSeen: j['lastSeen'] == null ? null : parseTime(j['lastSeen']),
      );
}

class StaffMember {
  StaffMember({
    required this.id,
    required this.name,
    this.roleLabel = '',
    this.active = true,
  });

  String id;
  String name;
  String roleLabel;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'roleLabel': roleLabel,
        'active': active,
      };

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        roleLabel: parseStr(j['roleLabel']) ?? '',
        active: parseBool(j['active'], true),
      );
}

class ServiceOffering {
  ServiceOffering({
    required this.id,
    required this.name,
    this.price = 0,
    this.durationMin = 30,
  });

  String id;
  String name;
  double price;
  int durationMin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'durationMin': durationMin,
      };

  factory ServiceOffering.fromJson(Map<String, dynamic> j) => ServiceOffering(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        price: parseNum(j['price']),
        durationMin: parseInt(j['durationMin'], 30),
      );
}

class Appointment {
  Appointment({
    required this.id,
    required this.serviceId,
    required this.staffId,
    required this.customerName,
    this.customerPhone = '',
    DateTime? start,
    this.status = 'booked',
    this.notes = '',
  }) : start = start ?? DateTime.now();

  String id;
  String serviceId;
  String staffId;
  String customerName;
  String customerPhone;
  DateTime start;
  String status;
  String notes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'serviceId': serviceId,
        'staffId': staffId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'start': start.toIso8601String(),
        'status': status,
        'notes': notes,
      };

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: parseStr(j['id']) ?? newId(),
        serviceId: parseStr(j['serviceId']) ?? '',
        staffId: parseStr(j['staffId']) ?? '',
        customerName: parseStr(j['customerName']) ?? '',
        customerPhone: parseStr(j['customerPhone']) ?? '',
        start: parseTime(j['start']),
        status: parseStr(j['status']) ?? 'booked',
        notes: parseStr(j['notes']) ?? '',
      );
}

class PrinterConfig {
  PrinterConfig({
    this.host = '',
    this.port = kEscPosPort,
    this.enabled = false,
    this.transport = 'lan',
    this.btAddress = '',
    this.btName = '',
  });

  String host;
  int port;
  bool enabled;
  /// lan | bluetooth
  String transport;
  String btAddress;
  String btName;

  bool get isBluetooth => transport == 'bluetooth';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'enabled': enabled,
        'transport': transport,
        'btAddress': btAddress,
        'btName': btName,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return PrinterConfig(
      host: parseStr(m['host']) ?? '',
      port: parseInt(m['port'], kEscPosPort),
      enabled: parseBool(m['enabled']),
      transport: parseStr(m['transport']) ?? 'lan',
      btAddress: parseStr(m['btAddress']) ?? '',
      btName: parseStr(m['btName']) ?? '',
    );
  }
}

class AppNotice {
  AppNotice({
    required this.id,
    required this.title,
    required this.body,
    this.tableId,
    this.orderId,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String title;
  final String body;
  final String? tableId;
  final String? orderId;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'tableId': tableId,
        'orderId': orderId,
        'at': at.toIso8601String(),
      };

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        id: parseStr(j['id']) ?? newId(),
        title: parseStr(j['title']) ?? '',
        body: parseStr(j['body']) ?? '',
        tableId: parseStr(j['tableId']),
        orderId: parseStr(j['orderId']),
        at: parseTime(j['at']),
      );
}

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
    this.ticketSeq = 1000,
    this.seeded = false,
    this.lastDayClose,
    this.shiftCashier = '',
    DateTime? shiftStartedAt,
  })  : profile = profile ?? BillProfile(),
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
        shiftStartedAt = shiftStartedAt;

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
  int ticketSeq;
  bool seeded;
  DateTime? lastDayClose;
  String shiftCashier;
  DateTime? shiftStartedAt;

  String get currency => profile.currencySymbol;

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
        'ticketSeq': ticketSeq,
        'seeded': seeded,
        'lastDayClose': lastDayClose?.toIso8601String(),
        'shiftCashier': shiftCashier,
        'shiftStartedAt': shiftStartedAt?.toIso8601String(),
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
      ticketSeq: parseInt(m['ticketSeq'], 1000),
      seeded: parseBool(m['seeded']),
      lastDayClose: m['lastDayClose'] == null ? null : parseTime(m['lastDayClose']),
      shiftCashier: parseStr(m['shiftCashier']) ?? '',
      shiftStartedAt: m['shiftStartedAt'] == null ? null : parseTime(m['shiftStartedAt']),
    );
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

class NetCommand {
  NetCommand({
    required this.name,
    Map<String, dynamic>? payload,
    this.actor = '',
    this.role = '',
    String? id,
    DateTime? at,
  })  : payload = payload ?? <String, dynamic>{},
        id = id ?? newId(),
        at = at ?? DateTime.now();

  final String id;
  final String name;
  final Map<String, dynamic> payload;
  final String actor;
  final String role;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'payload': payload,
        'actor': actor,
        'role': role,
        'at': at.toIso8601String(),
      };

  factory NetCommand.fromJson(Map<String, dynamic> j) => NetCommand(
        id: parseStr(j['id']),
        name: parseStr(j['name']) ?? '',
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : <String, dynamic>{},
        actor: parseStr(j['actor']) ?? '',
        role: parseStr(j['role']) ?? '',
        at: parseTime(j['at']),
      );
}

class LicenseRecord {
  LicenseRecord({
    this.key = '',
    this.valid = false,
    this.locked = false,
    this.lockReason = '',
    this.customerName = '',
    this.businessName = '',
    this.expiresAt,
    this.lastValidatedAt,
    this.message = '',
  });

  String key;
  bool valid;
  bool locked;
  String lockReason;
  String customerName;
  String businessName;
  DateTime? expiresAt;
  DateTime? lastValidatedAt;
  String message;

  bool get inGrace {
    if (locked || !valid || lastValidatedAt == null) return false;
    final limit = lastValidatedAt!.add(const Duration(hours: kOfflineGraceHours));
    return DateTime.now().isBefore(limit);
  }

  Duration? get graceLeft {
    if (lastValidatedAt == null) return null;
    final limit = lastValidatedAt!.add(const Duration(hours: kOfflineGraceHours));
    final d = limit.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'valid': valid,
        'locked': locked,
        'lockReason': lockReason,
        'customerName': customerName,
        'businessName': businessName,
        'expiresAt': expiresAt?.toIso8601String(),
        'lastValidatedAt': lastValidatedAt?.toIso8601String(),
        'message': message,
      };

  factory LicenseRecord.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return LicenseRecord(
      key: parseStr(m['key']) ?? '',
      valid: parseBool(m['valid']),
      locked: parseBool(m['locked']),
      lockReason: parseStr(m['lockReason']) ?? '',
      customerName: parseStr(m['customerName']) ?? '',
      businessName: parseStr(m['businessName']) ?? '',
      expiresAt: m['expiresAt'] == null ? null : parseTime(m['expiresAt']),
      lastValidatedAt:
          m['lastValidatedAt'] == null ? null : parseTime(m['lastValidatedAt']),
      message: parseStr(m['message']) ?? '',
    );
  }
}

class SessionPrefs {
  SessionPrefs({
    this.deviceId = '',
    this.role = AppRole.none,
    this.displayName = '',
    this.locale = 'en',
    this.theme = ThemeChoice.system,
    this.apiBase = kDefaultApiBase,
    this.mainHost = '',
    this.pairedDriverId,
    this.modelPicked = false,
    this.lastReceiptOrderId,
    LicenseRecord? license,
  }) : license = license ?? LicenseRecord();

  String deviceId;
  AppRole role;
  String displayName;
  String locale;
  ThemeChoice theme;
  String apiBase;
  String mainHost;
  String? pairedDriverId;
  bool modelPicked;
  String? lastReceiptOrderId;
  LicenseRecord license;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'role': role.name,
        'displayName': displayName,
        'locale': locale,
        'theme': theme.name,
        'apiBase': apiBase,
        'mainHost': mainHost,
        'pairedDriverId': pairedDriverId,
        'modelPicked': modelPicked,
        'lastReceiptOrderId': lastReceiptOrderId,
        'license': license.toJson(),
      };

  factory SessionPrefs.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return SessionPrefs(
      deviceId: parseStr(m['deviceId']) ?? '',
      role: enumParse(AppRole.values, m['role'], AppRole.none),
      displayName: parseStr(m['displayName']) ?? '',
      locale: parseStr(m['locale']) ?? 'en',
      theme: enumParse(ThemeChoice.values, m['theme'], ThemeChoice.system),
      apiBase: parseStr(m['apiBase']) ?? kDefaultApiBase,
      mainHost: parseStr(m['mainHost']) ?? '',
      pairedDriverId: parseStr(m['pairedDriverId']),
      modelPicked: parseBool(m['modelPicked']),
      lastReceiptOrderId: parseStr(m['lastReceiptOrderId']),
      license: LicenseRecord.fromJson(
        m['license'] is Map ? Map<String, dynamic>.from(m['license'] as Map) : null,
      ),
    );
  }
}

class ClientInfo {
  ClientInfo({
    required this.deviceId,
    required this.name,
    required this.role,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String deviceId;
  final String name;
  final String role;
  DateTime lastSeen;
}
