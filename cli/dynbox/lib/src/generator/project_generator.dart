import 'dart:io';

import '../config/dynbox_config.dart';
import '../sdk/flutter_sdk_runner.dart';
import '../sdk/safe_process_executor.dart';
import '../sdk/sdk_resolver.dart';
import 'preset_applier.dart';

/// Supported platform options for flutter create.
const Set<String> kSupportedPlatforms = {
  'android',
  'ios',
  'web',
  'linux',
  'macos',
  'windows',
};

/// Exception thrown when project creation fails at any stage.
class ProjectCreationException implements Exception {
  final String stage;
  final String message;
  final String? projectPath;
  final int? exitCode;
  final String? details;

  const ProjectCreationException({
    required this.stage,
    required this.message,
    this.projectPath,
    this.exitCode,
    this.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer(
      'ProjectCreationException during [$stage]: $message\n',
    );
    if (projectPath != null) buffer.writeln('  Project path: $projectPath');
    if (exitCode != null) buffer.writeln('  Exit code: $exitCode');
    if (details != null && details!.isNotEmpty) {
      buffer.writeln('  Details:\n${details!.trim()}');
    }
    return buffer.toString().trim();
  }
}

/// Parameters for creating a new Flutter project.
class CreateProjectOptions {
  final String projectName;
  final String? parentDirectory;
  final String? organization;
  final List<String> platforms;
  final ArchitecturePreset preset;
  final String? explicitSdkPath;
  final ProjectKind kind;

  const CreateProjectOptions({
    required this.projectName,
    this.parentDirectory,
    this.organization = 'com.example',
    this.platforms = const ['android', 'ios'],
    this.preset = ArchitecturePreset.minimal,
    this.explicitSdkPath,
    this.kind = ProjectKind.flutterApp,
  });
}

/// Orchestrates Flutter application creation using the resolved SDK and architecture presets.
class ProjectGenerator {
  final SdkResolver sdkResolver;
  final PresetApplier presetApplier;
  final SafeProcessExecutor executor;

  ProjectGenerator({
    SdkResolver? sdkResolver,
    PresetApplier? presetApplier,
    SafeProcessExecutor? executor,
  }) : sdkResolver = sdkResolver ?? SdkResolver(),
       presetApplier = presetApplier ?? const PresetApplier(),
       executor = executor ?? SafeProcessExecutor();

  static final RegExp _projectNameRegex = RegExp(r'^[a-z][a-z0-9_]*$');
  static final RegExp _orgRegex = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  );

  /// Validates input options before filesystem changes.
  void validateOptions(CreateProjectOptions options) {
    // 1. Kind check (Phase 3 only supports flutter_app)
    if (options.kind != ProjectKind.flutterApp) {
      throw ProjectCreationException(
        stage: 'validation',
        message:
            'Project kind "${options.kind.value}" is not supported yet. Only "flutter_app" is supported in Phase 3.',
      );
    }

    // 2. Project name check
    final name = options.projectName.trim();
    if (name.isEmpty) {
      throw const ProjectCreationException(
        stage: 'validation',
        message: 'Project name cannot be empty.',
      );
    }

    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      throw ProjectCreationException(
        stage: 'validation',
        message:
            'Project name cannot contain path separators or directory traversal sequences: "$name".',
      );
    }

    if (!_projectNameRegex.hasMatch(name)) {
      throw ProjectCreationException(
        stage: 'validation',
        message:
            'Invalid project name "$name". Project names must match ${_projectNameRegex.pattern} (lowercase alphanumeric and underscores, beginning with a letter).',
      );
    }

    // 3. Organization identifier check
    final org = (options.organization ?? 'com.example').trim();
    if (!_orgRegex.hasMatch(org)) {
      throw ProjectCreationException(
        stage: 'validation',
        message:
            'Invalid organization identifier "$org". Must be a valid reverse-domain format (e.g. "com.example").',
      );
    }

    // 4. Platforms check
    if (options.platforms.isEmpty) {
      throw const ProjectCreationException(
        stage: 'validation',
        message: 'At least one platform must be selected.',
      );
    }

