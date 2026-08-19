import 'models.dart';

AppStore seedFor(BusinessModel model, AppStore store) {
  store.model = model;
  store.seeded = true;
  store.categories.clear();
  store.products.clear();
  store.stock.clear();
  store.tables.clear();
  store.services.clear();
  store.staff.clear();
  store.drivers.clear();
  store.appointments.clear();

  void cat(String name, String ur) {
    store.categories.add(MenuCategory(
      id: newId(),
      name: name,
      nameUr: ur,
      sort: store.categories.length,
    ));
  }

  void item(String catName, String name, String ur, double price,
      {String sku = '', String? inv}) {
    final c = store.categories.firstWhere((e) => e.name == catName);
    store.products.add(MenuProduct(
      id: newId(),
      categoryId: c.id,
      name: name,
      nameUr: ur,
      price: price,
      sku: sku,
      inventoryId: inv,
    ));
  }

  void stock(String name, double qty, {String unit = 'pcs', double low = 5, String sku = ''}) {
    store.stock.add(StockItem(
      id: newId(),
      name: name,
      sku: sku.isEmpty ? name.toUpperCase().replaceAll(' ', '') : sku,
      quantity: qty,
      unit: unit,
      lowStockAt: low,
    ));
  }

  switch (model) {
    case BusinessModel.restaurant:
      store.profile.businessName = 'Green Oven';
      for (var i = 1; i <= 8; i++) {
        store.tables.add(FloorTable(id: newId(), name: 'T$i', seats: i <= 4 ? 4 : 6));
      }
      cat('Starters', 'اسٹارٹرز');
      cat('Grills', 'گرل');
      cat('Breads', 'روٹی');
      cat('Drinks', 'مشروبات');
      stock('Chicken', 20, unit: 'kg', low: 4, sku: 'CHK');
      stock('Beef', 12, unit: 'kg', low: 3, sku: 'BEF');
      stock('Flour', 15, unit: 'kg', low: 4, sku: 'FLR');
      stock('Cola cans', 24, unit: 'pcs', low: 6, sku: 'COLA');
      final chicken = store.stock.firstWhere((s) => s.sku == 'CHK').id;
      final cola = store.stock.firstWhere((s) => s.sku == 'COLA').id;
      item('Starters', 'Chicken Soup', 'چکن سوپ', 280);
      item('Grills', 'Seekh Kebab', 'سیخ کباب', 650, inv: chicken);
      item('Grills', 'Chicken Karahi', 'چکن کڑاہی', 980, inv: chicken);
      item('Breads', 'Naan', 'نان', 40);
      item('Drinks', 'Cola', 'کولا', 80, inv: cola);
      store.drivers.add(Driver(id: newId(), name: 'Ali', phone: '0300-0000000', status: DriverStatus.offline));
      break;
    case BusinessModel.retail:
      store.profile.businessName = 'Daily Mart';
      cat('Grocery', 'گروسری');
      cat('Household', 'گھریلو');
      cat('Snacks', 'اسنیکس');
      stock('Rice 5kg', 18, sku: 'RICE5', low: 4);
      stock('Cooking oil 1L', 30, sku: 'OIL1', low: 6);
      stock('Soap bar', 40, sku: 'SOAP', low: 8);
      stock('Chips pack', 22, sku: 'CHIP', low: 6);
      item('Grocery', 'Rice 5kg', 'چاول ۵ کلو', 980, sku: 'RICE5', inv: store.stock[0].id);
      item('Grocery', 'Cooking oil 1L', 'تیل ۱ لیٹر', 520, sku: 'OIL1', inv: store.stock[1].id);
      item('Household', 'Soap bar', 'صابن', 90, sku: 'SOAP', inv: store.stock[2].id);
      item('Snacks', 'Chips pack', 'چپس', 60, sku: 'CHIP', inv: store.stock[3].id);
      break;
    case BusinessModel.fastfood:
      store.profile.businessName = 'Quick Bite';
      cat('Burgers', 'برگر');
      cat('Sides', 'سائیڈز');
      cat('Drinks', 'مشروبات');
      stock('Patty', 40, low: 8, sku: 'PAT');
      stock('Buns', 40, low: 8, sku: 'BUN');
      stock('Fries bags', 25, low: 6, sku: 'FRY');
      stock('Cups', 50, low: 10, sku: 'CUP');
      item('Burgers', 'Classic Burger', 'کلاسیک برگر', 450, inv: store.stock[0].id);
      item('Burgers', 'Chicken Burger', 'چکن برگر', 420);
      item('Sides', 'Fries', 'فرائز', 180, inv: store.stock[2].id);
      item('Drinks', 'Soft drink', 'سافٹ ڈرنک', 90, inv: store.stock[3].id);
      break;
    case BusinessModel.services:
      store.profile.businessName = 'City Care';
      store.staff.addAll([
        StaffMember(id: newId(), name: 'Sara', roleLabel: 'Stylist'),
        StaffMember(id: newId(), name: 'Omar', roleLabel: 'Therapist'),
      ]);
      store.services.addAll([
        ServiceOffering(id: newId(), name: 'Haircut', price: 800, durationMin: 30),
        ServiceOffering(id: newId(), name: 'Beard trim', price: 400, durationMin: 15),
        ServiceOffering(id: newId(), name: 'Massage 30m', price: 1800, durationMin: 30),
      ]);
      stock('Shampoo', 10, unit: 'btl', low: 3, sku: 'SHMP');
      stock('Towels', 16, unit: 'pcs', low: 4, sku: 'TOW');
      break;
  }
  return store;
}
