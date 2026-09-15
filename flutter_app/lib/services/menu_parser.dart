/// v1.1.65 · Menu import parser.
///
/// Pure Dart: no Flutter or plugin imports, so it runs in plain unit tests.
/// Both input sources (ML Kit OCR on photos and on rendered PDF pages)
/// produce the same word geometry, and this reconstructs a menu from it:
/// rows by y, columns by x-gaps, prices at row ends, categories as
/// standalone caps/large lines, descriptions as the line under an item.
class ScanWord {
  const ScanWord(this.text, {required this.x, required this.y, required this.w, this.size = 12});

  final String text;
  final double x;
  final double y;
  final double w;

  /// Approximate glyph height (OCR: box height, PDF: font size).
  final double size;

  double get right => x + w;
}

class ScannedItem {
  ScannedItem({required this.name, this.price, this.category, this.description, this.include = true});

  String name;
  double? price;
  String? category;
  String? description;
  bool include;
}

class MenuParseResult {
  MenuParseResult({required this.items, required this.categories, required this.rawLineCount});

  final List<ScannedItem> items;
  final List<String> categories;
  final int rawLineCount;

  bool get isEmpty => items.isEmpty;
}

class MenuParser {
  /// Currency-prefixed or bare number token that can end a menu row.
  static final RegExp _priceTok = RegExp(
    r'^(?:rm|myr|rp|idr|thb|php|inr|vnd|rs\.?|[₱฿₹₫])?\s*'
    r'(\d{1,3}(?:[.,]\d{3})+|\d{1,6}(?:[.,]\d{1,2})?)\s*[/]?(?:pcs?|pax|each)?\.?$',
    caseSensitive: false,
  );

  static final RegExp _curWord = RegExp(r'^(rm|myr|rp|idr|₱|php|thb|฿|₹|inr|₫|vnd|rs\.?)$', caseSensitive: false);

  /// Junk that never belongs to an item: contacts, hours, legal notes.
  static final RegExp _noise = RegExp(
    r'(?:tel:|telephone|phone|whatsapp|watsapp|email|http|www\.|facebook|instagram|'
    r'open|closed|hourly|jam\s*[:\d]|GST|SST|service\s+charge|tax\s+inclusive|inclusive\s+of|'
    r'subject\s+to|tertakluk|all\s+prices|harga\s+tertakluk|promo\s+code|scan\s+to)',
    caseSensitive: false,
  );

  static final RegExp _leadBullet = RegExp(r'^(?:[\s•·*\-–—]+|\d{1,2}[.)\-]\s+)');
  static final RegExp _trailDots = RegExp(r'[.·\u2024\s]+$');
  static final RegExp _alphaRun = RegExp(r'[A-Za-z\u00C0-\u024F\u0600-\u06FF\u0400-\u04FF]');
  static final RegExp _thousands = RegExp(r'^\d{1,3}(?:[.,]\d{3})+$');

  static MenuParseResult parse(List<ScanWord> words, {double pageWidth = 1000}) {
    final clean = words.where((e) => e.text.trim().isNotEmpty).toList()
      ..sort((a, b) {
        final c = a.y.compareTo(b.y);
        return c != 0 ? c : a.x.compareTo(b.x);
      });
    if (clean.isEmpty) {
      return MenuParseResult(items: const [], categories: const [], rawLineCount: 0);
    }

    final sizes = clean.map((e) => e.size).toList()..sort();
    final double medSize = sizes[sizes.length ~/ 2].clamp(6.0, 400.0).toDouble();

    // 1 · group words into visual rows by baseline proximity
    final rows = <List<ScanWord>>[];
    var row = <ScanWord>[clean.first];
    var rowTop = clean.first.y;
    for (final wd in clean.skip(1)) {
      if (wd.y - rowTop > medSize * 0.75) {
        rows.add(row);
        row = [wd];
        rowTop = wd.y;
      } else {
        row.add(wd);
        rowTop = (rowTop + wd.y) / 2;
      }
    }
    rows.add(row);

    // 2 · per row: split into columns, peel trailing prices
    final items = <ScannedItem>[];
    final categories = <String>[];
    String? currentCat;
    var rawLineCount = 0;

    for (final r in rows) {
      r.sort((a, b) => a.x.compareTo(b.x));
      rawLineCount++;
      for (final seg in _splitColumns(r, pageWidth)) {
        if (seg.isEmpty) continue;
        final leftover = _consumePrice(seg, items, medSize);
        if (leftover == null) {
          // an item was just appended — give it the active category
          final made = items.last;
          if (made.category == null) made.category = currentCat;
          continue;
        }
        final text = leftover;
        if (_looksNoise(text)) continue;
        if (_looksCategory(text, seg, medSize)) {
          final name = _titleCase(text.replaceAll(RegExp(r'[:\-–—\s]+$'), ''));
          if (name.length >= 3 && name.length <= 28 &&
              !categories.any((c) => c.toLowerCase() == name.toLowerCase())) {
            categories.add(name);
            currentCat = name;
          }
          continue;
        }
        // no price, not a category: a description under the previous item
        if (items.isNotEmpty && text.length <= 120 && _alphaRun.hasMatch(text)) {
          final prev = items.last;
          prev.description = prev.description == null ? text : '${prev.description} $text';
        }
      }
    }

    // v1.1.70 fallback — when NOT a single row matched (odd price formats,
    // prices printed in a far column the grouping split off), still offer the
    // plausible dish rows with blank prices: the review sheet edits them in.
    // Only when completely empty, so normal menus are untouched.
    if (items.isEmpty) {
      for (final r0 in rows) {
        r0.sort((a, c) => a.x.compareTo(c.x));
        final t = r0.map((e) => e.text).join(' ').replaceAll(_leadBullet, '').replaceAll(_trailDots, '').trim();
        if (t.length < 2 || t.length > 40 || _looksNoise(t)) continue;
        if (_priceTok.hasMatch(t.split(RegExp(r'\s+')).last)) continue;
        final wc = t.split(RegExp(r'\s+')).where((x) => _alphaRun.hasMatch(x)).length;
        if (wc < 1 || wc > 6) continue;
        if (categories.any((c) => c.toLowerCase() == t.toLowerCase())) continue;
        items.add(ScannedItem(name: _titleCase(t), price: null, category: currentCat));
      }
    }

    // drop accidental duplicates: same name + price
    final seen = <String>{};
    items.removeWhere((e) => !seen.add('${e.name.toLowerCase()}|${e.price ?? ''}'));
    items.removeWhere((e) => e.name.length < 2);

    return MenuParseResult(items: items, categories: categories, rawLineCount: rawLineCount);
  }

