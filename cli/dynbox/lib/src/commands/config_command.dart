import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/global_config.dart';
import '../sdk/sdk_validator.dart';

/// Top-level command `dynbox config`.
class ConfigCommand extends Command<int> {
  @override
  final String name = 'config';

  @override
  final String description =
      'Inspect and modify persistent global DynBox configuration settings.';

  final File? globalConfigFileOverride;
  final SdkValidator? validator;

  ConfigCommand({this.globalConfigFileOverride, this.validator}) {
    addSubcommand(
      ConfigSetCommand(
        globalConfigFileOverride: globalConfigFileOverride,
        validator: validator,
      ),
    );
    addSubcommand(
      ConfigGetCommand(globalConfigFileOverride: globalConfigFileOverride),
    );
    addSubcommand(
      ConfigListCommand(globalConfigFileOverride: globalConfigFileOverride),
    );
    addSubcommand(
      ConfigUnsetCommand(globalConfigFileOverride: globalConfigFileOverride),
    );
  }

  @override
  int run() {
    printUsage();
    return 0;
  }
}

/// Subcommand `dynbox config set <key> <value>`.
class ConfigSetCommand extends Command<int> {
  @override
  final String name = 'set';

  @override
  final String description =
      'Set a persistent user configuration key (e.g. flutter-root <path>).';

  final File? globalConfigFileOverride;
  final SdkValidator validator;

  ConfigSetCommand({this.globalConfigFileOverride, SdkValidator? validator})
    : validator = validator ?? const SdkValidator();

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.length < 2) {
      throw UsageException(
        'Missing key or value. Usage: dynbox config set <key> <value>\n'
        'Example: dynbox config set flutter-root /opt/homebrew/share/flutter',
        usage,
      );
    }

    final key = rest[0].trim();
    final value = rest[1].trim();

    // Specific validation for Flutter SDK root
    if (key == 'flutter-root' ||
        key == 'flutter_root' ||
        key == 'sdk.flutter.path') {
      final validation = validator.validate(value);
      if (!validation.isValid) {
        stderr.writeln('✗ Error: Invalid Flutter SDK path: "$value".');
        stderr.writeln('  Reason: ${validation.message}');
        stderr.writeln(
          '  Remedy: Provide a valid directory containing bin/flutter.',
        );
        return 1;
      }
    }

    final targetFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();

    try {
      GlobalConfig.setKey(file: targetFile, key: key, value: value);
      stdout.writeln('✓ Successfully set "$key" in ${targetFile.path}');
      if (key == 'flutter-root' ||
          key == 'flutter_root' ||
          key == 'sdk.flutter.path') {
        stdout.writeln('  Verified SDK: $value');
      }
      return 0;
    } catch (e) {
      stderr.writeln('✗ Failed to write configuration: $e');
      return 1;
    }
  }
}

/// Subcommand `dynbox config get <key>`.
class ConfigGetCommand extends Command<int> {
  @override
  final String name = 'get';

  @override
  final String description = 'Get the value of a configuration key.';

  final File? globalConfigFileOverride;

  ConfigGetCommand({this.globalConfigFileOverride});

  @override
  int run() {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException(
        'Missing key. Usage: dynbox config get <key>',
        usage,
      );
    }

    final key = rest.first.trim();
    final targetFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();

    if (!targetFile.existsSync()) {
      stderr.writeln(
        'No persistent configuration found at: ${targetFile.path}',
      );
      return 1;
    }

    final config = GlobalConfig.fromFile(targetFile);
    if (key == 'flutter-root' ||
        key == 'flutter_root' ||
        key == 'sdk.flutter.path') {
      if (config.flutterSdkPath != null) {
        stdout.writeln(config.flutterSdkPath);
        return 0;
      }
    } else if (config.rawConfig.containsKey(key)) {
      stdout.writeln(config.rawConfig[key]);
      return 0;
    }

    stderr.writeln('Key "$key" is not configured.');
    return 1;
  }
}

/// Subcommand `dynbox config list`.
class ConfigListCommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description =
      'List all persistent global configuration settings.';

  final File? globalConfigFileOverride;

  ConfigListCommand({this.globalConfigFileOverride});

  @override
  int run() {
    final targetFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();

    stdout.writeln('DynBox Persistent Global Configuration:');
    stdout.writeln('  Config File: ${targetFile.path}');
    stdout.writeln('----------------------------------------');

    if (!targetFile.existsSync()) {
      stdout.writeln('  (no configuration file found)');
      return 0;
    }

    final config = GlobalConfig.fromFile(targetFile);
    if (config.rawConfig.isEmpty && config.flutterSdkPath == null) {
      stdout.writeln('  (configuration is empty)');
      return 0;
    }

    if (config.flutterSdkPath != null) {
      stdout.writeln('  flutter-root: ${config.flutterSdkPath}');
    }

    config.rawConfig.forEach((k, v) {
      if (k != 'sdk' && k != 'flutter-root' && k != 'configVersion') {
        stdout.writeln('  $k: $v');
      }
    });

    return 0;
  }
}

/// Subcommand `dynbox config unset <key>`.
class ConfigUnsetCommand extends Command<int> {
  @override
  final String name = 'unset';

  @override
  final String description = 'Remove a persistent global configuration key.';

  final File? globalConfigFileOverride;

  ConfigUnsetCommand({this.globalConfigFileOverride});

  @override
  int run() {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException(
        'Missing key. Usage: dynbox config unset <key>',
        usage,
      );
    }

    final key = rest.first.trim();
    final targetFile =
        globalConfigFileOverride ?? GlobalConfig.resolveConfigFile();

    if (!targetFile.existsSync()) {
      stdout.writeln('Configuration file does not exist.');
      return 0;
    }

    GlobalConfig.removeKey(file: targetFile, key: key);
    stdout.writeln('✓ Successfully unset "$key" in ${targetFile.path}');
    return 0;
  }
}
