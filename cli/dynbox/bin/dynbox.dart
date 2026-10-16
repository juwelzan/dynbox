import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dynbox/src/runner.dart';

Future<void> main(List<String> args) async {
  final runner = DynboxRunner();
  try {
    final exitCode = await runner.run(args);
    exit(exitCode ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(e.usage);
    exit(64); // EX_USAGE
  } catch (e, stack) {
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(stack);
    exit(1);
  }
}
