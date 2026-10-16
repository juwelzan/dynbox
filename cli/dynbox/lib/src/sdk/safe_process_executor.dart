import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Exception thrown when process execution fails or times out.
class ProcessExecutionException implements Exception {
  final String message;
  final String executable;
  final List<String> arguments;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final bool isTimeout;

  const ProcessExecutionException({
    required this.message,
    required this.executable,
    required this.arguments,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.isTimeout = false,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ProcessExecutionException: $message\n');
    buffer.writeln('  Executable: $executable');
    buffer.writeln('  Arguments: $arguments');
    if (exitCode != null) buffer.writeln('  Exit Code: $exitCode');
    if (isTimeout) buffer.writeln('  Status: Timed out');
    if (stderr != null && stderr!.isNotEmpty) {
      buffer.writeln('  Stderr: ${stderr!.trim()}');
    }
    return buffer.toString().trim();
  }
}

/// Structured result of a safe process execution.
class ProcessExecutionResult {
  final String executable;
  final List<String> arguments;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration elapsed;

  const ProcessExecutionResult({
    required this.executable,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.elapsed,
  });

  bool get isSuccess => exitCode == 0;
}

/// Abstract runner for processes to enable clean unit testing without external tools.
abstract class ProcessRunnerAdapter {
  Future<ProcessExecutionResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });
}

/// Standard system process runner using dart:io Process.
class SystemProcessRunnerAdapter implements ProcessRunnerAdapter {
  const SystemProcessRunnerAdapter();

  @override
  Future<ProcessExecutionResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: false, // Security: Never run in shell
      );
    } catch (e) {
      throw ProcessExecutionException(
        message: 'Failed to launch executable "$executable": $e',
        executable: executable,
        arguments: arguments,
      );
    }

    final stdoutCompleter = Completer<String>();
    final stderrCompleter = Completer<String>();

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    process.stdout
        .transform(utf8.decoder)
        .listen(
          stdoutBuffer.write,
          onDone: () => stdoutCompleter.complete(stdoutBuffer.toString()),
        );

    process.stderr
        .transform(utf8.decoder)
        .listen(
          stderrBuffer.write,
          onDone: () => stderrCompleter.complete(stderrBuffer.toString()),
        );

    int exitCode;
    try {
      if (timeout != null) {
        exitCode = await process.exitCode.timeout(
          timeout,
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            throw TimeoutException(
              'Process exceeded timeout of ${timeout.inSeconds} seconds',
            );
          },
        );
      } else {
        exitCode = await process.exitCode;
      }
    } on TimeoutException {
      stopwatch.stop();
      throw ProcessExecutionException(
        message: 'Process timed out after ${timeout?.inSeconds} seconds',
        executable: executable,
        arguments: arguments,
        isTimeout: true,
      );
    }

    final stdoutStr = await stdoutCompleter.future;
    final stderrStr = await stderrCompleter.future;
    stopwatch.stop();

    return ProcessExecutionResult(
      executable: executable,
      arguments: arguments,
      exitCode: exitCode,
      stdout: stdoutStr,
      stderr: stderrStr,
      elapsed: stopwatch.elapsed,
    );
  }
}

/// Safe subprocess executor for official Flutter and SDK toolchain commands.
class SafeProcessExecutor {
  final ProcessRunnerAdapter runner;
  final Set<String> secretMasks;

  SafeProcessExecutor({ProcessRunnerAdapter? runner, Set<String>? secretMasks})
    : runner = runner ?? const SystemProcessRunnerAdapter(),
      secretMasks = secretMasks ?? const {};

  /// Redacts known secret strings from logged output.
  String redact(String input) {
    if (secretMasks.isEmpty || input.isEmpty) return input;
    String sanitized = input;
    for (final secret in secretMasks) {
      if (secret.isNotEmpty && sanitized.contains(secret)) {
        sanitized = sanitized.replaceAll(secret, '[REDACTED]');
      }
    }
    return sanitized;
  }

  /// Executes an external process safely without shell evaluation.
  Future<ProcessExecutionResult> execute(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool checkExitCode = false,
  }) async {
    // 1. Validate working directory if specified
    if (workingDirectory != null) {
      final dir = Directory(workingDirectory);
      if (!dir.existsSync()) {
        throw ProcessExecutionException(
          message: 'Working directory does not exist: "$workingDirectory"',
          executable: executable,
          arguments: arguments,
        );
      }
    }

    // 2. Execute process safely
    final result = await runner.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
    );

    // 3. Sanitized output result
    final sanitizedResult = ProcessExecutionResult(
      executable: result.executable,
      arguments: result.arguments,
      exitCode: result.exitCode,
      stdout: redact(result.stdout),
      stderr: redact(result.stderr),
      elapsed: result.elapsed,
    );

    // 4. Optionally verify zero exit code
    if (checkExitCode && sanitizedResult.exitCode != 0) {
      throw ProcessExecutionException(
        message: 'Command failed with exit code ${sanitizedResult.exitCode}',
        executable: executable,
        arguments: arguments,
        exitCode: sanitizedResult.exitCode,
        stdout: sanitizedResult.stdout,
        stderr: sanitizedResult.stderr,
      );
    }

    return sanitizedResult;
  }
}
