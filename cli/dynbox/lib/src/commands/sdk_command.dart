import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/global_config.dart';
import '../sdk/flutter_sdk_manager.dart';

/// Top-level command `dynbox sdk`.
class SdkCommand extends Command<int> {
  @override
  final String name = 'sdk';

  @override
  final String description =
      'Manage official Flutter SDK installations, versions, and active defaults.';

  final FlutterSdkManager sdkManager;
  final File? globalConfigFileOverride;

  SdkCommand({FlutterSdkManager? sdkManager, this.globalConfigFileOverride})
    : sdkManager = sdkManager ?? FlutterSdkManager() {
    addSubcommand(SdkListCommand(sdkManager: this.sdkManager));
    addSubcommand(SdkListInstalledCommand(sdkManager: this.sdkManager));
    addSubcommand(
      SdkInstallCommand(
        sdkManager: this.sdkManager,
        globalConfigFileOverride: globalConfigFileOverride,
      ),
    );
    addSubcommand(
      SdkUseCommand(
        sdkManager: this.sdkManager,
        globalConfigFileOverride: globalConfigFileOverride,
      ),
    );
    addSubcommand(
      SdkCurrentCommand(
        sdkManager: this.sdkManager,
        globalConfigFileOverride: globalConfigFileOverride,
      ),
    );
    addSubcommand(SdkRemoveCommand(sdkManager: this.sdkManager));
  }

  @override
  int run() {
    printUsage();
    return 0;
  }
}

/// Subcommand `dynbox sdk list`.
class SdkListCommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description =
      'List official Flutter releases available for the host platform.';

  final FlutterSdkManager sdkManager;

  SdkListCommand({required this.sdkManager}) {
    argParser.addOption(
      'channel',
      abbr: 'c',
      defaultsTo: 'stable',
      help: 'Filter releases by channel (stable, beta, all).',
    );
  }

  @override
  Future<int> run() async {
    final channel = argResults?['channel'] as String? ?? 'stable';
    stdout.writeln(
      'Fetching official Flutter releases for ${Platform.operatingSystem}...',
    );

    try {
      final catalog = await sdkManager.downloadClient.fetchCatalog();
      final targetArch = Platform.version.contains('arm64') ? 'arm64' : 'x64';

      stdout.writeln(
        'Available Official Flutter Releases (${Platform.operatingSystem} - $targetArch):',
      );
      stdout.writeln(
        '-----------------------------------------------------------------',
      );

      final releases = catalog.releases.where((r) {
        if (channel != 'all' && r.channel != channel) return false;
        if (r.dartSdkArch.isNotEmpty &&
            r.dartSdkArch != targetArch &&
            r.dartSdkArch != 'x64') {
          return false;
        }
        return true;
      }).toList();

      if (releases.isEmpty) {
        stdout.writeln('No releases found for channel "$channel".');
        return 0;
      }

      // Show up to 15 most recent releases
      final displayed = releases.take(15).toList();
      for (final rel in displayed) {
        final isCurrentStable = catalog.currentReleases['stable'] == rel.hash;
        final mark = isCurrentStable ? ' [current-stable]' : '';
        stdout.writeln(
          '  • Version: ${rel.version.padRight(12)} Channel: ${rel.channel.padRight(8)} Date: ${rel.releaseDate.split('T').first}$mark',
        );
      }
      stdout.writeln(
        '-----------------------------------------------------------------',
      );
      stdout.writeln(
        'Run "dynbox sdk install <version>" to download and install.',
      );
      return 0;
    } catch (e) {
      stderr.writeln('✗ Failed to fetch releases: $e');
      return 1;
    }
  }
}

/// Subcommand `dynbox sdk list-installed`.
class SdkListInstalledCommand extends Command<int> {
  @override
  final String name = 'list-installed';

  @override
  final String description = 'List all locally installed managed Flutter SDKs.';

  final FlutterSdkManager sdkManager;

  SdkListInstalledCommand({required this.sdkManager});

