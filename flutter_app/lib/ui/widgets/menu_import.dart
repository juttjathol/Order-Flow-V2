/// v1.1.65 · Menu import: photo or PDF → on-device OCR → editable review →
/// bulk upsert. All recognition is on-device (ML Kit bundled model, no
/// network, no keys). Photos and PDF pages share one pipeline:
/// image bytes → [MenuParser] words → items.
///
/// Known limitation, by design: ML Kit reads Latin script only — Malay/English
/// menus work great; Urdu-script menus still need manual entry.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/menu_parser.dart';
import '../../state/app_controller.dart';
import './common.dart';

/// Entry point — called from the menu screen header.
Future<void> openMenuImport(BuildContext context, WidgetRef ref) async {
  if (_busy) return;
  _busy = true;
  final s = L10n(ref.read(appControllerProvider).session.locale);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(s.t('menu_scan_title'),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.t('menu_scan_photo')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.t('menu_scan_gallery')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(s.t('menu_scan_pdf')),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(s.t('menu_scan_tip'),
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: OfColors.mute(ctx))),
            ),
          ],
        ),
      ),
    );
    if (src == null || !context.mounted) return;

    final status = ValueNotifier<String>(s.t('menu_scan_reading'));
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScanProgress(label: status),
    ));

    List<ScanWord> words = const [];
    var pageWidth = 1000.0;
    Object? fail;
    try {
      if (src == 'pdf') {
        final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
        final path = (picked == null || picked.files.isEmpty) ? null : picked.files.single.path;
        if (path == null) {
          fail = 'no-file';
        } else {
          final out = await _wordsFromPdf(path, status, s);
          words = out.$1;
          pageWidth = out.$2;
        }
      } else {
        final xf = await ImagePicker().pickImage(
          source: src == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2400,
          imageQuality: 95,
        );
        if (xf == null) {
          fail = 'no-file';
        } else {
          final recognizer = TextRecognizer();
          try {
            final img = InputImage.fromFilePath(xf.path);
            final result = await recognizer.processImage(img);
            words = _wordsFromMlKit(result);
            final rightMost = words.fold<double>(0.0, (a, e) => e.right > a ? e.right : a);
            pageWidth = math.max(600.0, rightMost).toDouble();
          } finally {
            await recognizer.close();
          }
        }
      }
    } catch (e) {
      fail = e;
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (fail != null) {
      if (fail is! String) {
        messenger.showSnackBar(SnackBar(content: Text('${s.t('menu_scan_failed')}  $fail')));
      }
      return;
    }

    final res = MenuParser.parse(words, pageWidth: pageWidth);
    if (res.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('menu_scan_none'))));
      return;
    }

    if (!context.mounted) return;
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => _MenuReviewSheet(items: res.items, categories: res.categories),
    );
    if ((added ?? 0) > 0) {
      messenger.showSnackBar(SnackBar(content: Text('$added ${s.t('menu_scan_done')}')));
    }
  } finally {
    _busy = false;
  }
}

bool _busy = false;

// ---------------------------------------------------------------- recognizers

/// The single ML Kit touch point — if the plugin's model shape ever shifts,
/// only this function changes.
List<ScanWord> _wordsFromMlKit(RecognizedText result) {
  final out = <ScanWord>[];
  for (final block in result.blocks) {
    for (final line in block.lines) {
      final els = line.elements;
      if (els.isEmpty) {
        final r = line.boundingBox;
        if (r == null) continue;
        out.add(ScanWord(line.text.trim(), x: r.left.toDouble(), y: r.top.toDouble(), w: r.width.toDouble(), size: r.height.toDouble()));
        continue;
      }
      for (final e in els) {
        final t = e.text.trim();
        if (t.isEmpty) continue;
        final r = e.boundingBox;
        if (r == null) continue;
        out.add(ScanWord(t, x: r.left.toDouble(), y: r.top.toDouble(), w: r.width.toDouble(), size: r.height.toDouble()));
      }
    }
  }
  return out;
}

