import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dynbox/src/commands/sdk_command.dart';
import 'package:dynbox/src/commands/setup_command.dart';
import 'package:dynbox/src/config/global_config.dart';
import 'package:dynbox/src/doctor/environment_inspector.dart';
import 'package:dynbox/src/doctor/output_formatter.dart';
import 'package:dynbox/src/sdk/flutter_sdk_manager.dart';
import 'package:dynbox/src/sdk/safe_process_executor.dart';
import 'package:dynbox/src/sdk/sdk_validator.dart';
import 'package:test/test.dart';

/// Mock download client for deterministic testing without external network.
class MockFlutterDownloadClient implements FlutterDownloadClient {
  final FlutterReleasesCatalog catalog;
  final Map<String, List<int>> downloadPayloads;

  MockFlutterDownloadClient({
    required this.catalog,
    this.downloadPayloads = const {},
  });

  @override
  Future<FlutterReleasesCatalog> fetchCatalog({String? os}) async {
    return catalog;
  }

  @override
  Future<void> downloadArchive({
    required String url,
    required File destination,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (!destination.parent.existsSync()) {
      destination.parent.createSync(recursive: true);
    }
    final payload = downloadPayloads[url] ?? [1, 2, 3, 4, 5];
    destination.writeAsBytesSync(payload);
    onProgress?.call(payload.length, payload.length);
  }
}

/// Fake process adapter that simulates archive extraction safely.
class MockArchiveProcessAdapter implements ProcessRunnerAdapter {
  final bool failOnTar;

  MockArchiveProcessAdapter({this.failOnTar = false});

  @override
  Future<ProcessExecutionResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    if (executable == 'unzip' || executable == 'tar') {
      if (failOnTar && executable == 'tar') {
        return ProcessExecutionResult(
          executable: executable,
          arguments: arguments,
          exitCode: 1,
          stdout: '',
          stderr: 'Simulated archive extraction failure',
          elapsed: const Duration(milliseconds: 10),
        );
      }

      // Find destination path after -d or -C
      String? destPath;
      if (arguments.contains('-d')) {
        destPath = arguments[arguments.indexOf('-d') + 1];
      } else if (arguments.contains('-C')) {
        destPath = arguments[arguments.indexOf('-C') + 1];
      }

      if (destPath != null) {
        final binDir = Directory('$destPath/bin')..createSync(recursive: true);
        final exeName = Platform.isWindows ? 'flutter.bat' : 'flutter';
        File('${binDir.path}/$exeName').writeAsStringSync('');
        File('$destPath/version').writeAsStringSync('3.47.7');
      }

      return ProcessExecutionResult(
        executable: executable,
        arguments: arguments,
        exitCode: 0,
        stdout: 'Extracted successfully',
        stderr: '',
        elapsed: const Duration(milliseconds: 20),
      );
    }

    return ProcessExecutionResult(
      executable: executable,
      arguments: arguments,
      exitCode: 0,
      stdout: '',
      stderr: '',
      elapsed: const Duration(milliseconds: 5),
    );
  }
}

