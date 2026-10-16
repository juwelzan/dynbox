import 'dart:io';

import 'package:args/command_runner.dart';

import '../backend/firebase_adapter.dart';
import '../backend/supabase_adapter.dart';

/// Top-level command `dynbox backend`.
class BackendCommand extends Command<int> {
  @override
  final String name = 'backend';

  @override
  final String description =
      'Inspect and configure backend provider integrations (Firebase, Supabase).';

  BackendCommand({
    FirebaseAdapter? firebaseAdapter,
    SupabaseAdapter? supabaseAdapter,
  }) {
    addSubcommand(
      BackendStatusCommand(
        firebaseAdapter: firebaseAdapter,
        supabaseAdapter: supabaseAdapter,
      ),
    );
    addSubcommand(
      BackendConfigureCommand(
        firebaseAdapter: firebaseAdapter,
        supabaseAdapter: supabaseAdapter,
      ),
    );
  }

  @override
  int run() {
    printUsage();
    return 0;
  }
}

/// Subcommand `dynbox backend status`.
class BackendStatusCommand extends Command<int> {
  @override
  final String name = 'status';

  @override
  final String description =
      'Inspect local tools, authentication state, and configuration for backend providers.';

  final FirebaseAdapter firebaseAdapter;
  final SupabaseAdapter supabaseAdapter;

  BackendStatusCommand({
    FirebaseAdapter? firebaseAdapter,
    SupabaseAdapter? supabaseAdapter,
  }) : firebaseAdapter = firebaseAdapter ?? FirebaseAdapter(),
       supabaseAdapter = supabaseAdapter ?? SupabaseAdapter();

  @override
  Future<int> run() async {
    final projectDir = Directory.current;

    stdout.writeln('DynBox Backend Provider Status:');
    stdout.writeln('========================================');

    // 1. Firebase inspection
    final fbStatus = await firebaseAdapter.inspectStatus(projectDir);
    stdout.writeln('Provider: Firebase');
    stdout.writeln(
      '  Configured in workspace: ${fbStatus.isConfigured ? 'Yes (${fbStatus.projectId})' : 'No'}',
    );
    for (final tool in fbStatus.tools) {
      final mark = tool.isInstalled ? '[✓]' : '[✗]';
      final ver = tool.version != null ? ' (${tool.version})' : '';
      stdout.writeln('  $mark Tool: ${tool.name}$ver');
      if (!tool.isInstalled) {
        stdout.writeln('      • Install: ${tool.installGuide}');
      }
    }
    stdout.writeln('  Auth Status: ${fbStatus.auth.details}');
    if (!fbStatus.auth.isAuthenticated) {
      stdout.writeln('      • Action: ${fbStatus.auth.loginGuide}');
    }
    for (final warn in fbStatus.warnings) {
      stdout.writeln('  [!] Warning: $warn');
    }

    stdout.writeln('----------------------------------------');

    // 2. Supabase inspection
    final sbStatus = await supabaseAdapter.inspectStatus(projectDir);
    stdout.writeln('Provider: Supabase');
    stdout.writeln(
      '  Configured in workspace: ${sbStatus.isConfigured ? 'Yes (${sbStatus.projectId})' : 'No'}',
    );
    for (final tool in sbStatus.tools) {
      final mark = tool.isInstalled ? '[✓]' : '[!]';
      final ver = tool.version != null ? ' (${tool.version})' : '';
      stdout.writeln('  $mark Tool: ${tool.name}$ver');
      if (!tool.isInstalled) {
        stdout.writeln('      • Note: ${tool.installGuide}');
      }
    }
    for (final warn in sbStatus.warnings) {
      stdout.writeln('  [!] Warning: $warn');
    }

    stdout.writeln('========================================');
    return 0;
  }
}

/// Subcommand `dynbox backend configure <provider>`.
class BackendConfigureCommand extends Command<int> {
  @override
  final String name = 'configure';

  @override
  final String description =
      'Connect this Flutter workspace to an existing Firebase or Supabase project.';

  final FirebaseAdapter firebaseAdapter;
  final SupabaseAdapter supabaseAdapter;

