import 'dart:io';

import 'package:dynbox/src/doctor/environment_inspector.dart';
import 'package:dynbox/src/doctor/output_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('Doctor & OutputFormatter', () {
    test('formats pass, warning, and fail correctly without ANSI', () {
      const formatter = OutputFormatter(useAnsi: false);

      expect(formatter.formatStatus(CheckStatus.pass), '[✓]');
      expect(formatter.formatStatus(CheckStatus.warning), '[!]');
      expect(formatter.formatStatus(CheckStatus.fail), '[✗]');
    });

    test('generates doctor summary report accurately', () {
      const formatter = OutputFormatter(useAnsi: false);
      const report = DoctorReport([
        CheckItem(
          title: 'Check 1',
          status: CheckStatus.pass,
          details: 'Working properly',
        ),
        CheckItem(
          title: 'Check 2',
          status: CheckStatus.warning,
          details: 'Needs attention',
          remedy: 'Run command X',
        ),
      ]);

      expect(report.hasFailures, isFalse);
      expect(report.hasWarnings, isTrue);
      expect(report.passCount, 1);
      expect(report.warningCount, 1);

      final output = formatter.formatReport(report);
      expect(output, contains('[✓] Check 1'));
      expect(output, contains('[!] Check 2'));
      expect(output, contains('Action: Run command X'));
      expect(output, contains('Doctor found 1 warning(s)'));
    });

    test('environment inspector produces warning on unconfigured SDK', () {
      final inspector = EnvironmentInspector(environment: {});
      final report = inspector.runInspection();

      final sdkCheck = report.items.firstWhere(
        (i) => i.title.contains('Flutter SDK Configuration'),
      );

      expect(sdkCheck.status, CheckStatus.warning);
      expect(sdkCheck.details, contains('No explicit Flutter SDK configured'));
    });

    test('environment inspector produces fail on invalid SDK path', () {
      final inspector = EnvironmentInspector(environment: {});
      final report = inspector.runInspection(
        explicitSdkPath: '/some/bogus/path/flutter',
      );

      final sdkCheck = report.items.firstWhere(
        (i) => i.title.contains('Flutter SDK Configuration'),
      );

      expect(sdkCheck.status, CheckStatus.fail);
      expect(sdkCheck.details, contains('is invalid'));
      expect(report.hasFailures, isTrue);
    });

    test('environment inspector produces pass on valid SDK path', () {
      final tempDir = Directory.systemTemp.createTempSync('dynbox_mock_sdk_');
      final binDir = Directory('${tempDir.path}/bin')..createSync();
      final binaryName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      File('${binDir.path}/$binaryName').writeAsStringSync('');

      final inspector = EnvironmentInspector(environment: {});
      final report = inspector.runInspection(explicitSdkPath: tempDir.path);

      final sdkCheck = report.items.firstWhere(
        (i) => i.title.contains('Flutter SDK Configuration'),
      );

      expect(sdkCheck.status, CheckStatus.pass);
      expect(report.hasFailures, isFalse);

      tempDir.deleteSync(recursive: true);
    });
  });
}
