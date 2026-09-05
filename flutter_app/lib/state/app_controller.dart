import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/l10n.dart';
import '../core/role_access.dart';
import '../models/models.dart';
import '../models/reducer.dart';
import '../models/seed.dart';
import '../services/backup_service.dart';
import '../services/lan_client.dart';
import '../services/lan_server.dart';
import '../services/license_service.dart';
import '../services/print_service.dart';
import '../services/shop_keepalive.dart';
import '../services/storage_service.dart';

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('storageProvider must be overridden');
});

final appControllerProvider =
    NotifierProvider<AppController, AppSnapshot>(AppController.new);

class AppSnapshot {
  AppSnapshot({
    required this.ready,
    required this.session,
    required this.store,
    required this.gate,
    required this.serverOn,
    required this.connected,
    required this.lanIp,
    required this.busy,
    required this.error,
    required this.notices,
    required this.online,
    required this.clients,
    required this.pendingSync,
  });

  final bool ready;
  final SessionPrefs session;
  final AppStore store;
  final LicenseGate gate;
  final bool serverOn;
  final bool connected;
  final String? lanIp;
  final bool busy;
  final String? error;
  final List<AppNotice> notices;
  final bool online;
  final List<ClientInfo> clients;
  final int pendingSync;

  L10nView get l10n => L10nView(session.locale);
  String get currency => store.profile.currencySymbol;
  bool get currencyPrefix => store.profile.currencyPrefix;

  /// Plan-gated feature check (v1.1.59). Always true for legacy keys.
  bool canFeature(String key) => store.entitlements.allowsFeature(key);
  bool canModel(BusinessModel model) =>
      store.entitlements.allowsModel(model.name);
  String get planLabel => store.entitlements.planLabel;
  bool get planLimited => !store.entitlements.allOn;

  bool get isMain => session.role == AppRole.main;
  bool get isManager => session.role == AppRole.manager;
  bool get isClient =>
      session.role != AppRole.none && session.role != AppRole.main;

