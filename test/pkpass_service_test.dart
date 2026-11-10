import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/models/pass.dart';
import 'package:wallet/services/pkpass_service.dart';

/// Dummy pass data only.
Pass dummyPass() => Pass(
      type: 'storeCard',
      organizationName: 'DUMMY STORE',
      description: 'Dummy loyalty card',
      barcodeValue: '1234567890',
      barcodeFormat: 'PKBarcodeFormatQR',
    );

List<int> zipOf(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.addFile(ArchiveFile(name, content.length, content));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory dir;
  final service = PkpassService.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rcbwallet_pkpass_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<String> writeFile(String name, List<int> bytes) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('parsePkpass', () {
    test('imports a pass exported by generatePkpass', () async {
      final bytes = await service.generatePkpass(dummyPass());
      expect(bytes, isNotNull);
      final path = await writeFile('dummy.pkpass', bytes!);

      final pass = await service.parsePkpass(path);

      expect(pass, isNotNull);
      expect(pass!.organizationName, 'DUMMY STORE');
      expect(pass.description, 'Dummy loyalty card');
      expect(pass.barcodeValue, '1234567890');
      expect(pass.barcodeFormat, 'PKBarcodeFormatQR');
    });

    test('imports a .pkpass nested inside another archive', () async {
      final inner = await service.generatePkpass(dummyPass());
      final path = await writeFile(
        'outer.pkpasses',
        zipOf({'inner.pkpass': inner!}),
      );

      final pass = await service.parsePkpass(path);

      expect(pass?.organizationName, 'DUMMY STORE');
    });

    test('returns null for a file that does not exist', () async {
      expect(await service.parsePkpass('${dir.path}/missing.pkpass'), isNull);
    });

    test('returns null for a file that is not a zip archive', () async {
      final path = await writeFile('not_a_zip.pkpass', utf8.encode('hello'));
      expect(await service.parsePkpass(path), isNull);
    });

    test('returns null for an archive without pass.json', () async {
      final path = await writeFile(
        'no_pass_json.pkpass',
        zipOf({'manifest.json': utf8.encode('{}')}),
      );
      expect(await service.parsePkpass(path), isNull);
    });

    test('returns null for malformed pass.json', () async {
      final path = await writeFile(
        'bad_json.pkpass',
        zipOf({'pass.json': utf8.encode('{ not valid json')}),
      );
      expect(await service.parsePkpass(path), isNull);
    });
  });
}
