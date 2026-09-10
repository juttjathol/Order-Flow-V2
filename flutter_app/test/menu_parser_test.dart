import 'package:flutter_test/flutter_test.dart';
import 'package:order_flow_app/services/menu_parser.dart';

/// word helper: width approximated like real glyphs (~0.55 em per char)
ScanWord w(String t, double x, double y, [double size = 12]) =>
    ScanWord(t, x: x, y: y, w: t.length * size * 0.55, size: size);

void main() {
  group('MenuParser', () {
    test('category + leader dots + decimal price', () {
      final r = MenuParser.parse([
        w('APPETIZERS', 200, 20),
        w('Nasi', 20, 40), w('Goreng', 60, 40), w('....', 120, 40), w('8.50', 300, 40),
        w('Roti', 20, 60), w('Canai', 60, 60), w('RM', 250, 60), w('4.00', 290, 60),
      ]);
      expect(r.categories, ['Appetizers']);
      expect(r.items.length, 2);
      expect(r.items[0].name, 'Nasi Goreng');
      expect(r.items[0].price, 8.5);
      expect(r.items[0].category, 'Appetizers');
      expect(r.items[1].name, 'Roti Canai');
      expect(r.items[1].price, 4.0);
    });

    test('IDR-style thousands separator beats decimal', () {
      final r = MenuParser.parse([
        w('Nasi', 20, 40), w('Goreng', 60, 40), w('Spesial', 130, 40), w('Rp', 300, 40), w('15.000', 340, 40),
        w('Teh', 20, 60), w('Tarik', 50, 60), w('8.000', 330, 60),
      ]);
      expect(r.items.length, 2);
      expect(r.items[0].price, 15000);
      expect(r.items[1].price, 8000);
    });

    test('two-column menus split on the middle gap', () {
      final r = MenuParser.parse([
        w('Ayam', 20, 40), w('Penyet', 60, 40), w('12', 200, 40),
        w('Sate', 560, 40), w('Kambing', 600, 40), w('25', 800, 40),
      ], pageWidth: 1000);
      expect(r.items.length, 2);
      expect(r.items[0].name, 'Ayam Penyet');
      expect(r.items[0].price, 12);
      expect(r.items[1].name, 'Sate Kambing');
      expect(r.items[1].price, 25);
    });

    test('description line under an item is attached', () {
      final r = MenuParser.parse([
        w('Nasi', 20, 40), w('Lemak', 60, 40), w('7.00', 300, 40),
        w('with', 20, 56, 10), w('egg', 55, 56, 10), w('and', 85, 56, 10), w('sambal', 115, 56, 10),
      ]);
      expect(r.items.length, 1);
      expect(r.items[0].description, 'with egg and sambal');
    });

    test('contact / hours / digit rows are dropped', () {
      final r = MenuParser.parse([
        w('Tel:', 20, 20), w('03-2688', 50, 20), w('1234', 120, 20),
        w('Open', 20, 40), w('daily', 60, 40), w('9am-10pm', 110, 40),
        w('1234', 20, 60), w('5678', 70, 60), // pure digits
        w('Mee', 20, 80), w('Goreng', 60, 80), w('6.50', 300, 80),
      ]);
      expect(r.items.length, 1);
      expect(r.items.first.name, 'Mee Goreng');
    });

    test('duplicate name+price is deduped, all-caps gets title case', () {
      final r = MenuParser.parse([
        w('MEE', 20, 40), w('GORENG', 60, 40), w('6.50', 300, 40),
        w('MEE', 20, 60), w('GORENG', 60, 60), w('6.50', 300, 60),
      ]);
      expect(r.items.length, 1);
      expect(r.items.first.name, 'Mee Goreng');
    });

    test('font-size-driven category detection for mixed case', () {
      final r = MenuParser.parse([
        w('Minuman', 150, 20, 26), // large header
        w('Es', 20, 50), w('Teh', 45, 50), w('3.00', 300, 50),
      ]);
      expect(r.categories, ['Minuman']);
      expect(r.items.single.category, 'Minuman');
    });

    test('comma decimals normalize to dots', () {
      final r = MenuParser.parse([
        w('Kopi', 20, 40), w('O', 60, 40), w('3,50', 300, 40),
      ]);
      expect(r.items.single.price, 3.5);
    });

    test('empty input is safe', () {
      expect(MenuParser.parse([]).isEmpty, isTrue);
    });
  });
}
