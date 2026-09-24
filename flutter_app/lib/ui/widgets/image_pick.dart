import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../../core/platform_check.dart';

/// Picks one image and returns its raw bytes.
///
/// Phones use the system gallery (image_picker). Desktop has no endorsed
/// image_picker backend, so we go through the OS file dialog (file_picker)
/// instead — same bytes either way.
Future<List<int>?> pickImageBytes({
  int maxWidth = 600,
  int imageQuality = 70,
}) async {
  if (!kIsWeb && OfPlatform.isDesktop) {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.single;
    if (f.bytes != null) return f.bytes;
    final path = f.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: maxWidth,
    imageQuality: imageQuality,
  );
  if (picked == null) return null;
  return picked.readAsBytes();
}
