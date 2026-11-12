import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wallet/models/db_helper.dart';
import 'package:wallet/models/provider_helper.dart';
import 'package:wallet/models/startup_settings_provider.dart';
import 'package:wallet/models/theme_provider.dart';
import 'package:wallet/pages/walletdetails.dart';
import 'package:wallet/screens/barcode_card_details_screen.dart';
import 'package:wallet/screens/identity_card_details_screen.dart';
import 'package:wallet/widgets/barcode_card_entry_form.dart';
import 'package:wallet/widgets/credit_card_entry_form.dart';
import 'package:wallet/widgets/identity_card_entry_form.dart';

/// When the app draws edge-to-edge (enforced on Android 15+ for apps that
/// target SDK 35+), the Save button of every add/edit form and the last
/// section of every detail screen must end above Android's navigation bar,
/// for gesture and three-button navigation, and Save must stay reachable
/// above the keyboard.
void main() {
  const dpr = 2.625;
  const screen = Size(1080, 2400); // physical pixels, a typical phone

  // Bottom system inset in logical pixels.
  const insets = {'no inset': 0.0, 'gesture navigation': 24.0, 'three-button navigation': 48.0};

  void setInset(WidgetTester t, double bottomDp, {double keyboardDp = 0}) {
    t.view.physicalSize = screen;
    t.view.devicePixelRatio = dpr;
    t.view.viewPadding = FakeViewPadding(bottom: bottomDp * dpr);
    // As on a device: padding is viewPadding minus what the keyboard covers.
    final padBottom = (bottomDp - keyboardDp).clamp(0, double.infinity) * dpr;
    t.view.padding = FakeViewPadding(bottom: padBottom.toDouble());
    t.view.viewInsets = FakeViewPadding(bottom: keyboardDp * dpr);
    addTearDown(t.view.reset);
  }

  Widget app(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => StartupSettingsProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => PassProvider()),
          ChangeNotifierProvider(create: (_) => IdentityProvider()),
        ],
        child: MaterialApp(home: home),
      );

  // The card edit screen has a debug-only notice (a ListTile in a coloured
  // DecoratedBox hides its ripple) that is unrelated to these tests. Ignore
  // exactly that message; any other error still fails.
  void Function(FlutterErrorDetails)? ignoreKnownNotice() {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('ListTile background color or ink splashes may be invisible')) return;
      original?.call(d);
    };
    return original;
  }

  Future<void> scrollToEnd(WidgetTester t) async {
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var i = 0; i < 30 && pos.pixels < pos.maxScrollExtent; i++) {
      pos.jumpTo(pos.maxScrollExtent);
      await t.pump();
    }
  }

  double visibleBottom(double insetDp, double keyboardDp) =>
      screen.height / dpr - (keyboardDp > insetDp ? keyboardDp : insetDp);

  Rect saveButton(WidgetTester t, String label) =>
      t.getRect(find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)));

  // --- Add / edit forms with a bottom Save button ---------------------------------

  final forms = <String, (Widget Function(), String)>{
    'Add payment card': (() => const Scaffold(body: CreditCardEntryForm()), 'SAVE CARD'),
    'Add/edit identity document': (() => const Scaffold(body: IdentityCardEntryForm()), 'SAVE IDENTITY CARD'),
    'Add/edit pass or other item': (() => const Scaffold(body: BarcodeCardEntryForm()), 'SAVE PASS'),
  };

  for (final MapEntry(key: name, value: (build, label)) in forms.entries) {
    for (final MapEntry(key: mode, value: inset) in insets.entries) {
      testWidgets('$name: Save is fully above the navigation bar ($mode)', (t) async {
        setInset(t, inset);
        await t.pumpWidget(app(build()));
        await t.pump();
        await scrollToEnd(t);
        final button = saveButton(t, label);
        expect(button.bottom, lessThanOrEqualTo(visibleBottom(inset, 0)),
            reason: '$label ends at ${button.bottom}, the navigation bar starts at ${visibleBottom(inset, 0)}');
      });
    }

    testWidgets('$name: with the keyboard open, Save can still be scrolled above it', (t) async {
      setInset(t, 48, keyboardDp: 300);
      await t.pumpWidget(app(build()));
      await t.pump();
      await scrollToEnd(t);
      expect(saveButton(t, label).bottom, lessThanOrEqualTo(visibleBottom(48, 300)));
      // No extra navigation-bar gap above the keyboard.
      expect((t.widget<ListView>(find.byType(ListView).first).padding as EdgeInsets).bottom, 16);
    });
  }

  // --- Long form and detail screens: the last content scrolls above the bar ---

  final screens = <String, Widget Function()>{
    'Edit payment card': () =>
        WalletEditScreen(wallet: Wallet(name: 'DUMMY', number: '4111111111111111', expiry: '0127')),
    'Card details': () => WalletDetailScreen(
          wallet: Wallet(
            id: 1,
            name: 'DUMMY',
            number: '4111111111111111',
            expiry: '0127',
            customFields: {'Note': 'dummy note', 'Branch': 'dummy branch'},
          ),
        ),
    'Pass details': () => BarcodeCardDetailScreen(
          pass: Pass(type: 'loyaltyCard', organizationName: 'DUMMY STORE', barcodeValue: '000000000000'),
        ),
    'Identity details': () => IdentityCardDetailScreen(
          card: IdentityCard(name: 'DUMMY PERSON', value: 'X0000000'),
        ),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final MapEntry(key: mode, value: inset) in insets.entries) {
      testWidgets('$name: the last content scrolls above the navigation bar ($mode)', (t) async {
        setInset(t, inset);
        final original = ignoreKnownNotice();
        await t.pumpWidget(app(build()));
        await t.pump();

        final listFinder = find.byType(ListView).first;
        expect((t.widget<ListView>(listFinder).padding as EdgeInsets).bottom, 16 + inset,
            reason: 'the list keeps its 16 px and adds the bottom system inset');

        await scrollToEnd(t);
        var lowest = 0.0;
        for (final e in find.descendant(of: listFinder, matching: find.byType(Text)).evaluate()) {
          final box = e.renderObject as RenderBox?;
          if (box == null || !box.hasSize || !box.attached) continue;
          final r = box.localToGlobal(Offset.zero) & box.size;
          if (r.top < screen.height / dpr && r.bottom > lowest) lowest = r.bottom;
        }
        expect(lowest, lessThanOrEqualTo(visibleBottom(inset, 0)),
            reason: 'lowest text ends at $lowest, the navigation bar starts at ${visibleBottom(inset, 0)}');
        FlutterError.onError = original;
      });
    }
  }
}
