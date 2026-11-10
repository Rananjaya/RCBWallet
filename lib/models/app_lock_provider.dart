import 'package:flutter/material.dart';
import 'package:wallet/models/startup_settings_provider.dart';
import 'package:wallet/services/app_lock_service.dart';

/// Holds the app-lock state. The app starts locked when the app lock is
/// enabled, and is locked again whenever it moves to the background.
class AppLockProvider with ChangeNotifier {
  AppLockProvider(this._settings) {
    _isLocked = _lockEnabled;
  }

  final StartupSettingsProvider _settings;

  late bool _isLocked;
  bool _authInProgress = false;
  AppAuthResult? _lastResult;

  /// Number of in-app authentication prompts (e.g. before a backup) that are
  /// currently open. The device PIN/pattern screen briefly moves the app to
  /// the background; that must not lock the app on top of the prompt.
  int _actionAuthCount = 0;

  /// Set when the app went to the background during such a prompt. The lock
  /// is applied if that prompt does not succeed.
  bool _lockPending = false;

  /// Whether the wallet content is currently hidden behind the lock screen.
  bool get isLocked => _isLocked;

  /// Whether the unlock prompt is currently showing.
  bool get authInProgress => _authInProgress;

  /// Whether any authentication prompt (unlock or in-app action) is showing.
  bool get isAuthenticating => _authInProgress || _actionAuthCount > 0;

  /// Result of the last failed unlock attempt, or null.
  AppAuthResult? get lastResult => _lastResult;

  bool get _lockEnabled =>
      _settings.showAuthenticationScreen && AppLockService.isSupportedPlatform;

  /// Lock the app if the app lock is enabled.
  void lock() {
    if (!_lockEnabled || _isLocked) return;
    if (_actionAuthCount > 0) {
      _lockPending = true;
      return;
    }
    _isLocked = true;
    _lastResult = null;
    notifyListeners();
  }

  /// Authenticate the user for a sensitive in-app action without locking the
  /// app. Use this instead of calling [AppLockService] directly from screens.
  Future<AppAuthResult> authenticateForAction(String reason) async {
    _actionAuthCount++;
    AppAuthResult result;
    try {
      result = await AppLockService.authenticate(reason);
    } finally {
      _actionAuthCount--;
    }
    if (_lockPending && _actionAuthCount == 0) {
      _lockPending = false;
      // The user left the app during the prompt and did not authenticate.
      if (result != AppAuthResult.success) lock();
    }
    return result;
  }

  /// Ask the user to authenticate and unlock on success. Any other outcome
  /// keeps the app locked.
  Future<void> unlock() async {
    if (!_isLocked || _authInProgress) return;

    // The lock was turned off in Settings; nothing to protect.
    if (!_lockEnabled) {
      _isLocked = false;
      _lastResult = null;
      notifyListeners();
      return;
    }

    _authInProgress = true;
    _lastResult = null;
    notifyListeners();

    final result = await AppLockService.authenticate(
      'Authenticate to open RCBWallet',
    );

    _authInProgress = false;
    if (result == AppAuthResult.success) {
      _isLocked = false;
      _lastResult = null;
    } else {
      _lastResult = result;
    }
    notifyListeners();
  }
}
