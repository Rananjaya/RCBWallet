import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/models/startup_settings_provider.dart';
import 'package:wallet/services/currency_formatter.dart';

String lkrValue(double v) =>
    CurrencyFormatter.formatValue(v, currencyCode: 'LKR', symbol: 'Rs.');

String lkrStored(String? raw, {String fallback = ''}) =>
    CurrencyFormatter.formatStored(
      raw,
      currencyCode: 'LKR',
      symbol: 'Rs.',
      fallback: fallback,
    );

void main() {
  group('LKR formatting', () {
    test('formats amounts with symbol, separators and two decimals', () {
      expect(lkrValue(1000), 'Rs. 1,000.00');
      expect(lkrValue(25500), 'Rs. 25,500.00');
      expect(lkrValue(125000), 'Rs. 125,000.00');
    });

    test('handles small, large and fractional values', () {
      expect(lkrValue(0), 'Rs. 0.00');
      expect(lkrValue(7), 'Rs. 7.00');
      expect(lkrValue(999), 'Rs. 999.00');
      expect(lkrValue(999.999), 'Rs. 1,000.00');
      expect(lkrValue(1500.5), 'Rs. 1,500.50');
      expect(lkrValue(1234567.891), 'Rs. 1,234,567.89');
      expect(lkrValue(1000000000), 'Rs. 1,000,000,000.00');
    });

    test('places the minus sign before the symbol', () {
      expect(lkrValue(-1500.5), '-Rs. 1,500.50');
      expect(lkrValue(-0.001), 'Rs. 0.00');
    });

    test('formats stored digit strings from the card form', () {
      expect(lkrStored('125000'), 'Rs. 125,000.00');
      expect(lkrStored('25500'), 'Rs. 25,500.00');
      expect(lkrStored(' 1000 '), 'Rs. 1,000.00');
      expect(lkrStored('0'), 'Rs. 0.00');
    });

    test('uses the fallback when no amount is stored', () {
      expect(lkrStored(null, fallback: '0.00'), 'Rs. 0.00');
      expect(lkrStored(null, fallback: 'N/A'), 'Rs. N/A');
      expect(lkrStored(''), 'Rs.');
    });

    test('shows non-numeric stored text unchanged instead of failing', () {
      expect(lkrStored('abc'), 'Rs. abc');
      expect(lkrStored('1,000'), 'Rs. 1,000');
      expect(lkrStored('NaN'), 'Rs. NaN');
      expect(lkrStored('Infinity'), 'Rs. Infinity');
    });

    test('rule uses a space, thousands grouping and 2 decimals', () {
      final rule = CurrencyFormatter.ruleFor('LKR');
      expect(rule.symbolSeparator, ' ');
      expect(rule.groupThousands, isTrue);
      expect(rule.decimalDigits, 2);
      expect(rule.formatStoredValues, isTrue);
    });
  });

  group('existing currencies keep their original formatting', () {
    final others = StartupSettingsProvider.majorCurrencies
        .where((c) => c['code'] != 'LKR');

    test('stored amounts are the symbol followed by the raw text', () {
      for (final c in others) {
        final code = c['code']!, symbol = c['symbol']!;
        for (final raw in ['100000', '0', 'abc', '']) {
          expect(
            CurrencyFormatter.formatStored(
              raw,
              currencyCode: code,
              symbol: symbol,
            ),
            '$symbol$raw',
            reason: code,
          );
        }
        expect(
          CurrencyFormatter.formatStored(
            null,
            currencyCode: code,
            symbol: symbol,
            fallback: 'N/A',
          ),
          '${symbol}N/A',
        );
      }
    });

    test('computed amounts use the original toStringAsFixed(2) output', () {
      for (final c in others) {
        final code = c['code']!, symbol = c['symbol']!;
        for (final v in [0.0, 1234.5, 1000000.0, -12.345]) {
          expect(
            CurrencyFormatter.formatValue(
              v,
              currencyCode: code,
              symbol: symbol,
            ),
            '$symbol${v.toStringAsFixed(2)}',
            reason: code,
          );
        }
      }
    });

    test('examples match the previous display strings', () {
      expect(
        CurrencyFormatter.formatStored(
          '100000',
          currencyCode: 'INR',
          symbol: '₹',
        ),
        '₹100000',
      );
      expect(
        CurrencyFormatter.formatValue(
          1234.5,
          currencyCode: 'USD',
          symbol: r'$',
        ),
        r'$1234.50',
      );
    });

    test('unknown codes (e.g. from a restored backup) use legacy rules', () {
      expect(
        identical(CurrencyFormatter.ruleFor('XYZ'), CurrencyFormatRule.legacy),
        isTrue,
      );
      expect(
        CurrencyFormatter.formatStored('500', currencyCode: 'XYZ', symbol: 'X'),
        'X500',
      );
    });
  });

  group('amount input validation (unchanged)', () {
    // The card edit form uses FilteringTextInputFormatter.digitsOnly for
    // Max Limit, Current Spends and Annual Fee Waiver, so stored amounts
    // are plain digit strings regardless of the selected currency.
    test('formatted LKR text typed into an amount field keeps digits only',
        () {
      final result = FilteringTextInputFormatter.digitsOnly.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'Rs. 25,500.00'),
      );
      expect(result.text, '2550000');
    });

    test('a digits-only amount round-trips into LKR display', () {
      final typed = FilteringTextInputFormatter.digitsOnly.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '125000'),
      );
      expect(lkrStored(typed.text), 'Rs. 125,000.00');
    });
  });
}
