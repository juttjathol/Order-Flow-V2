import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'storage_service.dart';

class BackupService {
  BackupService(this.storage);
  final StorageService storage;

  Future<String> exportAndShare(AppStore store) async {
    final path = await storage.exportPath(store);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/json')],
      subject: 'Order Flow backup',
      text: 'Order Flow shop backup',
    );
    return path;
  }

  Future<AppStore?> pickImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      raw = await File(file.path!).readAsString();
    } else {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Backup is not a JSON object');
    }
    return AppStore.fromJson(Map<String, dynamic>.from(decoded));
  }
}
