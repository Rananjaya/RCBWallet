import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:wallet/models/app_lock_provider.dart';
import 'package:wallet/models/theme_provider.dart';
import 'package:wallet/services/app_lock_service.dart';

/// Covers the whole app (including dialogs and pushed screens) with a lock
/// screen while [AppLockProvider.isLocked] is true.
///
/// The app is locked when it moves to the background (app switch, Home,
/// screen off) and the user is asked to authenticate on return. The current
/// screen stays mounted underneath, so nothing is lost.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late final AppLifecycleListener _lifecycleListener;

  /// Set when the app went to the background, so that exactly one prompt is
  /// shown automatically on return. Cancelling that prompt does not trigger
  /// another one; the user can tap Unlock instead.
  bool _promptOnResume = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onStateChange: _onStateChange);

    // Cold start: prompt once after the first frame if the app starts locked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lock = context.read<AppLockProvider>();
      if (lock.isLocked &&
          SchedulerBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) {
        lock.unlock();
      } else if (lock.isLocked) {
        _promptOnResume = true;
      }
    });
  }

  void _onStateChange(AppLifecycleState state) {
    final lock = context.read<AppLockProvider>();
    switch (state) {
      case AppLifecycleState.inactive:
        // Recents, the notification shade and system dialogs only make the
        // app inactive, so lock here too. The fingerprint/PIN prompt itself
        // also makes the app inactive; never lock for that, or the prompt
        // would cause another lock and prompt.
        if (lock.isAuthenticating) break;
        _lockForBackground(lock);
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Also reached if the user leaves the app while a prompt is open.
        // During an unlock attempt lock() is a no-op (already locked); during
        // an in-app action prompt the lock is applied if that prompt fails.
        _lockForBackground(lock);
        break;
      case AppLifecycleState.resumed:
        if (_promptOnResume) {
          _promptOnResume = false;
          if (lock.isLocked) lock.unlock();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _lockForBackground(AppLockProvider lock) {
    lock.lock();
    if (lock.isLocked) {
      FocusManager.instance.primaryFocus?.unfocus();
      _promptOnResume = true;
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = context.select<AppLockProvider, bool>((l) => l.isLocked);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the current screen alive but hidden, non-interactive and out
        // of the accessibility tree while locked.
        Offstage(
          offstage: isLocked,
          child: TickerMode(enabled: !isLocked, child: widget.child),
        ),
        if (isLocked) const _LockScreen(),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondary = isDark ? Colors.white54 : Colors.black54;
    final result = lock.lastResult;

    return Material(
      color: isDark ? Colors.black : Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFF0F0F0),
                  ),
                  child: Icon(Icons.lock_rounded, size: 44, color: textColor),
                ),
                const SizedBox(height: 28),
                Text(
                  'RCBWallet is locked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  result == null
                      ? 'Use your fingerprint, face or screen lock to continue.'
                      : AppLockService.messageFor(result),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.4, color: secondary),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: lock.authInProgress ? null : lock.unlock,
                    icon: lock.authInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint_rounded),
                    label: Text(
                      lock.authInProgress
                          ? 'Waiting for authentication…'
                          : 'Unlock',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
