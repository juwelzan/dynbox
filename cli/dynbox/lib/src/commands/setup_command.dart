import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/global_config.dart';
import '../sdk/flutter_sdk_manager.dart';
import '../sdk/sdk_validator.dart';

/// Command `dynbox setup`.
/// Provides a guided first-time setup experience for new machines.
class SetupCommand extends Command<int> {
  @override
  final String name = 'setup';

  @override
  final String description =
      'Guided first-time setup: detects, configures, or installs an official Flutter SDK.';

  final FlutterSdkManager sdkManager;
  final SdkValidator sdkValidator;
  final File? globalConfigFileOverride;

  SetupCommand({
    FlutterSdkManager? sdkManager,
    SdkValidator? sdkValidator,
    this.globalConfigFileOverride,
  }) : sdkManager = sdkManager ?? FlutterSdkManager(),
       sdkValidator = sdkValidator ?? const SdkValidator() {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Automatically accept prompts and install stable SDK if missing.',
    );
  }

  @override
  Future<int> run() async {
    final autoConfirm = argResults?['yes'] as bool? ?? false;
    final configFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();

    stdout.writeln(
      '================================================================',
    );
    stdout.writeln('          DynBox — First-Time Environment Setup');
    stdout.writeln(
      '================================================================',
    );
    stdout.writeln(
      'Host Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
    );
    stdout.writeln(
      'Architecture:  ${Platform.version.contains('arm64') ? 'arm64' : 'x64'}',
    );
    stdout.writeln('Config File:   ${configFile.path}');
    stdout.writeln(
      '----------------------------------------------------------------',
    );

    // 1. Check existing global configuration or workspace configuration
    final sdkConfig = sdkValidator.resolveConfig(
      configFile: File('.dynbox/config.yaml'),
    );

    if (sdkConfig.isConfigured) {
      final validation = sdkValidator.validate(sdkConfig.flutterSdkPath!);
      if (validation.isValid) {
        stdout.writeln('✓ Valid Flutter SDK is already configured:');
        stdout.writeln('  Source:    ${sdkConfig.source}');
        stdout.writeln('  Path:      ${sdkConfig.flutterSdkPath}');
        if (validation.flutterVersion != null) {
          stdout.writeln('  Flutter:   ${validation.flutterVersion}');
        }
        if (validation.dartVersion != null) {
          stdout.writeln('  Dart:      ${validation.dartVersion}');
        }
        stdout.writeln('');
        stdout.writeln('No additional SDK installation is necessary.');
        _checkPlatformPrerequisites();
        stdout.writeln('');
        stdout.writeln('Ready to create projects:');
        stdout.writeln('  dynbox create my_app');
        return 0;
      } else {
        stdout.writeln('! Configured Flutter SDK path is currently invalid:');
        stdout.writeln('  Path:   ${sdkConfig.flutterSdkPath}');
        stdout.writeln('  Reason: ${validation.message}');
      }
    } else {
      stdout.writeln('No Flutter SDK is currently configured for DynBox.');
    }

    // 2. Offer official stable Flutter SDK installation
    stdout.writeln('');
    stdout.writeln(
      'DynBox can automatically download, verify, and configure the',
    );
    stdout.writeln(
      'latest official stable Flutter SDK for your operating system.',
    );
    stdout.writeln('Target Installation Directory:');
    stdout.writeln('  ${sdkManager.resolveSdksDirectory().path}/<version>');
    stdout.writeln('');

    if (!autoConfirm) {
      stdout.write(
        'Would you like DynBox to install official stable Flutter now? [y/N]: ',
      );
      final line = stdin.readLineSync()?.trim().toLowerCase();
      if (line != 'y' && line != 'yes') {
        stdout.writeln('Setup paused.');
        stdout.writeln(
          'You can manually configure an existing SDK anytime via:',
        );
        stdout.writeln(
          '  dynbox config set flutter-root /path/to/official/flutter',
        );
        return 0;
      }
    }

    try {
      stdout.writeln('Fetching official release catalog...');
      final catalog = await sdkManager.downloadClient.fetchCatalog();
      final targetArch = Platform.version.contains('arm64') ? 'arm64' : 'x64';
      final stable = catalog.findLatestStable(arch: targetArch);

      if (stable == null) {
        stderr.writeln(
          '✗ Error: No official stable Flutter release found for $targetArch.',
        );
        return 1;
      }

      stdout.writeln(
        'Selected release: Flutter ${stable.version} (${stable.dartSdkArch})',
      );
      final installed = await sdkManager.installRelease(
        release: stable,
        baseUrl: catalog.baseUrl,
        onStatus: (msg) => stdout.writeln(msg),
      );

      // Persist as global default
      GlobalConfig.setKey(
        file: configFile,
        key: 'flutter-root',
        value: installed.directory.path,
      );

      stdout.writeln('');
      stdout.writeln('✓ Global Flutter SDK successfully configured!');
      stdout.writeln('  Path:    ${installed.directory.path}');
      stdout.writeln('  Flutter: ${installed.version}');
      if (installed.dartVersion != null) {
        stdout.writeln('  Dart:    ${installed.dartVersion}');
      }

      stdout.writeln('');
      _checkPlatformPrerequisites();

      stdout.writeln(
        '================================================================',
      );
      stdout.writeln('DynBox setup is complete! You can now create projects:');
      stdout.writeln('  dynbox create my_app');
      stdout.writeln('  dynbox doctor');
      stdout.writeln(
        '================================================================',
      );
      return 0;
    } catch (e) {
      stderr.writeln('✗ Setup failed during SDK installation: $e');
      return 1;
    }
  }

  void _checkPlatformPrerequisites() {
    stdout.writeln('Platform Build Prerequisites (Informational):');
    stdout.writeln(
      '----------------------------------------------------------------',
    );

    // Android
    final hasJava = _checkTool('java', ['-version']);
    final androidHome =
        Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'];
    final javaStr = hasJava
        ? '[✓] JDK / Java installed'
        : '[!] JDK not detected in PATH';
    final androidHomeStr =
        androidHome != null && Directory(androidHome).existsSync()
        ? '[✓] Android SDK directory detected ($androidHome)'
        : '[!] Android SDK not detected (Install Android Studio for Android apps)';
    stdout.writeln('  Android:');
    stdout.writeln('    $javaStr');
    stdout.writeln('    $androidHomeStr');

    // iOS (macOS only)
    if (Platform.isMacOS) {
      final hasXcode = _checkTool('xcodebuild', ['-version']);
      final xcodeStr = hasXcode
          ? '[✓] Xcode detected'
          : '[!] Xcode not detected (Install Xcode from App Store for iOS apps)';
      stdout.writeln('  iOS:');
      stdout.writeln('    $xcodeStr');
    }

    stdout.writeln(
      '  Note: Platform build tools (Xcode, Android SDK) are managed by',
    );
    stdout.writeln(
      '  their respective vendors and are only needed for native compilation.',
    );
    stdout.writeln(
      '----------------------------------------------------------------',
    );
  }

  bool _checkTool(String executable, List<String> args) {
    try {
      final res = Process.runSync(executable, args);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
