import 'dart:io';

import '../config/dynbox_config.dart';
import '../sdk/safe_process_executor.dart';
import 'build_models.dart';

/// Preflight validator for build prerequisites, host tools, and project configuration.
class BuildValidator {
  final SafeProcessExecutor executor;
  final Map<String, String>? environment;

  BuildValidator({SafeProcessExecutor? executor, this.environment})
    : executor = executor ?? SafeProcessExecutor();

  /// Validates project directory and returns parsed [DynboxConfig].
  DynboxConfig validateProject(Directory projectDir) {
    if (!projectDir.existsSync()) {
      throw FileSystemException(
        'Project directory does not exist: ${projectDir.path}',
        projectDir.path,
      );
    }

    final pubspecFile = File('${projectDir.path}/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      throw FileSystemException(
        'Missing pubspec.yaml in project directory: ${projectDir.path}',
        pubspecFile.path,
      );
    }

    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      throw FileSystemException(
        'Missing .dynbox/config.yaml in project directory: ${projectDir.path}',
        configFile.path,
      );
    }

    final config = DynboxConfig.fromFile(
      configFile,
      workspaceRoot: projectDir.path,
    );
    if (config.project.kind != ProjectKind.flutterApp) {
      throw ArgumentError(
        'Building is only supported for "flutter_app" projects (found: ${config.project.kind.value}).',
      );
    }

    return config;
  }

  /// Verifies host operating system and required external tooling.
  Future<void> validateHostTools(BuildPlatform platform) async {
    if (platform == BuildPlatform.android) {
      // Validate Java Development Kit (JDK) presence
      final hasJava = await _checkToolAvailable('java', ['-version']);
      if (!hasJava) {
        throw StateError(
          'Java (JDK) is required for Android builds but was not found in PATH or environment.',
        );
      }
    } else if (platform == BuildPlatform.ios) {
      if (!Platform.isMacOS) {
        throw StateError(
          'iOS builds are only supported on macOS host systems.',
        );
      }

      final hasXcode = await _checkToolAvailable('xcodebuild', ['-version']);
      if (!hasXcode) {
        throw StateError(
          'Xcode is required for iOS builds but "xcodebuild" was not found in PATH or active developer directory.',
        );
      }
    }
  }

  /// Checks whether an external host command/tool is available.
  Future<bool> checkToolAvailable(String executable, List<String> args) =>
      _checkToolAvailable(executable, args);

  /// Validates output directory write permissions.
  void validateOutputDirectory(Directory projectDir) {
    final buildDir = Directory('${projectDir.path}/build');
    try {
      if (!buildDir.existsSync()) {
        buildDir.createSync(recursive: true);
      }
      // Test write permissions using a temporary probe file
      final probe = File(
        '${buildDir.path}/.dynbox_write_test_${DateTime.now().millisecondsSinceEpoch}',
      );
      probe.writeAsStringSync('probe');
      probe.deleteSync();
    } catch (e) {
      throw FileSystemException(
        'Output directory is not writable: ${buildDir.path}',
        buildDir.path,
        OSError(e.toString()),
      );
    }
  }

  /// Checks if Android project has signing configured either via
  /// the DYNBOX_KEY_PROPERTIES_PATH environment variable or in android/key.properties.
  bool isAndroidSigningConfigured(Directory projectDir) {
    return resolveAndroidSigningConfig(projectDir) != null;
  }

  /// Resolves the Android signing properties [File], checking:
  /// 1. [DYNBOX_KEY_PROPERTIES_PATH] environment variable (if set and points to an existing file).
  /// 2. Local `$projectDir/android/key.properties` (if exists).
  ///
  /// Returns `null` if neither is configured or existing.
  File? resolveAndroidSigningConfig(Directory projectDir) {
    final env = environment ?? Platform.environment;
    final envPath = env['DYNBOX_KEY_PROPERTIES_PATH'];
    if (envPath != null && envPath.trim().isNotEmpty) {
      final envFile = File(envPath.trim());
      if (envFile.existsSync()) {
        return envFile;
      }
    }

    final localFile = File('${projectDir.path}/android/key.properties');
    if (localFile.existsSync()) {
      return localFile;
    }

    return null;
  }

  Future<bool> _checkToolAvailable(String executable, List<String> args) async {
    try {
      final result = await executor.execute(
        executable,
        args,
        timeout: const Duration(seconds: 5),
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
