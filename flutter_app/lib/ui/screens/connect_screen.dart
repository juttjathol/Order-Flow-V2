import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/barcode_scan.dart';
import '../widgets/common.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final ip = TextEditingController();
  final driverName = TextEditingController();
  bool asDriver = false;

  @override
  void dispose() {
    ip.dispose();
    driverName.dispose();
    super.dispose();
  }

  String? _hostFrom(String raw) {
    var v = raw.trim();
    if (v.startsWith('orderflow://')) {
      final uri = Uri.tryParse(v);
      return uri?.queryParameters['host'];
    }
    if (v.startsWith('http://') || v.startsWith('https://')) {
      return Uri.tryParse(v)?.host;
    }
    return v.split(':').first.split('/').first;
  }

  Future<void> _go(String host) async {
    final s = L10n(ref.read(appControllerProvider).session.locale);
    if (asDriver) {
      final err = await ref.ctrl.pairDriver(host, driverName.text.trim().isEmpty ? 'Driver' : driverName.text.trim());
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(err))));
      }
      return;
    }
    final err = await ref.ctrl.connectToMain(host);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(err))));
      return;
    }
    if (mounted) context.push('/role');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final snap = ref.snap;
    final dark = OfColors.isDark(context);

    return OfScaffold(
      title: s.t('connect_main'),
      subtitle: 'Multi-device POS',
      body: BusyBarrier(
        busy: snap.busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(
                color: dark ? OfColors.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: dark ? OfColors.line : const Color(0x14000000)),
                boxShadow: dark
                    ? null
                    : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: OfColors.forest.withValues(alpha: dark ? 0.35 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.devices, color: dark ? OfColors.mint : OfColors.forest, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.t('connect_main'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.t('same_wifi'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: OfColors.mute(context), height: 1.35),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final value = await scanBarcode(context, title: s.t('scan_now'), hint: s.t('manual_ip'));
                        if (!context.mounted || value == null) return;
                        final host = _hostFrom(value);
                        if (host == null || host.isEmpty) return;
                        ip.text = host;
                        _go(host);
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(s.t('scan_now')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final host = _hostFrom(ip.text);
                        if (host == null || host.isEmpty) return;
                        _go(host);
                      },
                      icon: const Icon(Icons.link),
                      label: Text(s.t('continue')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(s.t('manual_ip'), style: TextStyle(color: OfColors.mute(context), fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: ip,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: s.t('enter_ip'),
                hintText: '192.168.1.10',
                prefixIcon: const Icon(Icons.lan),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: asDriver,
              onChanged: (v) => setState(() => asDriver = v),
              title: Text(s.t('role_driver')),
              subtitle: Text(s.t('role_driver_hint')),
            ),
            if (asDriver)
              TextField(
                controller: driverName,
                decoration: InputDecoration(labelText: s.t('your_name')),
              ),
            if (snap.error != null && snap.error != 'queued_offline')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.t(snap.error!), style: const TextStyle(color: OfColors.danger)),
              ),
            if (snap.connected) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OfColors.mint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: OfColors.mint),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.t('connected'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
