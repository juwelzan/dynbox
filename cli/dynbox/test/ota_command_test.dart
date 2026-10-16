import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dynbox/src/runner.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dynbox_ota_cmd_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OtaCommand Tests', () {
    test('dynbox ota status reports error if no project exists', () async {
      final runner = DynboxRunner();
      final exitCode = await runner.run([
        'ota',
        'status',
        '${tempDir.path}/nonexistent',
      ]);
      expect(exitCode, equals(1));
    });

    test(
      'dynbox ota init creates .dynbox/config.yaml with ota block',
      () async {
        final runner = DynboxRunner();
        final exitCode = await runner.run([
          'ota',
          'init',
          tempDir.path,
          '--channel',
          'staging',
          '--server-url',
          'https://ota.dynbox.dev',
          '--public-key',
          'my-secret-key',
        ]);
        expect(exitCode, equals(0));

        final configFile = File('${tempDir.path}/.dynbox/config.yaml');
        expect(configFile.existsSync(), isTrue);

        final content = configFile.readAsStringSync();
        expect(content, contains('ota:'));
        expect(content, contains('channel: staging'));
        expect(content, contains('serverUrl: https://ota.dynbox.dev'));
        expect(content, contains('publicKey: my-secret-key'));
      },
    );

    test('dynbox ota status outputs formatted configuration', () async {
      final runner = DynboxRunner();
      await runner.run([
        'ota',
        'init',
        tempDir.path,
        '--channel',
        'production',
      ]);

      final exitCode = await runner.run(['ota', 'status', tempDir.path]);
      expect(exitCode, equals(0));
    });

    test('dynbox ota check reports up to date in offline/mock mode', () async {
      final runner = DynboxRunner();
      await runner.run([
        'ota',
        'init',
        tempDir.path,
        '--channel',
        'production',
      ]);

      final exitCode = await runner.run(['ota', 'check', tempDir.path]);
      expect(exitCode, equals(0));
    });

    test(
      'dynbox ota validate validates Dynamic UI JSON and Release Manifest',
      () async {
        final runner = DynboxRunner();

        // 1. Dynamic UI payload validation
        final payloadFile = File('${tempDir.path}/payload.json');
        payloadFile.writeAsStringSync('{"schemaVersion":1,"screens":{}}');

        final exitCode1 = await runner.run([
          'ota',
          'validate',
          payloadFile.path,
          '--secret-key',
          'test-secret',
        ]);
        expect(exitCode1, equals(0));

        // 2. Valid Manifest validation
        final sha = crypto.sha256
            .convert(utf8.encode('{"schemaVersion":1,"screens":{}}'))
            .toString();
        final manifestFile = File('${tempDir.path}/manifest.json');
        manifestFile.writeAsStringSync(
          jsonEncode({
            'schemaVersion': '1.0',
            'appId': 'test.app',
            'releaseId': 'rel_1',
            'version': 1,
            'channel': 'production',
            'platform': 'all',
            'minAppVersion': '1.0.0',
            'runtimeSchemaVersion': '1.0',
            'payloadSha256': sha,
            'payloadSizeBytes': 32,
            'publishedAt': DateTime.now().toIso8601String(),
          }),
        );

        final exitCode2 = await runner.run([
          'ota',
          'validate',
          manifestFile.path,
        ]);
        expect(exitCode2, equals(0));

        // 3. Invalid Manifest validation (bad sha length)
        final invalidManifest = File('${tempDir.path}/invalid.json');
        invalidManifest.writeAsStringSync(
          jsonEncode({
            'schemaVersion': '1.0',
            'appId': 'test.app',
            'releaseId': 'rel_1',
            'version': 1,
            'payloadSha256': 'short_hash',
            'payloadSizeBytes': 32,
          }),
        );

        final exitCode3 = await runner.run([
          'ota',
          'validate',
          invalidManifest.path,
        ]);
        expect(exitCode3, equals(1));
      },
    );

    test(
      'dynbox ota publish stages local manifest when no server is set',
      () async {
        final runner = DynboxRunner();
        await runner.run([
          'ota',
          'init',
          tempDir.path,
          '--channel',
          'production',
        ]);

        final payloadFile = File('${tempDir.path}/ui.json');
        payloadFile.writeAsStringSync('{"schemaVersion":1,"screens":{}}');

        final exitCode = await runner.run([
          'ota',
          'publish',
          tempDir.path,
          '--payload',
          payloadFile.path,
          '--secret-key',
          'my-key',
          '--confirm',
        ]);
        expect(exitCode, equals(0));
      },
    );

    test('dynbox ota publish to production requires explicit --confirm flag', () async {
      final runner = DynboxRunner();
      await runner.run([
        'ota',
        'init',
        tempDir.path,
        '--channel',
        'production',
      ]);

      final payloadFile = File('${tempDir.path}/ui.json');
      payloadFile.writeAsStringSync('{"schemaVersion":1,"screens":{}}');

      final exitCode = await runner.run([
        'ota',
        'publish',
        tempDir.path,
        '--payload',
        payloadFile.path,
      ]);
      expect(exitCode, equals(1));
    });

    test('dynbox ota sync-source creates valid secret-free snapshot', () async {
      final runner = DynboxRunner();
      await runner.run([
        'ota',
        'init',
        tempDir.path,
        '--channel',
        'production',
      ]);

      // Add a normal source file
      final srcFile = File('${tempDir.path}/lib/main.dart');
      srcFile.parent.createSync(recursive: true);
      srcFile.writeAsStringSync('void main() {}');

      // Add a secret file that MUST be excluded
      final secretFile = File('${tempDir.path}/android/key.properties');
      secretFile.parent.createSync(recursive: true);
      secretFile.writeAsStringSync('storePassword=secret');

      final dotEnvFile = File('${tempDir.path}/.env');
      dotEnvFile.writeAsStringSync('API_SECRET=supersecret');

      final outSnapshot = File('${tempDir.path}/snapshot.json');

      final exitCode = await runner.run([
        'ota',
        'sync-source',
        tempDir.path,
        '--output',
        outSnapshot.path,
      ]);
      expect(exitCode, equals(0));
      expect(outSnapshot.existsSync(), isTrue);

      final snapshotData = jsonDecode(outSnapshot.readAsStringSync()) as Map<String, dynamic>;
      expect(snapshotData['schemaVersion'], equals('1.0'));
      expect(snapshotData['files'], isNotNull);

      final files = snapshotData['files'] as Map<String, dynamic>;
      expect(files.containsKey('lib/main.dart'), isTrue);
      // Secrets must be excluded
      expect(files.containsKey('android/key.properties'), isFalse);
      expect(files.containsKey('.env'), isFalse);
    });
  });
}

