import 'package:dynbox_ui_runtime/dynbox_ui_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('DynamicUiParser', () {
    const validJson = '''
    {
      "schemaVersion": 1,
      "configId": "test_config",
      "revision": 1,
      "minAppVersion": "1.0.0",
      "screens": {
        "screen_1": {
          "title": "Home",
          "root": {
            "id": "root_col",
            "type": "column",
            "children": [
              {
                "id": "t1",
                "type": "text",
                "properties": {
                  "text": "Hello DynBox",
                  "color": "#336699",
                  "fontSize": 18.0
                }
              },
              {
                "id": "b1",
                "type": "button",
                "properties": {
                  "label": "Click me",
                  "action": {
                    "type": "navigate",
                    "route": "/home"
                  }
                }
              }
            ]
          }
        }
      }
    }
    ''';

    test('successfully parses valid document', () {
      final parser = DynamicUiParser();
      final doc = parser.parseJsonString(validJson);
      expect(doc.schemaVersion, 1);
      expect(doc.configId, 'test_config');
      expect(doc.revision, 1);
      expect(doc.screens.length, 1);
      expect(doc.screens['screen_1']!.root.type, ComponentType.column);
      expect(doc.screens['screen_1']!.root.children.length, 2);
    });

    test('rejects malformed JSON', () {
      final parser = DynamicUiParser();
      expect(
        () => parser.parseJsonString('{ not valid json'),
        throwsA(isA<DynamicUiException>()),
      );
    });

    test('rejects unsupported schema version', () {
      final parser = DynamicUiParser();
      final invalid = validJson.replaceFirst(
        '"schemaVersion": 1',
        '"schemaVersion": 2',
      );
      expect(
        () => parser.parseJsonString(invalid),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('Unsupported or missing schemaVersion'),
          ),
        ),
      );
    });

    test('rejects unknown widget type', () {
      final parser = DynamicUiParser();
      final invalid = validJson.replaceFirst('"text"', '"unsupported_hack"');
      expect(
        () => parser.parseJsonString(invalid),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('Unknown or disallowed component type'),
          ),
        ),
      );
    });

    test('rejects disallowed non-https image URL', () {
      const imgDoc = '''
      {
        "schemaVersion": 1,
        "configId": "test_img",
        "revision": 1,
        "screens": {
          "s1": {
            "title": "Test",
            "root": {
              "id": "img1",
              "type": "image",
              "properties": {
                "url": "http://insecure.example.com/test.png"
              }
            }
          }
        }
      }
      ''';
      final parser = DynamicUiParser();
      expect(
        () => parser.parseJsonString(imgDoc),
        throwsA(
          predicate((e) => e.toString().contains('must start with https://')),
        ),
      );
    });

    test('rejects unapproved icon identifiers', () {
      const iconDoc = '''
      {
        "schemaVersion": 1,
        "configId": "test_icon",
        "revision": 1,
        "screens": {
          "s1": {
            "title": "Test",
            "root": {
              "id": "ico1",
              "type": "icon",
              "properties": {
                "iconName": "malicious_unregistered_icon"
              }
            }
          }
        }
      }
      ''';
      final parser = DynamicUiParser();
      expect(
        () => parser.parseJsonString(iconDoc),
        throwsA(
          predicate((e) => e.toString().contains('Unknown or unapproved icon')),
        ),
      );
    });

    test('rejects excessive document size', () {
      final parser = DynamicUiParser();
      final huge = ' ' * (512 * 1024 + 10);
      expect(
        () => parser.parseJsonString(huge),
        throwsA(
          predicate((e) => e.toString().contains('exceeds maximum limit')),
        ),
      );
    });
  });

  group('DynamicUiController Lifecycle & Rollback', () {
    const defaultJson = '''
    {
      "schemaVersion": 1,
      "configId": "app_flow",
      "revision": 1,
      "screens": {
        "home": {
          "title": "Default Home",
          "root": {
            "id": "t1",
            "type": "text",
            "properties": { "text": "Default Bundled Text" }
          }
        }
      }
    }
    ''';

    const candidateJson = '''
    {
      "schemaVersion": 1,
      "configId": "app_flow",
      "revision": 2,
      "screens": {
        "home": {
          "title": "Updated Home",
          "root": {
            "id": "t1",
            "type": "text",
            "properties": { "text": "Updated Remote Text" }
          }
        }
      }
    }
    ''';

    test('initializes with bundled default offline', () async {
      final controller = DynamicUiController(appVersion: '1.0.0');
      final doc = await controller.initialize(bundledDefaultJson: defaultJson);
      expect(doc.revision, 1);
      expect(controller.status, DynamicUiStatus.bundledDefault);
      expect(controller.activeRevision, 1);
    });

    test('activates valid candidate and stores last known-good', () async {
      final memorySource = MemoryConfigSource(jsonPayload: candidateJson);
      final memoryStorage = MemoryDynamicUiStorage();
      final controller = DynamicUiController(
        remoteSource: memorySource,
        storage: memoryStorage,
        appVersion: '1.0.0',
      );

      await controller.initialize(bundledDefaultJson: defaultJson);
      final success = await controller.checkForUpdates();

      expect(success, isTrue);
      expect(controller.activeRevision, 2);
      expect(controller.status, DynamicUiStatus.activeRemote);
      expect(await memoryStorage.readLastKnownGood(), candidateJson);
    });

    test(
      'rejects candidate with incompatible app version and retains previous',
      () async {
        const highReqCandidate = '''
      {
        "schemaVersion": 1,
        "configId": "app_flow",
        "revision": 3,
        "minAppVersion": "2.0.0",
        "screens": {
          "home": {
            "title": "Incompatible",
            "root": { "id": "t", "type": "text", "properties": { "text": "New" } }
          }
        }
      }
      ''';
        final memorySource = MemoryConfigSource(jsonPayload: highReqCandidate);
        final controller = DynamicUiController(
          remoteSource: memorySource,
          appVersion: '1.2.0',
        );

        await controller.initialize(bundledDefaultJson: defaultJson);
        final success = await controller.checkForUpdates();

        expect(success, isFalse);
        expect(controller.activeRevision, 1);
        expect(controller.lastError, contains('Incompatible app version'));
      },
    );

    test('source failure does not break active state', () async {
      final failingSource = MemoryConfigSource(
        jsonPayload: candidateJson,
        shouldFail: true,
        failureMessage: 'Network timeout 504',
      );
      final controller = DynamicUiController(remoteSource: failingSource);

      await controller.initialize(bundledDefaultJson: defaultJson);
      final success = await controller.checkForUpdates();

      expect(success, isFalse);
      expect(controller.activeRevision, 1);
      expect(controller.lastError, contains('Network timeout 504'));
    });

    test(
      'explicit rollback returns to last known-good configuration',
      () async {
        final memorySource = MemoryConfigSource(jsonPayload: candidateJson);
        final controller = DynamicUiController(remoteSource: memorySource);

        await controller.initialize(bundledDefaultJson: defaultJson);
        await controller.checkForUpdates();
        expect(controller.activeRevision, 2);

        final rolledBack = controller.rollbackToLastKnownGood();
        expect(rolledBack, isTrue);
        expect(controller.activeRevision, 1);
        expect(controller.status, DynamicUiStatus.rolledBack);
      },
    );
  });

  group('RenderContext and WidgetRegistry', () {
    test('enforces registered routes for navigation actions', () {
      final context = RenderContext(registeredRoutes: {'/home', '/details'});

      const safeAction = DynamicAction(
        type: ActionType.navigate,
        route: '/home',
      );
      expect(() => context.dispatchAction(safeAction), returnsNormally);

      const maliciousAction = DynamicAction(
        type: ActionType.navigate,
        route: '/secret/admin',
      );
      expect(
        () => context.dispatchAction(maliciousAction),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'Disallowed or missing navigation target',
            ),
          ),
        ),
      );
    });

    test('enforces https for openUrl actions', () {
      final context = RenderContext();

      const safeUrl = DynamicAction(
        type: ActionType.openUrl,
        url: 'https://example.com',
      );
      expect(() => context.dispatchAction(safeUrl), returnsNormally);

      const unsafeUrl = DynamicAction(
        type: ActionType.openUrl,
        url: 'http://insecure.example.com',
      );
      expect(
        () => context.dispatchAction(unsafeUrl),
        throwsA(predicate((e) => e.toString().contains('must be HTTPS'))),
      );
    });

    test('registry contains all required built-in widgets', () {
      for (final type in ComponentType.values) {
        expect(WidgetRegistry.isRegistered(type), isTrue);
        final descriptor = WidgetRegistry.getDescriptor(type);
        expect(descriptor.type, type);
      }
    });
  });
}
