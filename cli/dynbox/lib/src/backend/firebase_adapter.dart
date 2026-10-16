import 'dart:io';

import '../config/dynbox_config.dart';
import '../sdk/safe_process_executor.dart';
import 'backend_adapter.dart';

/// Adapter for integrating existing Firebase projects using official Firebase & FlutterFire tooling.
class FirebaseAdapter implements BackendAdapter {
  final SafeProcessExecutor executor;

  FirebaseAdapter({SafeProcessExecutor? executor})
    : executor = executor ?? SafeProcessExecutor();

  @override
  BackendProviderType get provider => BackendProviderType.firebase;

  @override
  Future<ProviderStatusReport> inspectStatus(Directory projectDir) async {
    final tools = <CliToolStatus>[];
    final warnings = <String>[];

    // 1. Detect Firebase CLI
    String? firebaseExe;
    String? firebaseVer;
    try {
      final res = await executor.execute('firebase', ['--version']);
      if (res.isSuccess) {
        firebaseVer = res.stdout.trim();
        firebaseExe = 'firebase';
      }
    } catch (_) {}

    tools.add(
      CliToolStatus(
        name: 'Firebase CLI (firebase)',
        isInstalled: firebaseVer != null,
        version: firebaseVer,
        executablePath: firebaseExe,
        installGuide: 'Install via npm: npm install -g firebase-tools (or standalone binary)',
      ),
    );

    // 2. Detect FlutterFire CLI
    String? flutterfireExe;
    String? flutterfireVer;
    try {
      final res = await executor.execute('flutterfire', ['--version']);
      if (res.isSuccess) {
        flutterfireVer = res.stdout.trim();
        flutterfireExe = 'flutterfire';
      }
    } catch (_) {}

    tools.add(
      CliToolStatus(
        name: 'FlutterFire CLI (flutterfire)',
        isInstalled: flutterfireVer != null,
        version: flutterfireVer,
        executablePath: flutterfireExe,
        installGuide:
            'Activate via pub: dart pub global activate flutterfire_cli',
      ),
    );

    // 3. Detect Authentication
    bool isAuthenticated = false;
    String? accountEmail;
    if (firebaseVer != null) {
      try {
        final authRes = await executor.execute('firebase', ['login:list']);
        if (authRes.isSuccess) {
          final out = authRes.stdout;
          if (!out.contains('No authorized accounts') && out.isNotEmpty) {
            isAuthenticated = true;
            final match = RegExp(
              r'([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
            ).firstMatch(out);
            accountEmail = match?.group(1);
          }
        }
      } catch (_) {}
    }

    final authStatus = AuthStatus(
      isAuthenticated: isAuthenticated,
      accountEmail: accountEmail,
      details: isAuthenticated
          ? 'Authenticated as $accountEmail'
          : 'Not authenticated with Firebase CLI',
      loginGuide: 'Run: firebase login',
    );

    // 4. Project Configuration Status
    bool isConfigured = false;
    String? configuredProjectId;
    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (configFile.existsSync()) {
      try {
        final config = DynboxConfig.fromFile(
          configFile,
          workspaceRoot: projectDir.path,
        );
        if (config.backend.provider == BackendProviderKind.firebase) {
          configuredProjectId =
              config.backend.providerConfig['firebase']?['projectId']
                  as String?;
          isConfigured =
              configuredProjectId != null && configuredProjectId.isNotEmpty;
        }
      } catch (_) {}
    }

    final optionsFile = File('${projectDir.path}/lib/firebase_options.dart');
    if (isConfigured && !optionsFile.existsSync()) {
      warnings.add(
        '.dynbox/config.yaml specifies firebase, but lib/firebase_options.dart is missing.',
      );
    }

    return ProviderStatusReport(
      provider: BackendProviderType.firebase,
      isConfigured: isConfigured,
      projectId: configuredProjectId,
      tools: tools,
      auth: authStatus,
      supportedCapabilities: [
        'configure_existing_project',
        'generate_firebase_options',
        'platform_registration',
      ],
      warnings: warnings,
    );
  }

