import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dynbox/src/generator/preset_applier.dart';
import 'package:dynbox/src/generator/project_generator.dart';
import 'package:dynbox/src/runner.dart';
import 'package:dynbox/src/sdk/safe_process_executor.dart';
import 'package:dynbox/src/sdk/sdk_resolver.dart';
import 'package:test/test.dart';

/// Fake process adapter that simulates flutter create behavior deterministically.
class MockFlutterCreateAdapter implements ProcessRunnerAdapter {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool shouldSimulatePubspec;

  String? lastExecutable;
  List<String>? lastArguments;
  String? lastWorkingDirectory;

  MockFlutterCreateAdapter({
    this.exitCode = 0,
    this.stdout = 'All done!',
    this.stderr = '',
    this.shouldSimulatePubspec = true,
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
    lastWorkingDirectory = workingDirectory;

    if (exitCode == 0 && shouldSimulatePubspec && arguments.isNotEmpty) {
      // Last argument is the target directory
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
  group('ProjectGenerator Validation & Safety', () {
    late Directory tempRoot;
    late Directory mockSdkDir;
    late SdkResolver mockResolver;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('dynbox_gen_test_');
      mockSdkDir = Directory('${tempRoot.path}/flutter_sdk')
        ..createSync(recursive: true);
      final binDir = Directory('${mockSdkDir.path}/bin')..createSync();
      final exeName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      File('${binDir.path}/$exeName').writeAsStringSync('');
      File('${mockSdkDir.path}/version').writeAsStringSync('3.49.0');

      mockResolver = SdkResolver(
        environment: {'DYNBOX_FLUTTER_ROOT': mockSdkDir.path},
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('validates valid project options without exception', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(
            projectName: 'my_good_app',
            organization: 'com.example.app',
            platforms: ['android', 'ios'],
          ),
        ),
        returnsNormally,
      );
    });

    test('rejects empty project name', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(projectName: ''),
        ),
        throwsA(
          isA<ProjectCreationException>().having(
            (e) => e.message,
            'message',
            contains('cannot be empty'),
          ),
        ),
      );
    });

