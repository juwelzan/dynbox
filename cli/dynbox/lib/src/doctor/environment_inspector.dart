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
          remedy: 'Run "dynbox setup" for automatic official installation, or "dynbox config set flutter-root <path>".',
        ),
      );
    } else {
      final validation = sdkValidator.validate(sdkConfig.flutterSdkPath!);
      if (validation.isValid) {
        final versionInfo = validation.flutterVersion != null
            ? ' (Version: ${validation.flutterVersion})'
            : '';
        final dartInfo = validation.dartVersion != null
            ? ' - Bundled Dart: ${validation.dartVersion}'
            : '';
        items.add(
          CheckItem(
            title: 'DynBox Flutter SDK Configuration',
            status: CheckStatus.pass,
            details:
                'Configured via ${sdkConfig.source}: ${sdkConfig.flutterSdkPath}$versionInfo$dartInfo\n'
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
            remedy: 'Run "dynbox setup" or provide a valid path containing bin/flutter.',
          ),
        );
      }
    }

    // 5. Host Platform Build Prerequisites (Informational)
    _inspectPlatformPrerequisites(items);

    return DoctorReport(items);
  }

  void _inspectPlatformPrerequisites(List<CheckItem> items) {
    // Java / Android
    var javaOk = false;
    try {
      final res = Process.runSync('java', ['-version']);
      javaOk = res.exitCode == 0;
    } catch (_) {}

    final androidHome =
        environment['ANDROID_HOME'] ?? environment['ANDROID_SDK_ROOT'];
    final hasAndroidSdk =
        androidHome != null && Directory(androidHome).existsSync();

    items.add(
      CheckItem(
        title: 'Android Toolchain (Prerequisite for Android builds)',
        status: (javaOk && hasAndroidSdk)
            ? CheckStatus.pass
            : CheckStatus.warning,
        details:
            'JDK: ${javaOk ? "Detected" : "Not found in PATH"} | Android SDK: ${hasAndroidSdk ? androidHome : "Not detected"}',
        remedy: (!javaOk || !hasAndroidSdk)
            ? 'Install Android Studio and ensure JDK & ANDROID_HOME are set.'
            : null,
      ),
    );

    // iOS (macOS only)
    if (Platform.isMacOS) {
      var xcodeOk = false;
      try {
        final res = Process.runSync('xcodebuild', ['-version']);
        xcodeOk = res.exitCode == 0;
      } catch (_) {}

      items.add(
        CheckItem(
          title: 'iOS Toolchain (Prerequisite for iOS builds)',
          status: xcodeOk ? CheckStatus.pass : CheckStatus.warning,
          details: xcodeOk
              ? 'Xcode detected'
              : 'xcodebuild not detected in PATH',
          remedy: !xcodeOk
              ? 'Install Xcode from Mac App Store for iOS application development.'
              : null,
        ),
      );
    }
  }
}
