import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/models/identity_card.dart';
import 'package:wallet/widgets/identity_card_widget.dart';

// Dummy identity data only.
const longName =
    'Mudiyanselage Rananjaya Chathuranga Bandaranayake Wijesekara Senanayake';
const docNumber = '200012345678';

Future<void> pumpCard(
  WidgetTester tester,
  IdentityCard card, {
  double screenWidth = 360,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(screenWidth * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Padding(
            // Same horizontal padding as the identity list on the home screen.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: IdentityCardWidget(card: card, onTap: () {}),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The widget's rect must contain the rect of the text [text].
void expectInsideCard(WidgetTester tester, String text) {
  final card = tester.getRect(find.byType(IdentityCardWidget));
  final finder = find.textContaining(text);
  expect(finder, findsOneWidget, reason: '"$text" should be shown');
  final r = tester.getRect(finder);
  const eps = 0.5;
  expect(r.top >= card.top - eps && r.bottom <= card.bottom + eps, isTrue,
      reason: '"$text" ($r) must be vertically inside the card ($card)');
  expect(r.left >= card.left - eps && r.right <= card.right + eps, isTrue,
      reason: '"$text" ($r) must be horizontally inside the card ($card)');
}

void main() {
  testWidgets('short name: name and document number inside the card',
      (tester) async {
    await pumpCard(tester, IdentityCard(name: 'Jane Doe', value: docNumber));
    expect(tester.takeException(), isNull);
    expectInsideCard(tester, 'JANE DOE');
    expectInsideCard(tester, docNumber);
  });

  testWidgets('long full name: document number stays visible inside the card',
      (tester) async {
    await pumpCard(tester, IdentityCard(name: longName, value: docNumber));
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
    expectInsideCard(tester, docNumber);
    expectInsideCard(tester, 'MUDIYANSELAGE');
  });

  testWidgets('long full name on a small phone (320 dp)', (tester) async {
    await pumpCard(tester, IdentityCard(name: longName, value: docNumber),
        screenWidth: 320);
    expect(tester.takeException(), isNull);
    expectInsideCard(tester, docNumber);
  });

  testWidgets('long full name with large system font (130%)', (tester) async {
    await pumpCard(tester, IdentityCard(name: longName, value: docNumber),
        textScale: 1.3);
    expect(tester.takeException(), isNull);
    expectInsideCard(tester, docNumber);
  });

  testWidgets('very long document number is shown in full inside the card',
      (tester) async {
    const longNumber = 'P1234567890ABCDEFGHIJ1234567890';
    await pumpCard(tester, IdentityCard(name: 'Jane Doe', value: longNumber));
    expect(tester.takeException(), isNull);
    expectInsideCard(tester, longNumber);
  });

  testWidgets('long card type does not overflow the header', (tester) async {
    await pumpCard(
      tester,
      IdentityCard(
        name: 'Jane Doe',
        value: docNumber,
        cardType: 'National Identity Card Of The Democratic Socialist Republic',
      ),
    );
    expect(tester.takeException(), isNull);
    expectInsideCard(tester, docNumber);
  });
}
