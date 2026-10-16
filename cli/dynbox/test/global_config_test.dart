import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dynbox/src/commands/config_command.dart';
import 'package:dynbox/src/config/global_config.dart';
import 'package:dynbox/src/doctor/environment_inspector.dart';
import 'package:dynbox/src/doctor/output_formatter.dart';
import 'package:dynbox/src/generator/project_generator.dart';
import 'package:dynbox/src/sdk/safe_process_executor.dart';
import 'package:dynbox/src/sdk/sdk_resolver.dart';
import 'package:dynbox/src/sdk/sdk_validator.dart';
import 'package:test/test.dart';

/// Fake process adapter that simulates flutter create behavior deterministically.
class MockFlutterCreateAdapter implements ProcessRunnerAdapter {
  final int exitCode;
  final String stdout;
  final String stderr;

  String? lastExecutable;
  List<String>? lastArguments;

  MockFlutterCreateAdapter({
    this.exitCode = 0,
    this.stdout = 'All done!',
    this.stderr = '',
  });

  @override
  Future<ProcessExecutionResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    lastExecutable = executable;
    lastArguments = arguments;

    if (exitCode == 0 && arguments.isNotEmpty) {
      final targetPath = arguments.last;
      final targetDir = Directory(targetPath)..createSync(recursive: true);
      final libDir = Directory('${targetDir.path}/lib')
        ..createSync(recursive: true);
      File('${targetDir.path}/pubspec.yaml')
          .writeAsStringSync('name: mock_app\n');
      File('${libDir.path}/main.dart').writeAsStringSync('void main() {}\n');
    }

    return ProcessExecutionResult(
      executable: executable,
      arguments: arguments,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      elapsed: const Duration(milliseconds: 20),
    );
  }
}

