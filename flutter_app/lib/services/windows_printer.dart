import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Raw ESC/POS printing through the Windows print spooler.
///
/// Any printer installed in Windows works — USB thermal printers almost
/// always install as "Generic / Text Only" with exactly this raw path, and
/// vendor drivers accept RAW jobs too. Only native calls involved: winspool
/// is called directly through dart:ffi. Everything no-ops off Windows.
class WindowsRawPrinter {
  WindowsRawPrinter._();

  // winspool constants
  static const int _PRINTER_ENUM_LOCAL = 0x2;
  static const int _PRINTER_ENUM_CONNECTIONS = 0x4;

  static DynamicLibrary? _lib;
  static DynamicLibrary _winspool() {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsRawPrinter is only available on Windows');
    }
    return _lib ??= DynamicLibrary.open('winspool.drv');
  }

  // ── signatures ────────────────────────────────────────────────────────────
  //
  // BOOL OpenPrinterW(LPWSTR pPrinterName, LPHANDLE phPrinter, LPPRINTER_DEFAULTSW pDefault);
  // BOOL EnumPrintersW(DWORD Flags, LPWSTR Name, DWORD Level, LPBYTE pPrinterEnum,
  //                    DWORD cbBuf, LPDWORD pcbNeeded, LPDWORD pcReturned);
  // DWORD StartDocPrinterW(HANDLE hPrinter, DWORD Level, DOC_INFO_1W* pDocInfo);
  // BOOL StartPagePrinter(HANDLE hPrinter);
  // BOOL WritePrinter(HANDLE hPrinter, LPVOID pBuf, DWORD cbBuf, LPDWORD pcWritten);
  // BOOL EndPagePrinter(HANDLE hPrinter);
  // BOOL EndDocPrinter(HANDLE hPrinter);
  // BOOL ClosePrinter(HANDLE hPrinter);

  /// Reads a null-terminated wide (UTF-16) string from [p]. Hand-rolled so
  /// we do not need the ffi helper package as an extra dependency.
  static String _readW(Pointer<Uint16> p) {
    final codes = <int>[];
    var i = 0;
    while (p[i] != 0) {
      codes.add(p[i]);
      i++;
    }
    return String.fromCharCodes(codes);
  }

  static Pointer<Uint16> _w(String s) {
    final units = s.codeUnits;
    final p = calloc<Uint16>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    return p;
  }

  /// Names of all local (and connected network) printers installed in
  /// Windows ("Printers & scanners"). Empty list off Windows.
  static List<String> listNames() {
    if (!Platform.isWindows) return const [];
    final lib = _winspool();
    final e = lib.lookupFunction<
        Int32 Function(Uint32, Pointer<Uint16>, Uint32, Pointer<Uint8>,
            Uint32, Pointer<Uint32>, Pointer<Uint32>),
        int Function(int, Pointer<Uint16>, int, Pointer<Uint8>, int,
            Pointer<Uint32>, Pointer<Uint32>)>('EnumPrintersW');

    // Level 4 → array of PRINTER_INFO_4W { LPWSTR pPrinterName; LPWSTR
    // pServerName; DWORD Attributes } — the cheapest to walk (single stride).
    const flags = _PRINTER_ENUM_LOCAL | _PRINTER_ENUM_CONNECTIONS;
    final needed = calloc<Uint32>();
    final returned = calloc<Uint32>();
    try {
      // First call: discover the buffer size. It is EXPECTED to fail with
      // ERROR_INSUFFICIENT_BUFFER — that is how winspool reports the size.
      e(flags, nullptr.cast<Uint16>(), 4, nullptr.cast<Uint8>(), 0, needed,
          returned);
      final size = needed.value;
      if (size <= 0) return const [];
      final buf = calloc<Uint8>(size);
      try {
        final ok = e(flags, nullptr.cast<Uint16>(), 4, buf, size, needed,
            returned);
        if (ok == 0 || returned.value == 0) return const [];
        final count = returned.value;
        // PRINTER_INFO_4W on 64-bit: 3 pointer/DWORD slots padded to 8 →
        // stride is 24 bytes; first field is the name pointer.
        const stride = 24;
        final names = <String>[];
        for (var i = 0; i < count; i++) {
          final slot = buf.elementAt(i * stride);
          final namePtr = slot.cast<Pointer<Uint16>>().value;
          if (namePtr != nullptr && namePtr.address != 0) {
            final name = _readW(namePtr).trim();
            if (name.isNotEmpty) names.add(name);
          }
        }
        return names;
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(needed);
      calloc.free(returned);
    }
  }

  /// Sends ALREADY RENDERED ESC/POS bytes as a RAW spool job to
  /// [printerName]. Throws [StateError] with a short reason on failure so
  /// callers can toast it (matching the BT channel behaviour).
  static Future<void> printRaw(
    String printerName,
    List<int> data, {
    String docName = 'Order Flow ticket',
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows spooler printing only works on Windows');
    }
    if (data.isEmpty) return;
    final lib = _winspool();

    final open = lib.lookupFunction<
        Int32 Function(Pointer<Uint16>, Pointer<IntPtr>, Pointer),
        int Function(Pointer<Uint16>, Pointer<IntPtr>, Pointer)>(
      'OpenPrinterW');
    final startDoc = lib.lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer),
        int Function(int, int, Pointer)>('StartDocPrinterW');
    final startPage = lib.lookupFunction<Int32 Function(IntPtr),
        int Function(int)>('StartPagePrinter');
    final write = lib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>(
      'WritePrinter');
    final endPage = lib.lookupFunction<Int32 Function(IntPtr),
        int Function(int)>('EndPagePrinter');
    final endDoc = lib.lookupFunction<Int32 Function(IntPtr),
        int Function(int)>('EndDocPrinter');
    final close = lib.lookupFunction<Int32 Function(IntPtr),
        int Function(int)>('ClosePrinter');

    final hPrinter = calloc<IntPtr>();
    final nameW = _w(printerName);
    try {
      final ok = open(nameW, hPrinter, nullptr);
      if (ok == 0 || hPrinter.value == 0) {
        throw StateError('Windows could not open "$printerName" — check it exists in Printers & scanners.');
      }
      final h = hPrinter.value;
      // DOC_INFO_1W { LPWSTR pDocName; LPWSTR pOutputFile; LPWSTR pDatatype }
      final docInfo = calloc<Uint8>(24);
      final docNameW = _w(docName);
      final typeW = _w('RAW');
      try {
        docInfo.cast<Pointer<Uint16>>().value = docNameW;
        docInfo.cast<Pointer<Uint16>>().elementAt(1).value = nullptr.cast<Uint16>();
        docInfo.cast<Pointer<Uint16>>().elementAt(2).value = typeW.cast<Uint16>();
        final jobId = startDoc(h, 1, docInfo);
        if (jobId == 0) {
          close(h);
          throw StateError('Windows refused the print job for "$printerName".');
        }
        var buffer = calloc<Uint8>(data.length);
        final written = calloc<Uint32>();
        try {
          buffer.asTypedList(data.length).setAll(0, data);
          if (startPage(h) == 0 ||
              write(h, buffer, data.length, written) == 0) {
            throw StateError('Printing to "$printerName" failed mid-job.');
          }
        } finally {
          calloc.free(buffer);
          calloc.free(written);
        }
        endPage(h);
        endDoc(h);
      } finally {
        calloc.free(docInfo);
        calloc.free(docNameW);
        calloc.free(typeW);
        close(h);
      }
    } finally {
      calloc.free(hPrinter);
      calloc.free(nameW);
    }
  }
}
