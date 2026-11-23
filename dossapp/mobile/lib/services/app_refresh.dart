import 'dart:async';

import 'package:flutter/widgets.dart';

/// One app-wide signal that what is on screen may be out of date.
///
/// Screens used to load once and then wait for a manual pull to refresh, so a
/// parent who had just paid still saw "Pay now" on Home. Now every live
/// screen reloads quietly (no spinner, the old data stays up) when:
///  - something was changed from this phone ([dataChanged]),
///  - a push arrives,
///  - the app comes back to the foreground or a tab is opened ([nudge]),
///  - its own timer fires while the app is open.
class AppRefresh {
  static final ValueNotifier<int> _changed = ValueNotifier(0);
  static final ValueNotifier<int> _nudged = ValueNotifier(0);

  /// Something definitely changed: every live screen reloads now.
  static void dataChanged() => _changed.value++;

  /// A good moment to refresh: only screens with old data reload.
  static void nudge() => _nudged.value++;
}

mixin AutoRefresh<T extends StatefulWidget> on State<T> {
  /// Reload without a full-screen spinner. Must be safe to call any time.
  Future<void> silentReload();

  /// Data younger than this is left alone on a nudge.
  Duration get staleAfter => const Duration(seconds: 15);

  /// Reload this often while the app is open. Null turns the timer off.
  Duration? get refreshEvery => const Duration(seconds: 60);

  DateTime _lastReload = DateTime.now();
  bool _reloading = false;
  bool _queued = false;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    AppRefresh._changed.addListener(_onChanged);
    AppRefresh._nudged.addListener(_onNudge);
    _lifecycle = AppLifecycleListener(onResume: _onNudge);
    final every = refreshEvery;
    if (every != null) {
      _timer = Timer.periodic(every, (_) {
        // Never poll from the background
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _onNudge();
      });
    }
  }

  @override
  void dispose() {
    AppRefresh._changed.removeListener(_onChanged);
    AppRefresh._nudged.removeListener(_onNudge);
    _lifecycle?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged() => _reload(force: true);
  void _onNudge() => _reload(force: false);

  Future<void> _reload({required bool force}) async {
    if (!mounted) return;
    if (_reloading) {
      // A change landed while a reload was in flight: run once more after it
      if (force) _queued = true;
      return;
    }
    if (!force && DateTime.now().difference(_lastReload) < staleAfter) return;
    _reloading = true;
    try {
      await silentReload();
    } catch (_) {
      // The old data stays on screen; the next signal tries again
    } finally {
      _reloading = false;
      _lastReload = DateTime.now();
    }
    if (_queued && mounted) {
      _queued = false;
      _reload(force: true);
    }
  }
}
