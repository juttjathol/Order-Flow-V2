// Tripwires for the two silent-breakage classes the v1.1.67 audit found:
//  1. a t('key') whose copy exists in only one language — English users saw
//     raw snake_case keys (staff_pin!), Urdu users saw English leaking in.
//  2. a NetCommand name some screen sends that StoreReducer never handles —
//     such a command vanishes silently: no crash, just a dead button.
// The scans mirror the lib/ tree at test time; flutter test runs with the
// package root as cwd (same assumption as app_version_sync_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _mapBody(String src, String marker) {
  final m = RegExp("static const $marker = \\{").firstMatch(src);
  expect(m, isNotNull, reason: 'l10n map $marker not found');
  final start = src.indexOf('{', m!.start);
  var depth = 0, i = start;
  String? q;
  while (i < src.length) {
    final c = src[i];
    if (q != null) {
      if (c == '\\') {
        i += 2;
        continue;
      }
      if (c == q) q = null;
    } else if (c == "'" || c == '"') {
      q = c;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) break;
    }
    i++;
  }
  return src.substring(start, i);
}

Set<String> _keys(String body) => RegExp(r"^\s+'([A-Za-z0-9_]+)'\s*:",
        multiLine: true)
    .allMatches(body)
    .map((e) => e.group(1)!)
    .toSet();

List<String> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.path)
    .toList();

void main() {
  test('every t(\'key\') literal resolves in BOTH English and Urdu', () {
    final l10n = File('lib/core/l10n.dart').readAsStringSync();
    final en = _keys(_mapBody(l10n, '_en'));
    final ur = _keys(_mapBody(l10n, '_ur'));
    final used = <String, String>{};
    for (final p in _dartFiles('lib')) {
      if (p.endsWith('l10n.dart')) continue;
      final src = File(p).readAsStringSync();
      for (final m in RegExp(r"\.t\(\s*'([A-Za-z0-9_]+)'\s*\)")
          .allMatches(src)) {
        used.putIfAbsent(m.group(1)!, () => p);
      }
    }
    expect(used.isNotEmpty, isTrue, reason: 'scan found no keys — regex broke');
    final missEn = used.keys.where((k) => !en.contains(k)).toList()..sort();
    final missUr = used.keys.where((k) => !ur.contains(k)).toList()..sort();
    expect(missEn, isEmpty,
        reason: 'keys raw-rendered in English UI: '
            '${missEn.map((k) => '$k (${used[k]})').join(', ')}');
    expect(missUr, isEmpty,
        reason: 'keys leaking English into Urdu UI: '
            '${missUr.map((k) => '$k (${used[k]})').join(', ')}');
  });

  test('dynamically-built key prefixes are complete in both languages', () {
    final l10n = File('lib/core/l10n.dart').readAsStringSync();
    final en = _keys(_mapBody(l10n, '_en'));
    final ur = _keys(_mapBody(l10n, '_ur'));
    // t('duty_${duty.name}') — keep this list in step with StaffDuty.
    const duty = ['onShift', 'offline', 'teaBreak', 'mealBreak'];
    const courses = ['starter', 'main', 'side', 'drink', 'dessert'];
    const cloudErrors = [
      'cloud_unreachable', 'plan', 'server', 'bad_pairing', 'join_failed',
      'not_main', 'is_main', 'no_license', 'plan_feature',
    ];
    for (final lang in {en, ur}) {
      for (final d in duty) {
        expect(lang, contains('duty_$d'), reason: 'duty_$d missing');
      }
      for (final c in courses) {
        expect(lang, contains('course_$c'), reason: 'course_$c missing');
      }
      for (final e in cloudErrors) {
        expect(lang, contains('cloud_err_$e'), reason: 'cloud_err_$e missing');
      }
    }
  });

  test('every NetCommand name sent by the UI is handled by the reducer', () {
    final reducer = File('lib/models/reducer.dart').readAsStringSync();
    final handled =
        RegExp(r"case\s+'([A-Za-z_]\w*)'").allMatches(reducer).map((e) => e.group(1)!).toSet();
    // Names the transport layers recognise without a reducer case.
    const transport = {'hello', 'state', 'cmd', 'notice', 'ping', 'sync'};
    final missing = <String>[];
    final re2 = RegExp(r"NetCommand\s*\(([^;]{0,400}?)\)\s*;", dotAll: true);
    for (final p in _dartFiles('lib')) {
      if (p.endsWith('reducer.dart')) continue;
      final src = File(p).readAsStringSync();
      for (final m in re2.allMatches(src)) {
        final n = RegExp(r"name:\s*'([A-Za-z_][A-Za-z0-9_]*)'")
            .firstMatch(m.group(1)!);
        if (n == null) continue;
        final name = n.group(1)!;
        if (!handled.contains(name) && !transport.contains(name)) {
          missing.add('$name ($p)');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'commands that would silently do nothing: $missing');
  });
}
