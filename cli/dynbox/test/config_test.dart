import 'dart:io';

import 'package:dynbox/src/config/dynbox_config.dart';
import 'package:test/test.dart';

void main() {
  group('DynboxConfig', () {
    const validYaml = '''
configVersion: 1
project:
  name: demo_app
  kind: flutter_app
  description: A sample DynBox app
sdk:
  flutter:
    source: local
    path: /custom/flutter
    versionConstraint: ">=3.24.0"
backend:
  provider: none
''';

    test('parses valid configuration successfully', () {
      final config = DynboxConfig.fromYamlString(
        validYaml,
        workspaceRoot: '/workspace',
      );

      expect(config.configVersion, 1);
      expect(config.project.name, 'demo_app');
      expect(config.project.kind, ProjectKind.flutterApp);
      expect(config.project.description, 'A sample DynBox app');
      expect(config.flutterSdk.source, 'local');
      expect(config.flutterSdk.path, '/custom/flutter');
      expect(config.flutterSdk.versionConstraint, '>=3.24.0');
      expect(config.backend.provider, BackendProviderKind.none);
    });

    test('resolves relative Flutter SDK path against workspaceRoot', () {
      const relYaml = '''
configVersion: 1
project:
  name: test_pkg
  kind: flutter_package
sdk:
  flutter:
    source: local
    path: tools/flutter_sdk
backend:
  provider: none
''';

      final config = DynboxConfig.fromYamlString(
        relYaml,
        workspaceRoot: '/my/workspace',
      );

      expect(config.flutterSdk.path, '/my/workspace/tools/flutter_sdk');
    });

    test('parses firebase backend configuration', () {
      const firebaseYaml = '''
configVersion: 1
project:
  name: cloud_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: /opt/flutter
backend:
  provider: firebase
  firebase:
    projectId: demo-proj-123
''';

      final config = DynboxConfig.fromYamlString(
        firebaseYaml,
        workspaceRoot: '/workspace',
      );

      expect(config.backend.provider, BackendProviderKind.firebase);
      expect(
        config.backend.providerConfig['firebase']['projectId'],
        'demo-proj-123',
      );
    });

    test('throws on unsupported configVersion', () {
      const badVersionYaml = '''
configVersion: 99
project:
  name: my_app
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: /flutter
''';

      expect(
        () => DynboxConfig.fromYamlString(
          badVersionYaml,
          workspaceRoot: '/workspace',
        ),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported configVersion'),
          ),
        ),
      );
    });

    test('throws on invalid project name', () {
      const badNameYaml = '''
configVersion: 1
project:
  name: 123-invalid-name!
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: /flutter
''';

      expect(
        () => DynboxConfig.fromYamlString(
          badNameYaml,
          workspaceRoot: '/workspace',
        ),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('Invalid "project.name"'),
          ),
        ),
      );
    });

    test('throws on unsupported project kind', () {
      const badKindYaml = '''
configVersion: 1
project:
  name: good_name
  kind: unsupported_kind
sdk:
  flutter:
    source: local
    path: /flutter
''';

      expect(
        () => DynboxConfig.fromYamlString(
          badKindYaml,
          workspaceRoot: '/workspace',
        ),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported project kind'),
          ),
        ),
      );
    });

    test('throws on missing SDK section', () {
      const noSdkYaml = '''
configVersion: 1
project:
  name: good_name
  kind: flutter_app
''';

      expect(
        () =>
            DynboxConfig.fromYamlString(noSdkYaml, workspaceRoot: '/workspace'),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('Missing or invalid "sdk" section'),
          ),
        ),
      );
    });

    test('throws on malformed YAML syntax', () {
      const malformedYaml = '''
configVersion: 1
project: [unclosed list
''';

      expect(
        () => DynboxConfig.fromYamlString(
          malformedYaml,
          workspaceRoot: '/workspace',
        ),
        throwsA(isA<ConfigException>()),
      );
    });

    test('loads from File correctly', () {
      final tempDir = Directory.systemTemp.createTempSync('dynbox_cfg_test_');
      final file = File('${tempDir.path}/.dynbox/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(validYaml);

      final config = DynboxConfig.fromFile(file, workspaceRoot: tempDir.path);
      expect(config.project.name, 'demo_app');

      tempDir.deleteSync(recursive: true);
    });
  });
}
