import 'package:wallet/models/wallet.dart';

/// The kinds of reminders RCBWallet schedules for a payment card.
///
/// The order is part of the notification ID scheme: do not reorder, only
/// append (see [ReminderPlanner.notificationId]).
enum ReminderKind { expiry30, expiry7, expiryDay, annualFee30, annualFee7 }

/// User preferences for reminders.
class ReminderSettings {
  final bool expiryEnabled;
  final bool annualFeeEnabled;

  /// Local time of day the reminders are delivered, in minutes after
  /// midnight (default 9:00 AM = 540).
  final int minutesOfDay;

  const ReminderSettings({
    this.expiryEnabled = true,
    this.annualFeeEnabled = true,
    this.minutesOfDay = defaultMinutesOfDay,
  });

  static const int defaultMinutesOfDay = 9 * 60;
}

/// One reminder that should be scheduled.
class PlannedReminder {
  final int id;
  final int cardId;
  final ReminderKind kind;

  /// Local date and time the reminder is due.
  final DateTime when;

  const PlannedReminder({
    required this.id,
    required this.cardId,
    required this.kind,
    required this.when,
  });

  @override
  String toString() => 'PlannedReminder($id, card $cardId, $kind, $when)';
}

/// Annual fee state of a card, for display.
class AnnualFeeStatus {
  /// Next due date (date only), or null if no due date is configured.
  final DateTime? nextDue;

  /// True when [nextDue] is before today and hasn't been marked as paid.
  final bool overdue;

  const AnnualFeeStatus({this.nextDue, this.overdue = false});
}

/// Pure date calculations for card reminders. No I/O, no plugins.
///
/// Card numbers are never read here: only the card ID, expiry and annual
/// fee fields are used.
class ReminderPlanner {
  const ReminderPlanner._();

  /// Slots per card in the notification ID space (1-based, room to grow).
  static const int _slotsPerCard = 8;

  /// Highest card ID that still fits in a 32-bit notification ID.
  static const int maxCardId = 0x7FFFFFFF ~/ _slotsPerCard - 1;

  /// Unique, stable notification ID for a card and reminder kind.
  static int notificationId(int cardId, ReminderKind kind) =>
      cardId * _slotsPerCard + kind.index + 1;

  /// Whether [id] belongs to the reminder ID scheme.
  static bool isReminderId(int id) {
    if (id < _slotsPerCard) return false;
    final slot = id % _slotsPerCard;
    return slot >= 1 && slot <= ReminderKind.values.length;
  }

  /// Date-only (midnight) version of [d].
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Last day of [month] in [year].
  static DateTime lastDayOfMonth(int year, int month) =>
      DateTime(year, month + 1, 0);

