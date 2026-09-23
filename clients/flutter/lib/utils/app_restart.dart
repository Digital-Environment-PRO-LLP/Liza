import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class AppRestart {
  static void restart() {
    if (kIsWeb) {
      // Web: handled separately with dart:html in call site if needed.
      // This branch exists for completeness; on web, prefer
      // html.window.location.reload() directly.
      return;
    }
    if (Platform.isAndroid) {
      SystemNavigator.pop();
      return;
    }
    // Desktop & iOS: exit the process. The OS restarts on next user tap.
    exit(0);
  }
}
