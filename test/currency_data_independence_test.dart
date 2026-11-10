import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/models/startup_settings_provider.dart';
import 'package:wallet/models/wallet.dart';
import 'package:wallet/services/currency_formatter.dart';

Wallet sampleCard() => Wallet(
      id: 1,
      name: 'Sample Card',
      number: '4111111111111111',
      expiry: '12/30',
      network: 'visa',
      issuer: 'Sample Bank',
      customFields: const {'note': 'test'},
      spends: '25500',
      rewards: '2',
      annualFeeWaiver: '125000',
      maxlimit: '500000',
      cardtype: 'Paid',
      billdate: '15',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('changing the currency does not change stored card amounts', () async {
    final card = sampleCard();
    final before = card.toMap();

    final provider = StartupSettingsProvider();
    for (final c in StartupSettingsProvider.majorCurrencies) {
      await provider.setCurrency(c['code']!, c['symbol']!);
      // Display formatting is read-only.
      CurrencyFormatter.formatStored(
        card.maxlimit,
        currencyCode: c['code']!,
        symbol: c['symbol']!,
      );
      CurrencyFormatter.formatStored(
        card.spends,
        currencyCode: c['code']!,
        symbol: c['symbol']!,
      );
    }

    expect(card.toMap(), before);
    expect(card.maxlimit, '500000');
    expect(card.spends, '25500');
    expect(card.annualFeeWaiver, '125000');
  });

  test('card data has no currency field, so amounts are never converted', () {
    final keys = sampleCard().toMap().keys;
    expect(keys.any((k) => k.toLowerCase().contains('currency')), isFalse);
  });

  test('backup/share JSON round-trip keeps cards and the LKR setting', () {
    // Mirrors the structure BackupService writes to data.json: cards via
    // Wallet.toMap() and settings as plain SharedPreferences values.
    final card = sampleCard();
    final exported = jsonEncode({
      'version': '4.0',
      'wallets': [card.toMap()],
      'settings': {
        'selectedCurrencyCode': 'LKR',
        'selectedCurrencySymbol': 'Rs.',
      },
    });

    final imported = jsonDecode(exported) as Map<String, dynamic>;
    final restored = Wallet.fromMap(
      Map<String, dynamic>.from((imported['wallets'] as List).single as Map),
    );
    expect(restored.toMap(), card.toMap());

    final settings = imported['settings'] as Map<String, dynamic>;
    expect(settings['selectedCurrencyCode'], 'LKR');
    expect(settings['selectedCurrencySymbol'], 'Rs.');
    expect(
      CurrencyFormatter.formatStored(
        restored.maxlimit,
        currencyCode: settings['selectedCurrencyCode'] as String,
        symbol: settings['selectedCurrencySymbol'] as String,
      ),
      'Rs. 500,000.00',
    );
  });

  test('restored LKR settings load correctly after restart', () async {
    // BackupService restores String settings with prefs.setString.
    SharedPreferences.setMockInitialValues({
      'selectedCurrencyCode': 'LKR',
      'selectedCurrencySymbol': 'Rs.',
    });
    final provider = StartupSettingsProvider();
    await provider.loadStartupSettings();
    expect(provider.selectedCurrencyCode, 'LKR');
    expect(provider.selectedCurrencySymbol, 'Rs.');
  });
}
