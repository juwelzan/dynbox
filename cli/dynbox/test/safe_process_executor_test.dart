import 'dart:async';

import 'package:dynbox/src/sdk/safe_process_executor.dart';
import 'package:test/test.dart';

/// Fake process adapter for deterministic testing of process execution.
class MockProcessRunnerAdapter implements ProcessRunnerAdapter {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool shouldTimeout;
  final bool shouldThrowLaunchError;

  String? lastExecutable;
  List<String>? lastArguments;
  String? lastWorkingDirectory;
  Map<String, String>? lastEnvironment;

  MockProcessRunnerAdapter({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.shouldTimeout = false,
    this.shouldThrowLaunchError = false,
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
    lastEnvironment = environment;

    if (shouldThrowLaunchError) {
      throw ProcessExecutionException(
        message: 'Binary not found or execution denied',
        executable: executable,
        arguments: arguments,
      );
    }

    if (shouldTimeout) {
      throw ProcessExecutionException(
        message: 'Process timed out after ${timeout?.inSeconds} seconds',
        executable: executable,
        arguments: arguments,
        isTimeout: true,
      );
    }

    return ProcessExecutionResult(
      executable: executable,
      arguments: arguments,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      elapsed: const Duration(milliseconds: 15),
    );
  }
}

void main() {
  group('SafeProcessExecutor', () {
    test('executes command successfully and captures output', () async {
      final mock = MockProcessRunnerAdapter(
        exitCode: 0,
        stdout: 'Flutter 3.49.0\nChannel stable',
      );
      final executor = SafeProcessExecutor(runner: mock);

      final result = await executor.execute('/path/to/flutter', ['--version']);

      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Flutter 3.49.0'));
      expect(mock.lastExecutable, '/path/to/flutter');
      expect(mock.lastArguments, ['--version']);
    });

    test('preserves arguments with spaces and special characters without shell interpretation', () async {
      final mock = MockProcessRunnerAdapter();
      final executor = SafeProcessExecutor(runner: mock);

      final argsWithSpecialChars = [
        'create',
        '--org',
        'com.example.app',
        '--description',
        'My App with spaces & symbols; echo injected!',
      ];

      await executor.execute('/path/to/flutter', argsWithSpecialChars);

      expect(mock.lastArguments, argsWithSpecialChars);
      expect(
        mock.lastArguments![4],
        'My App with spaces & symbols; echo injected!',
      );
    });

    test('redacts known secrets from stdout and stderr', () async {
      const sensitiveToken = 'ghp_secretToken1234567890';
      final mock = MockProcessRunnerAdapter(
        stdout: 'Authenticated using token: $sensitiveToken',
        stderr: 'Warning: token $sensitiveToken logged',
      );

      final executor = SafeProcessExecutor(
        runner: mock,
        secretMasks: {sensitiveToken},
      );

      final result = await executor.execute('/path/to/tool', ['login']);

      expect(result.stdout, contains('Authenticated using token: [REDACTED]'));
      expect(result.stdout, isNot(contains(sensitiveToken)));
      expect(result.stderr, contains('Warning: token [REDACTED] logged'));
      expect(result.stderr, isNot(contains(sensitiveToken)));
    });

    test('throws ProcessExecutionException when exit code is non-zero and checkExitCode is true', () async {
      final mock = MockProcessRunnerAdapter(
        exitCode: 1,
        stderr: 'Error: invalid argument',
      );
      final executor = SafeProcessExecutor(runner: mock);

      expect(
        () => executor.execute('/path/to/flutter', [
          'invalid-subcommand',
        ], checkExitCode: true),
        throwsA(
          isA<ProcessExecutionException>().having(
            (e) => e.exitCode,
            'exitCode',
            1,
          ),
        ),
      );
    });

    test('throws ProcessExecutionException on launch failure', () async {
      final mock = MockProcessRunnerAdapter(shouldThrowLaunchError: true);
      final executor = SafeProcessExecutor(runner: mock);

      expect(
        () => executor.execute('/nonexistent/binary', ['help']),
        throwsA(
          isA<ProcessExecutionException>().having(
            (e) => e.message,
            'message',
            contains('Binary not found'),
          ),
        ),
      );
    });

    test('throws ProcessExecutionException on timeout', () async {
      final mock = MockProcessRunnerAdapter(shouldTimeout: true);
      final executor = SafeProcessExecutor(runner: mock);

      expect(
        () => executor.execute('/path/to/hang', [
          'wait',
        ], timeout: const Duration(seconds: 1)),
        throwsA(
          isA<ProcessExecutionException>().having(
            (e) => e.isTimeout,
            'isTimeout',
            isTrue,
          ),
        ),
      );
    });

    test(
      'throws ProcessExecutionException when working directory does not exist',
      () async {
        final mock = MockProcessRunnerAdapter();
        final executor = SafeProcessExecutor(runner: mock);

        expect(
          () => executor.execute('/path/to/flutter', [
            'doctor',
          ], workingDirectory: '/directory/that/does/not/exist/anywhere'),
          throwsA(
            isA<ProcessExecutionException>().having(
              (e) => e.message,
              'message',
              contains('Working directory does not exist'),
            ),
          ),
        );
      },
    );
  });
}
