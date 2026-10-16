import 'safe_process_executor.dart';
import 'sdk_resolver.dart';

/// High-level runner that executes official Flutter commands using the pinned SDK.
class FlutterSdkRunner {
  final PinnedSdk pinnedSdk;
  final SafeProcessExecutor executor;

  FlutterSdkRunner({required this.pinnedSdk, SafeProcessExecutor? executor})
    : executor = executor ?? SafeProcessExecutor();

  /// Executes an official Flutter command.
  /// Example: `runner.run(['doctor', '-v'])`
  Future<ProcessExecutionResult> run(
    List<String> flutterArguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool checkExitCode = false,
  }) async {
    return executor.execute(
      pinnedSdk.executablePath,
      flutterArguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
      checkExitCode: checkExitCode,
    );
  }
}
