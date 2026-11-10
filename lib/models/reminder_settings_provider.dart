import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/services/reminder_planner.dart';
import 'package:wallet/services/reminder_service.dart';

/// Card reminder preferences: expiry reminders, annual fee reminders and the
/// time of day reminders are delivered. Both reminders are on by default, at
/// 9:00 AM.
class ReminderSettingsProvider with ChangeNotifier {
  static const String expiryKey = 'expiryRemindersEnabled';
  static const String annualFeeKey = 'annualFeeRemindersEnabled';
  static const String timeKey = 'reminderMinutesOfDay';

  ReminderSettings _settings = const ReminderSettings();

  bool get expiryEnabled => _settings.expiryEnabled;
  bool get annualFeeEnabled => _settings.annualFeeEnabled;
  int get minutesOfDay => _settings.minutesOfDay;
  TimeOfDay get reminderTime =>
      TimeOfDay(hour: minutesOfDay ~/ 60, minute: minutesOfDay % 60);

  /// Reads the saved settings (defaults when nothing is saved).
  static Future<ReminderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt(timeKey);
    return ReminderSettings(
      expiryEnabled: prefs.getBool(expiryKey) ?? true,
      annualFeeEnabled: prefs.getBool(annualFeeKey) ?? true,
      minutesOfDay: (minutes != null && minutes >= 0 && minutes < 24 * 60)
          ? minutes
          : ReminderSettings.defaultMinutesOfDay,
    );
  }

  Future<void> init() async {
    _settings = await load();
    notifyListeners();
  }

  Future<void> setExpiryEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(expiryKey, value);
    await _changed(askPermission: value);
  }

  Future<void> setAnnualFeeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(annualFeeKey, value);
    await _changed(askPermission: value);
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(timeKey, time.hour * 60 + time.minute);
    await _changed(askPermission: false);
  }

  Future<void> _changed({required bool askPermission}) async {
    _settings = await load();
    notifyListeners();
    if (askPermission) {
      await ReminderService.instance.ensurePermission(force: true);
    }
    await ReminderService.instance.sync();
  }
}
