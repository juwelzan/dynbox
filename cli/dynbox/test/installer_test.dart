import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dynbox/src/commands/uninstall_command.dart';
import 'package:dynbox/src/commands/upgrade_command.dart';
import 'package:dynbox/src/installer/installer_models.dart';
import 'package:dynbox/src/installer/uninstaller.dart';
import 'package:dynbox/src/installer/updater.dart';
import 'package:dynbox/src/runner.dart';
import 'package:dynbox/src/version.dart';
import 'package:test/test.dart';

class MockReleaseClient implements ReleaseClient {
  final ReleaseManifest manifest;
  final Map<String, List<int>> artifactBytes;

  MockReleaseClient({required this.manifest, required this.artifactBytes});

  @override
  Future<ReleaseManifest> fetchManifest({String? version}) async {
    return manifest;
  }

  @override
  Future<void> downloadArtifact({
    required String url,
    required File destination,
  }) async {
    final fileName = Uri.parse(url).pathSegments.last;
    final bytes = artifactBytes[fileName];
    if (bytes == null) {
      throw HttpException('Not found: $fileName');
    }
    await destination.writeAsBytes(bytes);
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dynbox_installer_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DistributionPlatform & Installer Models', () {
    test('resolves current host platform and architecture', () {
      final host = DistributionPlatform.currentHost();
      expect(host, isNotNull);
      if (Platform.isMacOS) {
        expect(
          host == DistributionPlatform.macosArm64 ||
              host == DistributionPlatform.macosX64,
          isTrue,
        );
      }
    });

    test('serializes and deserializes ReleaseManifest cleanly', () {
      final manifestJson = '''
{
  "schemaVersion": "1.0",
  "version": "0.2.0",
  "publishedAt": "2026-10-16T12:00:00.000Z",
  "artifacts": {
    "macos-arm64": {
      "fileName": "dynbox-v0.2.0-macos-arm64.tar.gz",
      "sha256": "abcdef123456",
      "sizeBytes": 15000000
    }
  }
}
''';
      final manifest = ReleaseManifest.fromString(manifestJson);
      expect(manifest.version, '0.2.0');
      expect(manifest.artifacts.containsKey('macos-arm64'), isTrue);
      expect(
        manifest.artifacts['macos-arm64']!.fileName,
        'dynbox-v0.2.0-macos-arm64.tar.gz',
      );

      final encoded = manifest.toJson();
      expect(encoded['version'], '0.2.0');
      expect(
        (encoded['artifacts'] as Map)['macos-arm64']['sha256'],
        'abcdef123456',
      );
    });

    test(
      'IntegrityVerifier verifies matching SHA-256 and rejects mismatches',
      () async {
        final testFile = File('${tempDir.path}/test_binary');
        final content = utf8.encode('DYNBOX_BINARY_MOCK_CONTENT');
        testFile.writeAsBytesSync(content);
        final expectedSha = crypto.sha256.convert(content).toString();

        final matches = await IntegrityVerifier.verifyFile(
          testFile,
          expectedSha,
        );
        expect(matches, isTrue);

        final wrongSha =
            '0000000000000000000000000000000000000000000000000000000000000000';
        final rejects = await IntegrityVerifier.verifyFile(testFile, wrongSha);
        expect(rejects, isFalse);
      },
    );
  });

  group('DynboxUpdater & Atomic Upgrades', () {
    test('checkForUpgrade detects newer version', () async {
      final manifest = ReleaseManifest(
        schemaVersion: '1.0',
        version: '0.2.0',
        publishedAt: DateTime.now(),
        artifacts: {
          DistributionPlatform.currentHost()!.identifier: const ReleaseArtifact(
            fileName: 'dynbox-v0.2.0-test.tar.gz',
            sha256: 'mockhash',
            sizeBytes: 1000,
          ),
        },
      );

      final client = MockReleaseClient(manifest: manifest, artifactBytes: {});

      final updater = DynboxUpdater(client: client);
      final check = await updater.checkForUpgrade();

      expect(check.isUpgradeAvailable, isTrue);
      expect(check.currentVersion, DynboxVersion.version);
      expect(check.latestVersion, '0.2.0');
    });

    test(
      'performUpgrade replaces target binary and verifies checksum',
      () async {
        final currentExe = File('${tempDir.path}/dynbox');
        currentExe.writeAsStringSync('OLD_DYNBOX_V0_1_0');

        final newContent = utf8.encode('NEW_DYNBOX_V0_2_0');
        final newSha = crypto.sha256.convert(newContent).toString();
        final hostId = DistributionPlatform.currentHost()!.identifier;

        final manifest = ReleaseManifest(
          schemaVersion: '1.0',
          version: '0.2.0',
          publishedAt: DateTime.now(),
          artifacts: {
            hostId: ReleaseArtifact(
              fileName: 'dynbox-v0.2.0-mock',
              sha256: newSha,
              sizeBytes: newContent.length,
            ),
          },
        );

        final client = MockReleaseClient(
          manifest: manifest,
          artifactBytes: {'dynbox-v0.2.0-mock': newContent},
        );

        final updater = DynboxUpdater(
          client: client,
          targetExecutableOverride: currentExe,
        );

        final message = await updater.performUpgrade();
        expect(message, contains('Successfully upgraded DynBox'));
        expect(currentExe.readAsStringSync(), 'NEW_DYNBOX_V0_2_0');
        expect(File('${currentExe.path}.dynbox_backup').existsSync(), isFalse);
      },
    );

    test(
      'performUpgrade rejects corrupted checksum and retains existing binary',
      () async {
        final currentExe = File('${tempDir.path}/dynbox');
        currentExe.writeAsStringSync('OLD_DYNBOX_V0_1_0');

        final newContent = utf8.encode('CORRUPTED_DOWNLOAD');
        final hostId = DistributionPlatform.currentHost()!.identifier;

        final manifest = ReleaseManifest(
          schemaVersion: '1.0',
          version: '0.2.0',
          publishedAt: DateTime.now(),
          artifacts: {
            hostId: ReleaseArtifact(
              fileName: 'dynbox-v0.2.0-corrupt',
              sha256: 'DIFFERENT_HASH_VALUE',
              sizeBytes: newContent.length,
            ),
          },
        );

        final client = MockReleaseClient(
          manifest: manifest,
          artifactBytes: {'dynbox-v0.2.0-corrupt': newContent},
        );

        final updater = DynboxUpdater(
          client: client,
          targetExecutableOverride: currentExe,
        );

        expect(
          () => updater.performUpgrade(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Checksum verification failed'),
            ),
          ),
        );
        expect(currentExe.readAsStringSync(), 'OLD_DYNBOX_V0_1_0');
      },
    );
  });

  group('DynboxUninstaller & Non-Destructive Scoping', () {
    test('removes only dynbox-owned files in installation directory', () async {
      final installDir = Directory('${tempDir.path}/dynbox_bin');
      installDir.createSync(recursive: true);

      final dynboxExe = File('${installDir.path}/dynbox');
      dynboxExe.writeAsStringSync('binary');

      final dynboxTmp = File('${installDir.path}/.dynbox_tmp');
      dynboxTmp.writeAsStringSync('tmp');

      final unrelatedUserFile = File('${installDir.path}/user_script.sh');
      unrelatedUserFile.writeAsStringSync('echo hello');

      final uninstaller = DynboxUninstaller(installDirOverride: installDir);
      final targeted = uninstaller.listDynboxFiles();

      expect(targeted.any((f) => f.path.endsWith('/dynbox')), isTrue);
      expect(targeted.any((f) => f.path.endsWith('/.dynbox_tmp')), isTrue);
      expect(targeted.any((f) => f.path.endsWith('/user_script.sh')), isFalse);

      final result = await uninstaller.uninstall();
      expect(result, contains('Successfully removed 2 DynBox file(s)'));
      expect(dynboxExe.existsSync(), isFalse);
      expect(dynboxTmp.existsSync(), isFalse);
      expect(unrelatedUserFile.existsSync(), isTrue);
    });
  });

  group('CLI Commands Integration', () {
    test('dynbox --help registers upgrade and uninstall commands', () async {
      final runner = DynboxRunner();
      expect(runner.commands.containsKey('upgrade'), isTrue);
      expect(runner.commands.containsKey('uninstall'), isTrue);
    });

    test('dynbox upgrade --check reports status cleanly', () async {
      final manifest = ReleaseManifest(
        schemaVersion: '1.0',
        version: DynboxVersion.version,
        publishedAt: DateTime.now(),
        artifacts: {
          DistributionPlatform.currentHost()!.identifier: const ReleaseArtifact(
            fileName: 'dynbox-latest',
            sha256: 'mock',
            sizeBytes: 100,
          ),
        },
      );
      final client = MockReleaseClient(manifest: manifest, artifactBytes: {});
      final updater = DynboxUpdater(client: client);

      final command = UpgradeCommand(updaterOverride: updater);
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);

      final exitCode = await runner.run(['upgrade', '--check']);
      expect(exitCode, 0);
    });

    test('dynbox uninstall --yes runs non-interactively', () async {
      final installDir = Directory('${tempDir.path}/dynbox_bin');
      installDir.createSync(recursive: true);
      File('${installDir.path}/dynbox').writeAsStringSync('binary');

      final uninstaller = DynboxUninstaller(installDirOverride: installDir);
      final command = UninstallCommand(uninstallerOverride: uninstaller);
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);

      final exitCode = await runner.run(['uninstall', '--yes']);
      expect(exitCode, 0);
      expect(File('${installDir.path}/dynbox').existsSync(), isFalse);
    });
  });
}