  @override
  Future<ProviderConfigureResult> configure(
    Directory projectDir,
    Map<String, dynamic> options,
  ) async {
    final projectId = options['projectId'] as String?;
    if (projectId == null || projectId.trim().isEmpty) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Missing required option "projectId".',
        actionableError:
            'Supply an existing Firebase project ID via --project-id <id>.',
      );
    }

    final cleanProjectId = projectId.trim();

    // 1. Verify project directory & DynboxConfig
    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Not a valid DynBox project directory. Missing .dynbox/config.yaml.',
        actionableError: 'Navigate to a DynBox-managed Flutter workspace.',
      );
    }

    DynboxConfig currentConfig;
    try {
      currentConfig = DynboxConfig.fromFile(
        configFile,
        workspaceRoot: projectDir.path,
      );
    } catch (e) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Failed to parse .dynbox/config.yaml: $e',
      );
    }

    // 2. Check tool prerequisites
    final status = await inspectStatus(projectDir);
    final flutterfireTool = status.tools.firstWhere(
      (t) => t.name.contains('FlutterFire'),
    );
    if (!flutterfireTool.isInstalled) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Required tool FlutterFire CLI is not installed.',
        actionableError: flutterfireTool.installGuide,
      );
    }

    final firebaseTool = status.tools.firstWhere(
      (t) => t.name.contains('Firebase CLI'),
    );
    if (!firebaseTool.isInstalled) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Required tool Firebase CLI is not installed.',
        actionableError: firebaseTool.installGuide,
      );
    }

    if (!status.auth.isAuthenticated) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Firebase CLI is not authenticated.',
        actionableError: status.auth.loginGuide,
      );
    }

    // 3. Execute flutterfire configure
    final platforms =
        (options['platforms'] as List<dynamic>?)
            ?.map((p) => p.toString())
            .toList() ??
        ['android', 'ios'];

    final args = <String>[
      'configure',
      '--project=$cleanProjectId',
      '--platforms=${platforms.join(',')}',
      '--yes',
    ];

    ProcessExecutionResult result;
    try {
      result = await executor.execute(
        'flutterfire',
        args,
        workingDirectory: projectDir.absolute.path,
      );
    } catch (e) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Failed to launch flutterfire command: $e',
      );
    }

    if (!result.isSuccess) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message:
            'flutterfire configure exited with non-zero exit code ${result.exitCode}.',
        details: result.stderr.isNotEmpty ? result.stderr : result.stdout,
        actionableError:
            'Verify that project "$cleanProjectId" exists and your Firebase account has permissions.',
      );
    }

    // 4. Verify output files
    final optionsFile = File('${projectDir.path}/lib/firebase_options.dart');
    final modified = <String>[];
    if (optionsFile.existsSync()) {
      modified.add(optionsFile.path);
    }

    // 5. Update .dynbox/config.yaml safely
    try {
      final updatedYaml =
          '''
configVersion: ${currentConfig.configVersion}

project:
  name: ${currentConfig.project.name}
  kind: ${currentConfig.project.kind.value}

sdk:
  flutter:
    source: ${currentConfig.flutterSdk.source}
    path: ${currentConfig.flutterSdk.path}

backend:
  provider: firebase
  firebase:
    projectId: $cleanProjectId
''';

      configFile.writeAsStringSync('${updatedYaml.trim()}\n');
      modified.add(configFile.path);
    } catch (e) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.firebase,
        message: 'Failed to update .dynbox/config.yaml: $e',
        modifiedFiles: modified,
      );
    }

    return ProviderConfigureResult.success(
      provider: BackendProviderType.firebase,
      message:
          'Successfully configured Firebase project "$cleanProjectId" for workspace.',
      modifiedFiles: modified,
    );
  }
}
