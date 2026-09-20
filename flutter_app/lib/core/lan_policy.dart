import '../models/models_enums.dart';

/// Commands the in-app owner web console actually sends.
const kWebCommands = <String>{
  'createOrder',
  'addLine',
  'setOrderStatus',
  'setProfile',
  'upsertProduct',
  'setModel',
};

/// Never accepted from a station role (or from the cloud unless role is main).
const kPrivilegedCommands = <String>{
  'replaceState',
  'setEntitlements',
  'seedModel',
  'setModel',
};

const kHelloRoles = <String>{
  'web',
  'manager',
  'orderTaker',
  'kitchen',
  'cashier',
  'driver',
  'stockClerk',
  'frontDesk',
  'specialist',
};

bool helloRoleOk(String role) {
  if (role.isEmpty || role == 'main' || role == 'none') return false;
  if (kHelloRoles.contains(role)) return true;
  for (final r in AppRole.values) {
    if (r != AppRole.none && r != AppRole.main && r.name == role) return true;
  }
  return false;
}

bool corsOriginOk(String? origin, String? host) {
  if (origin == null || origin.isEmpty) return true;
  if (host == null || host.isEmpty) return false;
  return origin == 'http://$host';
}

bool isPrivileged(String name, String role) {
  if (!kPrivilegedCommands.contains(name)) return false;
  if (role == 'main') return false;
  if (name == 'setModel' && role == 'web') return false;
  return true;
}
