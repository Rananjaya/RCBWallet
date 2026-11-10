import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wallet/models/db_helper.dart';
import 'package:wallet/models/reminder_settings_provider.dart';
import 'package:wallet/services/reminder_planner.dart';

/// Generic notification text. The notification plugin stores title and body
/// unencrypted (to restore reminders after a reboot), so these never contain
/// card names, numbers, bank names or amounts.
class ReminderTexts {
  const ReminderTexts._();

  static String title(ReminderKind kind) {
    switch (kind) {
      case ReminderKind.expiry30:
      case ReminderKind.expiry7:
      case ReminderKind.expiryDay:
        return 'Card expiry reminder';
      case ReminderKind.annualFee30:
      case ReminderKind.annualFee7:
        return 'Annual fee reminder';
    }
  }

  static String body(ReminderKind kind) {
    switch (kind) {
      case ReminderKind.expiry30:
        return 'One of your cards expires in 30 days. Open RCBWallet for details.';
      case ReminderKind.expiry7:
        return 'One of your cards expires in 7 days. Open RCBWallet for details.';
      case ReminderKind.expiryDay:
        return 'One of your cards expires today. Open RCBWallet for details.';
      case ReminderKind.annualFee30:
        return 'A card annual fee is due in 30 days. Open RCBWallet for details.';
      case ReminderKind.annualFee7:
        return 'A card annual fee is due in 7 days. Open RCBWallet for details.';
    }
  }
}

/// Thin interface over the notification plugin, so scheduling logic can be
/// tested without a device.
abstract class ReminderNotifier {
  Future<void> initialize();
  Future<List<int>> pendingIds();
  Future<void> schedule(PlannedReminder reminder);
  Future<void> cancel(int id);
  Future<bool> requestPermission();
}

/// Local notifications on Android via flutter_local_notifications. Works fully
/// offline. Other platforms are a no-op.
class LocalReminderNotifier implements ReminderNotifier {
  LocalReminderNotifier();

  static const String _channelId = 'card_reminders';
  static const String _channelName = 'Card reminders';
  static const String _channelDescription =
      'Card expiry and annual fee reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> initialize() async {
    if (_initialized || !_supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<List<int>> pendingIds() async {
    if (!_supported) return const [];
    final pending = await _plugin.pendingNotificationRequests();
    return [for (final p in pending) p.id];
  }

  @override
  Future<void> schedule(PlannedReminder reminder) async {
    if (!_supported) return;
    await _plugin.zonedSchedule(
      id: reminder.id,
      // The local reminder time converted to an exact instant (UTC), so no
      // time-zone database is needed. Re-synced on every app start.
      scheduledDate: tz.TZDateTime.from(reminder.when.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          // Lock screen shows only that RCBWallet has a notification.
          visibility: NotificationVisibility.private,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      // Inexact: no exact-alarm permission needed. Delivery may be delayed
      // by Android's battery optimisation.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: ReminderTexts.title(reminder.kind),
      body: ReminderTexts.body(reminder.kind),
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }
}

/// Outcome of one sync, for tests and diagnostics (counts only).
class ReminderSyncResult {
  final int scheduled;
  final int cancelled;
  const ReminderSyncResult({required this.scheduled, required this.cancelled});
}

/// Keeps the scheduled reminders in line with the cards and settings.
///
/// [sync] computes the full plan, cancels every reminder that is no longer
/// wanted (deleted cards, changed dates, disabled settings) and schedules the
/// plan. Each reminder has a fixed ID per card and kind, and scheduling the
/// same ID replaces the earlier one, so reminders are never duplicated.
class ReminderService {
  ReminderService({
    required this.notifier,
    required this.loadCards,
    required this.loadSettings,
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
  }) : clock = clock ?? DateTime.now,
       _prefs = prefs ?? SharedPreferences.getInstance;

  final ReminderNotifier notifier;
  final Future<List<Wallet>> Function() loadCards;
  final Future<ReminderSettings> Function() loadSettings;
  final DateTime Function() clock;
  final Future<SharedPreferences> Function() _prefs;

  static const String permissionAskedKey = 'reminderPermissionAsked';

  static ReminderService? _instance;

  static ReminderService get instance => _instance ??= ReminderService(
    notifier: LocalReminderNotifier(),
    loadCards: () => DatabaseHelper.instance.getWallets(),
    loadSettings: ReminderSettingsProvider.load,
  );

  @visibleForTesting
  static set instance(ReminderService service) => _instance = service;

  Future<ReminderSyncResult>? _running;
  bool _rerun = false;

  /// Re-syncs all reminders. Concurrent calls are merged: if a sync is
  /// running, one more sync runs after it with the latest data.
  Future<ReminderSyncResult> sync() {
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    final future = _syncLoop();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<ReminderSyncResult> _syncLoop() async {
    ReminderSyncResult result;
    do {
      _rerun = false;
      result = await _syncOnce();
    } while (_rerun);
    return result;
  }

  Future<ReminderSyncResult> _syncOnce() async {
    try {
      await notifier.initialize();
      final settings = await loadSettings();
      final cards = await loadCards();
      final plan = ReminderPlanner.plan(cards, settings, clock());
      final wanted = {for (final r in plan) r.id};

      var cancelled = 0;
      for (final id in await notifier.pendingIds()) {
        if (ReminderPlanner.isReminderId(id) && !wanted.contains(id)) {
          await notifier.cancel(id);
          cancelled++;
        }
      }

      if (plan.isNotEmpty) await ensurePermission();
      for (final reminder in plan) {
        await notifier.schedule(reminder);
      }
      return ReminderSyncResult(scheduled: plan.length, cancelled: cancelled);
    } catch (e) {
      // Never log card data; the error type is enough.
      debugPrint('ReminderService: sync failed (${e.runtimeType})');
      return const ReminderSyncResult(scheduled: 0, cancelled: 0);
    }
  }

  /// Asks for the notification permission the first time reminders are
  /// needed. With [force], asks again (e.g. when a reminder is turned on).
  Future<bool> ensurePermission({bool force = false}) async {
    try {
      final prefs = await _prefs();
      if (!force && (prefs.getBool(permissionAskedKey) ?? false)) return true;
      await prefs.setBool(permissionAskedKey, true);
      return await notifier.requestPermission();
    } catch (e) {
      debugPrint(
        'ReminderService: permission request failed (${e.runtimeType})',
      );
      return false;
    }
  }
}
