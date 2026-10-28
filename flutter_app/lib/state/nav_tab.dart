import 'package:flutter/foundation.dart';

/// Shared main-shell tab index (0 home, 1 floor/register/queue, 2 menu/services,
/// 3 stock, 4 more). MainShell listens to this so overlays such as the guided
/// tour can hop to the tab that owns the highlighted control without prop
/// drilling or circular imports.
final ValueNotifier<int> mainTabIndex = ValueNotifier<int>(0);
