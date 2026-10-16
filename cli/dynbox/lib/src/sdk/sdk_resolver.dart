import 'dart:io';

import '../config/dynbox_config.dart';
import 'sdk_validator.dart';

/// Exception thrown when SDK resolution fails.
class SdkResolutionException implements Exception {
  final String message;
  final String? path;

  const SdkResolutionException(this.message, [this.path]);

  @override
  String toString() {
    if (path != null) {
      return 'SdkResolutionException: $message (Path: "$path")';
    }
    return 'SdkResolutionException: $message';
  }
}

/// Represents the resolved and verified SDK pinned for an execution context.
class PinnedSdk {
  final String sdkDirectory;
  final String executablePath;
  final String? version;
  final String source;

  const PinnedSdk({
    required this.sdkDirectory,
    required this.executablePath,
    required this.source,
    this.version,
  });
}

/// Resolves the explicit Flutter SDK to use based on strict precedence:
/// 1. Command-line argument (`--flutter-root`)
/// 2. Workspace configuration file (`.dynbox/config.yaml`)
/// 3. Environment variable (`DYNBOX_FLUTTER_ROOT`)
///
/// NOTE: Ambient system PATH is NEVER used as a fallback.
class SdkResolver {
  final SdkValidator validator;
  final Map<String, String> environment;

  SdkResolver({SdkValidator? validator, Map<String, String>? environment})
    : environment = environment ?? Platform.environment,
      validator =
          validator ??
          SdkValidator(environment: environment ?? Platform.environment);

  /// Resolves the SDK directory and verified executable.
  PinnedSdk resolve({
    String? cliArgument,
    File? configFile,
    String? workspaceRoot,
  }) {
    String? selectedPath;
    String source = 'none';

    // 1. CLI argument takes highest precedence for the current invocation
    if (cliArgument != null && cliArgument.trim().isNotEmpty) {
      selectedPath = cliArgument.trim();
      source = 'cli-argument (--flutter-root)';
    }

    // 2. Workspace configuration file (.dynbox/config.yaml)
    if (selectedPath == null && configFile != null && configFile.existsSync()) {
      try {
        final config = DynboxConfig.fromFile(
          configFile,
          workspaceRoot: workspaceRoot,
        );
        selectedPath = config.flutterSdk.path;
        source = 'workspace-config (${configFile.path})';
      } on ConfigException {
        // Rethrow config errors cleanly
        rethrow;
      } catch (e) {
        // Fallback for simple key-value config if not full yaml
        final simpleConfig = validator.resolveConfig(configFile: configFile);
        if (simpleConfig.isConfigured) {
          selectedPath = simpleConfig.flutterSdkPath;
          source = simpleConfig.source;
        }
      }
    }

    // 3. Environment variable
    if (selectedPath == null) {
      final envPath = environment['DYNBOX_FLUTTER_ROOT'];
      if (envPath != null && envPath.trim().isNotEmpty) {
        selectedPath = envPath.trim();
        source = 'environment-variable (DYNBOX_FLUTTER_ROOT)';
      }
    }

    // If still null, explicitly fail. No ambient fallback.
    if (selectedPath == null || selectedPath.isEmpty) {
      throw const SdkResolutionException(
        'No explicit Flutter SDK configured. DynBox requires an explicit SDK path and will not silently pick a random one from PATH.\n'
        'Remedy: Specify --flutter-root <path>, define DYNBOX_FLUTTER_ROOT, or configure .dynbox/config.yaml.',
      );
    }

    // Validate the path and resolve executable
    final validation = validator.validate(selectedPath);
    if (!validation.isValid) {
      throw SdkResolutionException(
        validation.message ?? 'Configured Flutter SDK path is invalid.',
        selectedPath,
      );
    }

    // Resolve directory and executable to absolute paths
    final resolvedDir = Directory(selectedPath).absolute.path;
    final resolvedExe = File(validation.flutterExecutablePath!).absolute.path;

    return PinnedSdk(
      sdkDirectory: resolvedDir,
      executablePath: resolvedExe,
      version: validation.flutterVersion,
      source: source,
    );
  }
}