  AppSnapshot copyWith({
    bool? ready,
    SessionPrefs? session,
    AppStore? store,
    LicenseGate? gate,
    bool? serverOn,
    bool? connected,
    String? lanIp,
    bool? busy,
    String? error,
    List<AppNotice>? notices,
    bool? online,
    List<ClientInfo>? clients,
    int? pendingSync,
    bool clearError = false,
    bool clearIp = false,
  }) {
    return AppSnapshot(
      ready: ready ?? this.ready,
      session: session ?? this.session,
      store: store ?? this.store,
      gate: gate ?? this.gate,
      serverOn: serverOn ?? this.serverOn,
      connected: connected ?? this.connected,
      lanIp: clearIp ? lanIp : (lanIp ?? this.lanIp),
      busy: busy ?? this.busy,
      error: clearError ? error : (error ?? this.error),
      notices: notices ?? this.notices,
      online: online ?? this.online,
      clients: clients ?? this.clients,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}

class L10nView {
  L10nView(this.code);
  final String code;

  /// Translation access for snapshot consumers (`snap.l10n.t(key)`).
  String t(String key) => L10n(code).t(key);
  bool get isUrdu => code == 'ur';
}

class AppController extends Notifier<AppSnapshot> {
  late StorageService _storage;
  final _license = LicenseService();
  final printer = PrintService();
  LanServer? _server;
  LanClient? _client;
  Timer? _revalidate;
  Timer? _ipTimer;
  StreamSubscription? _netSub;
  Timer? _saveTimer;
  Timer? _flushTimer;
  final _queue = <NetCommand>[];
  final _seenIds = <String>{};
  bool _booted = false;
  bool _flushing = false;
  bool _reconnecting = false;

  @override
  AppSnapshot build() {
    _storage = ref.read(storageProvider);
    ref.onDispose(() {
      _revalidate?.cancel();
      _ipTimer?.cancel();
      _saveTimer?.cancel();
      _flushTimer?.cancel();
      _netSub?.cancel();
      unawaited(_server?.stop());
      unawaited(_client?.close());
      unawaited(ShopKeepAlive.stop());
    });
    Future.microtask(bootstrap);
    return AppSnapshot(
      ready: false,
      session: SessionPrefs(),
      store: AppStore(),
      gate: LicenseGate.boot,
      serverOn: false,
      connected: false,
      lanIp: null,
      busy: true,
      error: null,
      notices: const [],
      online: true,
      clients: const [],
      pendingSync: _queue.length,
    );
  }

  Future<void> bootstrap() async {
    if (_booted) return;
    _booted = true;
    _queue
      ..clear()
      ..addAll(_storage.loadQueue());
    _seenIds
      ..clear()
      ..addAll(_storage.loadSeenIds());
    final started = DateTime.now();
    final session = _storage.loadSession();
    final store = await _storage.loadStore();
    final remain = const Duration(milliseconds: 1000) -
        DateTime.now().difference(started);
    if (remain > Duration.zero) await Future.delayed(remain);
    state = state.copyWith(
      ready: true,
      session: session,
      store: store,
      gate: _computeGate(session),
      busy: false,
      pendingSync: _queue.length,
      clearError: true,
    );
    _netSub = Connectivity().onConnectivityChanged.listen((events) {
      final online = events.any((e) => e != ConnectivityResult.none);
      state = state.copyWith(online: online);
      if (online && session.role == AppRole.main && session.license.valid) {
        unawaited(revalidate());
      }
    });
    if (session.role == AppRole.main &&
        session.license.valid &&
        !session.license.locked) {
      await startServer();
      unawaited(revalidate());
      unawaited(_syncEntitlements());
    } else if (session.role == AppRole.driver && session.pairedDriverId != null) {
      if (session.mainHost.isNotEmpty) {
        unawaited(_tryDriverSync());
      }
    } else if (_clientLike(session) && session.mainHost.isNotEmpty) {
      unawaited(connectToMain(session.mainHost, persist: false));
    }
    _revalidate = Timer.periodic(
      const Duration(minutes: kRevalidateMinutes),
      (_) => revalidate(),
    );
    _ipTimer = Timer.periodic(const Duration(seconds: 20), (_) => refreshIp());
    _flushTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_keepStationSynced());
    });
    await refreshIp();
    unawaited(_keepStationSynced());
  }

  bool _clientLike(SessionPrefs session) =>
      session.role != AppRole.none &&
      session.role != AppRole.main &&
      session.role != AppRole.driver;

  LicenseGate _computeGate(SessionPrefs session) {
    if (session.license.locked) return LicenseGate.locked;
    if (session.role == AppRole.none) return LicenseGate.license;
    if (session.role == AppRole.main) {
      if (!session.license.valid) return LicenseGate.license;
      if (!session.modelPicked) return LicenseGate.setup;
      return LicenseGate.ready;
    }
    if (session.role == AppRole.driver && session.pairedDriverId != null) {
      return LicenseGate.ready;
    }
    if (session.mainHost.isEmpty) return LicenseGate.license;
    return LicenseGate.ready;
  }

  Future<void> persist() async {
    await _storage.saveSession(state.session);
    await _storage.saveStore(state.store);
  }

  void _schedulePersist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(persist());
    });
  }

  void _emit(AppSnapshot next) {
    state = next;
    _schedulePersist();
  }

  Future<void> setLocale(String code) async {
    state.session.locale = code;
    _emit(state.copyWith(session: state.session));
  }

  Future<void> setTheme(ThemeChoice theme) async {
    state.session.theme = theme;
    _emit(state.copyWith(session: state.session));
  }

  /// The printer attached to THIS device (station or Main): LAN first,
  /// then Bluetooth. Falls back to null so shop-level targets apply.
  PrinterConfig? deviceLocalPrinter() {
    final s = state.session;
    if (s.hasLocalNetPrinter) {
      return PrinterConfig(
        name: 'LAN printer',
        enabled: true,
        transport: 'lan',
        host: s.localNetHost.trim(),
        port: s.localNetPort,
      );
    }
    if (s.hasLocalBtPrinter) {
      return PrinterConfig(
        name: s.localBtName.trim().isEmpty ? 'Bluetooth printer' : s.localBtName.trim(),
        enabled: true,
        transport: 'bluetooth',
        btAddress: s.localBtAddress.trim(),
        btName: s.localBtName.trim(),
      );
    }
    return null;
  }

  /// Printer this device uses for receipts / drawer kicks.
  PrinterConfig localReceiptTarget() =>
      deviceLocalPrinter() ?? state.store.receiptTarget(state.session.role);

  Future<void> setLocalBluetoothPrinter({
    required String address,
    String name = '',
    bool enabled = true,
  }) async {
    state.session.localBtAddress = address.trim();
    state.session.localBtName = name.trim();
    state.session.localBtEnabled = enabled && address.trim().isNotEmpty;
    if (state.session.localBtEnabled) {
      state.session.localNetEnabled = false;
    }
    _emit(state.copyWith(session: state.session));
    await persist();
  }

  Future<void> setLocalLanPrinter({
    required String host,
    int port = kEscPosPort,
    bool enabled = true,
  }) async {
    state.session.localNetHost = host.trim();
    state.session.localNetPort = port <= 0 ? kEscPosPort : port;
    state.session.localNetEnabled = enabled && host.trim().isNotEmpty;
    if (state.session.localNetEnabled) {
      state.session.localBtEnabled = false;
    }
    _emit(state.copyWith(session: state.session));
    await persist();
  }

  Future<void> clearLocalBluetoothPrinter() async {
    state.session.localBtAddress = '';
    state.session.localBtName = '';
    state.session.localBtEnabled = false;
    state.session.localNetHost = '';
    state.session.localNetPort = kEscPosPort;
    state.session.localNetEnabled = false;
    _emit(state.copyWith(session: state.session));
    await persist();
  }

  /// Kicks the cash drawer on the device-local receipt printer
  /// (or the shop receipt printer when this device has none).
  Future<void> openDrawer() async {
    await printer.openDrawer(localReceiptTarget());
  }

  Future<void> setDrawerAuto(bool on) async {
    await dispatch(NetCommand(name: 'setDrawer', payload: {'on': on}));
  }

  /// Shares a plain-text receipt via the Android share sheet
  /// (WhatsApp, SMS, email, …).
  Future<void> shareReceipt(PosOrder order) async {
    final text = printer.receiptText(state.store, order);
    await Share.share(text);
  }

  Future<void> setApiBase(String url) async {
    state.session.apiBase = url.trim();
    _emit(state.copyWith(session: state.session));
  }

  Future<void> setDisplayName(String name) async {
    state.session.displayName = name.trim();
    _emit(state.copyWith(session: state.session));
  }

  Future<String?> activateLicense(String key) async {
    state = state.copyWith(busy: true, clearError: true, error: null);
    state.session.license.key = key.trim();
    final result = await _license.validate(
      apiBase: kDefaultApiBase,
      licenseKey: key,
      deviceId: state.session.deviceId,
    );
    if (result.boundOther) {
      state = state.copyWith(busy: false, error: 'bound_other');
      return 'bound_other';
    }
    final rec = _license.applyOnlineResult(state.session.license, result);
    state.session.license = rec;
    if (rec.locked) {
      state.session.role = AppRole.main;
      _emit(state.copyWith(
        session: state.session,
        gate: LicenseGate.locked,
        busy: false,
        error: rec.lockReason,
      ));
      return rec.lockReason;
    }
    if (!rec.valid) {
      _emit(state.copyWith(
        session: state.session,
        busy: false,
        error: result.error.isEmpty ? 'key_invalid' : result.error,
      ));
      return state.error;
    }
    state.session.role = AppRole.main;
    state.session.modelPicked = state.store.seeded;
    _emit(state.copyWith(
      session: state.session,
      gate: state.store.seeded ? LicenseGate.ready : LicenseGate.setup,
      busy: false,
    ));
    await startServer();
    await _syncEntitlements();
    return null;
  }

  Future<void> revalidate() async {
    final session = state.session;
    if (session.role != AppRole.main || session.license.key.isEmpty) return;
    if (session.license.locked) {
      _emit(state.copyWith(gate: LicenseGate.locked));
      return;
    }
    final result = await _license.validate(
      apiBase: kDefaultApiBase,
      licenseKey: session.license.key,
      deviceId: session.deviceId,
    );
    final rec = _license.applyOnlineResult(session.license, result);
    session.license = rec;
    if (rec.locked) {
      await _server?.stop();
      _server = null;
      await ShopKeepAlive.stop();
      _emit(state.copyWith(
        session: session,
        gate: LicenseGate.locked,
        serverOn: false,
      ));
      return;
    }
    if (!rec.valid && !rec.inGrace) {
      await _server?.stop();
      _server = null;
      await ShopKeepAlive.stop();
      _emit(state.copyWith(
        session: session,
        gate: LicenseGate.license,
        serverOn: false,
        error: 'offline_expired',
      ));
      return;
    }
    _emit(state.copyWith(session: session, gate: _computeGate(session)));
    unawaited(_syncEntitlements());
  }

  Future<void> pickModel(BusinessModel model) async {
    if (!state.store.entitlements.allowsModel(model.name)) {
      state = state.copyWith(error: 'plan_model');
      return;
    }
    if (!state.store.seeded) {
      seedFor(model, state.store);
    } else {
      state.store.model = model;
    }
    state.session.modelPicked = true;
    _emit(state.copyWith(
      store: state.store,
      session: state.session,
      gate: LicenseGate.ready,
    ));
    _server?.broadcastState();
  }

  Future<void> changeBusinessModel(BusinessModel model) async {
    if (!state.isMain) return;
    if (!state.store.entitlements.allowsModel(model.name)) {
      state = state.copyWith(error: 'plan_model');
      return;
    }
    await dispatch(NetCommand(name: 'setModel', payload: {'model': model.name}));
  }

  Future<void> setQrOrdering(bool on) async {
    if (!state.store.canFeature('qr_ordering')) {
      state = state.copyWith(error: 'plan_feature');
      return;
    }
    await dispatch(NetCommand(name: 'setQrOrdering', payload: {'on': on}));
  }

  /// Main pushes license plan data into the shared store so every station
  /// and the LAN server enforce the same limits. No-op for other roles.
  Future<void> _syncEntitlements() async {
    if (!state.isMain) return;
    final lic = state.session.license;
    if (!lic.valid && !lic.inGrace) return;
    final next = lic.entitlements;
    if (state.store.entitlements.sameAs(next)) return;
    await dispatch(NetCommand(
      name: 'setEntitlements',
      payload: {'entitlements': next.toJson()},
    ));
  }

  bool _stationPlanBlocked = false;
  bool get stationPlanBlocked => _stationPlanBlocked;
  void clearStationPlanBlock() => _stationPlanBlocked = false;

  Future<void> startServer() async {
    if (state.session.license.locked) return;
    if (!state.session.license.valid && !state.session.license.inGrace) return;
    _server ??= LanServer(
      readStore: () => state.store,
      onCommand: _localApply,
    );
    try {
      await _server!.start(port: kLanPort);
      state = state.copyWith(serverOn: true, clients: _server!.clients.values.toList());
      await ShopKeepAlive.start(
        title: state.store.profile.businessName.isEmpty ? kBrandName : state.store.profile.businessName,
        text: 'Shop server · port $kLanPort',
      );
      await refreshIp();
    } catch (e) {
      await ShopKeepAlive.stop();
      state = state.copyWith(error: e.toString(), serverOn: false);
    }
  }

  ReduceResult _localApply(NetCommand cmd) {
    if (!RoleAccess.allow(cmd.role, cmd)) {
      return ReduceResult(state.store);
    }
    // Plan gating (v1.1.59): Main's license limits apply on every device.
    if (StoreGuard.denyReason(state.store, cmd).isNotEmpty) {
      return ReduceResult(state.store);
    }
    StoreGuard.sanitize(state.store, cmd);
    if (cmd.id.isNotEmpty && _seenIds.contains(cmd.id)) {
      return ReduceResult(state.store);
    }
    if (cmd.id.isNotEmpty) {
      _seenIds.add(cmd.id);
      if (_seenIds.length > 500) {
        final extra = _seenIds.length - 400;
        _seenIds.removeAll(_seenIds.take(extra).toList());
      }
      unawaited(_storage.saveSeenIds(_seenIds));
    }
    final result = StoreReducer.apply(state.store, cmd);
    // A restored/replaced store must never resurrect plan data baked into an
    // old backup — the live license stays the single source of truth (v1.1.59).
    if (cmd.name == 'replaceState') {
      final lic = state.session.license;
      if (lic.valid || lic.inGrace) {
        result.store.entitlements = lic.entitlements;
      }
    }
    state = state.copyWith(
      store: result.store,
      notices: result.notice == null
          ? state.notices
          : [result.notice!, ...state.notices].take(20).toList(),
      clients: _server?.clients.values.toList() ?? state.clients,
    );
    _schedulePersist();
    if (result.notice != null) {
      unawaited(ShopKeepAlive.alert(title: result.notice!.title, text: result.notice!.body));
      if (result.notice!.kind == 'kitchen' && result.notice!.orderId != null) {
        unawaited(_autoKitchenPrint(result.notice!.orderId!));
      }
    }
    return result;
  }

  NetCommand _stamp(NetCommand cmd) {
    if (cmd.role.isNotEmpty) return cmd;
    return NetCommand(
      id: cmd.id,
      name: cmd.name,
      payload: cmd.payload,
      actor: cmd.actor.isEmpty ? state.session.displayName : cmd.actor,
      role: state.session.role.name,
      at: cmd.at,
    );
  }

  Future<void> dispatch(NetCommand cmd) async {
    cmd = _stamp(cmd);
    if (state.isMain || state.session.role == AppRole.none) {
      final result = _localApply(cmd);
      _server?.broadcastState();
      if (result.notice != null) _server?.broadcastNotice(result.notice!);
      return;
    }
    _localApply(cmd);
    if (state.session.role == AppRole.driver) {
      unawaited(_tryDriverSync());
    }
    final client = _client;
    if (client == null || !state.connected) {
      _enqueue(cmd);
      return;
    }
    try {
      await client.send(cmd);
      unawaited(flushQueue());
    } catch (_) {
      _enqueue(cmd);
    }
  }

  void _enqueue(NetCommand cmd) {
    if (_queue.any((c) => c.id == cmd.id)) return;
    _queue.add(cmd);
    unawaited(_storage.saveQueue(_queue));
    state = state.copyWith(
      error: 'queued_offline',
      pendingSync: _queue.length,
    );
  }

  void _acceptRemoteStore(AppStore store) {
    if (_queue.isNotEmpty) {
      unawaited(flushQueue());
      return;
    }
    state = state.copyWith(store: store, connected: true, pendingSync: 0);
    unawaited(_storage.saveStore(store));
  }

  Future<void> flushQueue() async {
    if (_flushing || _queue.isEmpty || _client == null) return;
    _flushing = true;
    try {
      final pending = List<NetCommand>.from(_queue);
      _queue.clear();
      for (final cmd in pending) {
        try {
          await _client!.send(cmd);
        } catch (_) {
          _queue.add(cmd);
        }
      }
      await _storage.saveQueue(_queue);
      state = state.copyWith(pendingSync: _queue.length);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _keepStationSynced() async {
    if (!state.isClient && state.session.role != AppRole.driver) return;
    if (state.session.mainHost.isEmpty) return;
    if (!state.connected) {
      await _reconnectStation();
    }
    if (state.connected) {
      await flushQueue();
    }
  }

  Future<void> _reconnectStation() async {
    if (_reconnecting) return;
    final host = state.session.mainHost;
    if (host.isEmpty) return;
    _reconnecting = true;
    try {
      await connectToMain(host, persist: false, role: state.session.role, quiet: true);
    } finally {
      _reconnecting = false;
    }
  }

  String? _kitchenPrintedId;
  DateTime? _kitchenPrintedAt;

  Future<void> _autoKitchenPrint(String orderId) async {
    final now = DateTime.now();
    if (_kitchenPrintedId == orderId &&
        _kitchenPrintedAt != null &&
        now.difference(_kitchenPrintedAt!) < const Duration(seconds: 8)) {
      return;
    }
    final order = state.store.orderById(orderId);
    if (order == null || order.lines.isEmpty) return;
    _kitchenPrintedId = orderId;
    _kitchenPrintedAt = now;
    try {
      await printer.kitchenTicket(state.store, order, role: AppRole.kitchen, prefer: deviceLocalPrinter());
    } catch (_) {}
  }

  void rememberReceipt(String orderId) {
    state.session.lastReceiptOrderId = orderId;
    _schedulePersist();
  }

  Future<void> reprintLast() async {
    final id = state.session.lastReceiptOrderId;
    PosOrder? order = state.store.orderById(id);
    if (order == null) {
      for (final o in state.store.orders) {
        if (o.status == OrderStatus.paid) {
          order = o;
          break;
        }
      }
    }
    if (order == null) throw Exception('no_receipt');
    await printer.receipt(state.store, order, role: state.session.role, prefer: deviceLocalPrinter());
  }

  Future<String?> connectToMain(
    String host, {
    bool persist = true,
    AppRole? role,
    bool quiet = false,
  }) async {
    final clean = host.trim().replaceFirst(RegExp(r'^https?://'), '');
    final onlyHost = clean.split(':').first.split('/').first;
    if (onlyHost.isEmpty) return 'host_required';
    if (!quiet) {
      state = state.copyWith(busy: true, clearError: true, error: null);
    }
    await _client?.close();
    _client = LanClient(
      host: onlyHost,
      onStore: _acceptRemoteStore,
      onNotice: (notice) {
        state = state.copyWith(
          notices: [notice, ...state.notices].take(20).toList(),
        );
        unawaited(ShopKeepAlive.alert(title: notice.title, text: notice.body));
        if (notice.kind == 'kitchen' && notice.orderId != null) {
          unawaited(_autoKitchenPrint(notice.orderId!));
        }
      },
      onStatus: (up) {
        state = state.copyWith(connected: up);
        if (up) {
          _stationPlanBlocked = false;
          unawaited(flushQueue());
        }
      },
      onReject: (reason) {
        _stationPlanBlocked = true;
        state = state.copyWith(
          error: reason.isEmpty ? 'plan_stations' : reason,
        );
      },
    );
    try {
      final chosen = role ?? state.session.role;
      await _client!.connect(
        deviceId: state.session.deviceId,
        name: state.session.displayName.isEmpty ? 'Station' : state.session.displayName,
        role: chosen.name,
      );
      state.session.mainHost = onlyHost;
      if (chosen != AppRole.none && chosen != AppRole.main) {
        state.session.role = chosen;
      }
      if (persist) await _storage.saveSession(state.session);
      final ready = state.session.role != AppRole.none;
      _emit(state.copyWith(
        session: state.session,
        gate: ready ? LicenseGate.ready : LicenseGate.license,
        busy: false,
        connected: true,
        pendingSync: _queue.length,
      ));
      unawaited(flushQueue());
      return null;
    } catch (e) {
      final alreadyPaired = state.session.role != AppRole.none &&
          state.session.role != AppRole.main &&
          state.session.mainHost.isNotEmpty;
      state = state.copyWith(
        busy: false,
        error: quiet && alreadyPaired ? state.error : 'cannot_connect',
        connected: false,
        gate: alreadyPaired ? LicenseGate.ready : state.gate,
        pendingSync: _queue.length,
      );
      return 'cannot_connect';
    }
  }

  Future<String?> pairDriver(String host, String name) async {
    final err = await connectToMain(host, role: AppRole.driver);
    if (err != null) return err;
    try {
      final res = await _client!.driverCall({
        'name': 'pairDriver',
        'deviceId': state.session.deviceId,
        'name': name,
      });
      final driver = res['driver'];
      if (driver is Map && driver['id'] != null) {
        state.session.pairedDriverId = driver['id'].toString();
        state.session.displayName = name;
        state.session.role = AppRole.driver;
        _emit(state.copyWith(session: state.session, gate: LicenseGate.ready));
      }
      return null;
    } catch (e) {
      return 'cannot_connect';
    }
  }

  Future<void> _tryDriverSync() async {
    final host = state.session.mainHost;
    final id = state.session.pairedDriverId;
    if (host.isEmpty || id == null) return;
    try {
      _client ??= LanClient(
        host: host,
        onStore: _acceptRemoteStore,
        onNotice: (_) {},
        onStatus: (up) => state = state.copyWith(connected: up),
      );
      final driver = state.store.driverById(id);
      await _client!.driverCall({
        'id': id,
        'deviceId': state.session.deviceId,
        'status': driver?.status.name ?? DriverStatus.free.name,
        'name': state.session.displayName,
      });
      state = state.copyWith(connected: true);
    } catch (_) {
      state = state.copyWith(connected: false);
    }
  }

  Future<void> setDriverStatus(DriverStatus status) async {
    final id = state.session.pairedDriverId;
    if (id == null) return;
    await dispatch(NetCommand(
      name: 'setDriverStatus',
      payload: {
        'id': id,
        'deviceId': state.session.deviceId,
        'status': status.name,
        'name': state.session.displayName,
      },
      actor: state.session.displayName,
    ));
    unawaited(_tryDriverSync());
  }

  Future<void> chooseClientRole(AppRole role, String name, {String? staffId}) async {
    state.session.role = role;
    state.session.displayName = name.trim().isEmpty ? role.name : name.trim();
    state.session.staffId = staffId;
    _emit(state.copyWith(session: state.session, gate: LicenseGate.ready));
    if (staffId != null) {
      await dispatch(NetCommand(name: 'setStaffDuty', payload: {
        'id': staffId,
        'duty': StaffDuty.onShift.name,
      }));
    }
    if (state.session.mainHost.isNotEmpty) {
      await connectToMain(state.session.mainHost, role: role);
    }
  }

  Future<void> leaveRole() async {
    final sid = state.session.staffId;
    if (sid != null) {
      await dispatch(NetCommand(name: 'setStaffDuty', payload: {
        'id': sid,
        'duty': StaffDuty.offline.name,
      }));
    }
    await _server?.stop();
    await _client?.close();
    await ShopKeepAlive.stop();
    _server = null;
    _client = null;
    state.session.role = AppRole.none;
    state.session.mainHost = '';
    state.session.staffId = null;
    _emit(state.copyWith(
      session: state.session,
      gate: _computeGate(state.session),
      serverOn: false,
      connected: false,
    ));
  }

  Future<void> refreshIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      state = state.copyWith(lanIp: ip, clients: _server?.clients.values.toList());
    } catch (_) {}
  }

  void dismissNotice(String id) {
    state = state.copyWith(
      notices: state.notices.where((n) => n.id != id).toList(),
    );
  }

  void clearError() => state = state.copyWith(clearError: true, error: null);

  Future<void> importStore(AppStore store) async {
    if (!state.isMain) return;
    // Keep the license plan from the live session — an older backup must
    // never re-enable features the admin has switched off (v1.1.59).
    store.entitlements = state.store.entitlements;
    store.revision += 1;
    _emit(state.copyWith(store: store));
    _server?.broadcastState();
  }

  BackupService get backup => BackupService(_storage);

  String joinUrl() {
    final ip = state.lanIp ?? '0.0.0.0';
    return 'orderflow://join?host=$ip&port=$kLanPort';
  }
}