    final seen = <String>{};
    for (final p in options.platforms) {
      final normalized = p.trim().toLowerCase();
      if (!kSupportedPlatforms.contains(normalized)) {
        throw ProjectCreationException(
          stage: 'validation',
          message:
              'Unsupported platform "$p". Supported platforms: ${kSupportedPlatforms.join(', ')}',
        );
      }
      if (!seen.add(normalized)) {
        throw ProjectCreationException(
          stage: 'validation',
          message: 'Duplicate platform specified: "$p".',
        );
      }
    }
  }

  /// Resolves and validates target destination directory.
  Directory resolveDestination({
    required String projectName,
    String? parentDirectory,
  }) {
    final parentPath =
        parentDirectory != null && parentDirectory.trim().isNotEmpty
        ? parentDirectory.trim()
        : Directory.current.path;

    final parentDir = Directory(parentPath);
    if (!parentDir.existsSync()) {
      throw ProjectCreationException(
        stage: 'validation',
        message: 'Parent directory does not exist: "${parentDir.path}".',
      );
    }

    final canonicalParent = Directory(parentDir.absolute.path)
        .resolveSymbolicLinksSync();
    // Normalize path to resolve .. sequences
    final normalizedTargetPath = Uri.file('$canonicalParent/$projectName')
        .toFilePath();
    final targetDir = Directory(normalizedTargetPath);

    // Ensure path didn't escape parent directory
    if (!targetDir.absolute.path.startsWith('$canonicalParent/')) {
      throw ProjectCreationException(
        stage: 'validation',
        message:
            'Target directory escapes the parent directory: "${targetDir.path}".',
      );
    }

    // Never overwrite an existing directory
    if (targetDir.existsSync()) {
      throw ProjectCreationException(
        stage: 'validation',
        message:
            'Destination directory already exists: "${targetDir.path}". Overwrite is forbidden.',
        projectPath: targetDir.path,
      );
    }

    return targetDir;
  }

  /// Generates the Flutter project and applies the chosen preset.
  Future<Directory> generate(CreateProjectOptions options) async {
    // 1. Stage: Validation
    validateOptions(options);

    final targetDir = resolveDestination(
      projectName: options.projectName,
      parentDirectory: options.parentDirectory,
    );

    // 2. Stage: SDK Resolution
    PinnedSdk pinnedSdk;
    try {
      pinnedSdk = sdkResolver.resolve(cliArgument: options.explicitSdkPath);
    } catch (e) {
      throw ProjectCreationException(
        stage: 'sdk_resolution',
        message: 'Failed to resolve explicit Flutter SDK: $e',
      );
    }

    // 3. Stage: Flutter Generation
    final parentDir = targetDir.parent;
    final flutterRunner = FlutterSdkRunner(
      pinnedSdk: pinnedSdk,
      executor: executor,
    );

    final flutterArgs = <String>[
      'create',
      '--project-name',
      options.projectName,
      '--org',
      options.organization ?? 'com.example',
      '--platforms',
      options.platforms.join(','),
      targetDir.absolute.path,
    ];

    ProcessExecutionResult result;
    try {
      result = await flutterRunner.run(
        flutterArgs,
        workingDirectory: parentDir.absolute.path,
      );
    } catch (e) {
      throw ProjectCreationException(
        stage: 'flutter_generation',
        message: 'Subprocess error executing flutter create: $e',
        projectPath: targetDir.path,
      );
    }

    if (!result.isSuccess) {
      throw ProjectCreationException(
        stage: 'flutter_generation',
        message:
            'flutter create exited with non-zero exit code ${result.exitCode}.\nPartial project preserved at: ${targetDir.path}',
        exitCode: result.exitCode,
        projectPath: targetDir.path,
        details: result.stderr.isNotEmpty ? result.stderr : result.stdout,
      );
    }

    // 4. Stage: Output Verification
    final pubspec = File('${targetDir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      throw ProjectCreationException(
        stage: 'verification',
        message:
            'Expected pubspec.yaml was not generated in: "${targetDir.path}".\nPartial project preserved.',
        projectPath: targetDir.path,
      );
    }

    // 5. Stage: Architecture Preset Application
    try {
      await presetApplier.applyPreset(
        projectDir: targetDir,
        preset: options.preset,
        projectName: options.projectName,
      );
    } catch (e) {
      throw ProjectCreationException(
        stage: 'preset_application',
        message:
            'Failed to apply architecture preset "${options.preset.name}": $e\nPartial project preserved.',
        projectPath: targetDir.path,
      );
    }

    // 6. Stage: OTA SDK & Demo Integration
    try {
      await _integrateOta(targetDir, options.projectName);
    } catch (e) {
      throw ProjectCreationException(
        stage: 'ota_integration',
        message:
            'Failed to configure DynBox OTA integration: $e\nPartial project preserved.',
        projectPath: targetDir.path,
      );
    }

    // 7. Stage: DynBox Workspace Config Initialization
    try {
      final dynboxDir = Directory('${targetDir.path}/.dynbox')
        ..createSync(recursive: true);
      final configFile = File('${dynboxDir.path}/config.yaml');

      final configYaml =
          '''
configVersion: 1

project:
  name: ${options.projectName}
  kind: ${options.kind.value}

sdk:
  flutter:
    source: local
    path: ${pinnedSdk.sdkDirectory}

backend:
  provider: none

ota:
  enabled: true
  channel: production
  autoActivate: true
''';

      configFile.writeAsStringSync('${configYaml.trim()}\n');

      // Verify the generated configuration by reading it back
      DynboxConfig.fromFile(configFile, workspaceRoot: targetDir.path);
    } catch (e) {
      throw ProjectCreationException(
        stage: 'config_initialization',
        message:
            'Failed to write or validate .dynbox/config.yaml: $e\nPartial project preserved.',
        projectPath: targetDir.path,
      );
    }

    return targetDir;
  }

  Future<void> _integrateOta(Directory targetDir, String projectName) async {
    final libDir = Directory('${targetDir.path}/lib');
    if (!libDir.existsSync()) {
      libDir.createSync(recursive: true);
    }

    // 1. Add dynbox_ota and dynbox_ui_runtime to pubspec.yaml
    final pubspecFile = File('${targetDir.path}/pubspec.yaml');
    if (pubspecFile.existsSync()) {
      var content = pubspecFile.readAsStringSync();
      if (!content.contains('dynbox_ota:')) {
        // Check if dependencies: block exists
        if (content.contains('dependencies:')) {
          content = content.replaceFirst('dependencies:', '''dependencies:
  dynbox_ota:
    path: /Users/juwel/Developer/dynbox/packages/dynbox_ota
  dynbox_ui_runtime:
    path: /Users/juwel/Developer/dynbox/packages/dynbox_ui_runtime''');
        } else {
          content = '''$content

dependencies:
  dynbox_ota:
    path: /Users/juwel/Developer/dynbox/packages/dynbox_ota
  dynbox_ui_runtime:
    path: /Users/juwel/Developer/dynbox/packages/dynbox_ui_runtime
''';
        }
        pubspecFile.writeAsStringSync(content);
      }
    }

    // 2. Generate lib/dynbox_ota_service.dart
    final serviceFile = File('${libDir.path}/dynbox_ota_service.dart');
    serviceFile.writeAsStringSync('''import 'dart:io';
import 'package:dynbox_ota/dynbox_ota.dart';
import 'package:dynbox_ui_runtime/dynbox_ui_runtime.dart';

/// Top-level app OTA service coordinator.
class AppOtaCoordinator {
  static DynboxOtaService? service;
  static final DynamicUiController uiController = DynamicUiController();

  static const String bundledUiJson = \'\'\'
{
  "schemaVersion": 1,
  "configId": "$projectName",
  "revision": 1,
  "screens": {
    "home": {
      "title": "$projectName Dynamic UI",
      "root": {
        "type": "column",
        "children": [
          {
            "type": "text",
            "properties": {
              "text": "Welcome to $projectName",
              "fontSize": 20.0,
              "fontWeight": "bold"
            }
          },
          {
            "type": "sized_box",
            "properties": {
              "height": 12.0
            }
          },
          {
            "type": "text",
            "properties": {
              "text": "Powered by DynBox First-Party OTA Engine (No Shorebird)"
            }
          }
        ]
      }
    }
  }
}
\'\'\';

  /// Initializes the Dynamic UI and starts non-blocking background OTA check.
  static Future<void> initialize({
    OtaServerProvider? provider,
    String? storagePath,
    String? supabaseUrl,
    String? supabaseAnonKey,
  }) async {
    // 1. Initialize Dynamic UI with bundled configuration
    await uiController.initialize(bundledDefaultJson: bundledUiJson);

    // 2. Initialize OTA Service with offline mock or configured provider
    OtaServerProvider effectiveProvider;
    if (provider != null) {
      effectiveProvider = provider;
    } else if (supabaseUrl != null && supabaseAnonKey != null) {
      effectiveProvider = SupabaseOtaServerProvider(
        supabaseUrl: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
    } else {
      effectiveProvider = MockOtaServerProvider();
    }

    final effectiveStorage = storagePath != null ? Directory(storagePath) : null;

    service = await DynboxOtaService.create(
      config: const OtaClientConfig(
        appId: '$projectName',
        appVersion: '1.0.0',
        channel: 'production',
        autoActivate: true,
      ),
      uiController: uiController,
      provider: effectiveProvider,
      storageDir: effectiveStorage,
    );

    // 3. Asynchronous non-blocking background check
    service?.startBackgroundCheck();
  }
}
''');

    // 3. Generate lib/dynbox_ota_demo_screen.dart
    final demoScreenFile = File('${libDir.path}/dynbox_ota_demo_screen.dart');
    demoScreenFile.writeAsStringSync('''import 'package:flutter/material.dart';
import 'package:dynbox_ota/dynbox_ota.dart';
import 'package:dynbox_ui_runtime/dynbox_ui_runtime.dart';
import 'dynbox_ota_service.dart';

/// Interactive Demo Screen for DynBox First-Party OTA Updates.
class DynboxOtaDemoScreen extends StatefulWidget {
  const DynboxOtaDemoScreen({super.key});

  @override
  State<DynboxOtaDemoScreen> createState() => _DynboxOtaDemoScreenState();
}

class _DynboxOtaDemoScreenState extends State<DynboxOtaDemoScreen> {
  final _service = AppOtaCoordinator.service;
  final _controller = AppOtaCoordinator.uiController;

  @override
  Widget build(BuildContext context) {
    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('DynBox OTA Demo')),
        body: const Center(child: Text('OTA Service not initialized')),
      );
    }

    return StreamBuilder<OtaState>(
      stream: _service.client.stateStream,
      initialData: _service.client.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? _service.client.currentState;
        final activeDoc = _controller.activeDocument;

        return Scaffold(
          appBar: AppBar(
            title: const Text('DynBox OTA Status'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Check for updates',
                onPressed: () => _service.checkForUpdate(),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DynBox OTA Engine',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text('App Version: \${_service.client.config.appVersion}'),
                        Text('OTA Status: \${state.status.name}'),
                        Text('Active Config Revision: \${activeDoc?.revision ?? 0}'),
                        if (state.activeReleaseId != null)
                          Text('Active Release ID: \${state.activeReleaseId}'),
                        if (state.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Error: \${state.errorMessage}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Check for Updates'),
                      onPressed: () => _service.checkForUpdate(),
                    ),
                    if (state.status == OtaStatus.updateAvailable)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.verified),
                        label: const Text('Download & Apply'),
                        onPressed: () => _service.downloadAndVerify(),
                      ),
                    if (state.status == OtaStatus.failed)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.replay),
                        label: const Text('Retry'),
                        onPressed: () => _service.client.retry(),
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Rollback to LKG'),
                      onPressed: () => _service.rollback(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const Text(
                  'Dynamic UI Container:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: StreamBuilder<DynamicUiDocument>(
                    stream: _controller.updates,
                    initialData: _controller.activeDocument,
                    builder: (context, docSnapshot) {
                      final doc = docSnapshot.data;
                      if (doc == null || doc.screens.isEmpty) {
                        return const Text('No Dynamic UI Screen Loaded');
                      }
                      final screen = doc.screens['home'] ?? doc.screens.values.first;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Screen Title: \${screen.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Dynamic Content: \${screen.root.properties.text ?? "Composite Layout"}'),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
''');

    // 4. Update lib/main.dart with non-blocking initialization
    final mainFile = File('${libDir.path}/main.dart');
    mainFile.writeAsStringSync('''import 'package:flutter/material.dart';
import 'dynbox_ota_service.dart';
import 'dynbox_ota_demo_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Non-blocking initialization of DynBox OTA and Dynamic UI
  await AppOtaCoordinator.initialize();

  runApp(const DynboxApp());
}

class DynboxApp extends StatelessWidget {
  const DynboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DynboxOtaDemoScreen(),
    );
  }
}
''');
  }
}
