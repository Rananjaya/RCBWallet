import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/models/wallet.dart';
import 'package:wallet/services/currency_formatter.dart';
import 'package:wallet/services/reminder_planner.dart';
import 'package:wallet/services/reminder_service.dart';

/// In-memory stand-in for the notification plugin. Scheduling an existing ID
/// replaces it, like the real plugin.
class FakeNotifier implements ReminderNotifier {
  final Map<int, PlannedReminder> scheduled = {};
  final List<int> cancelled = [];
  int scheduleCalls = 0;
  int permissionRequests = 0;
  bool grant = true;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList();

  @override
  Future<void> schedule(PlannedReminder reminder) async {
    scheduleCalls++;
    scheduled[reminder.id] = reminder;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }
}

// Dummy cards only.
Wallet card(int id, {String expiry = '0127', String? fee, String? dueDay, String? paid}) =>
    Wallet(
      id: id,
      name: 'DUMMY CARD $id',
      number: '4111111111111111',
      expiry: expiry,
      annualFee: fee,
      annualFeeDueDay: dueDay,
      annualFeePaidYear: paid,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotifier notifier;
  late List<Wallet> cards;
  late ReminderSettings settings;
  late ReminderService service;
  final now = DateTime(2026, 11, 10, 9, 30);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifier = FakeNotifier();
    cards = [];
    settings = const ReminderSettings();
    service = ReminderService(
      notifier: notifier,
      loadCards: () async => List.of(cards),
      loadSettings: () async => settings,
      clock: () => now,
    );
  });

  test('schedules expiry and annual fee reminders for each card', () async {
    cards = [
      card(1, expiry: '0127'),
      card(2, expiry: '1230', fee: '5000', dueDay: '12-15', paid: '2025'),
    ];
    final result = await service.sync();
    // Card 1: 3 expiry. Card 2 (expires Dec 2030): 3 expiry + 2 annual fee.
    expect(result.scheduled, 8);
    expect(notifier.scheduled.keys.toSet(), {
      for (final kind in ReminderKind.values.take(3)) ...{
        ReminderPlanner.notificationId(1, kind),
        ReminderPlanner.notificationId(2, kind),
      },
      ReminderPlanner.notificationId(2, ReminderKind.annualFee30),
      ReminderPlanner.notificationId(2, ReminderKind.annualFee7),
    });
  });

  test('repeated syncs never create duplicates', () async {
    cards = [card(1, expiry: '0127')];
    await service.sync();
    await service.sync();
    await service.sync();
    expect(notifier.scheduled.length, 3);
  });

  test('concurrent sync calls are merged and still end consistent', () async {
    cards = [card(1, expiry: '0127')];
    await Future.wait([service.sync(), service.sync(), service.sync()]);
    expect(notifier.scheduled.length, 3);
  });

  test('deleting a card cancels its reminders', () async {
    cards = [card(1, expiry: '0127'), card(2, expiry: '0327')];
    await service.sync();
    expect(notifier.scheduled.length, 6);

    cards = [card(2, expiry: '0327')];
    final result = await service.sync();
    expect(result.cancelled, 3);
    expect(notifier.scheduled.values.every((r) => r.cardId == 2), isTrue);
  });

  test('changing the expiry date reschedules to the new date', () async {
    cards = [card(1, expiry: '0127')];
    await service.sync();
    final dayId = ReminderPlanner.notificationId(1, ReminderKind.expiryDay);
    expect(notifier.scheduled[dayId]!.when, DateTime(2027, 1, 31, 9));

    cards = [card(1, expiry: '0628')];
    await service.sync();
    expect(notifier.scheduled[dayId]!.when, DateTime(2028, 6, 30, 9));
    expect(notifier.scheduled.length, 3);
  });

  test('changing the expiry to an already expired date cancels reminders', () async {
    cards = [card(1, expiry: '0127')];
    await service.sync();
    cards = [card(1, expiry: '0125')];
    await service.sync();
    expect(notifier.scheduled, isEmpty);
  });

  test('marking the annual fee as paid moves reminders to next year', () async {
    var c = card(1, expiry: '1230', fee: '5000', dueDay: '12-15', paid: '2025');
    cards = [c];
    await service.sync();
    final id7 = ReminderPlanner.notificationId(1, ReminderKind.annualFee7);
    expect(notifier.scheduled[id7]!.when, DateTime(2026, 12, 8, 9));

    c = c.copyWithAnnualFee(
      annualFeePaidYear: ReminderPlanner.paidYearAfterMarkingPaid(c, now),
    );
    cards = [c];
    await service.sync();
    expect(notifier.scheduled[id7]!.when, DateTime(2027, 12, 8, 9));
  });

  test('disabling reminders cancels the scheduled ones', () async {
    cards = [card(1, expiry: '0127', fee: '5000', dueDay: '12-15', paid: '2025')];
    await service.sync();
    expect(notifier.scheduled.length, 5);

    settings = const ReminderSettings(expiryEnabled: false);
    await service.sync();
    expect(notifier.scheduled.values.map((r) => r.kind).toSet(),
        {ReminderKind.annualFee30, ReminderKind.annualFee7});

    settings = const ReminderSettings(expiryEnabled: false, annualFeeEnabled: false);
    await service.sync();
    expect(notifier.scheduled, isEmpty);
  });

  test('notifications that are not reminders are left alone', () async {
    notifier.scheduled[3] = PlannedReminder(
      id: 3, cardId: 0, kind: ReminderKind.expiry30, when: DateTime(2030));
    await service.sync();
    expect(notifier.scheduled.containsKey(3), isTrue);
  });

  test('permission is requested once, and again only when forced', () async {
    cards = [card(1, expiry: '0127')];
    await service.sync();
    await service.sync();
    expect(notifier.permissionRequests, 1);
    await service.ensurePermission(force: true);
    expect(notifier.permissionRequests, 2);
  });

  test('no permission request when nothing needs a reminder', () async {
    cards = [card(1, expiry: '1025')]; // expired
    await service.sync();
    expect(notifier.permissionRequests, 0);
  });

  test('a failing data source does not throw', () async {
    final broken = ReminderService(
      notifier: notifier,
      loadCards: () async => throw StateError('db unavailable'),
      loadSettings: () async => settings,
      clock: () => now,
    );
    final result = await broken.sync();
    expect(result.scheduled, 0);
  });

  test('notification text is generic: no card names, numbers or amounts', () {
    for (final kind in ReminderKind.values) {
      final text = '${ReminderTexts.title(kind)} ${ReminderTexts.body(kind)}';
      expect(text.contains(RegExp(r'\d{4}')), isFalse, reason: text);
      expect(text.contains('DUMMY'), isFalse);
      expect(text.contains('Rs.'), isFalse);
      expect(text.contains(RegExp(r'[₹$€£]')), isFalse);
    }
  });

  test('annual fee amounts use the existing currency formatter', () {
    expect(
      CurrencyFormatter.formatStored('5000', currencyCode: 'LKR', symbol: 'Rs.'),
      'Rs. 5,000.00',
    );
    expect(
      CurrencyFormatter.formatStored('5000', currencyCode: 'INR', symbol: '₹'),
      '₹5000',
    );
    expect(
      CurrencyFormatter.formatStored('5000', currencyCode: 'USD', symbol: r'$'),
      r'$5000',
    );
  });
}
