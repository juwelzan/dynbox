import 'package:args/command_runner.dart';
import 'package:dynbox/src/runner.dart';
import 'package:test/test.dart';

void main() {
  group('DynboxRunner CLI Arguments', () {
    late DynboxRunner runner;

    setUp(() {
      runner = DynboxRunner();
    });

    test('supports --help without error', () async {
      expect(() => runner.run(['--help']), returnsNormally);
    });

    test('supports --version without error', () async {
      final exitCode = await runner.run(['--version']);
      expect(exitCode, 0);
    });

    test('throws UsageException on invalid flag', () async {
      expect(
        () => runner.run(['--unrecognized-flag']),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws UsageException on invalid command', () async {
      expect(
        () => runner.run(['unknown-command']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
