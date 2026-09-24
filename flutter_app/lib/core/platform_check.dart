import 'dart:io';

/// Desktop (Windows / macOS / Linux) vs phone targets. Order Flow Main can
/// run on a shop laptop — stations stay on their phones and join over LAN
/// exactly like they would with a phone Main. Everything Android-only
/// (Bluetooth channel, camera scan, ML Kit OCR) is gated behind these.
class OfPlatform {
  OfPlatform._();

  static bool get isWindows => Platform.isWindows;
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Camera + ML Kit barcode scanning lives on phones only. Desktop stations
  /// use a USB scanner (keyboard-wedge, zero drivers) or the manual entry.
  static bool get supportsCameraScan => Platform.isAndroid || Platform.isIOS;

  /// Android Bluetooth ESC/POS channel. Desktop reaches printers over LAN
  /// (port 9100) or — on Windows — through the system print spooler.
  static bool get supportsBluetoothPrinting => Platform.isAndroid;

  /// Raw ESC/POS through the Windows print spooler (USB thermal printers,
  /// "Generic / Text Only" driver included with Windows).
  static bool get supportsWindowsSpooler => Platform.isWindows;
}
