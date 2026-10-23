// Pure-Dart logger (no Flutter): logs only when asserts are enabled, which
// matches Flutter's kDebugMode and stays silent in release / compiled servers.
// ignore_for_file: avoid_print

class AppLogger {
  static bool get _enabled {
    var on = false;
    assert(on = true);
    return on;
  }

  static void d(String tag, String message) {
    if (_enabled) print('[$tag] $message');
  }

  static void e(String tag, String message,
      [Object? error, StackTrace? stack]) {
    if (_enabled) {
      print('[$tag] ERROR: $message');
      if (error != null) print('  Error: $error');
      if (stack != null) print('  Stack: $stack');
    }
  }

  static void w(String tag, String message) {
    if (_enabled) print('[$tag] WARN: $message');
  }
}