  /// Split a row into column segments at a wide horizontal gap
  /// (two-column menus). Threshold = 18% of page width, floored sensibly.
  static List<List<ScanWord>> _splitColumns(List<ScanWord> row, double pageWidth) {
    if (row.length < 3) return [row];
    final gapMin = pageWidth * 0.18;
    final starts = <int>[];
    for (var i = 0; i + 1 < row.length; i++) {
      if (row[i + 1].x - row[i].right >= gapMin) starts.add(i + 1);
    }
    if (starts.isEmpty) return [row];
    final out = <List<ScanWord>>[];
    var start = 0;
    for (final s in starts) {
      out.add(row.sublist(start, s));
      start = s;
    }
    out.add(row.sublist(start));
    return out.where((e) => e.isNotEmpty).toList();
  }

  /// Find the row's price and append an item; returns null on success.
  /// v1.1.70: the price isn't always the LAST token — OCR often appends a
  /// size/unit after it ('8.50 (P)', '12 each'), and leader-dot noise can sit
  /// between. So scan back over the last few tokens, and whatever trails the
  /// price is dropped as unit-junk instead of killing the whole item.
  static String? _consumePrice(List<ScanWord> seg, List<ScannedItem> items, double medSize) {
    String joined() => seg.map((e) => e.text).join(' ').trim();

    if (seg.isEmpty) return null;
    var idx = -1;
    Match? pm;
    for (var k = seg.length - 1; k >= seg.length - 4 && k >= 1; k--) {
      var cand = seg[k].text;
      var j = k;
      if (_curWord.hasMatch(seg[k - 1].text.trim())) {
        cand = seg[k - 1].text + seg[k].text; // "RM" + "8.50"
        j = k - 1;
      }
      final mt = _priceTok.firstMatch(cand.trim());
      if (mt != null) {
        idx = j;
        pm = mt;
        break;
      }
    }
    if (idx < 0) return joined();
    final price = _normalizeNumber(pm?.group(1) ?? '');
    if (price == null || price <= 0 || price > 1e7) return joined();

    final nameWords = seg.sublist(0, idx);
    if (nameWords.isEmpty) return null; // price-only row (a number in the void)
    var name = nameWords.map((e) => e.text).join(' ');
    name = name.replaceAll(_leadBullet, '');
    name = name.replaceAll(RegExp(r'\s*[-–—:;]\s*$'), ''); // trailing dashes
    name = name.replaceAll(_trailDots, ''); // leader dots "Nasi Goreng ....."
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (name.length < 2 || !_alphaRun.hasMatch(name) || _looksNoise(name)) return joined();

    items.add(ScannedItem(name: _titleCase(name), price: price));
    return null;
  }

  static double? _normalizeNumber(String raw) {
    var s = raw.trim();
    if (_thousands.hasMatch(s)) {
      // 15.000 / 1,500 / 1.234.567 → strip grouping separators
      s = s.replaceAll(RegExp(r'[.,]'), '');
      return double.tryParse(s);
    }
    if (s.contains(',')) s = s.replaceAll(',', '.');
    return double.tryParse(s);
  }

  static bool _looksNoise(String t) {
    if (t.trim().length <= 3) return true;
    if (_noise.hasMatch(t)) return true;
    final digits = RegExp(r'\d').allMatches(t).length;
    final letters = _alphaRun.allMatches(t).length;
    if (digits > letters) return true; // page numbers, contacts, promos
    return false;
  }

  static bool _looksCategory(String text, List<ScanWord> seg, double medSize) {
    final stripped = text.replaceAll(RegExp(r'[^A-Za-z\u0600-\u06FF\s]'), '').trim();
    if (stripped.isEmpty || stripped.length > 28) return false;
    final big = seg.any((e) => e.size >= medSize * 1.35);
    final caps = text == text.toUpperCase() && text != text.toLowerCase();
    final colon = text.trimRight().endsWith(':');
    return big || caps || colon;
  }

  static String _titleCase(String t) {
    // SHOUTY OCR names become pleasant; mixed-case names untouched
    final trimmed = t.trim();
    if (trimmed.length < 3 || trimmed != trimmed.toUpperCase()) return trimmed;
    return trimmed
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
