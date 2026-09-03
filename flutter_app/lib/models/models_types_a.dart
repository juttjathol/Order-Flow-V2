import 'package:uuid/uuid.dart';

import '../core/constants.dart';

import 'models_enums.dart';

class SlipTemplate {
  SlipTemplate({
    this.heading = 'CASH RECEIPT',
    this.showLogo = true,
    this.showAddress = true,
    this.showPhone = true,
    this.showPrices = true,
    this.showTotals = true,
    this.showPayment = true,
    this.showQr = true,
    this.showCustomer = true,
  });

  String heading;
  bool showLogo;
  bool showAddress;
  bool showPhone;
  bool showPrices;
  bool showTotals;
  bool showPayment;
  bool showQr;
  bool showCustomer;

  SlipTemplate copy() => SlipTemplate(
        heading: heading,
        showLogo: showLogo,
        showAddress: showAddress,
        showPhone: showPhone,
        showPrices: showPrices,
        showTotals: showTotals,
        showPayment: showPayment,
        showQr: showQr,
        showCustomer: showCustomer,
      );

  Map<String, dynamic> toJson() => {
        'heading': heading,
        'showLogo': showLogo,
        'showAddress': showAddress,
        'showPhone': showPhone,
        'showPrices': showPrices,
        'showTotals': showTotals,
        'showPayment': showPayment,
        'showQr': showQr,
        'showCustomer': showCustomer,
      };

  factory SlipTemplate.fromJson(Map<String, dynamic>? j, SlipTemplate fallback) {
    final m = j ?? const {};
    return SlipTemplate(
      heading: parseStr(m['heading']) ?? fallback.heading,
      showLogo: parseBool(m['showLogo'], fallback.showLogo),
      showAddress: parseBool(m['showAddress'], fallback.showAddress),
      showPhone: parseBool(m['showPhone'], fallback.showPhone),
      showPrices: parseBool(m['showPrices'], fallback.showPrices),
      showTotals: parseBool(m['showTotals'], fallback.showTotals),
      showPayment: parseBool(m['showPayment'], fallback.showPayment),
      showQr: parseBool(m['showQr'], fallback.showQr),
      showCustomer: parseBool(m['showCustomer'], fallback.showCustomer),
    );
  }

  static SlipTemplate kitchen() => SlipTemplate(
        heading: 'KITCHEN TICKET',
        showLogo: false,
        showAddress: false,
        showPhone: false,
        showPrices: false,
        showTotals: false,
        showPayment: false,
        showQr: false,
        showCustomer: true,
      );

  static SlipTemplate counter() => SlipTemplate(heading: 'CASH RECEIPT');

  static SlipTemplate takeaway() => SlipTemplate(heading: 'TAKEAWAY RECEIPT');

  static SlipTemplate delivery() => SlipTemplate(heading: 'DELIVERY RECEIPT');
}

class BillProfile {
  BillProfile({
    this.businessName = 'My Shop',
    this.address = '',
    this.phone = '',
    this.taxId = '',
    this.footer = 'THANK YOU!',
    this.currencySymbol = kDefaultCurrency,
    this.currencyPrefix = true,
    this.taxRate = 0,
    this.serviceRate = 0,
    this.logoBase64,
    this.payQrBase64,
    this.payQrLabel = '',
    this.managerPin = '',
    SlipTemplate? kitchenSlip,
    SlipTemplate? counterSlip,
    SlipTemplate? takeawaySlip,
    SlipTemplate? deliverySlip,
  })  : kitchenSlip = kitchenSlip ?? SlipTemplate.kitchen(),
        counterSlip = counterSlip ?? SlipTemplate.counter(),
        takeawaySlip = takeawaySlip ?? SlipTemplate.takeaway(),
        deliverySlip = deliverySlip ?? SlipTemplate.delivery();

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
  String? payQrBase64;
  String payQrLabel;
  String managerPin;
  SlipTemplate kitchenSlip;
  SlipTemplate counterSlip;
  SlipTemplate takeawaySlip;
  SlipTemplate deliverySlip;

  SlipTemplate slipFor(dynamic order, {required bool kitchen}) {
    if (kitchen) return kitchenSlip;
    final t = order.type;
    if (t == OrderType.takeaway) return takeawaySlip;
    if (t == OrderType.delivery) return deliverySlip;
    return counterSlip;
  }

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
        payQrBase64: payQrBase64,
        payQrLabel: payQrLabel,
        managerPin: managerPin,
        kitchenSlip: kitchenSlip.copy(),
        counterSlip: counterSlip.copy(),
        takeawaySlip: takeawaySlip.copy(),
        deliverySlip: deliverySlip.copy(),
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
        'payQrBase64': payQrBase64,
        'payQrLabel': payQrLabel,
        'managerPin': managerPin,
        'kitchenSlip': kitchenSlip.toJson(),
        'counterSlip': counterSlip.toJson(),
        'takeawaySlip': takeawaySlip.toJson(),
        'deliverySlip': deliverySlip.toJson(),
      };

  factory BillProfile.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return BillProfile(
      businessName: parseStr(m['businessName']) ?? 'My Shop',
      address: parseStr(m['address']) ?? '',
      phone: parseStr(m['phone']) ?? '',
      taxId: parseStr(m['taxId']) ?? '',
      footer: parseStr(m['footer']) ?? 'THANK YOU!',
      currencySymbol: parseStr(m['currencySymbol']) ?? kDefaultCurrency,
      currencyPrefix: parseBool(m['currencyPrefix'], true),
      taxRate: parseNum(m['taxRate']),
      serviceRate: parseNum(m['serviceRate']),
      logoBase64: parseStr(m['logoBase64']),
      payQrBase64: parseStr(m['payQrBase64']),
      payQrLabel: parseStr(m['payQrLabel']) ?? '',
      managerPin: parseStr(m['managerPin']) ?? '',
      kitchenSlip: SlipTemplate.fromJson(
        m['kitchenSlip'] is Map ? Map<String, dynamic>.from(m['kitchenSlip'] as Map) : null,
        SlipTemplate.kitchen(),
      ),
      counterSlip: SlipTemplate.fromJson(
        m['counterSlip'] is Map ? Map<String, dynamic>.from(m['counterSlip'] as Map) : null,
        SlipTemplate.counter(),
      ),
      takeawaySlip: SlipTemplate.fromJson(
        m['takeawaySlip'] is Map ? Map<String, dynamic>.from(m['takeawaySlip'] as Map) : null,
        SlipTemplate.takeaway(),
      ),
      deliverySlip: SlipTemplate.fromJson(
        m['deliverySlip'] is Map ? Map<String, dynamic>.from(m['deliverySlip'] as Map) : null,
        SlipTemplate.delivery(),
      ),
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
