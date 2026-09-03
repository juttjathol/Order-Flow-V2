import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../models/models.dart';
import 'storage_service.dart';

class BackupService {
  BackupService(this.storage);
  final StorageService storage;

  static const kind = 'jathol.orderflow.backup';

  Future<String> exportAndShare(AppStore store) async {
    final shop = store.profile.businessName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final name = 'Jathol_${shop.isEmpty ? 'Shop' : shop}_backup_$stamp.ofbak.json';
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    final payload = {
      'kind': kind,
      'app': kAppName,
      'appVersion': kAppVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'store': store.toJson(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    await Share.shareXFiles(
      [XFile(file.path, name: name, mimeType: 'application/json')],
      subject: 'Order Flow backup — $name',
      text: 'Order Flow shop backup. Keep this file. Restore it in More → Import backup.',
    );
    return file.path;
  }

  Future<AppStore?> pickImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'ofbak', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    String raw;
    if (picked.bytes != null && picked.bytes!.isNotEmpty) {
      raw = utf8.decode(picked.bytes!);
    } else if (picked.path != null) {
      raw = await File(picked.path!).readAsString();
    } else {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('This file is not an Order Flow backup');
    }
    final map = Map<String, dynamic>.from(decoded);
    final storeRaw = map['store'];
    if (storeRaw is Map) {
      return AppStore.fromJson(Map<String, dynamic>.from(storeRaw));
    }
    return AppStore.fromJson(map);
  }
}
