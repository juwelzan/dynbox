enum CheckStatus { pass, warning, fail }

class CheckItem {
  final String title;
  final CheckStatus status;
  final String details;
  final String? remedy;

  const CheckItem({
    required this.title,
    required this.status,
    required this.details,
    this.remedy,
  });
}

class DoctorReport {
  final List<CheckItem> items;

  const DoctorReport(this.items);

  bool get hasFailures => items.any((i) => i.status == CheckStatus.fail);
  bool get hasWarnings => items.any((i) => i.status == CheckStatus.warning);

  int get passCount => items.where((i) => i.status == CheckStatus.pass).length;
  int get warningCount =>
      items.where((i) => i.status == CheckStatus.warning).length;
  int get failCount => items.where((i) => i.status == CheckStatus.fail).length;
}

/// Formatter for CLI output
class OutputFormatter {
  static const String reset = '\x1B[0m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String bold = '\x1B[1m';

  final bool useAnsi;

  const OutputFormatter({this.useAnsi = true});

  String formatStatus(CheckStatus status) {
    if (!useAnsi) {
      switch (status) {
        case CheckStatus.pass:
          return '[✓]';
        case CheckStatus.warning:
          return '[!]';
        case CheckStatus.fail:
          return '[✗]';
      }
    }

    switch (status) {
      case CheckStatus.pass:
        return '$green[✓]$reset';
      case CheckStatus.warning:
        return '$yellow[!]$reset';
      case CheckStatus.fail:
        return '$red[✗]$reset';
    }
  }

  String formatReport(DoctorReport report) {
    final buffer = StringBuffer();
    buffer.writeln('DynBox Doctor Summary:');
    buffer.writeln('----------------------------------------');

    for (final item in report.items) {
      buffer.writeln('${formatStatus(item.status)} ${item.title}');
      buffer.writeln('    ${item.details}');
      if (item.remedy != null) {
        buffer.writeln('    • Action: ${item.remedy}');
      }
    }

    buffer.writeln('----------------------------------------');
    if (report.hasFailures) {
      buffer.writeln(
        'Doctor found ${report.failCount} failure(s) and ${report.warningCount} warning(s).',
      );
    } else if (report.hasWarnings) {
      buffer.writeln(
        'Doctor found ${report.warningCount} warning(s). No critical failures.',
      );
    } else {
      buffer.writeln('All ${report.passCount} check(s) passed successfully!');
    }

    return buffer.toString();
  }
}
