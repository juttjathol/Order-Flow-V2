import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/platform_check.dart';
import 'services/storage_service.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await StorageService.open();
  // Desktop only: guarantee the process really dies with the window —
  // a ghost order_flow.exe in Task Manager holds the LAN port and makes
  // ZIP re-extraction fail with "folder in use". Phones are untouched.
  if (OfPlatform.isDesktop) {
    WidgetsBinding.instance.addObserver(const _DesktopCloseGuard());
  }
  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
      ],
      child: const OrderFlowApp(),
    ),
  );
}

class _DesktopCloseGuard extends WidgetsBindingObserver {
  const _DesktopCloseGuard();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && OfPlatform.isDesktop) {
      // Synchronous exit: the LAN server, relays and sockets die with the
      // process. Stations already handle a gone-Main (queue & resync).
      exit(0);
    }
  }
}
