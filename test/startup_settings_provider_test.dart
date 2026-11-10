import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/models/startup_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('supported currencies', () {
    const currencies = StartupSettingsProvider.majorCurrencies;

    test('LKR is listed with the correct code, symbol and name', () {
      final lkr = currencies.where((c) => c['code'] == 'LKR').toList();
      expect(lkr, hasLength(1));
      expect(lkr.single, {
        'code': 'LKR',
        'symbol': 'Rs.',
        'name': 'Sri Lankan Rupee',
      });
    });

    test('currency codes are unique', () {
      final codes = currencies.map((c) => c['code']).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('existing currencies are unchanged and in their original order', () {
      final withoutLkr = currencies.where((c) => c['code'] != 'LKR').toList();
      expect(withoutLkr, const [
        {'code': 'INR', 'symbol': '₹', 'name': 'Indian Rupee'},
        {'code': 'BDT', 'symbol': '৳', 'name': 'Bangladeshi Taka'},
        {'code': 'USD', 'symbol': r'$', 'name': 'US Dollar'},
        {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
        {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
        {'code': 'JPY', 'symbol': '¥', 'name': 'Japanese Yen'},
        {'code': 'AUD', 'symbol': r'A$', 'name': 'Australian Dollar'},
        {'code': 'CAD', 'symbol': r'C$', 'name': 'Canadian Dollar'},
        {'code': 'CHF', 'symbol': 'CHF', 'name': 'Swiss Franc'},
        {'code': 'CNY', 'symbol': '¥', 'name': 'Chinese Yuan'},
        {'code': 'NZD', 'symbol': r'NZ$', 'name': 'New Zealand Dollar'},
        {'code': 'SEK', 'symbol': 'kr', 'name': 'Swedish Krona'},
      ]);
    });
  });

  group('selecting LKR', () {
    test('default currency is still INR when nothing is saved', () async {
      final provider = StartupSettingsProvider();
      await provider.loadStartupSettings();
      expect(provider.selectedCurrencyCode, 'INR');
      expect(provider.selectedCurrencySymbol, '₹');
    });

    test('LKR can be selected the same way the settings dialog does it',
        () async {
      final provider = StartupSettingsProvider();
      await provider.loadStartupSettings();
      var notified = 0;
      provider.addListener(() => notified++);

      final lkr = StartupSettingsProvider.majorCurrencies
          .firstWhere((c) => c['code'] == 'LKR');
      await provider.setCurrency(lkr['code']!, lkr['symbol']!);

      expect(provider.selectedCurrencyCode, 'LKR');
      expect(provider.selectedCurrencySymbol, 'Rs.');
      expect(notified, 1);
    });

    test('LKR selection persists across an app restart', () async {
      final before = StartupSettingsProvider();
      await before.setCurrency('LKR', 'Rs.');

      // A fresh provider reading from storage simulates a restart.
      final after = StartupSettingsProvider();
      await after.loadStartupSettings();
      expect(after.selectedCurrencyCode, 'LKR');
      expect(after.selectedCurrencySymbol, 'Rs.');
    });

    test('changing currency only writes the two currency preferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'themePreference': 'dark',
        'paymentsOnlyMode': true,
        'defaultScreenIndex': 0,
        'selectedCurrencyCode': 'USD',
        'selectedCurrencySymbol': r'$',
      });
      final provider = StartupSettingsProvider();
      await provider.loadStartupSettings();
      await provider.setCurrency('LKR', 'Rs.');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {
        'themePreference',
        'paymentsOnlyMode',
        'defaultScreenIndex',
        'selectedCurrencyCode',
        'selectedCurrencySymbol',
      });
      expect(prefs.getString('themePreference'), 'dark');
      expect(prefs.getBool('paymentsOnlyMode'), isTrue);
      expect(prefs.getString('selectedCurrencyCode'), 'LKR');
      expect(prefs.getString('selectedCurrencySymbol'), 'Rs.');
    });

    test('switching from LKR back to an existing currency works', () async {
      final provider = StartupSettingsProvider();
      await provider.setCurrency('LKR', 'Rs.');
      await provider.setCurrency('INR', '₹');

      final reloaded = StartupSettingsProvider();
      await reloaded.loadStartupSettings();
      expect(reloaded.selectedCurrencyCode, 'INR');
      expect(reloaded.selectedCurrencySymbol, '₹');
    });
  });
}