  @override
  int run() {
    final installed = sdkManager.listInstalled();
    final sdksDir = sdkManager.resolveSdksDirectory();

    stdout.writeln('Installed Managed Flutter SDKs (${sdksDir.path}):');
    stdout.writeln(
      '-----------------------------------------------------------------',
    );

    if (installed.isEmpty) {
      stdout.writeln('  (no managed Flutter SDKs installed)');
      stdout.writeln(
        '  Run "dynbox sdk install stable" to install the latest official release.',
      );
      return 0;
    }

    for (final item in installed) {
      final validStr = item.isValid ? '[Valid]' : '[Corrupted]';
      final dartStr = item.dartVersion != null
          ? ' (Dart: ${item.dartVersion})'
          : '';
      stdout.writeln(
        '  • ${item.version.padRight(12)} $validStr$dartStr - ${item.directory.path}',
      );
    }
    stdout.writeln(
      '-----------------------------------------------------------------',
    );
    return 0;
  }
}

/// Subcommand `dynbox sdk install [version]`.
class SdkInstallCommand extends Command<int> {
  @override
  final String name = 'install';

  @override
  final String description =
      'Download, verify, and install an official Flutter SDK release (e.g. stable, 3.47.7).';

  final FlutterSdkManager sdkManager;
  final File? globalConfigFileOverride;

  SdkInstallCommand({required this.sdkManager, this.globalConfigFileOverride}) {
    argParser
      ..addFlag(
        'use',
        defaultsTo: true,
        help: 'Set the installed SDK as the global default.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Automatically confirm download without interactive prompt.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    final versionTarget = rest.isNotEmpty ? rest.first.trim() : 'stable';
    final autoUse = argResults?['use'] as bool? ?? true;
    final autoConfirm = argResults?['yes'] as bool? ?? false;

    stdout.writeln(
      'Checking official Flutter releases for "$versionTarget"...',
    );
    final catalog = await sdkManager.downloadClient.fetchCatalog();
    final targetArch = Platform.version.contains('arm64') ? 'arm64' : 'x64';

    final FlutterRelease? targetRelease;
    if (versionTarget.toLowerCase() == 'stable') {
      targetRelease = catalog.findLatestStable(arch: targetArch);
    } else {
      targetRelease = catalog.findVersion(versionTarget, arch: targetArch);
    }

    if (targetRelease == null) {
      stderr.writeln(
        '✗ Error: Could not find an official Flutter release matching "$versionTarget" for $targetArch.',
      );
      return 1;
    }

    stdout.writeln('Found official Flutter release:');
    stdout.writeln('  Version:     ${targetRelease.version}');
    stdout.writeln('  Channel:     ${targetRelease.channel}');
    stdout.writeln('  Dart:        ${targetRelease.dartSdkVersion}');
    stdout.writeln('  Archive:     ${targetRelease.archive}');
    stdout.writeln('  SHA-256:     ${targetRelease.sha256}');

    if (!autoConfirm) {
      stdout.write(
        'Do you want to download and install this official SDK? [y/N]: ',
      );
      final line = stdin.readLineSync()?.trim().toLowerCase();
      if (line != 'y' && line != 'yes') {
        stdout.writeln('Installation cancelled.');
        return 0;
      }
    }

    try {
      final installed = await sdkManager.installRelease(
        release: targetRelease,
        baseUrl: catalog.baseUrl,
        onStatus: (msg) => stdout.writeln(msg),
      );

      if (autoUse) {
        final configFile =
            globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();
        GlobalConfig.setKey(
          file: configFile,
          key: 'flutter-root',
          value: installed.directory.path,
        );
        stdout.writeln(
          '✓ Set as global default SDK: ${installed.directory.path}',
        );
      }

      return 0;
    } catch (e) {
      stderr.writeln('✗ Installation failed: $e');
      return 1;
    }
  }
}

/// Subcommand `dynbox sdk use <version>`.
class SdkUseCommand extends Command<int> {
  @override
  final String name = 'use';

  @override
  final String description =
      'Set an installed managed SDK version as the global default.';

  final FlutterSdkManager sdkManager;
  final File? globalConfigFileOverride;

  SdkUseCommand({required this.sdkManager, this.globalConfigFileOverride});