    test('rejects project names with path traversal or separators', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(projectName: '../bad_name'),
        ),
        throwsA(isA<ProjectCreationException>()),
      );
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(projectName: 'bad/name'),
        ),
        throwsA(isA<ProjectCreationException>()),
      );
    });

    test('rejects project names with uppercase or invalid chars', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(projectName: 'MyAppName'),
        ),
        throwsA(isA<ProjectCreationException>()),
      );
    });

    test('rejects invalid organization format', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(
            projectName: 'good_app',
            organization: 'invalid_org_no_dot',
          ),
        ),
        throwsA(
          isA<ProjectCreationException>().having(
            (e) => e.message,
            'message',
            contains('Invalid organization identifier'),
          ),
        ),
      );
    });

    test('rejects unsupported platforms and duplicate platforms', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(
            projectName: 'good_app',
            platforms: ['android', 'playstation'],
          ),
        ),
        throwsA(isA<ProjectCreationException>()),
      );
      expect(
        () => generator.validateOptions(
          const CreateProjectOptions(
            projectName: 'good_app',
            platforms: ['android', 'android'],
          ),
        ),
        throwsA(
          isA<ProjectCreationException>().having(
            (e) => e.message,
            'message',
            contains('Duplicate platform specified'),
          ),
        ),
      );
    });

    test('rejects destination directory if it already exists', () {
      final generator = ProjectGenerator();
      Directory('${tempRoot.path}/existing_app').createSync();

      expect(
        () => generator.resolveDestination(
          projectName: 'existing_app',
          parentDirectory: tempRoot.path,
        ),
        throwsA(
          isA<ProjectCreationException>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('rejects path traversal attempting to escape parent directory', () {
      final generator = ProjectGenerator();
      expect(
        () => generator.resolveDestination(
          projectName: '../../escaped',
          parentDirectory: tempRoot.path,
        ),
        throwsA(isA<ProjectCreationException>()),
      );
    });

    test('fails when explicit Flutter SDK is missing or invalid', () async {
      final generator = ProjectGenerator(
        sdkResolver: SdkResolver(environment: {}),
      );

      expect(
        () => generator.generate(
          CreateProjectOptions(
            projectName: 'test_app',
            parentDirectory: tempRoot.path,
          ),
        ),
        throwsA(
          isA<ProjectCreationException>().having(
            (e) => e.stage,
            'stage',
            'sdk_resolution',
          ),
        ),
      );
    });

    test(
      'generates project, applies preset, and writes valid .dynbox/config.yaml',
      () async {
        final mockRunner = MockFlutterCreateAdapter();
        final executor = SafeProcessExecutor(runner: mockRunner);

        final generator = ProjectGenerator(
          sdkResolver: mockResolver,
          executor: executor,
        );

        final projectDir = await generator.generate(
          CreateProjectOptions(
            projectName: 'test_sample_app',
            parentDirectory: tempRoot.path,
            organization: 'com.dynbox.test',
            platforms: ['android', 'ios', 'web'],
            preset: ArchitecturePreset.layered,
          ),
        );

        expect(projectDir.existsSync(), isTrue);

        // Verify command arguments passed to mock
        expect(mockRunner.lastArguments, contains('create'));
        expect(mockRunner.lastArguments, contains('--project-name'));
        expect(mockRunner.lastArguments, contains('test_sample_app'));
        expect(mockRunner.lastArguments, contains('--org'));
        expect(mockRunner.lastArguments, contains('com.dynbox.test'));
        expect(mockRunner.lastArguments, contains('--platforms'));
        expect(mockRunner.lastArguments, contains('android,ios,web'));

        // Verify preset application
        expect(Directory('${projectDir.path}/lib/app').existsSync(), isTrue);
        expect(Directory('${projectDir.path}/lib/core').existsSync(), isTrue);
        expect(
          Directory('${projectDir.path}/lib/features').existsSync(),
          isTrue,
        );
        expect(
          File('${projectDir.path}/lib/STRUCTURE.md').existsSync(),
          isTrue,
        );

        // Verify .dynbox/config.yaml was written and is valid
        final configFile = File('${projectDir.path}/.dynbox/config.yaml');
        expect(configFile.existsSync(), isTrue);
        final configContent = configFile.readAsStringSync();
        expect(configContent, contains('name: test_sample_app'));
        expect(configContent, contains('kind: flutter_app'));
        expect(configContent, contains('source: local'));
        expect(configContent, contains('ota:'));
        expect(configContent, contains('channel: production'));

        // Verify DynBox First-Party OTA integration in generated app
        expect(File('${projectDir.path}/lib/dynbox_ota_service.dart').existsSync(), isTrue);
        expect(File('${projectDir.path}/lib/dynbox_ota_demo_screen.dart').existsSync(), isTrue);
        final mainDart = File('${projectDir.path}/lib/main.dart').readAsStringSync();
        expect(mainDart, contains('AppOtaCoordinator.initialize'));
        expect(mainDart, contains('DynboxOtaDemoScreen'));
        final pubspecContent = File('${projectDir.path}/pubspec.yaml').readAsStringSync();
        expect(pubspecContent, contains('dynbox_ota:'));
        expect(pubspecContent, contains('dynbox_ui_runtime:'));
      },
    );

    test('applies feature_first preset correctly', () async {
      final mockRunner = MockFlutterCreateAdapter();
      final executor = SafeProcessExecutor(runner: mockRunner);

      final generator = ProjectGenerator(
        sdkResolver: mockResolver,
        executor: executor,
      );

      final projectDir = await generator.generate(
        CreateProjectOptions(
          projectName: 'feature_app',
          parentDirectory: tempRoot.path,
          preset: ArchitecturePreset.featureFirst,
        ),
      );

      expect(
        Directory('${projectDir.path}/lib/features/home/presentation')
            .existsSync(),
        isTrue,
      );
      expect(File('${projectDir.path}/lib/STRUCTURE.md').existsSync(), isTrue);
    });

    test(
      'preserves partial project on flutter create failure and reports path',
      () async {
        final mockRunner = MockFlutterCreateAdapter(
          exitCode: 1,
          stderr: 'Gradle configuration failed or network timeout',
          shouldSimulatePubspec: false,
        );
        final executor = SafeProcessExecutor(runner: mockRunner);

        final generator = ProjectGenerator(
          sdkResolver: mockResolver,
          executor: executor,
        );

        try {
          await generator.generate(
            CreateProjectOptions(
              projectName: 'failed_app',
              parentDirectory: tempRoot.path,
            ),
          );
          fail('Should have thrown ProjectCreationException');
        } on ProjectCreationException catch (e) {
          expect(e.stage, 'flutter_generation');
          expect(e.exitCode, 1);
          expect(e.projectPath, contains('failed_app'));
          expect(e.details, contains('Gradle configuration failed'));
        }
      },
    );
  });

  group('CreateCommand CLI Integration', () {
    late DynboxRunner runner;

    setUp(() {
      runner = DynboxRunner();
    });

    test('throws UsageException when project name is missing', () async {
      expect(
        () => runner.run(['create']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('Missing project name'),
          ),
        ),
      );
    });

    test('throws UsageException on invalid preset option', () async {
      expect(
        () => runner.run(['create', 'my_app', '--preset', 'invalid_preset']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
