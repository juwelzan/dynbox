import 'dart:io';

import '../config/dynbox_config.dart';
import '../sdk/safe_process_executor.dart';
import 'backend_adapter.dart';

/// Adapter for integrating existing Supabase projects using official client initialization.
class SupabaseAdapter implements BackendAdapter {
  final SafeProcessExecutor executor;

  SupabaseAdapter({SafeProcessExecutor? executor})
    : executor = executor ?? SafeProcessExecutor();

  @override
  BackendProviderType get provider => BackendProviderType.supabase;

  @override
  Future<ProviderStatusReport> inspectStatus(Directory projectDir) async {
    final tools = <CliToolStatus>[];
    final warnings = <String>[];

    // 1. Detect Supabase CLI
    String? supabaseExe;
    String? supabaseVer;
    try {
      final res = await executor.execute('supabase', ['--version']);
      if (res.isSuccess) {
        supabaseVer = res.stdout.trim();
        supabaseExe = 'supabase';
      }
    } catch (_) {}

    tools.add(
      CliToolStatus(
        name: 'Supabase CLI (supabase)',
        isInstalled: supabaseVer != null,
        version: supabaseVer,
        executablePath: supabaseExe,
        installGuide: 'Install via Homebrew: brew install supabase/tap/supabase (or official binary)',
      ),
    );

    // 2. Detect Authentication status
    final authStatus = AuthStatus(
      isAuthenticated: supabaseVer != null,
      details: supabaseVer != null
          ? 'CLI is installed locally'
          : 'Supabase CLI not detected',
      loginGuide: 'Run: supabase login',
    );

    // 3. Project Configuration Status
    bool isConfigured = false;
    String? configuredUrl;
    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (configFile.existsSync()) {
      try {
        final config = DynboxConfig.fromFile(
          configFile,
          workspaceRoot: projectDir.path,
        );
        if (config.backend.provider == BackendProviderKind.supabase) {
          configuredUrl =
              config.backend.providerConfig['supabase']?['projectUrl']
                  as String?;
          isConfigured = configuredUrl != null && configuredUrl.isNotEmpty;
        }
      } catch (_) {}
    }

    final supabaseConfigFile = File(
      '${projectDir.path}/lib/supabase_config.dart',
    );
    if (isConfigured && !supabaseConfigFile.existsSync()) {
      warnings.add(
        '.dynbox/config.yaml specifies supabase, but lib/supabase_config.dart is missing.',
      );
    }

    return ProviderStatusReport(
      provider: BackendProviderType.supabase,
      isConfigured: isConfigured,
      projectId: configuredUrl,
      tools: tools,
      auth: authStatus,
      supportedCapabilities: [
        'configure_existing_project',
        'generate_supabase_config',
        'add_dependency',
      ],
      warnings: warnings,
    );
  }

  @override
  Future<ProviderConfigureResult> configure(
    Directory projectDir,
    Map<String, dynamic> options,
  ) async {
    final projectUrl = options['projectUrl'] as String?;
    final anonKey = options['anonKey'] as String?;

    if (projectUrl == null || projectUrl.trim().isEmpty) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.supabase,
        message: 'Missing required option "projectUrl".',
        actionableError: 'Supply your Supabase project URL via --project-url <https://xyz.supabase.co>.',
      );
    }

    final cleanUrl = projectUrl.trim();
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.supabase,
        message: 'Invalid project URL "$cleanUrl". Must be a valid HTTPS URI.',
        actionableError: 'Provide a valid HTTPS URL such as https://<project-ref>.supabase.co',
      );
    }

    final keyError = validateApiKey(anonKey);
    if (keyError != null) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.supabase,
        message: keyError,
        actionableError: 'Supply your public anonymous or publishable key (e.g. sb_publishable_... or legacy JWT anon key). Never supply service_role keys.',
      );
    }
    final cleanAnonKey = anonKey!.trim();

    // 1. Verify project directory & DynboxConfig
    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.supabase,
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
        provider: BackendProviderType.supabase,
        message: 'Failed to parse .dynbox/config.yaml: $e',
      );
    }

    final modified = <String>[];

    // 2. Generate lib/supabase_config.dart
    final clientConfigFile = File(
      '${projectDir.path}/lib/supabase_config.dart',
    );
    try {
      final code =
          '''
// Generated by DynBox — Supabase Client Configuration
// NOTE: Public client identifiers and anon keys are subject to Row Level Security (RLS).
// Never place service-role keys or database passwords in client code.

class SupabaseConfig {
  static const String projectUrl = '$cleanUrl';
  static const String anonKey = '$cleanAnonKey';
}
''';
      clientConfigFile.writeAsStringSync('${code.trim()}\n');
      modified.add(clientConfigFile.path);
    } catch (e) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.supabase,
        message: 'Failed to write lib/supabase_config.dart: $e',
      );
    }

    // 3. Add supabase_flutter dependency if requested
    final addDep = options['addDependency'] == true;
    if (addDep) {
      final pubspec = File('${projectDir.path}/pubspec.yaml');
      if (pubspec.existsSync()) {
        try {
          final res = await executor.execute('flutter', [
            'pub',
            'add',
            'supabase_flutter',
          ], workingDirectory: projectDir.absolute.path);
          if (res.isSuccess) {
            modified.add(pubspec.path);
          }
        } catch (_) {}
      }
    }

    // 4. Update .dynbox/config.yaml safely
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
  provider: supabase
  supabase:
    projectUrl: $cleanUrl
''';

      configFile.writeAsStringSync('${updatedYaml.trim()}\n');
      modified.add(configFile.path);
    } catch (e) {
      return ProviderConfigureResult.failure(
        provider: BackendProviderType.supabase,
        message: 'Failed to update .dynbox/config.yaml: $e',
        modifiedFiles: modified,
      );
    }

    return ProviderConfigureResult.success(
      provider: BackendProviderType.supabase,
      message: 'Successfully configured Supabase for workspace ($cleanUrl).',
      modifiedFiles: modified,
      details: 'Created lib/supabase_config.dart. Remember to protect all data tables with Row Level Security (RLS) policies.',
    );
  }

  /// Validates a Supabase client API key.
  ///
  /// Supports both legacy JWT-format anon keys and newer `sb_publishable_...` tokens.
  /// Neither is rejected merely for being non-JWT. Secret and service_role keys are prohibited.
  String? validateApiKey(String? key) {
    if (key == null || key.trim().isEmpty) {
      return 'Missing required option "anonKey".';
    }
    final clean = key.trim();
    if (clean.toLowerCase().contains('service_role') ||
        clean.toLowerCase().contains('secret')) {
      return 'Privileged service-role or secret keys are forbidden in client configuration.';
    }
    return null;
  }
}
