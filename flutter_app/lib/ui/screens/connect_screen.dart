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
    return OfScaffold(
      title: s.t('connect_main'),
      body: BusyBarrier(
        busy: snap.busy,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.t('same_wifi')),
                  const SizedBox(height: 6),
                  Text(s.t('manual_ip'), style: const TextStyle(color: OfColors.muted)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ip,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: s.t('enter_ip'),
                      hintText: '192.168.1.10',
                      prefixIcon: const Icon(Icons.lan),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
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
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      final host = _hostFrom(ip.text);
                      if (host == null || host.isEmpty) return;
                      _go(host);
                    },
                    icon: const Icon(Icons.link),
                    label: Text(s.t('continue')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => scan = !scan),
                    icon: Icon(scan ? Icons.close : Icons.qr_code_scanner),
                    label: Text(scan ? s.t('stop_scan') : s.t('scan_now')),
                  ),
                ],
              ),
            ),
            if (scan)
              SizedBox(
                height: 280,
                child: ShopCameraScan(
                  onCode: (value) {
                    final host = _hostFrom(value);
                    if (host == null || host.isEmpty) return;
                    setState(() => scan = false);
                    ip.text = host;
                    _go(host);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