/// PDF → per-page PNG render at OCR-friendly scale → ML Kit → words.
/// Rendered pages are perfectly flat, so typed menus OCR almost perfectly;
/// scanned PDFs go through the exact same path — one pipeline, every PDF.
Future<(List<ScanWord>, double)> _wordsFromPdf(String path, ValueNotifier<String> status, L10n s) async {
  const maxPages = 6;
  final doc = await pdfx.PdfDocument.openFile(path);
  final recognizer = TextRecognizer();
  final words = <ScanWord>[];
  var pageWidth = 1000.0;
  final dir = await getTemporaryDirectory();
  try {
    final total = doc.pagesCount;
    final take = math.min(total, maxPages);
    for (var i = 1; i <= take; i++) {
      if (i > 1) status.value = '${s.t('menu_scan_page')} $i · ${s.t('menu_scan_of')} $total';
      final page = await doc.getPage(i);
      try {
        final scale = (1700.0 / math.max(1.0, page.width)).clamp(1.6, 3.2);
        final img = await page.render(
          width: (page.width * scale).round(),
          height: (page.height * scale).round(),
          format: pdfx.PdfPageImageFormat.png,
        );
        final data = img?.data;
        if (data != null) {
          final f = File('${dir.path}/menu_import_p$i.png');
          await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
          final result = await recognizer.processImage(InputImage.fromFilePath(f.path));
          final pw = (page.width * scale);
          if (i == 1) pageWidth = pw;
          words.addAll(_wordsFromMlKit(result));
          try {
            await f.delete();
          } catch (_) {}
        }
      } finally {
        await page.dispose();
      }
    }
    if (total > take) status.value = s.t('menu_scan_reading');
  } finally {
    await recognizer.close();
    await doc.dispose();
  }
  return (words, pageWidth);
}

// --------------------------------------------------------------------- chrome

