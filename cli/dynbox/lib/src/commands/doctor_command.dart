import 'dart:io';

import 'package:args/command_runner.dart';

import '../doctor/environment_inspector.dart';
import '../doctor/output_formatter.dart';

class DoctorCommand extends Command<int> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Inspect the local environment, runtime tools, and DynBox Flutter SDK configuration.';

  final EnvironmentInspector inspector;
  final OutputFormatter formatter;

  DoctorCommand({EnvironmentInspector? inspector, OutputFormatter? formatter})
    : inspector = inspector ?? EnvironmentInspector(),
      formatter = formatter ?? const OutputFormatter() {
    argParser.addOption(
      'flutter-root',
      help: 'Explicit path to the Flutter SDK directory to validate.',
    );
  }

  @override
  int run() {
    final flutterRoot = argResults?['flutter-root'] as String?;
    final configFile = File('.dynbox/config.yaml');

    final report = inspector.runInspection(
      explicitSdkPath: flutterRoot,
      configFile: configFile,
    );

    final formatted = formatter.formatReport(report);
    stdout.write(formatted);

    // Non-zero exit code if doctor detected failures
    if (report.hasFailures) {
      return 1;
    }
    return 0;
  }
}
