import '../models/models.dart';

/// What each station may do on the live shop store.
class RoleAccess {
  static bool allow(String roleName, NetCommand cmd) {
    final role = enumParse(AppRole.values, roleName, AppRole.none);
    if (role == AppRole.main) return true;
    if (cmd.name == 'closeDay') return false;
    // Empty / web dashboard on the shop LAN is the owner console.
    if (role == AppRole.none && (roleName.isEmpty || roleName == 'web')) {
      return true;
    }

    const ticketWrite = {
      'createOrder',
      'addLine',
      'updateLine',
      'removeLine',
      'patchOrder',
    };
    const kitchenStatus = {'preparing', 'ready', 'served'};
    const cashierStatus = {'open', 'preparing', 'ready', 'served', 'paid', 'cancelled'};
    const takerStatus = {'open', 'preparing', 'cancelled'};

    switch (role) {
      case AppRole.orderTaker:
        if (ticketWrite.contains(cmd.name)) return true;
        if (cmd.name == 'setOrderStatus') {
          return takerStatus.contains(cmd.payload['status']?.toString());
        }
        return false;
      case AppRole.cashier:
        if (ticketWrite.contains(cmd.name)) return true;
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
    }
  }
}