class _ScanProgress extends StatelessWidget {
  const _ScanProgress({required this.label});
  final ValueNotifier<String> label;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                const SizedBox(width: 16),
                ValueListenableBuilder<String>(
                  valueListenable: label,
                  builder: (_, v, __) => Flexible(child: Text(v, style: Theme.of(context).textTheme.bodyMedium)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- review sheet

class _Draft {
  _Draft({required this.include, required this.name, required this.price, required this.category, this.desc})
      : nameCtl = TextEditingController(text: name),
        priceCtl = TextEditingController(text: price == null ? '' : _num(price));

  bool include;
  String name;
  double? price;
  String category;
  String? desc;
  final TextEditingController nameCtl;
  final TextEditingController priceCtl;
  bool priceBad = false;

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void dispose() {
    nameCtl.dispose();
    priceCtl.dispose();
  }
}

class _MenuReviewSheet extends ConsumerStatefulWidget {
  const _MenuReviewSheet({required this.items, required this.categories});
  final List<ScannedItem> items;
  final List<String> categories;

  @override
  ConsumerState<_MenuReviewSheet> createState() => _MenuReviewSheetState();
}

class _MenuReviewSheetState extends ConsumerState<_MenuReviewSheet> {
  late final List<_Draft> drafts;
  late List<String> catOptions;
  bool importing = false;

  @override
  void initState() {
    super.initState();
    drafts = [
      for (final it in widget.items)
        _Draft(
          include: true,
          name: it.name,
          price: it.price,
          category: it.category ?? '',
          desc: it.description,
        ),
    ];
    final store = ref.read(appControllerProvider).store;
    catOptions = [
      ...store.categories.map((c) => c.name),
      ...widget.categories.where((c) => !store.categories.any((e) => e.name.toLowerCase() == c.toLowerCase())),
      'Imported',
    ].toSet().toList();
    for (final d in drafts) {
      if (d.category.isNotEmpty && !catOptions.contains(d.category)) catOptions.add(d.category);
    }
  }

  int get selected => drafts.where((d) => d.include && d.nameCtl.text.trim().isNotEmpty).length;

  Future<void> _import() async {
    // validate prices first
    var bad = false;
    for (final d in drafts) {
      if (!d.include) continue;
      final t = d.priceCtl.text.trim().replaceAll(',', '.');
      d.price = t.isEmpty ? 0 : double.tryParse(t);
      d.priceBad = d.price == null;
      bad = bad || d.priceBad;
    }
    setState(() {});
    if (bad) return;
    final chosen = drafts.where((d) => d.include && d.nameCtl.text.trim().isNotEmpty).toList();
    if (chosen.isEmpty) return;

    setState(() => importing = true);
    final store = ref.read(appControllerProvider).store;
    final s = L10n(ref.read(appControllerProvider).session.locale);
    final byName = {for (final c in store.categories) c.name.trim().toLowerCase(): c.id};
    var sort = store.categories.isEmpty ? 0 : store.categories.map((c) => c.sort).reduce((a, b) => a > b ? a : b) + 1;

    final toCreate = <String, String>{};
    for (final d in chosen) {
      final key = (d.category.isEmpty ? 'Imported' : d.category).toLowerCase();
      if (!byName.containsKey(key) && !toCreate.containsKey(key)) {
        toCreate[key] = newId();
      }
    }
    for (final e in toCreate.entries) {
      final cat = MenuCategory(id: e.value, name: e.key == 'imported' ? 'Imported' : _titleize(e.key), sort: sort++);
      byName[e.key] = e.id;
      await ref.ctrl.dispatch(NetCommand(name: 'upsertCategory', payload: {'category': cat.toJson()}));
    }

    final existingNames = store.products.map((p) => p.name.trim().toLowerCase()).toSet();
    var n = 0;
    for (final d in chosen) {
      final name = d.nameCtl.text.trim();
      if (existingNames.contains(name.toLowerCase())) continue;
      final key = (d.category.isEmpty ? 'Imported' : d.category).toLowerCase();
      final p = MenuProduct(
        id: newId(),
        categoryId: byName[key] ?? (store.categories.isEmpty ? newId() : store.categories.first.id),
        name: name,
        price: d.price ?? 0,
        description: d.desc ?? '',
        available: true,
      );
      await ref.ctrl.dispatch(NetCommand(name: 'upsertProduct', payload: {'product': p.toJson()}));
      existingNames.add(name.toLowerCase());
      n++;
    }
    if (!mounted) return;
    if (n == 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('menu_scan_all_exist'))));
    Navigator.pop(context, n);
  }

  static String _titleize(String k) => k
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: h * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${s.t('menu_scan_review')} · $selected',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  TextButton(onPressed: () => setState(() {
                        final turn = selected != drafts.length;
                        for (final d in drafts) {
                          d.include = turn;
                        }
                      }), child: Text(selected == drafts.length ? s.t('menu_scan_clear_btn') : s.t('menu_scan_all_btn'))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(s.t('menu_scan_edit_hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: OfColors.mute(context))),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: drafts.length + 1,
                itemBuilder: (_, i) {
                  if (i == drafts.length) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(s.t('menu_scan_add_row')),
                          onPressed: () => setState(() => drafts.add(_Draft(include: true, name: '', price: null, category: ''))),
                        ),
                      ),
                    );
                  }
                  final d = drafts[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(value: d.include, onChanged: (v) => setState(() => d.include = v ?? false)),
                        Expanded(
                          flex: 5,
                          child: TextField(
                            controller: d.nameCtl,
                            enabled: d.include,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(isDense: true, filled: false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: d.priceCtl,
                            enabled: d.include,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            textAlign: TextAlign.end,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixText: 'RM ',
                              errorText: d.priceBad ? ' !' : null,
                              errorStyle: const TextStyle(height: 0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: d.category.isEmpty ? null : d.category,
                              hint: Text(s.t('category'), style: const TextStyle(fontWeight: FontWeight.w400)),
                              items: [
                                for (final c in catOptions)
                                  DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => d.category = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: importing ? null : _import,
                    icon: importing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.playlist_add),
                    label: Text('${s.t('menu_scan_import')} ($selected)'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
