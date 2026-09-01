import 'package:uuid/uuid.dart';

import '../core/constants.dart';

import 'models_enums.dart';

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
    this.pin = '',
    this.duty = StaffDuty.offline,
    this.active = true,
    this.lastSeen,
  });

  String id;
  String name;
  String roleLabel;
  String pin;
  StaffDuty duty;
  bool active;
  DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'roleLabel': roleLabel,
        'pin': pin,
        'duty': duty.name,
        'active': active,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        roleLabel: parseStr(j['roleLabel']) ?? '',
        pin: parseStr(j['pin']) ?? '',
        duty: enumParse(StaffDuty.values, j['duty'], StaffDuty.offline),
        active: parseBool(j['active'], true),
        lastSeen: j['lastSeen'] == null ? null : parseTime(j['lastSeen']),
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

class ShopCustomer {
  ShopCustomer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.points = 0,
    this.credit = 0,
  });

  String id;
  String name;
  String phone;
  String address;
  String notes;
  double points;
  double credit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
        'points': points,
        'credit': credit,
      };

  factory ShopCustomer.fromJson(Map<String, dynamic> j) => ShopCustomer(
        id: parseStr(j['id']) ?? newId(),
        name: parseStr(j['name']) ?? '',
        phone: parseStr(j['phone']) ?? '',
        address: parseStr(j['address']) ?? '',
        notes: parseStr(j['notes']) ?? '',
        points: parseNum(j['points']),
        credit: parseNum(j['credit']),
      );
}

class PrinterConfig {
  PrinterConfig({
    String? id,
    this.name = '',
    this.host = '',
    this.port = kEscPosPort,
    this.enabled = false,
    this.transport = 'lan',
    this.btAddress = '',
    this.btName = '',
  }) : id = id ?? newId();

  String id;
  String name;
  String host;
  int port;
  bool enabled;
  /// lan | bluetooth
  String transport;
  String btAddress;
  String btName;

  bool get isBluetooth => transport == 'bluetooth';

  String get label {
    if (name.trim().isNotEmpty) return name.trim();
    if (isBluetooth && btName.trim().isNotEmpty) return btName.trim();
    if (isBluetooth && btAddress.trim().isNotEmpty) return btAddress.trim();
    if (host.trim().isNotEmpty) return host.trim();
    return 'Printer';
  }

  PrinterConfig copy() => PrinterConfig(
        id: id,
        name: name,
        host: host,
        port: port,
        enabled: enabled,
        transport: transport,
        btAddress: btAddress,
        btName: btName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
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
      id: parseStr(m['id']),
      name: parseStr(m['name']) ?? '',
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
    this.kind = 'ready',
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String title;
  final String body;
  final String? tableId;
  final String? orderId;
  /// ready | kitchen
  final String kind;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'tableId': tableId,
        'orderId': orderId,
        'kind': kind,
        'at': at.toIso8601String(),
      };

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        id: parseStr(j['id']) ?? newId(),
        title: parseStr(j['title']) ?? '',
        body: parseStr(j['body']) ?? '',
        tableId: parseStr(j['tableId']),
        orderId: parseStr(j['orderId']),
        kind: parseStr(j['kind']) ?? 'ready',
        at: parseTime(j['at']),
      );
}
