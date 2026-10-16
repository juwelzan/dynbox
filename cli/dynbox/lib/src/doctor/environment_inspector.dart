import 'dart:io';

import '../sdk/sdk_validator.dart';
import 'output_formatter.dart';

/// Environment inspector for dynbox doctor.
class EnvironmentInspector {
  final Map<String, String> environment;
  final SdkValidator sdkValidator;

  EnvironmentInspector({
    Map<String, String>? environment,
    SdkValidator? sdkValidator,
  }) : environment = environment ?? Platform.environment,
       sdkValidator =
           sdkValidator ??
           SdkValidator(environment: environment ?? Platform.environment);

  DoctorReport runInspection({String? explicitSdkPath, File? configFile}) {
    final items = <CheckItem>[];

    // 1. Operating System
    items.add(
      CheckItem(
        title: 'Operating System',
        status: CheckStatus.pass,
        details:
            '${Platform.operatingSystem} (${Platform.operatingSystemVersion}) - Architecture: ${Platform.version.contains('arm64') ? 'arm64' : 'x64'}',
      ),
    );

    // 2. Dart SDK Availability
    final currentDartVersion = Platform.version.split(' ').first;
    items.add(
      CheckItem(
        title: 'Current Dart Runtime',
        status: CheckStatus.pass,
        details:
            'Dart $currentDartVersion (Executable: ${Platform.executable})',
      ),
    );

    // 3. DynBox CLI Installation Details
    final dynboxExe = Platform.resolvedExecutable;
    items.add(
      CheckItem(
        title: 'DynBox CLI Installation',
        status: CheckStatus.pass,
        details: 'Executable: $dynboxExe',
      ),
    );

    // 4. Git Availability
    try {
      final gitResult = Process.runSync('git', ['--version']);
      if (gitResult.exitCode == 0) {
        final versionStr = gitResult.stdout.toString().trim();
        items.add(
          CheckItem(
            title: 'Git Version Control',
            status: CheckStatus.pass,
            details: versionStr,
          ),
        );
      } else {
        items.add(
          const CheckItem(
            title: 'Git Version Control',
            status: CheckStatus.warning,
            details: 'git command exited with non-zero exit code.',
            remedy: 'Verify git installation in your PATH.',
          ),
        );
      }
    } catch (e) {
      items.add(
        CheckItem(
          title: 'Git Version Control',
          status: CheckStatus.warning,
          details: 'Git is not found or failed to execute: $e',
          remedy: 'Install Git to enable version control and SDK operations.',
        ),
      );
    }

    // 4. DynBox Explicit Flutter SDK Configuration
    final sdkConfig = sdkValidator.resolveConfig(
      explicitPath: explicitSdkPath,
      configFile: configFile,
    );

    if (!sdkConfig.isConfigured) {
      items.add(
        const CheckItem(
          title: 'DynBox Flutter SDK Configuration',
          status: CheckStatus.warning,
          details: 'No explicit Flutter SDK configured. (DynBox requires an explicit SDK path and will not silently pick a random one from PATH).',
          remedy: 'Configure via --flutter-root <path>, DYNBOX_FLUTTER_ROOT environment variable, or .dynbox/config.yaml (flutter_sdk_path: ...).',
        ),
      );
    } else {
      final validation = sdkValidator.validate(sdkConfig.flutterSdkPath!);
      if (validation.isValid) {
        final versionInfo = validation.flutterVersion != null
            ? ' (Version: ${validation.flutterVersion})'
            : '';
        items.add(
          CheckItem(
            title: 'DynBox Flutter SDK Configuration',
            status: CheckStatus.pass,
            details:
                'Configured via ${sdkConfig.source}: ${sdkConfig.flutterSdkPath}$versionInfo\n'
                '    Executable: ${validation.flutterExecutablePath}',
          ),
        );
      } else {
        items.add(
          CheckItem(
            title: 'DynBox Flutter SDK Configuration',
            status: CheckStatus.fail,
            details:
                'Configured path via ${sdkConfig.source} is invalid: "${sdkConfig.flutterSdkPath}".\n'
                '    Reason: ${validation.message}',
            remedy: 'Provide a valid path to an official Flutter SDK directory containing bin/flutter.',
          ),
        );
      }
    }

    return DoctorReport(items);
  }
}
