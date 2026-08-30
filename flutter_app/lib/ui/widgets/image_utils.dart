import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Frame helpers from https://github.com/horlengg/barcode_scanner_animation
/// (image_utils.dart). Builds a valid NV21 buffer for ML Kit on Android.
class ImageUtils {
  ImageUtils._();

  static InputImage? buildAndroidInputImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final width = image.width;
    final height = image.height;

    if (image.planes.length == 1) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    if (image.planes.length < 3) return null;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 2;

    final buffer = WriteBuffer();

    for (var row = 0; row < height; row++) {
      final offset = row * yRowStride;
      final end = offset + width;
      if (end > yPlane.bytes.length) return null;
      buffer.putUint8List(yPlane.bytes.sublist(offset, end));
    }

    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final offset = row * uvRowStride + col * uvPixelStride;
        if (offset >= vPlane.bytes.length || offset >= uPlane.bytes.length) {
          return null;
        }
        buffer.putUint8(vPlane.bytes[offset]);
        buffer.putUint8(uPlane.bytes[offset]);
      }
    }

    return InputImage.fromBytes(
      bytes: buffer.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: width,
      ),
    );
  }

  static InputImage? buildIOSInputImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