  BackendConfigureCommand({
    FirebaseAdapter? firebaseAdapter,
    SupabaseAdapter? supabaseAdapter,
  }) : firebaseAdapter = firebaseAdapter ?? FirebaseAdapter(),
       supabaseAdapter = supabaseAdapter ?? SupabaseAdapter() {
    addSubcommand(ConfigureFirebaseSubcommand(adapter: this.firebaseAdapter));
    addSubcommand(ConfigureSupabaseSubcommand(adapter: this.supabaseAdapter));
  }

  @override
  int run() {
    printUsage();
    return 0;
  }
}

/// `dynbox backend configure firebase`
class ConfigureFirebaseSubcommand extends Command<int> {
  @override
  final String name = 'firebase';

  @override
  final String description =
      'Connect to an existing Firebase project using FlutterFire CLI.';

  final FirebaseAdapter adapter;

  ConfigureFirebaseSubcommand({required this.adapter}) {
    argParser
      ..addOption(
        'project-id',
        abbr: 'p',
        help: 'Existing Firebase Project ID to connect.',
      )
      ..addOption(
        'platforms',
        defaultsTo: 'android,ios',
        help: 'Comma-separated target platforms (e.g. android,ios,web).',
      );
  }

  @override
  Future<int> run() async {
    final projectId = argResults?['project-id'] as String?;
    if (projectId == null || projectId.trim().isEmpty) {
      throw UsageException('Missing required flag: --project-id <id>', usage);
    }

    final platformsRaw = argResults?['platforms'] as String? ?? 'android,ios';
    final platforms = platformsRaw.split(',').map((p) => p.trim()).toList();

    stdout.writeln('Configuring Firebase project "$projectId"...');

    final result = await adapter.configure(Directory.current, {
      'projectId': projectId,
      'platforms': platforms,
    });

    if (result.isSuccess) {
      stdout.writeln('✓ ${result.message}');
      for (final f in result.modifiedFiles) {
        stdout.writeln('  • Updated: $f');
      }
      return 0;
    } else {
      stderr.writeln('✗ Error: ${result.message}');
      if (result.actionableError != null) {
        stderr.writeln('  Action: ${result.actionableError}');
      }
      if (result.details != null && result.details!.isNotEmpty) {
        stderr.writeln('  Details:\n${result.details}');
      }
      return 1;
    }
  }
}

/// `dynbox backend configure supabase`
class ConfigureSupabaseSubcommand extends Command<int> {
  @override
  final String name = 'supabase';

  @override
  final String description =
      'Connect to an existing Supabase project using client configuration.';

  final SupabaseAdapter adapter;

  ConfigureSupabaseSubcommand({required this.adapter}) {
    argParser
      ..addOption(
        'project-url',
        abbr: 'u',
        help: 'Existing Supabase project HTTPS URL (e.g. https://xyz.supabase.co).',
      )
      ..addOption(
        'anon-key',
        abbr: 'k',
        help: 'Public anonymous client key (anon key). Never provide service_role keys.',
      )
      ..addFlag(
        'add-dependency',
        defaultsTo: false,
        help: 'Automatically add supabase_flutter to pubspec.yaml.',
      );
  }

  @override
  Future<int> run() async {
    final projectUrl = argResults?['project-url'] as String?;
    final anonKey = argResults?['anon-key'] as String?;
    final addDep = argResults?['add-dependency'] as bool? ?? false;

    if (projectUrl == null || projectUrl.trim().isEmpty) {
      throw UsageException('Missing required flag: --project-url <url>', usage);
    }

    if (anonKey == null || anonKey.trim().isEmpty) {
      throw UsageException('Missing required flag: --anon-key <key>', usage);
    }

    stdout.writeln('Configuring Supabase project "$projectUrl"...');

    final result = await adapter.configure(Directory.current, {
      'projectUrl': projectUrl,
      'anonKey': anonKey,
      'addDependency': addDep,
    });

    if (result.isSuccess) {
      stdout.writeln('✓ ${result.message}');
      for (final f in result.modifiedFiles) {
        stdout.writeln('  • Updated: $f');
      }
      if (result.details != null) {
        stdout.writeln('  ${result.details}');
      }
      return 0;
    } else {
      stderr.writeln('✗ Error: ${result.message}');
      if (result.actionableError != null) {
        stderr.writeln('  Action: ${result.actionableError}');
      }
      if (result.details != null && result.details!.isNotEmpty) {
        stderr.writeln('  Details:\n${result.details}');
      }
      return 1;
    }
  }
}
