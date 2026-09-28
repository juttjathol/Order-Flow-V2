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

/// A browser may only talk to Main by IP literal (or localhost).
///
/// v1.1.83 security: `origin == 'http://$host'` on its own is the classic
/// DNS-rebinding hole — an attacker's page at `http://shop.evil` can make the
/// victim's browser resolve `shop.evil` to the Main device's LAN IP, and then
/// BOTH the Origin and the Host header read `shop.evil:8787`, so the old check
/// passed and the page could read the whole store and issue web commands with
/// the token that `/` hands out. Requiring an IP-literal authority kills that:
/// real guests and the owner console always use `http://<lan-ip>:8787`.
/// Native apps send no Origin at all and are unaffected.
bool authorityIsIpLiteral(String host) {
  var h = host.trim();
  if (h.isEmpty) return false;
  if (h.startsWith('[')) return h.contains(']'); // IPv6 literal, e.g. [::1]:8787
  final colon = h.lastIndexOf(':');
  if (colon > 0) {
    final port = h.substring(colon + 1);
    if (port.isNotEmpty && port.split('').every((c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)) {
      h = h.substring(0, colon);
    }
  }
  h = h.toLowerCase();
  if (h == 'localhost') return true;
  final parts = h.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    for (final c in part.codeUnits) {
      if (c < 48 || c > 57) return false;
    }
    if (int.tryParse(part) == null) return false;
  }
  return true;
}

bool corsOriginOk(String? origin, String? host) {
  if (origin == null || origin.isEmpty) return true;
  if (host == null || host.isEmpty) return false;
  if (origin != 'http://$host') return false;
  return authorityIsIpLiteral(host);
}

bool isPrivileged(String name, String role) {
  if (!kPrivilegedCommands.contains(name)) return false;
  if (role == 'main') return false;
  if (name == 'setModel' && role == 'web') return false;
  return true;
}
