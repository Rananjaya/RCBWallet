import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/models/wallet.dart';
import 'package:wallet/services/reminder_planner.dart';

// Dummy card data only (Visa test number).
Wallet card({
  int? id = 1,
  String expiry = '1230',
  String? annualFee,
  String? dueDay,
  String? paidYear,
}) =>
    Wallet(
      id: id,
      name: 'DUMMY CARD',
      number: '4111111111111111',
      expiry: expiry,
      annualFee: annualFee,
      annualFeeDueDay: dueDay,
      annualFeePaidYear: paidYear,
    );

const on = ReminderSettings();
final now = DateTime(2026, 11, 10, 9, 30); // a fixed "now"

Map<ReminderKind, DateTime> byKind(List<PlannedReminder> plan) =>
    {for (final r in plan) r.kind: r.when};

void main() {
  group('expiryDate (MMYY = valid until the end of that month)', () {
    test('parses MMYY to the last day of the month', () {
      expect(ReminderPlanner.expiryDate('1230'), DateTime(2030, 12, 31));
      expect(ReminderPlanner.expiryDate('0427'), DateTime(2027, 4, 30));
    });
    test('handles February in leap and non-leap years', () {
      expect(ReminderPlanner.expiryDate('0228'), DateTime(2028, 2, 29));
      expect(ReminderPlanner.expiryDate('0227'), DateTime(2027, 2, 28));
    });
    test('accepts the displayed MM/YY form', () {
      expect(ReminderPlanner.expiryDate('12/30'), DateTime(2030, 12, 31));
    });
    test('returns null for missing or invalid expiry', () {
      for (final bad in [null, '', '123', '12345', '1330', '0030', 'abcd']) {
        expect(ReminderPlanner.expiryDate(bad), isNull, reason: '$bad');
      }
    });
  });

  group('expiry reminders', () {
    test('30 days, 7 days and on the expiry date, at 9:00 AM', () {
      final r = byKind(ReminderPlanner.plan([card(expiry: '0127')], on, now));
      expect(r[ReminderKind.expiry30], DateTime(2027, 1, 1, 9));
      expect(r[ReminderKind.expiry7], DateTime(2027, 1, 24, 9));
      expect(r[ReminderKind.expiryDay], DateTime(2027, 1, 31, 9));
    });

    test('crosses month boundaries correctly', () {
      final r = byKind(ReminderPlanner.plan([card(expiry: '0327')], on, now));
      expect(r[ReminderKind.expiry30], DateTime(2027, 3, 1, 9));
      expect(r[ReminderKind.expiry7], DateTime(2027, 3, 24, 9));
      expect(r[ReminderKind.expiryDay], DateTime(2027, 3, 31, 9));
    });

    test('leap-year February expiry (29 Feb 2028)', () {
      final r = byKind(ReminderPlanner.plan([card(expiry: '0228')], on, now));
      expect(r[ReminderKind.expiry30], DateTime(2028, 1, 30, 9));
      expect(r[ReminderKind.expiry7], DateTime(2028, 2, 22, 9));
      expect(r[ReminderKind.expiryDay], DateTime(2028, 2, 29, 9));
    });

    test('crosses the year boundary', () {
      final dec = DateTime(2026, 12, 1, 8);
      final r = byKind(ReminderPlanner.plan([card(expiry: '0127')], on, dec));
      expect(r[ReminderKind.expiry30], DateTime(2027, 1, 1, 9));
    });

    test('reminders already in the past are skipped', () {
      final late = DateTime(2027, 1, 20, 12);
      final r = byKind(ReminderPlanner.plan([card(expiry: '0127')], on, late));
      expect(r.containsKey(ReminderKind.expiry30), isFalse);
      expect(r[ReminderKind.expiry7], DateTime(2027, 1, 24, 9));
      expect(r[ReminderKind.expiryDay], DateTime(2027, 1, 31, 9));
    });

    test('expiry day itself: before vs after the reminder time', () {
      final morning = DateTime(2027, 1, 31, 8);
      expect(byKind(ReminderPlanner.plan([card(expiry: '0127')], on, morning)).keys,
          [ReminderKind.expiryDay]);
      final atNine = DateTime(2027, 1, 31, 9);
      expect(ReminderPlanner.plan([card(expiry: '0127')], on, atNine), isEmpty);
    });

    test('already expired cards get no reminders', () {
      expect(ReminderPlanner.plan([card(expiry: '1025')], on, now), isEmpty);
      expect(ReminderPlanner.plan([card(expiry: '1026')], on, now), isEmpty,
          reason: 'Oct 2026 ended before 10 Nov 2026');
    });

    test('invalid or missing expiry is skipped without errors', () {
      for (final bad in ['', '1330', 'xx', '12']) {
        expect(ReminderPlanner.plan([card(expiry: bad)], on, now), isEmpty);
      }
    });

    test('cards without an ID are skipped', () {
      expect(ReminderPlanner.plan([card(id: null)], on, now), isEmpty);
    });

    test('custom reminder time is used', () {
      const evening = ReminderSettings(minutesOfDay: 18 * 60 + 30);
      final r = byKind(ReminderPlanner.plan([card(expiry: '0127')], evening, now));
      expect(r[ReminderKind.expiryDay], DateTime(2027, 1, 31, 18, 30));
    });

    test('disabled expiry reminders schedule nothing', () {
      const off = ReminderSettings(expiryEnabled: false);
      expect(ReminderPlanner.plan([card(expiry: '0127')], off, now), isEmpty);
    });
  });

  group('annual fee due dates', () {
    test('parseDueDay accepts MM-DD, including 29 Feb', () {
      expect(ReminderPlanner.parseDueDay('12-15'), (month: 12, day: 15));
      expect(ReminderPlanner.parseDueDay('02-29'), (month: 2, day: 29));
      for (final bad in [null, '', '13-01', '00-10', '02-30', '04-31', '2-5', '12/15']) {
        expect(ReminderPlanner.parseDueDay(bad), isNull, reason: '$bad');
      }
    });

    test('29 Feb falls on 28 Feb in non-leap years, without drifting', () {
      expect(ReminderPlanner.dueDateInYear(2, 29, 2027), DateTime(2027, 2, 28));
      expect(ReminderPlanner.dueDateInYear(2, 29, 2028), DateTime(2028, 2, 29));
      final c = card(annualFee: '5000', dueDay: '02-29', paidYear: '2026');
      expect(ReminderPlanner.annualFeeStatus(c, now).nextDue, DateTime(2027, 2, 28));
      final c2 = card(annualFee: '5000', dueDay: '02-29', paidYear: '2027');
      expect(ReminderPlanner.annualFeeStatus(c2, now).nextDue, DateTime(2028, 2, 29));
    });

    test('initialPaidYear makes the next occurrence the first due date', () {
      expect(ReminderPlanner.initialPaidYear('12-15', now), '2025'); // due 15 Dec 2026
      expect(ReminderPlanner.initialPaidYear('03-01', now), '2026'); // due 1 Mar 2027
      expect(ReminderPlanner.initialPaidYear('11-10', now), '2025'); // due today
    });

    test('reminders 30 and 7 days before the due date', () {
      final c = card(annualFee: '5000', dueDay: '12-15', paidYear: '2025');
      final r = byKind(ReminderPlanner.plan([c], on, now));
      expect(r[ReminderKind.annualFee30], DateTime(2026, 11, 15, 9));
      expect(r[ReminderKind.annualFee7], DateTime(2026, 12, 8, 9));
    });

    test('a 30-day reminder already in the past is skipped', () {
      final c = card(annualFee: '5000', dueDay: '11-20', paidYear: '2025');
      final r = byKind(ReminderPlanner.plan([c], on, now));
      expect(r.containsKey(ReminderKind.annualFee30), isFalse);
      expect(r[ReminderKind.annualFee7], DateTime(2026, 11, 13, 9));
    });

    test('month boundary: due 5 Mar 2027 -> reminders 3 Feb and 26 Feb', () {
      final c = card(annualFee: '5000', dueDay: '03-05', paidYear: '2026');
      final r = byKind(ReminderPlanner.plan([c], on, now));
      expect(r[ReminderKind.annualFee30], DateTime(2027, 2, 3, 9));
      expect(r[ReminderKind.annualFee7], DateTime(2027, 2, 26, 9));
    });

    test('cards without an annual fee get no fee reminders', () {
      for (final fee in [null, '', '0', '00', 'abc']) {
        final c = card(annualFee: fee, dueDay: '12-15', paidYear: '2025');
        final kinds = byKind(ReminderPlanner.plan([c], on, now)).keys;
        expect(kinds.where((k) => k.name.startsWith('annualFee')), isEmpty,
            reason: 'fee $fee');
      }
    });

    test('a fee without a due date gets no fee reminders', () {
      final c = card(annualFee: '5000');
      final kinds = byKind(ReminderPlanner.plan([c], on, now)).keys;
      expect(kinds.where((k) => k.name.startsWith('annualFee')), isEmpty);
    });

    test('disabled annual fee reminders schedule nothing', () {
      const off = ReminderSettings(annualFeeEnabled: false);
      final c = card(annualFee: '5000', dueDay: '12-15', paidYear: '2025');
      final kinds = byKind(ReminderPlanner.plan([c], off, now)).keys;
      expect(kinds.where((k) => k.name.startsWith('annualFee')), isEmpty);
    });

    test('marking as paid moves the reminders to next year', () {
      final c = card(annualFee: '5000', dueDay: '12-15', paidYear: '2025');
      expect(ReminderPlanner.annualFeeStatus(c, now).nextDue, DateTime(2026, 12, 15));
      final paidYear = ReminderPlanner.paidYearAfterMarkingPaid(c, now);
      expect(paidYear, '2026');
      final paid = c.copyWithAnnualFee(annualFeePaidYear: paidYear);
      expect(ReminderPlanner.annualFeeStatus(paid, now).nextDue, DateTime(2027, 12, 15));
      final r = byKind(ReminderPlanner.plan([paid], on, now));
      expect(r[ReminderKind.annualFee30], DateTime(2027, 11, 15, 9));
      expect(r[ReminderKind.annualFee7], DateTime(2027, 12, 8, 9));
    });

    test('an unpaid past due date is overdue and gets no reminders', () {
      final c = card(annualFee: '5000', dueDay: '10-01', paidYear: '2025');
      final status = ReminderPlanner.annualFeeStatus(c, now);
      expect(status.nextDue, DateTime(2026, 10, 1));
      expect(status.overdue, isTrue);
      final kinds = byKind(ReminderPlanner.plan([c], on, now)).keys;
      expect(kinds.where((k) => k.name.startsWith('annualFee')), isEmpty);
    });

    test('marking an overdue fee as paid moves to the next year', () {
      final c = card(annualFee: '5000', dueDay: '10-01', paidYear: '2025');
      final paid = c.copyWithAnnualFee(
        annualFeePaidYear: ReminderPlanner.paidYearAfterMarkingPaid(c, now),
      );
      final status = ReminderPlanner.annualFeeStatus(paid, now);
      expect(status.nextDue, DateTime(2027, 10, 1));
      expect(status.overdue, isFalse);
    });
  });

  group('notification IDs and duplicates', () {
    test('IDs are unique per card and reminder kind', () {
      final ids = <int>{};
      for (var cardId = 1; cardId <= 50; cardId++) {
        for (final kind in ReminderKind.values) {
          final id = ReminderPlanner.notificationId(cardId, kind);
          expect(ids.add(id), isTrue, reason: 'duplicate id $id');
          expect(ReminderPlanner.isReminderId(id), isTrue);
        }
      }
    });

    test('IDs stay within 32 bits for the largest supported card ID', () {
      final id = ReminderPlanner.notificationId(
        ReminderPlanner.maxCardId,
        ReminderKind.values.last,
      );
      expect(id <= 0x7FFFFFFF, isTrue);
      expect(ReminderPlanner.plan([card(id: ReminderPlanner.maxCardId + 1)], on, now),
          isEmpty);
    });

    test('a plan never contains the same ID twice', () {
      final c = card(expiry: '0127', annualFee: '5000', dueDay: '12-15', paidYear: '2025');
      final plan = ReminderPlanner.plan([c, c], on, now);
      final ids = plan.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(plan.length, 5);
    });

    test('plan is sorted by time', () {
      final plan = ReminderPlanner.plan(
        [card(id: 1, expiry: '0327'), card(id: 2, expiry: '0127')],
        on,
        now,
      );
      for (var i = 1; i < plan.length; i++) {
        expect(!plan[i].when.isBefore(plan[i - 1].when), isTrue);
      }
    });
  });
}