  @override
  int run() {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException(
        'Missing SDK version. Usage: dynbox sdk use <version>',
        usage,
      );
    }

    final targetVersion = rest.first.trim();
    final sdkDir = sdkManager.getSdkDirectory(targetVersion);

    if (!sdkDir.existsSync()) {
      stderr.writeln(
        '✗ Error: Managed SDK version "$targetVersion" is not installed.',
      );
      stderr.writeln('  Location checked: ${sdkDir.path}');
      stderr.writeln(
        '  Run "dynbox sdk list-installed" to see installed versions.',
      );
      stderr.writeln(
        '  Or run "dynbox sdk install $targetVersion" to install it.',
      );
      return 1;
    }

    final validation = sdkManager.sdkValidator.validate(sdkDir.path);
    if (!validation.isValid) {
      stderr.writeln(
        '✗ Error: Managed SDK in "${sdkDir.path}" is invalid: ${validation.message}',
      );
      return 1;
    }

    final configFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();
    GlobalConfig.setKey(
      file: configFile,
      key: 'flutter-root',
      value: sdkDir.path,
    );

    stdout.writeln(
      '✓ Active global Flutter SDK is now: $targetVersion (${sdkDir.path})',
    );
    return 0;
  }
}

/// Subcommand `dynbox sdk current`.
class SdkCurrentCommand extends Command<int> {
  @override
  final String name = 'current';

  @override
  final String description =
      'Display the currently resolved active Flutter SDK.';

  final FlutterSdkManager sdkManager;
  final File? globalConfigFileOverride;

  SdkCurrentCommand({required this.sdkManager, this.globalConfigFileOverride});

  @override
  int run() {
    final configFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();
    final globalConfig = GlobalConfig.fromFile(configFile);

    stdout.writeln('DynBox Active SDK Inspection:');
    if (globalConfig.flutterSdkPath != null) {
      final validation = sdkManager.sdkValidator.validate(
        globalConfig.flutterSdkPath!,
      );
      stdout.writeln('  Global Path:    ${globalConfig.flutterSdkPath}');
      stdout.writeln('  Valid:          ${validation.isValid}');
      if (validation.flutterVersion != null) {
        stdout.writeln('  Flutter Version: ${validation.flutterVersion}');
      }
      if (validation.dartVersion != null) {
        stdout.writeln('  Dart Version:    ${validation.dartVersion}');
      }
    } else {
      stdout.writeln('  No global Flutter SDK is currently set.');
      stdout.writeln(
        '  Run "dynbox sdk install stable" or "dynbox setup" to configure one.',
      );
    }
    return 0;
  }
}

/// Subcommand `dynbox sdk remove <version>`.
class SdkRemoveCommand extends Command<int> {
  @override
  final String name = 'remove';

  @override
  final String description =
      'Remove an installed managed Flutter SDK version (with confirmation).';

  final FlutterSdkManager sdkManager;

  SdkRemoveCommand({required this.sdkManager}) {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Confirm removal without interactive prompt.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException(
        'Missing SDK version to remove. Usage: dynbox sdk remove <version>',
        usage,
      );
    }

    final targetVersion = rest.first.trim();
    final sdkDir = sdkManager.getSdkDirectory(targetVersion);

    if (!sdkDir.existsSync()) {
      stderr.writeln(
        '✗ Error: Managed SDK version "$targetVersion" does not exist in ${sdkDir.path}.',
      );
      return 1;
    }

    final autoConfirm = argResults?['yes'] as bool? ?? false;
    if (!autoConfirm) {
      stdout.write(
        'Are you sure you want to remove Flutter SDK "$targetVersion" (${sdkDir.path})? [y/N]: ',
      );
      final line = stdin.readLineSync()?.trim().toLowerCase();
      if (line != 'y' && line != 'yes') {
        stdout.writeln('Removal cancelled.');
        return 0;
      }
    }

    try {
      await sdkManager.removeSdk(targetVersion);
      stdout.writeln(
        '✓ Successfully removed managed Flutter SDK "$targetVersion".',
      );
      return 0;
    } catch (e) {
      stderr.writeln('✗ Failed to remove SDK: $e');
      return 1;
    }
  }
}
