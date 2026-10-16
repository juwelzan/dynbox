import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dynbox/src/build/build_models.dart';
import 'package:dynbox/src/build/build_orchestrator.dart';
import 'package:dynbox/src/build/build_validator.dart';
import 'package:dynbox/src/commands/build_command.dart';
import 'package:dynbox/src/runner.dart';
import 'package:dynbox/src/sdk/safe_process_executor.dart';
import 'package:test/test.dart';

class MockBuildProcessAdapter implements ProcessRunnerAdapter {
  final Map<String, ProcessExecutionResult> responses;
  final List<List<String>> executedCommands = [];

  MockBuildProcessAdapter(this.responses);

  @override
  Future<ProcessExecutionResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool checkExitCode = false,
  }) async {
    executedCommands.add([executable, ...arguments]);
    final key = '$executable ${arguments.join(' ')}';
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    // Prefix lookup with full key
    for (final entry in responses.entries) {
      if (key.startsWith(entry.key)) {
        return entry.value;
      }
    }
    // Basename lookup (e.g. apksigner in /Users/.../build-tools/36.0.0/apksigner)
    final execBasename = executable.split('/').last;
    final basenameKey = '$execBasename ${arguments.join(' ')}';
    if (responses.containsKey(basenameKey)) {
      return responses[basenameKey]!;
    }
    for (final entry in responses.entries) {
      if (basenameKey.startsWith(entry.key)) {
        return entry.value;
      }
    }

    return ProcessExecutionResult(
      executable: executable,
      arguments: arguments,
      exitCode: 0,
      stdout: '',
      stderr: '',
      elapsed: Duration.zero,
    );
  }
}

