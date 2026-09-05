import '../models/models.dart';

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
  static bool allow(String roleName, NetCommand cmd) {
    final role = enumParse(AppRole.values, roleName, AppRole.none);
    if (role == AppRole.main) return true;
    if (cmd.name == 'closeDay') return role == AppRole.manager;
    if (role == AppRole.manager) {
      return cmd.name != 'replaceState' &&
          cmd.name != 'seedModel' &&
          cmd.name != 'setModel';
    }
    // Empty / web dashboard on the shop LAN is the owner console.
    if (cmd.name == 'setStaffDuty') return role != AppRole.none;
    if (role == AppRole.none && (roleName.isEmpty || roleName == 'web')) {
      return true;
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
        return cmd.name == 'setOrderStatus' ||
            cmd.name == 'setDriverStatus' ||
            cmd.name == 'pairDriver';
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
        return roleName.isEmpty || roleName == 'web';
      case AppRole.main:
        return true;
      case AppRole.manager:
        return cmd.name != 'replaceState' &&
            cmd.name != 'seedModel' &&
            cmd.name != 'setModel';
    }
  }
}
