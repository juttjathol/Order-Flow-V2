import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:order_flow_app/core/constants.dart';

/// v1.1.66 · The More-screen footer prints kAppVersion — a hand-maintained
/// constant. Releases 1.1.62–1.1.65 bumped pubspec but not it, so every
/// phone kept showing "Version 1.1.61". This test is the tripwire: any CI
/// release where the two versions disagree fails before the APK is built.
void main() {
  test('kAppVersion matches the pubspec version', () {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final versionLine =
        lines.firstWhere((l) => l.trimLeft().startsWith('version:'), orElse: () => '');
    final pubspecVersion =
        versionLine.split(':').last.trim().split('+').first.trim();
    expect(pubspecVersion, isNotEmpty, reason: 'pubspec.yaml version line missing');
    expect(kAppVersion, pubspecVersion,
        reason: 'Bump kAppVersion in lib/core/constants.dart to match pubspec on every release');
  });
}
