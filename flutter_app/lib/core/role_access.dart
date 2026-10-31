import '../models/models.dart';
import 'lan_policy.dart';

/// Plan/license gating (v1.1.59). Runs after RoleAccess, on Main for remote
/// commands and locally for this device. Legacy keys (allOn) allow
/// everything, so behaviour is unchanged unless a plan restricts the key.
class StoreGuard {
  static const _gatedCommands = {
    'logWastage': 'wastage',
    'deleteWastage': 'wastage',
    'upsertSupplier': 'purchases',
    'deleteSupplier': 'purchases',
    'upsertPurchase': 'purchases',
    'receivePurchase': 'purchases',
    'cancelPurchase': 'purchases',
    'setQrOrdering': 'qr_ordering',
    'setQrFireOn': 'qr_ordering',
    'upsertQrBrand': 'qr_branding',
  };

  static String denyReason(AppStore store, NetCommand cmd) {
    // Ticket edits are valid only while the ticket is still operational. A
    // paid/cancelled ticket must not be rewritten or silently merged into a
    // live ticket through line/patch commands (which bypass payment reversal).
    PosOrder? target(String? id) => id == null ? null : store.orderById(id);
    if ({'addLine', 'updateLine', 'removeLine', 'patchOrder', 'moveOrder', 'fireCourse'}
        .contains(cmd.name)) {
      final id = cmd.name == 'patchOrder'
          ? ((cmd.payload['order'] is Map)
              ? (cmd.payload['order'] as Map)['id']?.toString()
              : null)
          : (cmd.payload['orderId'] ?? cmd.payload['id'])?.toString();
      final order = target(id);
      if (order == null || order.status == OrderStatus.paid ||
          order.status == OrderStatus.cancelled) return 'ticket_closed';
      if (cmd.name == 'patchOrder' && cmd.payload['order'] is Map) {
        final incoming = PosOrder.fromJson(
            Map<String, dynamic>.from(cmd.payload['order'] as Map));
        if (incoming.status != order.status) return 'ticket_status';
      }
    }
    if (cmd.name == 'setOrderStatus') {
      final order = target((cmd.payload['id'] ?? cmd.payload['orderId'])?.toString());
      if (order == null) return 'ticket_missing';
      if (order.status == OrderStatus.cancelled) return 'ticket_closed';
      final next = cmd.payload['status']?.toString();
      // A paid ticket has one exceptional path: a PIN-authorized cancellation
      // that runs the reducer's refund/credit/points reversals. It cannot be
      // paid again or edited through another status payload.
      if (order.status == OrderStatus.paid && next != OrderStatus.cancelled.name) {
        return 'ticket_closed';
      }
    }
    if (cmd.name == 'mergeOrders') {
      final keep = target(cmd.payload['keepId']?.toString());
      final drop = target(cmd.payload['dropId']?.toString());
      if (keep == null || drop == null ||
          keep.status == OrderStatus.paid || keep.status == OrderStatus.cancelled ||
          drop.status == OrderStatus.paid || drop.status == OrderStatus.cancelled) {
        return 'ticket_closed';
      }
    }
    if (cmd.name == 'setDelivery') {
      final order = target(cmd.payload['orderId']?.toString());
      if (order == null || order.type != OrderType.delivery ||
          order.status == OrderStatus.cancelled || order.status == OrderStatus.paid) {
        return 'delivery_order';
      }
    }
    // Shop shift lock is independent of the license plan — even allOn
    // keys cannot start a ticket while the shift is closed.
    if (cmd.name == 'createOrder' && store.shiftClosed) return 'shift_closed';
    final ent = store.entitlements;
    if (ent.allOn) return '';
    // Only Main may push entitlements into the shared store.
    if (cmd.name == 'setEntitlements') {
      return cmd.role == AppRole.main.name ? '' : 'forbidden';
    }
    final feature = _gatedCommands[cmd.name];
    if (feature != null && !ent.allowsFeature(feature)) return 'plan_feature';
    if (cmd.name == 'setModel') {
      final model = cmd.payload['model']?.toString() ?? '';
      if (model.isNotEmpty && !ent.allowsModel(model)) return 'plan_model';
    }
    if (cmd.name == 'seedModel') {
      final model = cmd.payload['model']?.toString() ?? '';
      if (model.isNotEmpty && !ent.allowsModel(model)) return 'plan_model';
    }
    return '';
  }

  static bool allow(AppStore store, NetCommand cmd) =>
      denyReason(store, cmd).isEmpty;

  /// Soft downgrade applied before the reducer: recipe lines ride on
  /// upsertProduct, and must simply not persist when the plan has no
  /// recipe costing. The product save itself is never blocked.
  static void sanitize(AppStore store, NetCommand cmd) {
    if (!store.entitlements.allOn &&
        !store.entitlements.allowsFeature('recipe_costing') &&
        cmd.name == 'upsertProduct') {
      final raw = cmd.payload['product'];
      if (raw is Map && (raw['recipe'] as List?)?.isNotEmpty == true) {
        raw['recipe'] = <String>[];
      }
    }
  }
}