void main() {
  late Directory tempDir;
  late Directory tempProject;
  late Directory mockSdkDir;
  late File mockFlutterBin;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dynbox_build_test_');
    tempProject = Directory('${tempDir.path}/sample_app')
      ..createSync(recursive: true);
    mockSdkDir = Directory('${tempDir.path}/mock_flutter_sdk')
      ..createSync(recursive: true);

    final binDir = Directory('${mockSdkDir.path}/bin')
      ..createSync(recursive: true);
    mockFlutterBin = File('${binDir.path}/flutter')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', ['+x', mockFlutterBin.path]);

    // Setup valid project files
    File('${tempProject.path}/pubspec.yaml').writeAsStringSync('''
name: sample_app
description: A sample Flutter project
environment:
  sdk: ^3.13.4
dependencies:
  flutter:
    sdk: flutter
''');

    final dynboxDir = Directory('${tempProject.path}/.dynbox')
      ..createSync(recursive: true);
    File('${dynboxDir.path}/config.yaml').writeAsStringSync('''
configVersion: 1
project:
  name: sample_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: ${mockSdkDir.path}
''');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('BuildCommand Argument Parsing & Validation', () {
    test('requires --platform and --target', () async {
      final runner = DynboxRunner();
      expect(
        () => runner.run(['build', tempProject.path]),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects incompatible target for android', () async {
      final orchestrator = BuildOrchestrator();
      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.ipa,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Target "ipa" is not valid for Android'));
    });

    test('rejects incompatible target for ios', () async {
      final orchestrator = BuildOrchestrator();
      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.ios,
        target: BuildTarget.apk,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Target "apk" is not valid for iOS'));
    });

    test('rejects build when project directory does not exist', () async {
      final orchestrator = BuildOrchestrator();
      final options = BuildOptions(
        projectDir: Directory('${tempDir.path}/nonexistent_project'),
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Project directory does not exist'));
    });

    test('rejects build when .dynbox/config.yaml is missing', () async {
      File('${tempProject.path}/.dynbox/config.yaml').deleteSync();
      final orchestrator = BuildOrchestrator();
      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Missing .dynbox/config.yaml'));
    });

    test('rejects build when project kind is not flutter_app', () async {
      File('${tempProject.path}/.dynbox/config.yaml').writeAsStringSync('''
configVersion: 1
project:
  name: sample_pkg
  kind: flutter_package
sdk:
  flutter:
    source: local
    path: ${mockSdkDir.path}
''');
      final orchestrator = BuildOrchestrator();
      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(
        result.message,
        contains('Building is only supported for "flutter_app"'),
      );
    });
  });

  group('BuildOrchestrator Execution & Artifact Verification', () {
    test(
      'dry run verifies command structure without executing build',
      () async {
        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: 'openjdk 25\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.apk,
          mode: BuildMode.release,
          dryRun: true,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isTrue);
        expect(result.isDryRun, isTrue);
        expect(result.message, contains('Dry run successful'));
        expect(result.executedArguments, contains('apk'));
        expect(result.executedArguments, contains('--release'));
      },
    );

    test('handles Flutter build failure exit code', () async {
      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
        '${mockFlutterBin.path} build apk --release':
            const ProcessExecutionResult(
              executable: 'flutter',
              arguments: ['build', 'apk', '--release'],
              exitCode: 1,
              stdout: '',
              stderr: 'Gradle build failed: Could not resolve dependencies.\n',
              elapsed: Duration.zero,
            ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
        mode: BuildMode.release,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Flutter build failed with exit code 1'));
      expect(result.actionableError, contains('Gradle build failed'));
    });

    test('reports failure when build reports success but expected artifact is missing', () async {
      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
        '${mockFlutterBin.path} build apk --release':
            const ProcessExecutionResult(
              executable: 'flutter',
              arguments: ['build', 'apk', '--release'],
              exitCode: 0,
              stdout: 'Built build/app/outputs/flutter-apk/app-release.apk (12.4MB).\n',
              stderr: '',
              elapsed: Duration.zero,
            ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
        mode: BuildMode.release,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('expected artifact was not found'));
    });

    test(
      'verifies Android APK signature with apksigner when available',
      () async {
        // Create expected artifact
        final apkDir = Directory(
          '${tempProject.path}/build/app/outputs/flutter-apk',
        )..createSync(recursive: true);
        final apkFile = File('${apkDir.path}/app-release.apk')
          ..writeAsStringSync('dummy apk binary payload');

        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
          '${mockFlutterBin.path} build apk --release':
              const ProcessExecutionResult(
                executable: 'flutter',
                arguments: ['build', 'apk', '--release'],
                exitCode: 0,
                stdout: 'Built build/app/outputs/flutter-apk/app-release.apk\n',
                stderr: '',
                elapsed: Duration.zero,
              ),
          'apksigner verify': const ProcessExecutionResult(
            executable: 'apksigner',
            arguments: ['verify', '--verbose'],
            exitCode: 0,
            stdout: 'Verifies\nVerified using v1 scheme (JAR signing): true\nVerified using v2 scheme (APK Signature Scheme v2): true\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.apk,
          mode: BuildMode.release,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isTrue);
        expect(result.artifact, isNotNull);
        expect(result.artifact!.file.path, apkFile.path);
        expect(result.artifact!.sha256, isNotEmpty);
        expect(result.artifact!.sizeBytes, greaterThan(0));
        expect(
          result.artifact!.signatureStatus,
          SignatureStatus.verifiedSigned,
        );
        expect(result.artifact!.isSigned, isTrue);
      },
    );

    test('detects verified unsigned Android APK', () async {
      final apkDir = Directory(
        '${tempProject.path}/build/app/outputs/flutter-apk',
      )..createSync(recursive: true);
      final apkFile = File('${apkDir.path}/app-release.apk')
        ..writeAsStringSync('dummy unsigned apk binary payload');

      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
        '${mockFlutterBin.path} build apk --release':
            const ProcessExecutionResult(
              executable: 'flutter',
              arguments: ['build', 'apk', '--release'],
              exitCode: 0,
              stdout: 'Built build/app/outputs/flutter-apk/app-release.apk\n',
              stderr: '',
              elapsed: Duration.zero,
            ),
        'apksigner verify': const ProcessExecutionResult(
          executable: 'apksigner',
          arguments: ['verify', '--verbose'],
          exitCode: 1,
          stdout: 'DOES NOT VERIFY\nERROR: No certificates were found in signing block\n',
          stderr: 'No signature found\n',
          elapsed: Duration.zero,
        ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
        mode: BuildMode.release,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isTrue);
      expect(result.artifact!.file.path, apkFile.path);
      expect(
        result.artifact!.signatureStatus,
        SignatureStatus.verifiedUnsigned,
      );
      expect(result.artifact!.isSigned, isFalse);
    });

    test(
      'verifies Android AAB signature using jarsigner on standard path',
      () async {
        final aabDir = Directory(
          '${tempProject.path}/build/app/outputs/bundle/release',
        )..createSync(recursive: true);
        final aabFile = File('${aabDir.path}/app-release.aab')
          ..writeAsStringSync('dummy aab payload');

        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
          '${mockFlutterBin.path} build appbundle --release':
              const ProcessExecutionResult(
                executable: 'flutter',
                arguments: ['build', 'appbundle', '--release'],
                exitCode: 0,
                stdout: 'Built appbundle\n',
                stderr: '',
                elapsed: Duration.zero,
              ),
          'jarsigner -verify ${aabFile.path}': const ProcessExecutionResult(
            executable: 'jarsigner',
            arguments: ['-verify', '...'],
            exitCode: 0,
            stdout: 'jar verified.\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.appbundle,
          mode: BuildMode.release,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isTrue);
        expect(
          result.artifact!.signatureStatus,
          SignatureStatus.verifiedSigned,
        );
        expect(result.artifact!.isSigned, isTrue);
        expect(result.artifact!.file.path, aabFile.path);
      },
    );

    test('resolves debug and profile AAB paths correctly without malformed strings', () async {
      // Setup debug AAB
      final debugDir = Directory(
        '${tempProject.path}/build/app/outputs/bundle/debug',
      )..createSync(recursive: true);
      final debugFile = File('${debugDir.path}/app-debug.aab')
        ..writeAsStringSync('dummy debug aab');

      // Setup profile AAB
      final profileDir = Directory(
        '${tempProject.path}/build/app/outputs/bundle/profile',
      )..createSync(recursive: true);
      final profileFile = File('${profileDir.path}/app-profile.aab')
        ..writeAsStringSync('dummy profile aab');

      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
        '${mockFlutterBin.path} build appbundle --debug':
            const ProcessExecutionResult(
              executable: 'flutter',
              arguments: ['build', 'appbundle', '--debug'],
              exitCode: 0,
              stdout: 'Built appbundle\n',
              stderr: '',
              elapsed: Duration.zero,
            ),
        '${mockFlutterBin.path} build appbundle --profile':
            const ProcessExecutionResult(
              executable: 'flutter',
              arguments: ['build', 'appbundle', '--profile'],
              exitCode: 0,
              stdout: 'Built appbundle\n',
              stderr: '',
              elapsed: Duration.zero,
            ),
        'jarsigner -verify ${debugFile.path}': const ProcessExecutionResult(
          executable: 'jarsigner',
          arguments: ['-verify', '...'],
          exitCode: 0,
          stdout: 'jar verified.\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'jarsigner -verify ${profileFile.path}': const ProcessExecutionResult(
          executable: 'jarsigner',
          arguments: ['-verify', '...'],
          exitCode: 0,
          stdout: 'jar verified.\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      // Verify debug AAB
      final debugResult = await orchestrator.build(
        BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.appbundle,
          mode: BuildMode.debug,
        ),
      );
      expect(debugResult.isSuccess, isTrue);
      expect(debugResult.artifact!.file.path, debugFile.path);

      // Verify profile AAB
      final profileResult = await orchestrator.build(
        BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.appbundle,
          mode: BuildMode.profile,
        ),
      );
      expect(profileResult.isSuccess, isTrue);
      expect(profileResult.artifact!.file.path, profileFile.path);
    });

    test(
      'iOS archive target generates ipa command without forcing ad-hoc export',
      () async {
        final mock = MockBuildProcessAdapter({
          'xcodebuild -version': const ProcessExecutionResult(
            executable: 'xcodebuild',
            arguments: ['-version'],
            exitCode: 0,
            stdout: 'Xcode 16.0\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final result = await orchestrator.build(
          BuildOptions(
            projectDir: tempProject,
            platform: BuildPlatform.ios,
            target: BuildTarget.archive,
            dryRun: true,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.executedArguments, contains('ipa'));
        expect(
          result.executedArguments,
          isNot(contains('--export-method=ad-hoc')),
        );
      },
    );

    test(
      'iOS codesign verification detects verified signed and verified unsigned',
      () async {
        final ipaDir = Directory('${tempProject.path}/build/ios/ipa')
          ..createSync(recursive: true);
        final ipaFile = File('${ipaDir.path}/app.ipa')
          ..writeAsStringSync('dummy ipa binary payload');

        final mock = MockBuildProcessAdapter({
          'xcodebuild -version': const ProcessExecutionResult(
            executable: 'xcodebuild',
            arguments: ['-version'],
            exitCode: 0,
            stdout: 'Xcode 16.0\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
          '${mockFlutterBin.path} build ipa --release':
              const ProcessExecutionResult(
                executable: 'flutter',
                arguments: ['build', 'ipa', '--release'],
                exitCode: 0,
                stdout: 'Built ipa\n',
                stderr: '',
                elapsed: Duration.zero,
              ),
          'codesign -v --deep ${ipaFile.path}': const ProcessExecutionResult(
            executable: 'codesign',
            arguments: ['-v', '--deep', '...'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final result = await orchestrator.build(
          BuildOptions(
            projectDir: tempProject,
            platform: BuildPlatform.ios,
            target: BuildTarget.ipa,
            codesign: true,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(
          result.artifact!.signatureStatus,
          SignatureStatus.verifiedSigned,
        );
        expect(result.artifact!.isSigned, isTrue);
      },
    );

    test('external signing configuration via DYNBOX_KEY_PROPERTIES_PATH resolves correctly', () {
      final externalFile = File('${tempDir.path}/external_signing.properties')
        ..writeAsStringSync('storePassword=external_secret\n');

      final defaultValidator = BuildValidator();
      // Unset environment
      expect(defaultValidator.isAndroidSigningConfigured(tempProject), isFalse);

      // Injected environment
      final envValidator = BuildValidator(
        environment: {'DYNBOX_KEY_PROPERTIES_PATH': externalFile.path},
      );
      expect(envValidator.isAndroidSigningConfigured(tempProject), isTrue);
      expect(
        envValidator.resolveAndroidSigningConfig(tempProject)?.path,
        externalFile.path,
      );
    });
  });

  group('BuildCommand CLI Integration', () {
    test('dynbox build --help displays supported flags and targets', () async {
      final runner = DynboxRunner();
      // Should not throw on help
      expect(() => runner.run(['build', '--help']), returnsNormally);
    });

    test('dynbox build dry run completes with exit code 0', () async {
      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);
      final command = BuildCommand(orchestrator: orchestrator);

      final runner = CommandRunner<int>('test', 'test')..addCommand(command);

      final exitCode = await runner.run([
        'build',
        tempProject.path,
        '--platform',
        'android',
        '--target',
        'apk',
        '--dry-run',
      ]);

      expect(exitCode, 0);
    });

    test('validates iOS build toolchain and options', () async {
      final mock = MockBuildProcessAdapter({
        'xcodebuild -version': const ProcessExecutionResult(
          executable: 'xcodebuild',
          arguments: ['-version'],
          exitCode: 0,
          stdout: 'Xcode 16.0\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.ios,
        target: BuildTarget.ipa,
        mode: BuildMode.release,
        dryRun: true,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isTrue);
      expect(result.executedArguments, contains('ipa'));
    });

    test(
      'detects missing Xcode on iOS builds when xcodebuild is unavailable',
      () async {
        final mock = MockBuildProcessAdapter({
          'xcodebuild -version': const ProcessExecutionResult(
            executable: 'xcodebuild',
            arguments: ['-version'],
            exitCode: 127,
            stdout: '',
            stderr: 'command not found\n',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.ios,
          target: BuildTarget.ipa,
          mode: BuildMode.release,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isFalse);
        expect(result.message, contains('Xcode is required for iOS builds'));
      },
    );

    test(
      'does not log or leak keystore passwords in build execution arguments',
      () async {
        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.apk,
          mode: BuildMode.release,
          dryRun: true,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isTrue);
        for (final arg in result.executedArguments) {
          expect(arg.toLowerCase(), isNot(contains('password')));
          expect(arg.toLowerCase(), isNot(contains('secret')));
        }
      },
    );

    test('build produces detailed BuildPlan during dry-run', () async {
      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'jarsigner -version': const ProcessExecutionResult(
          executable: 'jarsigner',
          arguments: ['-version'],
          exitCode: 0,
          stdout: 'jarsigner 21.0.1',
          stderr: '',
          elapsed: Duration.zero,
        ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.appbundle,
        mode: BuildMode.release,
        dryRun: true,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isTrue);
      expect(result.isDryRun, isTrue);
      expect(result.plan, isNotNull);

      final plan = result.plan!;
      expect(plan.platform, BuildPlatform.android);
      expect(plan.target, BuildTarget.appbundle);
      expect(plan.mode, BuildMode.release);
      expect(plan.expectedArtifactPath, contains('app-release.aab'));
      expect(plan.plannedCommand, contains('appbundle'));
      expect(plan.toolchainPrerequisites['java'], isTrue);
      expect(plan.signingConfigured, isFalse);

      final planJson = plan.toJson();
      expect(planJson['platform'], 'android');
      expect(planJson['target'], 'appbundle');
      expect(planJson['expectedArtifactPath'], contains('app-release.aab'));
    });

    test(
      'build emits verbose diagnostics and redacts sensitive error strings',
      () async {
        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
          '${mockSdkDir.path}/bin/flutter build apk --release':
              const ProcessExecutionResult(
                executable: 'flutter',
                arguments: ['build', 'apk', '--release'],
                exitCode: 1,
                stdout: 'Building APK...',
                stderr: 'Gradle failure: storePassword=supersecretkey and keyPassword=anothersecret and Bearer secrettoken123',
                elapsed: Duration.zero,
              ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.apk,
          mode: BuildMode.release,
          verbose: true,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isFalse);
        expect(result.diagnostics, isNotEmpty);
        expect(
          result.diagnostics.any(
            (d) => d.contains('Starting build orchestration'),
          ),
          isTrue,
        );
        expect(result.actionableError, contains('storePassword=[REDACTED]'));
        expect(result.actionableError, contains('keyPassword=[REDACTED]'));
        expect(result.actionableError, isNot(contains('supersecretkey')));
        expect(result.actionableError, isNot(contains('anothersecret')));
      },
    );

    test('generates machine-readable build manifest on success and writes to build/dynbox_manifest.json', () async {
      final apkDir = Directory(
        '${tempProject.path}/build/app/outputs/flutter-apk',
      );
      apkDir.createSync(recursive: true);
      final apkFile = File('${apkDir.path}/app-release.apk');
      apkFile.writeAsStringSync('SIMULATED_SIGNED_APK_BINARY');

      final mock = MockBuildProcessAdapter({
        'java -version': const ProcessExecutionResult(
          executable: 'java',
          arguments: ['-version'],
          exitCode: 0,
          stdout: '',
          stderr: '',
          elapsed: Duration.zero,
        ),
        '${mockSdkDir.path}/bin/flutter build apk --release':
            const ProcessExecutionResult(
              executable: 'flutter',
              arguments: ['build', 'apk', '--release'],
              exitCode: 0,
              stdout: 'Built build/app/outputs/flutter-apk/app-release.apk\n',
              stderr: '',
              elapsed: Duration.zero,
            ),
        'apksigner verify --verbose ${apkFile.path}':
            const ProcessExecutionResult(
              executable: 'apksigner',
              arguments: ['verify', '--verbose'],
              exitCode: 0,
              stdout: 'Verifies\nVerified using v1 scheme: true\n',
              stderr: '',
              elapsed: Duration.zero,
            ),
      });

      final executor = SafeProcessExecutor(runner: mock);
      final orchestrator = BuildOrchestrator(executor: executor);

      final options = BuildOptions(
        projectDir: tempProject,
        platform: BuildPlatform.android,
        target: BuildTarget.apk,
        mode: BuildMode.release,
        generateManifest: true,
      );

      final result = await orchestrator.build(options);
      expect(result.isSuccess, isTrue);
      expect(result.manifest, isNotNull);
      expect(result.manifestFile, isNotNull);
      expect(result.manifestFile!.existsSync(), isTrue);

      final manifestJson = jsonDecode(
        result.manifestFile!.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifestJson['schemaVersion'], '1.0');
      expect(manifestJson['platform'], 'android');
      expect(manifestJson['target'], 'apk');
      expect(manifestJson['mode'], 'release');
      expect(manifestJson['artifact']['path'], apkFile.path);
      expect(manifestJson['artifact']['signatureStatus'], 'verified_signed');
      expect(manifestJson['timing']['durationMs'], isA<int>());
    });

    test(
      'failed build does not generate or leave misleading success manifest',
      () async {
        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
          '${mockSdkDir.path}/bin/flutter build apk --release':
              const ProcessExecutionResult(
                executable: 'flutter',
                arguments: ['build', 'apk', '--release'],
                exitCode: 1,
                stdout: '',
                stderr: 'Gradle compilation error',
                elapsed: Duration.zero,
              ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.apk,
          mode: BuildMode.release,
          generateManifest: true,
        );

        final result = await orchestrator.build(options);
        expect(result.isSuccess, isFalse);
        expect(result.manifest, isNull);
        expect(result.manifestFile, isNull);
        final manifestPath = File(
          '${tempProject.path}/build/dynbox_manifest.json',
        );
        expect(manifestPath.existsSync(), isFalse);
      },
    );

    test(
      'CLI dynbox build --json outputs structured JSON with stable schema',
      () async {
        final mock = MockBuildProcessAdapter({
          'java -version': const ProcessExecutionResult(
            executable: 'java',
            arguments: ['-version'],
            exitCode: 0,
            stdout: '',
            stderr: '',
            elapsed: Duration.zero,
          ),
        });

        final executor = SafeProcessExecutor(runner: mock);
        final orchestrator = BuildOrchestrator(executor: executor);

        final options = BuildOptions(
          projectDir: tempProject,
          platform: BuildPlatform.android,
          target: BuildTarget.apk,
          mode: BuildMode.release,
          dryRun: true,
          json: true,
        );

        final result = await orchestrator.build(options);
        final jsonMap = result.toJson();

        expect(jsonMap['isSuccess'], isTrue);
        expect(jsonMap['isDryRun'], isTrue);
        expect(jsonMap['options']['platform'], 'android');
        expect(jsonMap['options']['target'], 'apk');
        expect(jsonMap['plan'], isNotNull);
        expect(
          jsonMap['plan']['expectedArtifactPath'],
          contains('app-release.apk'),
        );
      },
    );
  });
}