  /// The day a card expires, from its "MMYY" expiry (the card is valid
  /// until the end of that month). Returns null when missing or invalid.
  static DateTime? expiryDate(String? expiry) {
    if (expiry == null) return null;
    final digits = expiry.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 4) return null;
    final month = int.parse(digits.substring(0, 2));
    final year = 2000 + int.parse(digits.substring(2, 4));
    if (month < 1 || month > 12) return null;
    return lastDayOfMonth(year, month);
  }

  /// Parses an annual fee due day "MM-DD". Returns null when invalid.
  /// "02-29" is allowed (it falls on 28 Feb in non-leap years).
  static ({int month, int day})? parseDueDay(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (m == null) return null;
    final month = int.parse(m.group(1)!);
    final day = int.parse(m.group(2)!);
    if (month < 1 || month > 12 || day < 1) return null;
    // Validate against a leap year so 29 Feb is accepted.
    if (day > lastDayOfMonth(2024, month).day) return null;
    return (month: month, day: day);
  }

  /// Formats a month and day as "MM-DD".
  static String formatDueDay(int month, int day) =>
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// The due date in [year], moving 29 Feb to 28 Feb in non-leap years.
  static DateTime dueDateInYear(int month, int day, int year) {
    final last = lastDayOfMonth(year, month).day;
    return DateTime(year, month, day > last ? last : day);
  }

  /// The first occurrence of the due day on or after [today].
  static DateTime nextOccurrence(int month, int day, DateTime today) {
    final t = _day(today);
    final thisYear = dueDateInYear(month, day, t.year);
    return thisYear.isBefore(t)
        ? dueDateInYear(month, day, t.year + 1)
        : thisYear;
  }

  /// The paid-year value to store when a due day is first set or changed,
  /// so that the next due date is the next upcoming occurrence.
  static String initialPaidYear(String dueDay, DateTime today) {
    final d = parseDueDay(dueDay)!;
    return (nextOccurrence(d.month, d.day, today).year - 1).toString();
  }

  /// Whether the card has an annual fee greater than zero.
  static bool hasAnnualFee(String? amount) {
    final v = double.tryParse((amount ?? '').trim());
    return v != null && v.isFinite && v > 0;
  }

  /// Annual fee state for display.
  static AnnualFeeStatus annualFeeStatus(Wallet card, DateTime today) {
    final due = parseDueDay(card.annualFeeDueDay);
    if (due == null) return const AnnualFeeStatus();
    final t = _day(today);
    final paidYear = int.tryParse((card.annualFeePaidYear ?? '').trim());
    final next = paidYear == null
        ? nextOccurrence(due.month, due.day, t)
        : dueDateInYear(due.month, due.day, paidYear + 1);
    return AnnualFeeStatus(nextDue: next, overdue: next.isBefore(t));
  }

  /// The year to store when the current annual fee is marked as paid, or
  /// null if no due date is configured.
  static String? paidYearAfterMarkingPaid(Wallet card, DateTime today) {
    final next = annualFeeStatus(card, today).nextDue;
    return next?.year.toString();
  }

  /// [day] minus [n] calendar days (DST-safe, unlike subtracting a Duration).
  static DateTime daysBefore(DateTime day, int n) =>
      DateTime(day.year, day.month, day.day - n);

  static DateTime _at(DateTime day, int minutesOfDay) => DateTime(
    day.year,
    day.month,
    day.day,
    minutesOfDay ~/ 60,
    minutesOfDay % 60,
  );

  /// All reminders that should currently be scheduled. Reminders whose time
  /// is not after [now] are left out, so expired cards and past due dates
  /// produce nothing. Cards without an ID, with an invalid expiry, or without
  /// an annual fee are skipped safely.
  static List<PlannedReminder> plan(
    Iterable<Wallet> cards,
    ReminderSettings settings,
    DateTime now,
  ) {
    final result = <PlannedReminder>[];
    final today = _day(now);
    final seen = <int>{};

    void add(int cardId, ReminderKind kind, DateTime day) {
      final when = _at(day, settings.minutesOfDay);
      if (!when.isAfter(now)) return;
      final id = notificationId(cardId, kind);
      if (seen.add(id)) {
        result.add(
          PlannedReminder(id: id, cardId: cardId, kind: kind, when: when),
        );
      }
    }

    for (final card in cards) {
      final id = card.id;
      if (id == null || id < 1 || id > maxCardId) continue;

      if (settings.expiryEnabled) {
        final expires = expiryDate(card.expiry);
        if (expires != null && !expires.isBefore(today)) {
          add(id, ReminderKind.expiry30, daysBefore(expires, 30));
          add(id, ReminderKind.expiry7, daysBefore(expires, 7));
          add(id, ReminderKind.expiryDay, expires);
        }
      }

      if (settings.annualFeeEnabled && hasAnnualFee(card.annualFee)) {
        final status = annualFeeStatus(card, now);
        final due = status.nextDue;
        if (due != null && !status.overdue) {
          add(id, ReminderKind.annualFee30, daysBefore(due, 30));
          add(id, ReminderKind.annualFee7, daysBefore(due, 7));
        }
      }
    }
    result.sort((a, b) => a.when.compareTo(b.when));
    return result;
  }
}