/// What each station may do on the live shop store.
class RoleAccess {
  static bool bindDriverCommand(AppStore store, NetCommand cmd, String deviceId) {
    Driver? driver;
    for (final candidate in store.drivers) {
      if (candidate.deviceId == deviceId) {
        driver = candidate;
        break;
      }
    }
    if (driver == null) return false;
    if (cmd.name == 'setDriverStatus') {
      final status = cmd.payload['status']?.toString();
      if (!{'free', 'busy', 'offline'}.contains(status)) return false;
      cmd.payload['id'] = driver.id;
      cmd.payload['deviceId'] = deviceId;
      return true;
    }
    if (cmd.name != 'setDelivery') return false;
    final order = store.orderById(cmd.payload['orderId']?.toString());
    if (order == null || order.type != OrderType.delivery ||
        order.status == OrderStatus.paid || order.status == OrderStatus.cancelled ||
        (order.driverId != null && order.driverId != driver.id)) return false;
    final current = order.deliveryState == 'out' || order.deliveryState == 'delivered'
        ? order.deliveryState
        : 'queued';
    final expected = current == 'queued' ? 'out' : current == 'out' ? 'delivered' : '';
    if (cmd.payload['state']?.toString() != expected) return false;
    cmd.payload['driverId'] = driver.id;
    return true;
  }

  static bool allow(String roleName, NetCommand cmd) {
    final role = enumParse(AppRole.values, roleName, AppRole.none);
    if (role == AppRole.main) return true;
    if (cmd.name == 'closeDay' || cmd.name == 'openShift') {
      return role == AppRole.manager;
    }
    if (role == AppRole.manager) {
      return cmd.name != 'replaceState' &&
          cmd.name != 'seedModel' &&
          cmd.name != 'setModel';
    }
    // Empty / web dashboard on the shop LAN is the owner console.
    if (cmd.name == 'setStaffDuty') return role != AppRole.none;
    if (role == AppRole.none && (roleName.isEmpty || roleName == 'web')) {
      return kWebCommands.contains(cmd.name);
    }

    const ticketWrite = {
      'createOrder',
      'addLine',
      'updateLine',
      'removeLine',
      'patchOrder',
      'moveOrder',
      'mergeOrders',
      'fireCourse',
    };
    const kitchenStatus = {'preparing', 'ready', 'served'};
    const cashierStatus = {'open', 'preparing', 'ready', 'served', 'paid', 'cancelled'};
    const takerStatus = {'open', 'preparing', 'cancelled'};

    switch (role) {
      case AppRole.orderTaker:
        if (ticketWrite.contains(cmd.name)) return true;
        if (cmd.name == 'upsertCustomer' || cmd.name == 'deleteCustomer') return true;
        if (cmd.name == 'setOrderStatus') {
          return takerStatus.contains(cmd.payload['status']?.toString());
        }
        return false;
      case AppRole.cashier:
        if (ticketWrite.contains(cmd.name)) return true;
        if (cmd.name == 'startShift' || cmd.name == 'endShift') return true;
        if (cmd.name == 'upsertCustomer' || cmd.name == 'deleteCustomer') return true;
        if (cmd.name == 'setOrderStatus') {
          return cashierStatus.contains(cmd.payload['status']?.toString());
        }
        return false;
      case AppRole.kitchen:
        if (cmd.name != 'setOrderStatus') return false;
        return kitchenStatus.contains(cmd.payload['status']?.toString());
      case AppRole.driver:
        if (cmd.name == 'setOrderStatus' || cmd.name == 'pairDriver') {
          return false;
        }
        if (cmd.name == 'setDelivery') {
          final next = cmd.payload['state']?.toString();
          return next == 'out' || next == 'delivered';
        }
        if (cmd.name == 'setDriverStatus') {
          return {'free', 'busy', 'offline'}
              .contains(cmd.payload['status']?.toString());
        }
        return false;
      case AppRole.stockClerk:
        return cmd.name == 'upsertStock' ||
            cmd.name == 'adjustStock' ||
            cmd.name == 'deleteStock';
      case AppRole.frontDesk:
        if (cmd.name == 'upsertCustomer' || cmd.name == 'deleteCustomer') return true;
        if (ticketWrite.contains(cmd.name)) return true;
        if (cmd.name == 'setOrderStatus') {
          return cashierStatus.contains(cmd.payload['status']?.toString());
        }
        return cmd.name == 'upsertAppointment' || cmd.name == 'deleteAppointment';
      case AppRole.specialist:
        return cmd.name == 'upsertAppointment';
      case AppRole.none:
        return kWebCommands.contains(cmd.name);
      case AppRole.main:
        return true;
      case AppRole.manager:
        return cmd.name != 'replaceState' &&
            cmd.name != 'seedModel' &&
            cmd.name != 'setModel';
    }
  }
}

/// v1.1.93 — demo-mode guard. The license-screen demo is a guided look-around
/// over seeded sample data, never a free POS: hard cap on live orders so it
/// can't run a shift, and receipts never touch paper (PrintService.demoBlock).
/// Demo state resets fully on exit, so nothing here ever touches real shops.
class DemoGuard {
  DemoGuard._();

  /// Max orders (any status) the demo shop may hold at once.
  static const int maxOrders = 10;

  /// Returns a notice for the UI when the demo refuses a command, else null.
  static AppNotice? deny(AppStore store, NetCommand cmd) {
    if (cmd.name == 'createOrder' && store.orders.length >= maxOrders) {
      return AppNotice(
        id: newId(),
        title: 'Demo limit reached',
        body: 'The demo holds $maxOrders tickets. Exit the demo and activate a license for the real shop.',
        kind: 'demo',
      );
    }
    return null;
  }
}
