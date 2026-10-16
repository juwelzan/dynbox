import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dynbox/src/backend/backend_adapter.dart';
import 'package:dynbox/src/backend/firebase_adapter.dart';
import 'package:dynbox/src/backend/supabase_adapter.dart';
import 'package:dynbox/src/runner.dart';
import 'package:dynbox/src/sdk/safe_process_executor.dart';
import 'package:test/test.dart';

/// Fake process adapter for deterministic backend testing.
class MockBackendProcessAdapter implements ProcessRunnerAdapter {
  final Map<String, ProcessExecutionResult> responses;
  final List<String> executedCommands = [];

  MockBackendProcessAdapter(this.responses);

  @override
  Future<ProcessExecutionResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final fullCmd = ([executable, ...arguments]).join(' ');
    executedCommands.add(fullCmd);

    for (final key in responses.keys) {
      if (fullCmd.contains(key)) {
        return responses[key]!;
      }
    }

    return ProcessExecutionResult(
      executable: executable,
      arguments: arguments,
      exitCode: 0,
      stdout: 'mock default success',
      stderr: '',
      elapsed: const Duration(milliseconds: 10),
    );
  }
}

void main() {
  group('FirebaseAdapter', () {
    late Directory tempProject;

    setUp(() {
      tempProject = Directory.systemTemp.createTempSync('dynbox_fb_test_');
      final dynboxDir = Directory('${tempProject.path}/.dynbox')
        ..createSync(recursive: true);
      File('${dynboxDir.path}/config.yaml').writeAsStringSync('''
configVersion: 1
project:
  name: test_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: /fake/flutter
backend:
  provider: none
''');
      Directory('${tempProject.path}/lib').createSync(recursive: true);
    });

    tearDown(() {
      if (tempProject.existsSync()) {
        tempProject.deleteSync(recursive: true);
      }
    });

    test('inspectStatus detects missing tools and generates guides', () async {
      final mock = MockBackendProcessAdapter({
        'firebase --version': const ProcessExecutionResult(
          executable: 'firebase',
          arguments: ['--version'],
          exitCode: 1,
          stdout: '',
          stderr: 'not found',
          elapsed: Duration.zero,
        ),
        'flutterfire --version': const ProcessExecutionResult(
          executable: 'flutterfire',
          arguments: ['--version'],
          exitCode: 1,
          stdout: '',
          stderr: 'not found',
          elapsed: Duration.zero,
        ),
      });

      final adapter = FirebaseAdapter(
        executor: SafeProcessExecutor(runner: mock),
      );

      final status = await adapter.inspectStatus(tempProject);
      expect(status.provider, BackendProviderType.firebase);
      expect(status.hasMissingTools, isTrue);
      expect(status.tools.first.isInstalled, isFalse);
      expect(status.tools.first.installGuide, contains('npm install'));
    });

    test('inspectStatus detects installed tools and active auth', () async {
      final mock = MockBackendProcessAdapter({
        'firebase --version': const ProcessExecutionResult(
          executable: 'firebase',
          arguments: ['--version'],
          exitCode: 0,
          stdout: '15.34.0\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'flutterfire --version': const ProcessExecutionResult(
          executable: 'flutterfire',
          arguments: ['--version'],
          exitCode: 0,
          stdout: '1.4.1\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'firebase login:list': const ProcessExecutionResult(
          executable: 'firebase',
          arguments: ['login:list'],
          exitCode: 0,
          stdout: 'Logged in as developer@example.com\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
      });

      final adapter = FirebaseAdapter(
        executor: SafeProcessExecutor(runner: mock),
      );

      final status = await adapter.inspectStatus(tempProject);
      expect(status.hasMissingTools, isFalse);
      expect(status.auth.isAuthenticated, isTrue);
      expect(status.auth.accountEmail, 'developer@example.com');
    });

    test('configure fails when tools are not installed', () async {
      final mock = MockBackendProcessAdapter({
        'firebase --version': const ProcessExecutionResult(
          executable: 'firebase',
          arguments: ['--version'],
          exitCode: 1,
          stdout: '',
          stderr: 'not found',
          elapsed: Duration.zero,
        ),
        'flutterfire --version': const ProcessExecutionResult(
          executable: 'flutterfire',
          arguments: ['--version'],
          exitCode: 1,
          stdout: '',
          stderr: 'not found',
          elapsed: Duration.zero,
        ),
      });

      final adapter = FirebaseAdapter(
        executor: SafeProcessExecutor(runner: mock),
      );

      final result = await adapter.configure(tempProject, {
        'projectId': 'demo-fb',
      });
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('FlutterFire CLI is not installed'));
    });

    test('configure executes flutterfire configure and updates .dynbox/config.yaml on success', () async {
      final mock = MockBackendProcessAdapter({
        'firebase --version': const ProcessExecutionResult(
          executable: 'firebase',
          arguments: ['--version'],
          exitCode: 0,
          stdout: '15.34.0\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'flutterfire --version': const ProcessExecutionResult(
          executable: 'flutterfire',
          arguments: ['--version'],
          exitCode: 0,
          stdout: '1.4.1\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'firebase login:list': const ProcessExecutionResult(
          executable: 'firebase',
          arguments: ['login:list'],
          exitCode: 0,
          stdout: 'Logged in as developer@example.com\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
        'flutterfire configure': const ProcessExecutionResult(
          executable: 'flutterfire',
          arguments: ['configure'],
          exitCode: 0,
          stdout: 'Firebase options generated successfully\n',
          stderr: '',
          elapsed: Duration.zero,
        ),
      });

      final adapter = FirebaseAdapter(
        executor: SafeProcessExecutor(runner: mock),
      );

      final result = await adapter.configure(tempProject, {
        'projectId': 'my-cloud-project',
        'platforms': ['android', 'ios'],
      });

      expect(result.isSuccess, isTrue);
      expect(
        mock.executedCommands.any(
          (cmd) => cmd.contains('--project=my-cloud-project'),
        ),
        isTrue,
      );

      final configFile = File('${tempProject.path}/.dynbox/config.yaml');
      expect(configFile.readAsStringSync(), contains('provider: firebase'));
      expect(
        configFile.readAsStringSync(),
        contains('projectId: my-cloud-project'),
      );
    });
  });

  group('SupabaseAdapter', () {
    late Directory tempProject;

    setUp(() {
      tempProject = Directory.systemTemp.createTempSync('dynbox_sb_test_');
      final dynboxDir = Directory('${tempProject.path}/.dynbox')
        ..createSync(recursive: true);
      File('${dynboxDir.path}/config.yaml').writeAsStringSync('''
configVersion: 1
project:
  name: test_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: /fake/flutter
backend:
  provider: none
''');
      Directory('${tempProject.path}/lib').createSync(recursive: true);
      File('${tempProject.path}/pubspec.yaml')
          .writeAsStringSync('name: test_app\n');
    });

    tearDown(() {
      if (tempProject.existsSync()) {
        tempProject.deleteSync(recursive: true);
      }
    });

    test('configure rejects non-HTTPS or invalid URLs', () async {
      final adapter = SupabaseAdapter();

      final resultHttp = await adapter.configure(tempProject, {
        'projectUrl': 'http://insecure.supabase.co',
        'anonKey': 'anon_key_123',
      });
      expect(resultHttp.isSuccess, isFalse);
      expect(resultHttp.message, contains('Must be a valid HTTPS URI'));

      final resultInvalid = await adapter.configure(tempProject, {
        'projectUrl': 'not-a-url',
        'anonKey': 'anon_key_123',
      });
      expect(resultInvalid.isSuccess, isFalse);
    });

    test('configure rejects service_role and secret keys', () async {
      final adapter = SupabaseAdapter();

      final result = await adapter.configure(tempProject, {
        'projectUrl': 'https://myref.supabase.co',
        'anonKey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.service_role.secret',
      });

      expect(result.isSuccess, isFalse);
      expect(
        result.message,
        contains('Privileged service-role or secret keys are forbidden'),
      );
    });

    test('configure accepts both sb_publishable_... keys and legacy JWT anon keys', () async {
      final adapter = SupabaseAdapter();

      // Test sb_publishable_ format
      final pubKey = 'sb_publishable_abcdef1234567890';
      final errPub = adapter.validateApiKey(pubKey);
      expect(
        errPub,
        isNull,
        reason: 'sb_publishable_ keys must not be rejected merely because they are not JWTs',
      );

      // Test legacy JWT anon key format
      final legacyJwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyZWZlcmVuY2UiOiJ0ZXN0In0.signature';
      final errJwt = adapter.validateApiKey(legacyJwt);
      expect(errJwt, isNull);

      // Verify forbidden patterns still fail
      expect(
        adapter.validateApiKey('sb_publishable_service_role_bad'),
        contains('forbidden'),
      );
      expect(
        adapter.validateApiKey('secret_key_something'),
        contains('forbidden'),
      );
    });

    test('configure writes lib/supabase_config.dart and updates .dynbox/config.yaml', () async {
      final mock = MockBackendProcessAdapter({});
      final adapter = SupabaseAdapter(
        executor: SafeProcessExecutor(runner: mock),
      );

      final result = await adapter.configure(tempProject, {
        'projectUrl': 'https://sampleproject.supabase.co',
        'anonKey': 'sb_publishable_anon_token_12345',
        'addDependency': true,
      });

      expect(result.isSuccess, isTrue);

      final clientConfigFile = File(
        '${tempProject.path}/lib/supabase_config.dart',
      );
      expect(clientConfigFile.existsSync(), isTrue);
      final clientCode = clientConfigFile.readAsStringSync();
      expect(clientCode, contains('https://sampleproject.supabase.co'));
      expect(clientCode, contains('sb_publishable_anon_token_12345'));
      expect(clientCode, contains('Row Level Security (RLS)'));

      final dynboxConfigFile = File('${tempProject.path}/.dynbox/config.yaml');
      expect(
        dynboxConfigFile.readAsStringSync(),
        contains('provider: supabase'),
      );
      expect(
        dynboxConfigFile.readAsStringSync(),
        contains('projectUrl: https://sampleproject.supabase.co'),
      );
    });
  });

  group('BackendCommand CLI Integration', () {
    late DynboxRunner runner;

    setUp(() {
      runner = DynboxRunner();
    });

    test('backend configure firebase requires --project-id', () async {
      expect(
        () => runner.run(['backend', 'configure', 'firebase']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'backend configure supabase requires --project-url and --anon-key',
      () async {
        expect(
          () => runner.run(['backend', 'configure', 'supabase']),
          throwsA(isA<UsageException>()),
        );
        expect(
          () => runner.run([
            'backend',
            'configure',
            'supabase',
            '--project-url',
            'https://xyz.supabase.co',
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );
  });
}
