import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wallet/models/db_helper.dart';
import 'package:wallet/services/encryption_service.dart';

// The wallets table exactly as created by schema version 8 (before reminders).
const v8CreateSql = '''
  CREATE TABLE wallets(
    id INTEGER PRIMARY KEY,
    name TEXT, number TEXT, expiry TEXT, network TEXT, issuer TEXT,
    customFields TEXT, spends TEXT, rewards TEXT, annualFeeWaiver TEXT,
    maxlimit TEXT, cardtype TEXT, billdate TEXT, category TEXT, color TEXT,
    frontImagePath TEXT, backImagePath TEXT, pdfPath TEXT, pdfName TEXT,
    orderIndex INTEGER DEFAULT 0
  )''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;

  setUpAll(() async {
    // Dummy key (never a real one).
    FlutterSecureStorage.setMockInitialValues({
      'wallet_aes_256_master_key': base64Encode(Uint8List(32)..fillRange(0, 32, 0x42)),
    });
    await EncryptionService.instance.init(force: true);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rcbwallet_db_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<List<String>> columns(Database db) async =>
      [for (final c in await db.rawQuery('PRAGMA table_info(wallets)')) c['name'] as String];

  test('upgrade from v8 adds the annual fee columns and keeps cards', () async {
    final path = '${dir.path}/walletbox.db';
    final v8 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, _) => db.execute(v8CreateSql),
        ));
    final existing = Wallet(name: 'DUMMY', number: '4111111111111111', expiry: '0127');
    final id = await v8.insert('wallets', existing.toEncryptedMap()
      ..remove('annualFee')
      ..remove('annualFeeDueDay')
      ..remove('annualFeePaidYear'));
    await v8.close();

    final v9 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.walletsDbVersion,
          onCreate: DatabaseHelper.createWalletsTable,
          onUpgrade: DatabaseHelper.upgradeWalletsTable,
        ));
    expect(await v9.getVersion(), 9);
    expect(await columns(v9),
        containsAll(['annualFee', 'annualFeeDueDay', 'annualFeePaidYear']));

    final rows = await v9.query('wallets', where: 'id = ?', whereArgs: [id]);
    final restored = Wallet.fromEncryptedMap(rows.single);
    expect(restored.name, 'DUMMY');
    expect(restored.number, '4111111111111111');
    expect(restored.expiry, '0127');
    expect(restored.annualFee, isNull);
    expect(restored.annualFeeDueDay, isNull);
    expect(restored.annualFeePaidYear, isNull);
    await v9.close();
  });

  test('a fresh database is created at v9 with the new columns', () async {
    final db = await databaseFactoryFfi.openDatabase('${dir.path}/fresh.db',
        options: OpenDatabaseOptions(
          version: DatabaseHelper.walletsDbVersion,
          onCreate: DatabaseHelper.createWalletsTable,
          onUpgrade: DatabaseHelper.upgradeWalletsTable,
        ));
    expect(await columns(db),
        containsAll(['annualFee', 'annualFeeDueDay', 'annualFeePaidYear']));
    await db.close();
  });

  test('annual fee fields are stored encrypted and round-trip', () async {
    final wallet = Wallet(
      name: 'DUMMY',
      number: '4111111111111111',
      expiry: '0127',
      annualFee: '5000',
      annualFeeDueDay: '12-15',
      annualFeePaidYear: '2025',
    );
    final row = wallet.toEncryptedMap();
    for (final key in ['annualFee', 'annualFeeDueDay', 'annualFeePaidYear']) {
      expect(row[key], isNot(wallet.toMap()[key]), reason: '$key must not be plaintext');
      expect(row[key], contains(':'), reason: '$key uses the iv:ciphertext format');
    }
    final back = Wallet.fromEncryptedMap(row);
    expect(back.annualFee, '5000');
    expect(back.annualFeeDueDay, '12-15');
    expect(back.annualFeePaidYear, '2025');
  });

  test('backup/share maps include the new fields and old maps still load', () {
    final wallet = Wallet(
      name: 'DUMMY', number: '4111111111111111', expiry: '0127',
      annualFee: '5000', annualFeeDueDay: '12-15', annualFeePaidYear: '2025');
    final map = wallet.toMap();
    expect(Wallet.fromMap(jsonDecode(jsonEncode(map))).toMap(), map);

    // A map from an older backup has no annual fee keys.
    final oldMap = Map<String, dynamic>.from(map)
      ..remove('annualFee')
      ..remove('annualFeeDueDay')
      ..remove('annualFeePaidYear');
    final old = Wallet.fromMap(oldMap);
    expect(old.annualFee, isNull);
    expect(old.name, 'DUMMY');
  });
}
