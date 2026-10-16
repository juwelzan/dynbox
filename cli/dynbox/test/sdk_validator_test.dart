import 'dart:io';

import 'package:dynbox/src/sdk/sdk_validator.dart';
import 'package:test/test.dart';

void main() {
  group('SdkValidator', () {
    test('resolves unconfigured SDK when no options provided', () {
      const validator = SdkValidator(environment: {});
      final config = validator.resolveConfig();

      expect(config.isConfigured, isFalse);
      expect(config.flutterSdkPath, isNull);
      expect(config.source, 'none');
    });

    test('resolves explicit CLI argument as highest priority', () {
      const validator = SdkValidator(
        environment: {'DYNBOX_FLUTTER_ROOT': '/env/flutter'},
      );
      final config = validator.resolveConfig(explicitPath: '/cli/flutter');

      expect(config.isConfigured, isTrue);
      expect(config.flutterSdkPath, '/cli/flutter');
      expect(config.source, 'cli-argument');
    });

    test('resolves environment variable when explicit argument is absent', () {
      const validator = SdkValidator(
        environment: {'DYNBOX_FLUTTER_ROOT': '/env/flutter'},
      );
      final config = validator.resolveConfig();

      expect(config.isConfigured, isTrue);
      expect(config.flutterSdkPath, '/env/flutter');
      expect(config.source, 'environment-variable (DYNBOX_FLUTTER_ROOT)');
    });

    test('resolves from config file when present', () {
      final tempDir = Directory.systemTemp.createTempSync('dynbox_test_');
      final configFile = File('${tempDir.path}/config.yaml');
      configFile.writeAsStringSync('flutter_sdk_path: /config/flutter\n');

      const validator = SdkValidator(environment: {});
      final config = validator.resolveConfig(configFile: configFile);

      expect(config.isConfigured, isTrue);
      expect(config.flutterSdkPath, '/config/flutter');
      expect(config.source, contains('config-file'));

      tempDir.deleteSync(recursive: true);
    });

    test('returns invalid result when directory does not exist', () {
      const validator = SdkValidator();
      final result = validator.validate('/non/existent/path/for/flutter');

      expect(result.isValid, isFalse);
      expect(result.message, contains('does not exist'));
    });

    test('returns invalid result when bin/flutter is missing in directory', () {
      final tempDir = Directory.systemTemp.createTempSync('dynbox_empty_sdk_');
      const validator = SdkValidator();
      final result = validator.validate(tempDir.path);

      expect(result.isValid, isFalse);
      expect(result.message, contains('no Flutter executable found'));

      tempDir.deleteSync(recursive: true);
    });

    test('returns valid result when bin/flutter exists', () {
      final tempDir = Directory.systemTemp.createTempSync('dynbox_valid_sdk_');
      final binDir = Directory('${tempDir.path}/bin')..createSync();
      final binaryName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      final exe = File('${binDir.path}/$binaryName')..writeAsStringSync('');
      File('${tempDir.path}/version').writeAsStringSync('3.49.0\n');

      const validator = SdkValidator();
      final result = validator.validate(tempDir.path);

      expect(result.isValid, isTrue);
      expect(result.flutterExecutablePath, exe.path);
      expect(result.flutterVersion, '3.49.0');

      tempDir.deleteSync(recursive: true);
    });
  });
}