void main() {
  group('GlobalConfig & Persistent SDK Resolution', () {
    late Directory tempHome;
    late File globalConfigFile;
    late Directory mockSdkDir;
    late File flutterExe;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('dynbox_global_cfg_test_');
      globalConfigFile = File('${tempHome.path}/.dynbox/config.yaml');

      mockSdkDir = Directory('${tempHome.path}/flutter_sdk')
        ..createSync(recursive: true);
      final binDir = Directory('${mockSdkDir.path}/bin')..createSync();
      final exeName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      flutterExe = File('${binDir.path}/$exeName')..writeAsStringSync('');
      File('${mockSdkDir.path}/version').writeAsStringSync('3.49.0');
    });

    tearDown(() {
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
    });

    test('GlobalConfig.resolveConfigFile honors environment override', () {
      final customPath = '${tempHome.path}/custom_dir/custom_config.yaml';
      final file = GlobalConfig.resolveConfigFile(
        environment: {'DYNBOX_GLOBAL_CONFIG_PATH': customPath},
      );
      expect(file.path, customPath);
    });

    test('GlobalConfig writes and reads flutter-root safely', () {
      expect(GlobalConfig.fromFile(globalConfigFile).flutterSdkPath, isNull);

      GlobalConfig.setKey(
        file: globalConfigFile,
        key: 'flutter-root',
        value: mockSdkDir.path,
      );

      final loaded = GlobalConfig.fromFile(globalConfigFile);
      expect(loaded.flutterSdkPath, mockSdkDir.path);

      // Verify YAML content has valid structure
      final content = globalConfigFile.readAsStringSync();
      expect(content, contains('sdk:'));
      expect(content, contains('flutter:'));
      expect(content, contains('path: ${mockSdkDir.path}'));

      // Unset key
      GlobalConfig.removeKey(file: globalConfigFile, key: 'flutter-root');
      final afterRemove = GlobalConfig.fromFile(globalConfigFile);
      expect(afterRemove.flutterSdkPath, isNull);
    });

    test('GlobalConfig handles missing or malformed configuration safely', () {
      final nonExistent = File('${tempHome.path}/does_not_exist.yaml');
      expect(GlobalConfig.fromFile(nonExistent).flutterSdkPath, isNull);

      final malformed = File('${tempHome.path}/malformed.yaml')
        ..writeAsStringSync('invalid: [unclosed');
      expect(GlobalConfig.fromFile(malformed).flutterSdkPath, isNull);
    });

    test('ConfigCommand CLI integration: set, get, list, unset', () async {
      final configCommand = ConfigCommand(
        globalConfigFileOverride: globalConfigFile,
      );
      final runner = CommandRunner<int>('dynbox', 'test')
        ..addCommand(configCommand);

      // 1. Set invalid SDK path fails validation
      final failCode = await runner.run([
        'config',
        'set',
        'flutter-root',
        '${tempHome.path}/non_existent_sdk',
      ]);
      expect(failCode, 1);
      expect(globalConfigFile.existsSync(), isFalse);

      // 2. Set valid SDK path succeeds
      final setCode = await runner.run([
        'config',
        'set',
        'flutter-root',
        mockSdkDir.path,
      ]);
      expect(setCode, 0);
      expect(globalConfigFile.existsSync(), isTrue);

      // 3. Get key succeeds
      final getCode = await runner.run(['config', 'get', 'flutter-root']);
      expect(getCode, 0);

      // 4. List keys succeeds
      final listCode = await runner.run(['config', 'list']);
      expect(listCode, 0);

      // 5. Unset key succeeds
      final unsetCode = await runner.run(['config', 'unset', 'flutter-root']);
      expect(unsetCode, 0);
      expect(GlobalConfig.fromFile(globalConfigFile).flutterSdkPath, isNull);
    });

    test('Resolution precedence: CLI argument > Workspace config > Global config > Environment variable', () {
      final cliSdk = Directory('${tempHome.path}/cli_sdk')
        ..createSync(recursive: true);
      Directory('${cliSdk.path}/bin').createSync();
      File(
        '${cliSdk.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
      ).writeAsStringSync('');

      final wsSdk = Directory('${tempHome.path}/ws_sdk')
        ..createSync(recursive: true);
      Directory('${wsSdk.path}/bin').createSync();
      File(
        '${wsSdk.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
      ).writeAsStringSync('');

      final globalSdk = mockSdkDir;

      final envSdk = Directory('${tempHome.path}/env_sdk')
        ..createSync(recursive: true);
      Directory('${envSdk.path}/bin').createSync();
      File(
        '${envSdk.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
      ).writeAsStringSync('');

      // Write global config
      GlobalConfig.setKey(
        file: globalConfigFile,
        key: 'flutter-root',
        value: globalSdk.path,
      );

      // Write workspace config
      final wsConfigFile =
          File('${tempHome.path}/workspace/.dynbox/config.yaml')
            ..createSync(recursive: true)
            ..writeAsStringSync('''
configVersion: 1
project:
  name: test_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: ${wsSdk.path}
''');

      final resolver = SdkResolver(
        environment: {'DYNBOX_FLUTTER_ROOT': envSdk.path},
        globalConfigOverride: globalConfigFile,
      );

      // Case 1: CLI takes highest precedence
      final p1 = resolver.resolve(
        cliArgument: cliSdk.path,
        configFile: wsConfigFile,
      );
      expect(p1.sdkDirectory, cliSdk.path);
      expect(p1.source, contains('cli-argument'));

      // Case 2: Workspace config takes precedence over Global config and Env
      final p2 = resolver.resolve(configFile: wsConfigFile);
      expect(p2.sdkDirectory, wsSdk.path);
      expect(p2.source, contains('workspace-config'));

      // Case 3: Global config takes precedence over Environment variable
      final p3 = resolver.resolve();
      expect(p3.sdkDirectory, globalSdk.path);
      expect(p3.source, contains('global-config'));

      // Case 4: Environment variable is used when global config is absent
      GlobalConfig.removeKey(file: globalConfigFile, key: 'flutter-root');
      final p4 = resolver.resolve();
      expect(p4.sdkDirectory, envSdk.path);
      expect(p4.source, contains('environment-variable'));

      // Case 5: When all are absent, throws SdkResolutionException (NO ambient PATH fallback)
      final emptyResolver = SdkResolver(
        environment: {},
        globalConfigOverride: globalConfigFile,
      );
      expect(
        () => emptyResolver.resolve(),
        throwsA(isA<SdkResolutionException>()),
      );
    });

    test(
      'EnvironmentInspector reports global-config when configured globally',
      () {
        GlobalConfig.setKey(
          file: globalConfigFile,
          key: 'flutter-root',
          value: mockSdkDir.path,
        );

        final validator = SdkValidator(
          environment: {},
          globalConfigOverride: globalConfigFile,
        );
        final inspector = EnvironmentInspector(
          environment: {},
          sdkValidator: validator,
        );

        final report = inspector.runInspection();
        final sdkItem = report.items.firstWhere(
          (i) => i.title.contains('Flutter SDK Configuration'),
        );

        expect(sdkItem.status, CheckStatus.pass);
        expect(sdkItem.details, contains('global-config'));
        expect(sdkItem.details, contains(mockSdkDir.path));
      },
    );

    test('Project creation works using persistent global SDK without --flutter-root', () async {
      GlobalConfig.setKey(
        file: globalConfigFile,
        key: 'flutter-root',
        value: mockSdkDir.path,
      );

      final resolver = SdkResolver(
        environment: {},
        globalConfigOverride: globalConfigFile,
      );

      final mockAdapter = MockFlutterCreateAdapter();
      final executor = SafeProcessExecutor(runner: mockAdapter);
      final generator = ProjectGenerator(
        sdkResolver: resolver,
        executor: executor,
      );

      final targetDir = await generator.generate(
        CreateProjectOptions(
          projectName: 'global_sdk_app',
          parentDirectory: tempHome.path,
        ),
      );

      expect(targetDir.existsSync(), isTrue);
      expect(mockAdapter.lastExecutable, flutterExe.path);
      expect(mockAdapter.lastArguments, contains('global_sdk_app'));

      // Check generated workspace configuration recorded the SDK path
      final generatedConfig = File('${targetDir.path}/.dynbox/config.yaml');
      expect(generatedConfig.existsSync(), isTrue);
      expect(generatedConfig.readAsStringSync(), contains(mockSdkDir.path));
    });
  });
}