void main() {
  group('FlutterSdkManager & Setup Integration', () {
    late Directory tempRoot;
    late Directory tempSdksDir;
    late File globalConfigFile;
    late FlutterReleasesCatalog testCatalog;
    late String testArchiveUrl;
    late String testSha256;
    late List<int> testArchiveBytes;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('dynbox_sdk_mgr_test_');
      tempSdksDir = Directory('${tempRoot.path}/sdks')
        ..createSync(recursive: true);
      globalConfigFile = File('${tempRoot.path}/.dynbox/config.yaml');

      testArchiveBytes = [10, 20, 30, 40, 50, 60, 70, 80];
      testSha256 = crypto.sha256.convert(testArchiveBytes).toString();
      testArchiveUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.47.7-stable.zip';

      testCatalog = FlutterReleasesCatalog(
        baseUrl:
            'https://storage.googleapis.com/flutter_infra_release/releases',
        currentReleases: {'stable': 'mock_stable_hash_123'},
        releases: [
          FlutterRelease(
            hash: 'mock_stable_hash_123',
            channel: 'stable',
            version: '3.47.7',
            dartSdkVersion: '3.13.5',
            dartSdkArch: 'arm64',
            releaseDate: '2026-10-08T00:00:00Z',
            archive: 'stable/macos/flutter_macos_3.47.7-stable.zip',
            sha256: testSha256,
          ),
          FlutterRelease(
            hash: 'mock_beta_hash_456',
            channel: 'beta',
            version: '3.50.0-0.1.pre',
            dartSdkVersion: '3.14.0',
            dartSdkArch: 'arm64',
            releaseDate: '2026-10-14T00:00:00Z',
            archive: 'beta/macos/flutter_macos_3.50.0-0.1.pre-beta.zip',
            sha256: 'deadbeef_beta_sha',
          ),
        ],
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('listInstalled returns empty when no SDK is installed', () {
      final manager = FlutterSdkManager(sdksBaseDirOverride: tempSdksDir);
      expect(manager.listInstalled(), isEmpty);
    });

    test('installRelease downloads, verifies SHA-256, extracts, and reports installed SDK', () async {
      final mockDownload = MockFlutterDownloadClient(
        catalog: testCatalog,
        downloadPayloads: {testArchiveUrl: testArchiveBytes},
      );
      final mockAdapter = MockArchiveProcessAdapter();
      final executor = SafeProcessExecutor(runner: mockAdapter);

      final manager = FlutterSdkManager(
        sdksBaseDirOverride: tempSdksDir,
        downloadClient: mockDownload,
        executor: executor,
      );

      final statusMessages = <String>[];
      final installed = await manager.installRelease(
        release: testCatalog.releases.first,
        baseUrl: testCatalog.baseUrl,
        onStatus: (msg) => statusMessages.add(msg),
      );

      expect(installed.version, '3.47.7');
      expect(installed.isValid, isTrue);
      expect(installed.directory.existsSync(), isTrue);
      expect(manager.listInstalled().length, 1);
      expect(
        statusMessages,
        anyElement(contains('Cryptographic checksum verified')),
      );
    });

    test(
      'installRelease fails and cleans up when SHA-256 checksum mismatches',
      () async {
        final corruptedBytes = [99, 99, 99];
        final mockDownload = MockFlutterDownloadClient(
          catalog: testCatalog,
          downloadPayloads: {testArchiveUrl: corruptedBytes},
        );

        final manager = FlutterSdkManager(
          sdksBaseDirOverride: tempSdksDir,
          downloadClient: mockDownload,
        );

        expect(
          () => manager.installRelease(
            release: testCatalog.releases.first,
            baseUrl: testCatalog.baseUrl,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Checksum verification failed'),
            ),
          ),
        );

        // Verify no corrupted SDK was kept in managed directory
        expect(manager.listInstalled(), isEmpty);
      },
    );

    test('removeSdk removes installed SDK and rejects deletion outside managed directory', () async {
      final manager = FlutterSdkManager(sdksBaseDirOverride: tempSdksDir);
      final fakeVersionDir = Directory('${tempSdksDir.path}/3.47.7')
        ..createSync(recursive: true);
      Directory('${fakeVersionDir.path}/bin').createSync();
      File('${fakeVersionDir.path}/bin/flutter').writeAsStringSync('');

      expect(fakeVersionDir.existsSync(), isTrue);
      await manager.removeSdk('3.47.7');
      expect(fakeVersionDir.existsSync(), isFalse);

      // Security check: attempt to remove directory outside managed directory
      final outsideDir = Directory('${tempRoot.path}/outside_system')
        ..createSync();
      final managerWithOutside = FlutterSdkManager(
        sdksBaseDirOverride: tempSdksDir,
      );
      expect(
        () => managerWithOutside.removeSdk('../outside_system'),
        throwsA(isA<FileSystemException>()),
      );
      outsideDir.deleteSync();
    });

    test('SdkCommand CLI integration: list, list-installed, install, use, current, remove', () async {
      final mockDownload = MockFlutterDownloadClient(
        catalog: testCatalog,
        downloadPayloads: {testArchiveUrl: testArchiveBytes},
      );
      final mockAdapter = MockArchiveProcessAdapter();
      final executor = SafeProcessExecutor(runner: mockAdapter);
      final manager = FlutterSdkManager(
        sdksBaseDirOverride: tempSdksDir,
        downloadClient: mockDownload,
        executor: executor,
      );

      final sdkCommand = SdkCommand(
        sdkManager: manager,
        globalConfigFileOverride: globalConfigFile,
      );
      final runner = CommandRunner<int>('dynbox', 'test')
        ..addCommand(sdkCommand);

      // 1. sdk list
      final listCode = await runner.run(['sdk', 'list']);
      expect(listCode, 0);

      // 2. sdk list-installed (empty)
      final listInstalledCode = await runner.run(['sdk', 'list-installed']);
      expect(listInstalledCode, 0);

      // 3. sdk install stable with --yes
      final installCode = await runner.run([
        'sdk',
        'install',
        'stable',
        '--yes',
      ]);
      expect(installCode, 0);
      expect(
        GlobalConfig.fromFile(globalConfigFile).flutterSdkPath,
        contains('3.47.7'),
      );

      // 4. sdk current
      final currentCode = await runner.run(['sdk', 'current']);
      expect(currentCode, 0);

      // 5. sdk use
      final useCode = await runner.run(['sdk', 'use', '3.47.7']);
      expect(useCode, 0);

      // 6. sdk remove with --yes
      final removeCode = await runner.run(['sdk', 'remove', '3.47.7', '--yes']);
      expect(removeCode, 0);
      expect(manager.listInstalled(), isEmpty);
    });

    test('SetupCommand guided setup: detects existing SDK or installs stable with consent', () async {
      final mockDownload = MockFlutterDownloadClient(
        catalog: testCatalog,
        downloadPayloads: {testArchiveUrl: testArchiveBytes},
      );
      final mockAdapter = MockArchiveProcessAdapter();
      final executor = SafeProcessExecutor(runner: mockAdapter);
      final manager = FlutterSdkManager(
        sdksBaseDirOverride: tempSdksDir,
        downloadClient: mockDownload,
        executor: executor,
      );

      final setupCommand = SetupCommand(
        sdkManager: manager,
        globalConfigFileOverride: globalConfigFile,
      );
      final runner = CommandRunner<int>('dynbox', 'test')
        ..addCommand(setupCommand);

      // Run setup with --yes (clean machine scenario)
      final exitCode = await runner.run(['setup', '--yes']);
      expect(exitCode, 0);
      expect(globalConfigFile.existsSync(), isTrue);

      final config = GlobalConfig.fromFile(globalConfigFile);
      expect(config.flutterSdkPath, contains('3.47.7'));

      // Running setup a second time detects already configured SDK and avoids re-download
      final secondExit = await runner.run(['setup', '--yes']);
      expect(secondExit, 0);
    });

    test(
      'Doctor reports missing SDK with setup remedy when no SDK is configured',
      () {
        final validator = SdkValidator(
          environment: {},
          globalConfigOverride: File('${tempRoot.path}/empty.yaml'),
        );
        final inspector = EnvironmentInspector(
          environment: {},
          sdkValidator: validator,
        );

        final report = inspector.runInspection();
        final sdkItem = report.items.firstWhere(
          (i) => i.title.contains('Flutter SDK Configuration'),
        );

        expect(sdkItem.status, CheckStatus.warning);
        expect(sdkItem.remedy, contains('dynbox setup'));

        // Check that platform toolchains (Android/iOS) are reported separately
        expect(
          report.items.any((i) => i.title.contains('Android Toolchain')),
          isTrue,
        );
      },
    );
  });
}
