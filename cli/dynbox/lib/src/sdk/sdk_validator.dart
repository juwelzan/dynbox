import 'dart:io';

import '../config/dynbox_config.dart';
import '../config/global_config.dart';

/// Represents the validation result of a configured Flutter SDK path.
class SdkValidationResult {
  final bool isValid;
  final String? flutterVersion;
  final String? dartVersion;
  final String? flutterExecutablePath;
  final String? message;

  const SdkValidationResult({
    required this.isValid,
    this.flutterVersion,
    this.dartVersion,
    this.flutterExecutablePath,
    this.message,
  });

  factory SdkValidationResult.invalid(String message) {
    return SdkValidationResult(isValid: false, message: message);
  }

  factory SdkValidationResult.valid({
    required String flutterExecutablePath,
    String? flutterVersion,
    String? dartVersion,
    String? message,
  }) {
    return SdkValidationResult(
      isValid: true,
      flutterExecutablePath: flutterExecutablePath,
      flutterVersion: flutterVersion,
      dartVersion: dartVersion,
      message: message,
    );
  }
}

/// Represents the configured SDK selection.
class SdkConfig {
  /// Custom path to Flutter SDK directory or null if not explicitly set.
  final String? flutterSdkPath;

  /// Source of the configuration (e.g., 'cli-argument', 'workspace-config', 'global-config', 'environment-variable', 'none').
  final String source;

  const SdkConfig({this.flutterSdkPath, this.source = 'none'});

  bool get isConfigured =>
      flutterSdkPath != null && flutterSdkPath!.trim().isNotEmpty;
}

/// Responsible for resolving and validating Flutter SDK paths explicitly.
class SdkValidator {
  final Map<String, String> environment;
  final File? globalConfigOverride;

  const SdkValidator({this.environment = const {}, this.globalConfigOverride});

  /// Resolves the SDK configuration without silently using PATH Flutter.
  SdkConfig resolveConfig({String? explicitPath, File? configFile}) {
    // 1. CLI explicit argument
    if (explicitPath != null && explicitPath.trim().isNotEmpty) {
      return SdkConfig(
        flutterSdkPath: explicitPath.trim(),
        source: 'cli-argument',
      );
    }

    // 2. Workspace configuration (.dynbox/config.yaml)
    if (configFile != null && configFile.existsSync()) {
      try {
        final content = configFile.readAsStringSync();
        // Check for YAML structure
        if (content.contains('flutter:')) {
          final config = DynboxConfig.fromFile(configFile);
          return SdkConfig(
            flutterSdkPath: config.flutterSdk.path,
            source: 'config-file (${configFile.path})',
          );
        }
        // Fallback for simple line-based legacy format
        final lines = configFile.readAsLinesSync();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('flutter_sdk_path:')) {
            final val = trimmed.substring('flutter_sdk_path:'.length).trim();
            if (val.isNotEmpty) {
              return SdkConfig(
                flutterSdkPath: val,
                source: 'config-file (${configFile.path})',
              );
            }
          }
        }
      } catch (_) {
        // Ignored or handled as unconfigured
      }
    }

    // 3. Persistent global DynBox SDK configuration (~/.dynbox/config.yaml)
    final globalFile =
        globalConfigOverride ??
        GlobalConfig.resolveConfigFile(environment: environment);
    if (globalFile.existsSync()) {
      final global = GlobalConfig.fromFile(globalFile);
      if (global.flutterSdkPath != null &&
          global.flutterSdkPath!.trim().isNotEmpty) {
        return SdkConfig(
          flutterSdkPath: global.flutterSdkPath!.trim(),
          source: 'global-config (${globalFile.path})',
        );
      }
    }

    // 4. Environment variable
    final envPath = environment['DYNBOX_FLUTTER_ROOT'];
    if (envPath != null && envPath.trim().isNotEmpty) {
      return SdkConfig(
        flutterSdkPath: envPath.trim(),
        source: 'environment-variable (DYNBOX_FLUTTER_ROOT)',
      );
    }

    return const SdkConfig(flutterSdkPath: null, source: 'none');
  }

  /// Validates the provided Flutter SDK directory path.
  SdkValidationResult validate(String sdkPath) {
    final dir = Directory(sdkPath);
    if (!dir.existsSync()) {
      return SdkValidationResult.invalid(
        'The configured Flutter SDK path does not exist: "$sdkPath"',
      );
    }

    // Check for flutter executable in bin/
    final isWindows = Platform.isWindows;
    final binaryName = isWindows ? 'flutter.bat' : 'flutter';
    final binDir = Directory('${dir.path}/bin');
    final flutterExe = File('${binDir.path}/$binaryName');

    if (!flutterExe.existsSync()) {
      return SdkValidationResult.invalid(
        'Directory exists, but no Flutter executable found at "${flutterExe.path}".',
      );
    }

    // Inspect version files if present
    String? flutterVer;
    final versionFile = File('${dir.path}/version');
    if (versionFile.existsSync()) {
      try {
        flutterVer = versionFile.readAsStringSync().trim();
      } catch (_) {}
    }

    return SdkValidationResult.valid(
      flutterExecutablePath: flutterExe.path,
      flutterVersion: flutterVer,
      message: 'Explicitly configured Flutter SDK is valid.',
    );
  }
}
