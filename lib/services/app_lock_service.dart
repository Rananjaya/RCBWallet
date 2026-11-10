import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Outcome of a device authentication attempt.
enum AppAuthResult {
  /// The user authenticated with biometrics or the device PIN/pattern/password.
  success,

  /// The user cancelled, or the biometric/credential check failed.
  failed,

  /// No secure screen lock (PIN, pattern or password) is set on the device.
  noDeviceSecurity,

  /// Too many failed attempts; authentication is temporarily unavailable.
  lockedOut,

  /// The authentication system reported an unexpected error.
  error,
}

/// Single entry point for device authentication (biometrics with
/// PIN/pattern/password fallback).
///
/// Every failure, cancellation or exception is reported as a non-success
/// result. Callers must never treat a non-success result as "unlocked".
class AppLockService {
  const AppLockService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Platforms where device authentication is not available to the app.
  /// Linux and web are only used for development; Android is the shipped
  /// platform.
  static bool get isSupportedPlatform => !kIsWeb && !Platform.isLinux;

  /// Whether the device can authenticate the user with a screen lock or
  /// enrolled biometrics. Returns false if the check itself fails.
  static Future<bool> hasDeviceSecurity() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Ask the user to authenticate. Biometrics are offered when enrolled, and
  /// the device PIN, pattern or password is always accepted as an
  /// alternative. Never throws.
  static Future<AppAuthResult> authenticate(String reason) async {
    if (!await hasDeviceSecurity()) return AppAuthResult.noDeviceSecurity;

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return authenticated ? AppAuthResult.success : AppAuthResult.failed;
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.passcodeNotSet:
        case auth_error.notEnrolled:
        case auth_error.notAvailable:
          return AppAuthResult.noDeviceSecurity;
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          return AppAuthResult.lockedOut;
        default:
          return AppAuthResult.error;
      }
    } catch (_) {
      return AppAuthResult.error;
    }
  }

  /// User-facing explanation for a non-success result.
  static String messageFor(AppAuthResult result) {
    switch (result) {
      case AppAuthResult.success:
        return '';
      case AppAuthResult.failed:
        return 'Authentication was cancelled or not recognised. Tap Unlock to try again.';
      case AppAuthResult.noDeviceSecurity:
        return 'Set up a screen lock (PIN, pattern or password) in Android '
            'Settings > Security, then come back and tap Unlock. '
            'RCBWallet uses your screen lock and biometrics to protect your cards.';
      case AppAuthResult.lockedOut:
        return 'Too many failed attempts. Wait a moment, or unlock your device '
            'with its PIN, pattern or password, then tap Unlock.';
      case AppAuthResult.error:
        return 'Authentication is not available right now. Tap Unlock to try again.';
    }
  }
}
