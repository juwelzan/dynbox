import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dynbox_ota/dynbox_ota.dart';
import 'package:dynbox_ui_runtime/dynbox_ui_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('OtaManifest Tests', () {
    test('parses valid manifest from JSON map', () {
      final json = {
        'schemaVersion': '1.0',
        'appId': 'com.example.app',
        'releaseId': 'rel_001',
        'version': 2,
        'channel': 'production',
        'platform': 'android',
        'minAppVersion': '1.0.0',
        'runtimeSchemaVersion': '1.0',
        'payloadSha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'payloadSizeBytes': 1024,
        'publishedAt': '2026-10-16T12:00:00Z',
      };

      final manifest = OtaManifest.fromJson(json);
      expect(manifest.appId, equals('com.example.app'));
      expect(manifest.releaseId, equals('rel_001'));
      expect(manifest.version, equals(2));
      expect(manifest.channel, equals(OtaChannel.production));
      expect(manifest.platform, equals(OtaPlatform.android));
      expect(
        manifest.payloadSha256,
        equals(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
      );
    });

    test('rejects manifest with unsupported schemaVersion', () {
      final json = {
        'schemaVersion': '2.0',
        'appId': 'com.example.app',
        'releaseId': 'rel_001',
        'version': 2,
        'payloadSha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'payloadSizeBytes': 100,
        'publishedAt': '2026-10-16T12:00:00Z',
      };
      expect(
        () => OtaManifest.fromJson(json),
        throwsA(isA<OtaManifestException>()),
      );
    });

    test('rejects manifest with missing or empty appId', () {
      final json = {
        'schemaVersion': '1.0',
        'appId': '  ',
        'releaseId': 'rel_001',
        'version': 2,
        'payloadSha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'payloadSizeBytes': 100,
        'publishedAt': '2026-10-16T12:00:00Z',
      };
      expect(
        () => OtaManifest.fromJson(json),
        throwsA(isA<OtaManifestException>()),
      );
    });

    test('rejects manifest with invalid payloadSha256 length', () {
      final json = {
        'schemaVersion': '1.0',
        'appId': 'com.example.app',
        'releaseId': 'rel_001',
        'version': 2,
        'payloadSha256': 'short_hash',
        'payloadSizeBytes': 100,
        'publishedAt': '2026-10-16T12:00:00Z',
      };
      expect(
        () => OtaManifest.fromJson(json),
        throwsA(isA<OtaManifestException>()),
      );
    });

    test('rejects manifest with excessive payload size (>512KB)', () {
      final json = {
        'schemaVersion': '1.0',
        'appId': 'com.example.app',
        'releaseId': 'rel_001',
        'version': 2,
        'payloadSha256':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'payloadSizeBytes': 600000,
        'publishedAt': '2026-10-16T12:00:00Z',
      };
      expect(
        () => OtaManifest.fromJson(json),
        throwsA(isA<OtaManifestException>()),
      );
    });
  });

  group('OtaVerifier Tests', () {
    test('computes and verifies SHA256 digest accurately', () {
      final data = utf8.encode('Hello DynBox OTA');
      final expectedSha = crypto.sha256.convert(data).toString();

      expect(OtaVerifier.verifyDigest(data, expectedSha), isTrue);
      expect(OtaVerifier.verifyDigest(data, 'wrong_digest'), isFalse);
    });

    test('signs and verifies HMAC-SHA256 signature', () {
      const secret = 'super-secret-key';
      const payload = '{"type":"Text","text":"Updated DynBox UI"}';

      final signature = OtaVerifier.signData(data: payload, secretKey: secret);
      expect(signature, isNotEmpty);

      final valid = OtaVerifier.verifySignature(
        data: payload,
        signature: signature,
        secretOrPublicKey: secret,
      );
      expect(valid, isTrue);

      final tampered = OtaVerifier.verifySignature(
        data: '{"type":"Text","text":"Tampered UI"}',
        signature: signature,
        secretOrPublicKey: secret,
      );
      expect(tampered, isFalse);
    });
  });

  group('OtaCache & Rollback Tests', () {
    late Directory tempDir;
    late OtaCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dynbox_ota_cache_test_');
      cache = OtaCache(storageDir: tempDir);
      await cache.init();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initializes with activeVersion 0', () {
      expect(cache.state.activeVersion, equals(0));
      expect(cache.state.activeReleaseId, isNull);
    });

    test('stages and activates release with LKG preservation', () async {
      final manifest1 = OtaManifest(
        schemaVersion: '1.0',
        appId: 'test.app',
        releaseId: 'rel_1',
        version: 1,
        channel: OtaChannel.production,
        platform: OtaPlatform.all,
        minAppVersion: '1.0.0',
        runtimeSchemaVersion: '1.0',
        payloadSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        payloadSizeBytes: 50,
        publishedAt: DateTime.now(),
      );

      await cache.activateRelease(manifest: manifest1, payloadJson: '{"v":1}');
      expect(cache.state.activeVersion, equals(1));
      expect(cache.state.lkgVersion, isNull);

      final manifest2 = OtaManifest(
        schemaVersion: '1.0',
        appId: 'test.app',
        releaseId: 'rel_2',
        version: 2,
        channel: OtaChannel.production,
        platform: OtaPlatform.all,
        minAppVersion: '1.0.0',
        runtimeSchemaVersion: '1.0',
        payloadSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        payloadSizeBytes: 50,
        publishedAt: DateTime.now(),
      );

      await cache.activateRelease(manifest: manifest2, payloadJson: '{"v":2}');
      expect(cache.state.activeVersion, equals(2));
      expect(cache.state.lkgVersion, equals(1));
      expect(cache.state.lkgPayloadJson, equals('{"v":1}'));

      // Rollback to LKG
      final rolledBack = await cache.rollbackToLkg();
      expect(rolledBack, isTrue);
      expect(cache.state.activeVersion, equals(1));
      expect(cache.state.activePayloadJson, equals('{"v":1}'));
    });
  });

  group('DynboxOtaClient End-to-End Tests', () {
    late Directory tempDir;
    late OtaCache cache;
    late MockOtaServerProvider mockServer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'dynbox_ota_client_test_',
      );
      cache = OtaCache(storageDir: tempDir);
      await cache.init();
      mockServer = MockOtaServerProvider();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('no update returns upToDate status', () async {
      final client = DynboxOtaClient(
        config: const OtaClientConfig(appId: 'com.test', appVersion: '1.0.0'),
        provider: mockServer,
        cache: cache,
      );
      await client.init();

      final state = await client.checkForUpdate();
      expect(state.status, equals(OtaStatus.upToDate));
      expect(client.currentState.status, equals(OtaStatus.upToDate));
      client.dispose();
    });

    test('network failure sets failed status with message', () async {
      mockServer.shouldFail = true;
      final client = DynboxOtaClient(
        config: const OtaClientConfig(appId: 'com.test', appVersion: '1.0.0'),
        provider: mockServer,
        cache: cache,
      );
      await client.init();

      final state = await client.checkForUpdate();
      expect(state.status, equals(OtaStatus.failed));
      expect(state.errorMessage, contains('Mock server connection error'));
      client.dispose();
    });

    test('incompatible app version is rejected safely', () async {
      const payload = '{"type":"Text","text":"Hello"}';
      final payloadBytes = utf8.encode(payload);
      final sha = crypto.sha256.convert(payloadBytes).toString();

      final manifest = OtaManifest(
        schemaVersion: '1.0',
        appId: 'com.test',
        releaseId: 'rel_2',
        version: 2,
        channel: OtaChannel.production,
        platform: OtaPlatform.all,
        minAppVersion: '2.0.0', // Current app is 1.0.0
        runtimeSchemaVersion: '1.0',
        payloadSha256: sha,
        payloadSizeBytes: payloadBytes.length,
        publishedAt: DateTime.now(),
      );

      mockServer.stageRelease(manifest: manifest, payload: payload);

      final client = DynboxOtaClient(
        config: const OtaClientConfig(appId: 'com.test', appVersion: '1.0.0'),
        provider: mockServer,
        cache: cache,
      );
      await client.init();

      final state = await client.checkForUpdate();
      expect(state.status, equals(OtaStatus.failed));
      expect(state.errorMessage, contains('requires app version 2.0.0'));
      client.dispose();
    });

    test('successful check, download, verification, and auto-activation', () async {
      const payload =
          '{"schemaVersion":1,"configId":"test","revision":1,"screens":{"home":{"title":"OTA","root":{"type":"text","properties":{"text":"Welcome to OTA"}}}}}';
      final payloadBytes = utf8.encode(payload);
      final sha = crypto.sha256.convert(payloadBytes).toString();
      const secret = 'verify-key-123';
      final sig = OtaVerifier.signData(data: payload, secretKey: secret);

      final manifest = OtaManifest(
        schemaVersion: '1.0',
        appId: 'com.test',
        releaseId: 'rel_1',
        version: 1,
        channel: OtaChannel.production,
        platform: OtaPlatform.all,
        minAppVersion: '1.0.0',
        runtimeSchemaVersion: '1.0',
        payloadSha256: sha,
        payloadSizeBytes: payloadBytes.length,
        publishedAt: DateTime.now(),
        signature: sig,
      );

      mockServer.stageRelease(manifest: manifest, payload: payload);

      final client = DynboxOtaClient(
        config: const OtaClientConfig(
          appId: 'com.test',
          appVersion: '1.0.0',
          verificationKey: secret,
          autoActivate: true,
        ),
        provider: mockServer,
        cache: cache,
      );
      await client.init();

      final checkState = await client.checkForUpdate();
      expect(checkState.status, equals(OtaStatus.updateAvailable));

      final success = await client.downloadAndVerifyUpdate();
      expect(success, isTrue);
      expect(client.currentState.status, equals(OtaStatus.upToDate));
      expect(client.currentState.activeVersion, equals(1));
      expect(client.activePayloadJson, equals(payload));
      client.dispose();
    });

    test('corrupted payload SHA-256 causes download verification rejection', () async {
      const payload =
          '{"schemaVersion":1,"configId":"test","revision":1,"screens":{}}';
      const tampered =
          '{"schemaVersion":1,"configId":"test","revision":1,"screens":{"h":{}}}';
      final originalSha = crypto.sha256
          .convert(utf8.encode(payload))
          .toString();

      final manifest = OtaManifest(
        schemaVersion: '1.0',
        appId: 'com.test',
        releaseId: 'rel_1',
        version: 1,
        channel: OtaChannel.production,
        platform: OtaPlatform.all,
        minAppVersion: '1.0.0',
        runtimeSchemaVersion: '1.0',
        payloadSha256: originalSha,
        payloadSizeBytes: 200,
        publishedAt: DateTime.now(),
      );

      // Server serves tampered bytes
      mockServer.stageRelease(manifest: manifest, payload: tampered);

      final client = DynboxOtaClient(
        config: const OtaClientConfig(appId: 'com.test', appVersion: '1.0.0'),
        provider: mockServer,
        cache: cache,
      );
      await client.init();

      await client.checkForUpdate();
      final success = await client.downloadAndVerifyUpdate();

      expect(success, isFalse);
      expect(client.currentState.status, equals(OtaStatus.failed));
      expect(
        client.currentState.errorMessage,
        contains('SHA-256 digest mismatch'),
      );
      client.dispose();
    });
  });

  group('DynboxOtaService Integration with DynamicUiController', () {
    late Directory tempDir;
    late MockOtaServerProvider mockServer;
    late DynamicUiController uiController;

    final bundledJson = jsonEncode({
      'schemaVersion': 1,
      'configId': 'com.test.app',
      'revision': 1,
      'screens': {
        'home': {
          'title': 'Bundled Screen',
          'root': {
            'type': 'text',
            'properties': {'text': 'Bundled Version'},
          },
        },
      },
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'dynbox_ota_service_test_',
      );
      mockServer = MockOtaServerProvider();
      uiController = DynamicUiController();
      await uiController.initialize(bundledDefaultJson: bundledJson);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'updates DynamicUiController when update succeeds and rolls back cleanly',
      () async {
        final updatedPayload = jsonEncode({
          'schemaVersion': 1,
          'configId': 'com.test.app',
          'revision': 2,
          'screens': {
            'home': {
              'title': 'OTA Screen',
              'root': {
                'type': 'text',
                'properties': {'text': 'Over-The-Air Updated Version'},
              },
            },
          },
        });
        final sha = crypto.sha256
            .convert(utf8.encode(updatedPayload))
            .toString();

        final manifest = OtaManifest(
          schemaVersion: '1.0',
          appId: 'com.test',
          releaseId: 'rel_2',
          version: 2,
          channel: OtaChannel.production,
          platform: OtaPlatform.all,
          minAppVersion: '1.0.0',
          runtimeSchemaVersion: '1.0',
          payloadSha256: sha,
          payloadSizeBytes: utf8.encode(updatedPayload).length,
          publishedAt: DateTime.now(),
        );

        mockServer.stageRelease(manifest: manifest, payload: updatedPayload);

        final service = await DynboxOtaService.create(
          config: const OtaClientConfig(appId: 'com.test', appVersion: '1.0.0'),
          uiController: uiController,
          provider: mockServer,
          storageDir: tempDir,
        );

        // Initially bundled
        expect(uiController.activeDocument!.revision, equals(1));
        expect(
          uiController.activeDocument!.screens['home']!.root.properties.text,
          equals('Bundled Version'),
        );

        // Check and update
        await service.checkForUpdate();
        final updated = await service.downloadAndVerify();
        expect(updated, isTrue);

        // Verifying controller updated dynamically
        expect(uiController.activeDocument!.revision, equals(2));
        expect(
          uiController.activeDocument!.screens['home']!.root.properties.text,
          equals('Over-The-Air Updated Version'),
        );

        // Rollback
        final rolledBack = await service.rollback();
        expect(rolledBack, isTrue);
        // Back to bundled default
        expect(uiController.activeDocument!.revision, equals(1));
        expect(
          uiController.activeDocument!.screens['home']!.root.properties.text,
          equals('Bundled Version'),
        );

        service.dispose();
      },
    );
  });

  group('SupabaseOtaServerProvider Tests', () {
    test('strictly forbids service_role or secret keys at construction', () {
      expect(
        () => SupabaseOtaServerProvider(
          supabaseUrl: 'https://xyz.supabase.co',
          anonKey: 'sb_secret_role_1234567890',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => SupabaseOtaServerProvider(
          supabaseUrl: 'https://xyz.supabase.co',
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.service_role',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts valid publishable or anon keys', () {
      final provider = SupabaseOtaServerProvider(
        supabaseUrl: 'https://xyz.supabase.co',
        anonKey: 'sb_publishable_testkey123',
      );
      expect(provider.supabaseUrl, equals('https://xyz.supabase.co'));
      expect(provider.anonKey, equals('sb_publishable_testkey123'));
    });
  });
}

