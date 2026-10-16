import 'package:dynbox_ui_runtime/dynbox_ui_runtime.dart';

void main() async {
  const jsonDoc = '''
  {
    "schemaVersion": 1,
    "configId": "welcome_flow",
    "revision": 1,
    "screens": {
      "home": {
        "title": "Welcome Screen",
        "root": {
          "id": "col_1",
          "type": "column",
          "children": [
            {
              "id": "title_text",
              "type": "text",
              "properties": {
                "text": "Welcome to DynBox Dynamic UI!",
                "fontSize": 22.0
              }
            },
            {
              "id": "btn_explore",
              "type": "button",
              "properties": {
                "label": "Get Started",
                "action": {
                  "type": "navigate",
                  "route": "/dashboard"
                }
              }
            }
          ]
        }
      }
    }
  }
  ''';

  final parser = DynamicUiParser();
  final document = parser.parseJsonString(jsonDoc);
  print(
    'Successfully parsed dynamic UI config: ${document.configId} (rev: ${document.revision})',
  );
  print('Screens available: ${document.screens.keys.toList()}');

  final controller = DynamicUiController(
    remoteSource: MemoryConfigSource(jsonPayload: jsonDoc),
  );
  await controller.initialize(bundledDefaultJson: jsonDoc);
  print('Active configuration status: ${controller.status}');
}
