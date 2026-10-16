import 'dart:io';

import 'package:dynbox/src/sdk/sdk_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('SdkResolver', () {
    late Directory tempSdkDir;
    late File flutterExe;

    setUp(() {
      tempSdkDir = Directory.systemTemp.createTempSync('dynbox_mock_sdk_');
      final binDir = Directory('${tempSdkDir.path}/bin')..createSync();
      final exeName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      flutterExe = File('${binDir.path}/$exeName')..writeAsStringSync('');
      File('${tempSdkDir.path}/version').writeAsStringSync('3.49.0');
    });

    tearDown(() {
      if (tempSdkDir.existsSync()) {
        tempSdkDir.deleteSync(recursive: true);
      }
    });

    test('CLI argument takes highest precedence over config and env', () {
      final otherSdk = Directory.systemTemp.createTempSync('dynbox_other_sdk_');
      final otherBin = Directory('${otherSdk.path}/bin')..createSync();
      final otherExeName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      File('${otherBin.path}/$otherExeName').writeAsStringSync('');

      final configFile = File('${tempSdkDir.path}/config.yaml')
        ..writeAsStringSync('''
configVersion: 1
project:
  name: test_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: ${otherSdk.path}
''');

      final resolver = SdkResolver(
        environment: {'DYNBOX_FLUTTER_ROOT': otherSdk.path},
      );

      final pinned = resolver.resolve(
        cliArgument: tempSdkDir.path,
        configFile: configFile,
      );

      expect(pinned.sdkDirectory, tempSdkDir.absolute.path);
      expect(pinned.executablePath, flutterExe.absolute.path);
      expect(pinned.source, contains('cli-argument'));

      otherSdk.deleteSync(recursive: true);
    });

    test('Workspace config takes precedence over environment variable', () {
      final envSdk = Directory.systemTemp.createTempSync('dynbox_env_sdk_');
      final envBin = Directory('${envSdk.path}/bin')..createSync();
      final exeName = Platform.isWindows ? 'flutter.bat' : 'flutter';
      File('${envBin.path}/$exeName').writeAsStringSync('');

      final configFile = File('${tempSdkDir.path}/config.yaml')
        ..writeAsStringSync('''
configVersion: 1
project:
  name: test_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: ${tempSdkDir.path}
''');

      final resolver = SdkResolver(
        environment: {'DYNBOX_FLUTTER_ROOT': envSdk.path},
      );

      final pinned = resolver.resolve(configFile: configFile);

      expect(pinned.sdkDirectory, tempSdkDir.absolute.path);
      expect(pinned.source, contains('workspace-config'));

      envSdk.deleteSync(recursive: true);
    });

    test('Environment variable is used when CLI and config are absent', () {
      final resolver = SdkResolver(
        environment: {'DYNBOX_FLUTTER_ROOT': tempSdkDir.path},
      );

      final pinned = resolver.resolve();

      expect(pinned.sdkDirectory, tempSdkDir.absolute.path);
      expect(pinned.source, contains('environment-variable'));
      expect(pinned.version, '3.49.0');
    });

    test('throws SdkResolutionException when no configuration is present', () {
      final resolver = SdkResolver(environment: {});

      expect(
        () => resolver.resolve(),
        throwsA(
          isA<SdkResolutionException>().having(
            (e) => e.message,
            'message',
            contains('No explicit Flutter SDK configured'),
          ),
        ),
      );
    });

    test('throws SdkResolutionException when path exists but executable is missing', () {
      final emptyDir = Directory.systemTemp.createTempSync('dynbox_empty_sdk_');
      final resolver = SdkResolver(environment: {});

      expect(
        () => resolver.resolve(cliArgument: emptyDir.path),
        throwsA(
          isA<SdkResolutionException>().having(
            (e) => e.message,
            'message',
            contains('no Flutter executable found'),
          ),
        ),
      );

      emptyDir.deleteSync(recursive: true);
    });

    test('resolves absolute executable path across platforms', () {
      final resolver = SdkResolver();
      final pinned = resolver.resolve(cliArgument: tempSdkDir.path);

      expect(pinned.executablePath, isNotEmpty);
      expect(File(pinned.executablePath).isAbsolute, isTrue);
    });
  });
}
