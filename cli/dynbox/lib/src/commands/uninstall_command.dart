import 'dart:io';

import 'package:args/command_runner.dart';

import '../installer/uninstaller.dart';

/// CLI command for safely uninstalling DynBox-owned binaries.
class UninstallCommand extends Command<int> {
  @override
  final String name = 'uninstall';

  @override
  final String description =
      'Safely uninstall DynBox CLI binaries from this machine.';

  final DynboxUninstaller? uninstallerOverride;

  UninstallCommand({this.uninstallerOverride}) {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Confirm uninstallation without prompting interactively.',
    );
  }

  @override
  Future<int> run() async {
    final uninstaller = uninstallerOverride ?? DynboxUninstaller();
    final installDir = uninstaller.resolveInstallDir();
    final files = uninstaller.listDynboxFiles();

    stdout.writeln('DynBox Uninstaller');
    stdout.writeln('  Installation Directory: ${installDir.path}');
    stdout.writeln('  Files targeted for removal:');
    if (files.isEmpty) {
      stdout.writeln('    (none found)');
    } else {
      for (final file in files) {
        stdout.writeln('    - ${file.path}');
      }
    }
    stdout.writeln('');

    if (files.isEmpty) {
      stdout.writeln('No DynBox installation detected in ${installDir.path}.');
      return 0;
    }

    final confirmed = argResults?['yes'] as bool? ?? false;
    if (!confirmed) {
      stdout.write('Are you sure you want to uninstall DynBox? [y/N]: ');
      final line = stdin.readLineSync()?.trim().toLowerCase();
      if (line != 'y' && line != 'yes') {
        stdout.writeln('Uninstallation cancelled.');
        return 0;
      }
    }

    try {
      final message = await uninstaller.uninstall();
      stdout.writeln('✅ $message');
      stdout.writeln('');
      stdout.writeln(
        'Notice: Your shell profiles and PATH environment variables were preserved.',
      );
      stdout.writeln(
        'If desired, you may remove "${installDir.path}" from your PATH in ~/.zshrc or ~/.bashrc.',
      );
      return 0;
    } catch (e) {
      stderr.writeln('❌ Uninstallation failed: $e');
      return 1;
    }
  }
}
