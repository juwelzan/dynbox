import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/backend_command.dart';
import 'commands/build_command.dart';
import 'commands/config_command.dart';
import 'commands/create_command.dart';
import 'commands/doctor_command.dart';
import 'commands/ota_command.dart';
import 'commands/sdk_command.dart';
import 'commands/setup_command.dart';
import 'commands/uninstall_command.dart';
import 'commands/upgrade_command.dart';
import 'version.dart';

class DynboxRunner extends CommandRunner<int> {
  DynboxRunner({File? globalConfigFileOverride})
    : super(
        'dynbox',
        'DynBox — Developer-owned Flutter project orchestration platform.',
      ) {
    argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print DynBox CLI version.',
    );

    addCommand(DoctorCommand());
    addCommand(
      SetupCommand(globalConfigFileOverride: globalConfigFileOverride),
    );
    addCommand(SdkCommand(globalConfigFileOverride: globalConfigFileOverride));
    addCommand(
      ConfigCommand(globalConfigFileOverride: globalConfigFileOverride),
    );
    addCommand(CreateCommand());
    addCommand(BackendCommand());
    addCommand(BuildCommand());
    addCommand(OtaCommand());
    addCommand(UpgradeCommand());
    addCommand(UninstallCommand());
  }

  @override
  Future<int> runCommand(dynamic topLevelResults) async {
    if (topLevelResults['version'] == true) {
      stdout.writeln('dynbox version: ${DynboxVersion.version}');
      return 0;
    }

    // Default to help if no command and no arguments provided
    if (topLevelResults.command == null) {
      if (topLevelResults.rest.isNotEmpty) {
        throw UsageException(
          'Could not find a command named "${topLevelResults.rest.first}".',
          usage,
        );
      }
      printUsage();
      return 0;
    }

    final result = await super.runCommand(topLevelResults);
    return result ?? 0;
  }
}
