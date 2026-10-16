import 'dart:convert';
import 'dart:io';

import 'package:dynbox/src/config/dynbox_config.dart';
import 'package:test/test.dart';

void main() {
  group('Project Specification Fixtures', () {
    test('valid project specification passes typed schema checks', () {
      final file = File('test/fixtures/project_spec_valid.json');
      expect(file.existsSync(), isTrue);

      final jsonContent = file.readAsStringSync();
      final decoded = jsonDecode(jsonContent);

      expect(decoded['schemaVersion'], 1);
      final project = ProjectConfig.fromYaml(decoded['project']);
      expect(project.name, 'sample_mobile_app');
      expect(project.kind, ProjectKind.flutterApp);

      final sdk = FlutterSdkConfig.fromYaml(
        decoded['sdk']['flutter'],
        workspaceRoot: '/root',
      );
      expect(sdk.source, 'local');
      expect(sdk.path, '/opt/flutter');

      final backend = BackendConfig.fromYaml(decoded['backend']);
      expect(backend.provider, BackendProviderKind.firebase);
      expect(
        backend.providerConfig['firebase']['projectId'],
        'demo-dynbox-project',
      );
    });

    test('invalid project specification fails typed validation rules', () {
      final file = File('test/fixtures/project_spec_invalid.json');
      expect(file.existsSync(), isTrue);

      final jsonContent = file.readAsStringSync();
      final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;

      // Invalid project name check
      expect(
        () => ProjectConfig.fromYaml(decoded['project']),
        throwsA(isA<ConfigException>()),
      );

      // Missing SDK check
      expect(decoded.containsKey('sdk'), isFalse);

      // Invalid backend provider check
      expect(
        () => BackendConfig.fromYaml(decoded['backend']),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
