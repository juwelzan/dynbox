import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../config/dynbox_config.dart';
import '../source/source_archiver.dart';

/// Top-level command `dynbox ota`.
class OtaCommand extends Command<int> {
  @override
  final String name = 'ota';

  @override
  final String description =
      'Inspect, configure, validate, and check DynBox OTA updates without Shorebird.';

  OtaCommand() {
    addSubcommand(OtaStatusCommand());
    addSubcommand(OtaInitCommand());
    addSubcommand(OtaCheckCommand());
    addSubcommand(OtaValidateCommand());
    addSubcommand(OtaSyncSourceCommand());
    addSubcommand(OtaPublishCommand());
  }

  @override
  int run() {
    printUsage();
    return 0;
  }
}

/// Subcommand `dynbox ota sync-source [project-path]`.
class OtaSyncSourceCommand extends Command<int> {
  @override
  final String name = 'sync-source';

  @override
  final String description =
      'Create an immutable, secret-free source release snapshot for verifiable build synchronization.';

  OtaSyncSourceCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to write source snapshot manifest JSON or archive.',
      )
      ..addFlag(
        'archive',
        defaultsTo: false,
        help: 'Whether to package tracked source into a compressed zip.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    final targetPath = rest.isNotEmpty ? rest.first : Directory.current.path;
    final projectDir = Directory(targetPath);

    if (!projectDir.existsSync()) {
      stderr.writeln('Error: Project directory does not exist at: $targetPath');
      return 1;
    }

    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      stderr.writeln(
        'Error: Missing .dynbox/config.yaml at: ${configFile.path}',
      );
      return 1;
    }

    final config = DynboxConfig.fromFile(
      configFile,
      workspaceRoot: projectDir.path,
    );

    stdout.writeln('Generating secret-free source release snapshot:');
    stdout.writeln('  Project: ${config.project.name}');
    stdout.writeln('  Source Root: ${projectDir.path}');

    // Exclude secrets and non-source directories
    final safeFiles = SourceArchiver.getSafeSourceFiles(projectDir: projectDir);
    stdout.writeln('  Filtered files scanned: ${safeFiles.length}');

    final manifest = SourceArchiver.generateSourceManifest(
      projectDir: projectDir,
      appId: config.project.name,
      appVersion: '1.0.0',
    );

    stdout.writeln('  Snapshot Digest: ${manifest['snapshotSha256']}');
    stdout.writeln('  Total Source Size: ${manifest['totalSizeBytes']} bytes');

    final outputPath =
        argResults?['output'] as String? ??
        '${projectDir.path}/build/source_snapshot.json';
    final outFile = File(outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    stdout.writeln('✓ Source snapshot written to: ${outFile.path}');
    stdout.writeln(
      '✓ No keystores, certificates, or local env files were included.',
    );
    return 0;
  }
}

/// Subcommand `dynbox ota status [project-path]`.
class OtaStatusCommand extends Command<int> {
  @override
  final String name = 'status';

  @override
  final String description =
      'Inspect OTA update configuration, release channel, and active verification parameters.';

  @override
  Future<int> run() async {
    final targetPath = (argResults?.rest.isNotEmpty ?? false)
        ? argResults!.rest.first
        : Directory.current.path;

    final projectDir = Directory(targetPath);
    if (!projectDir.existsSync()) {
      stderr.writeln('Error: Project directory does not exist at: $targetPath');
      return 1;
    }

    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      stderr.writeln(
        'Error: No DynBox configuration found at: ${configFile.path}',
      );
      stderr.writeln(
        'Run "dynbox ota init $targetPath" to initialize OTA settings.',
      );
      return 1;
    }

    DynboxConfig config;
    try {
      config = DynboxConfig.fromFile(
        configFile,
        workspaceRoot: projectDir.path,
      );
    } catch (e) {
      stderr.writeln('Error loading .dynbox/config.yaml: $e');
      return 1;
    }

    stdout.writeln('DynBox OTA Configuration Status:');
    stdout.writeln('  Project:         ${config.project.name}');
    stdout.writeln('  OTA Enabled:     ${config.ota.enabled}');
    stdout.writeln('  Channel:         ${config.ota.channel}');
    stdout.writeln('  Auto-Activate:   ${config.ota.autoActivate}');
    stdout.writeln(
      '  Server URL:      ${config.ota.serverUrl ?? "None (using offline/mock provider)"}',
    );
    stdout.writeln(
      '  VerificationKey: ${config.ota.publicKey != null ? "[Configured]" : "[Not set - integrity check only]"}',
    );
    stdout.writeln(
      '  Architecture:    Schema-driven Dynamic UI (No Shorebird)',
    );

    return 0;
  }
}

/// Subcommand `dynbox ota init [project-path]`.
class OtaInitCommand extends Command<int> {
  @override
  final String name = 'init';

  @override
  final String description =
      'Initialize or update OTA configuration in .dynbox/config.yaml.';

  OtaInitCommand() {
    argParser
      ..addOption(
        'channel',
        defaultsTo: 'production',
        help: 'Target OTA channel.',
      )
      ..addOption('server-url', help: 'Remote DynBox OTA server endpoint URL.')
      ..addOption(
        'public-key',
        help: 'Public key or HMAC secret for verifying update signatures.',
      );
  }

  @override
  Future<int> run() async {
    final targetPath = (argResults?.rest.isNotEmpty ?? false)
        ? argResults!.rest.first
        : Directory.current.path;

    final projectDir = Directory(targetPath);
    if (!projectDir.existsSync()) {
      stderr.writeln('Error: Project directory does not exist at: $targetPath');
      return 1;
    }

    final dynboxDir = Directory('${projectDir.path}/.dynbox');
    if (!dynboxDir.existsSync()) {
      dynboxDir.createSync(recursive: true);
    }

    final rawName = projectDir.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final validName = RegExp(r'^[a-z]').hasMatch(rawName)
        ? rawName
        : 'app_$rawName';

    final configFile = File('${dynboxDir.path}/config.yaml');
    var yamlContent = configFile.existsSync()
        ? configFile.readAsStringSync()
        : '''configVersion: 1
project:
  name: $validName
  kind: flutter_app
sdk:
  flutter:
    source: local
    path: /opt/homebrew/share/flutter
backend:
  provider: none
''';

    final channel = argResults?['channel'] as String? ?? 'production';
    final serverUrl = argResults?['server-url'] as String?;
    final publicKey = argResults?['public-key'] as String?;

    // Append or replace ota: section
    if (yamlContent.contains('\nota:') || yamlContent.startsWith('ota:')) {
      final otaRegex = RegExp(r'\nota:[\s\S]*?(?=\n\w+:|$)', multiLine: true);
      yamlContent = yamlContent.replaceFirst(otaRegex, '');
    }

    final otaBlock =
        '''

ota:
  enabled: true
  channel: $channel
  autoActivate: true
${serverUrl != null ? '  serverUrl: $serverUrl\n' : ''}${publicKey != null ? '  publicKey: $publicKey\n' : ''}''';

    yamlContent = '${yamlContent.trim()}$otaBlock\n';
    configFile.writeAsStringSync(yamlContent);

    stdout.writeln(
      '✓ Successfully initialized OTA settings in: ${configFile.path}',
    );
    return 0;
  }
}

/// Subcommand `dynbox ota check [project-path]`.
class OtaCheckCommand extends Command<int> {
  @override
  final String name = 'check';

  @override
  final String description =
      'Simulate or query an OTA update check against the configured server endpoint.';

  OtaCheckCommand() {
    argParser
      ..addOption(
        'app-version',
        defaultsTo: '1.0.0',
        help: 'Simulated current app version.',
      )
      ..addOption(
        'platform',
        defaultsTo: 'android',
        help: 'Simulated platform.',
      );
  }

  @override
  Future<int> run() async {
    final targetPath = (argResults?.rest.isNotEmpty ?? false)
        ? argResults!.rest.first
        : Directory.current.path;

    final projectDir = Directory(targetPath);
    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      stderr.writeln(
        'Error: Missing .dynbox/config.yaml at: ${configFile.path}',
      );
      return 1;
    }

    final config = DynboxConfig.fromFile(
      configFile,
      workspaceRoot: projectDir.path,
    );
    if (!config.ota.enabled) {
      stdout.writeln('OTA is currently disabled in .dynbox/config.yaml.');
      return 0;
    }

    stdout.writeln('Checking for updates...');
    stdout.writeln('  App ID:   ${config.project.name}');
    stdout.writeln('  Channel:  ${config.ota.channel}');
    stdout.writeln(
      '  Endpoint: ${config.ota.serverUrl ?? "Offline/Local Mock"}',
    );

    if (config.ota.serverUrl == null) {
      stdout.writeln(
        '✓ Up to date (No remote server configured; running in local mock mode).',
      );
      return 0;
    }

    try {
      final client = HttpClient();
      final uri = Uri.parse('${config.ota.serverUrl}/api/v1/ota/check').replace(
        queryParameters: {
          'appId': config.project.name,
          'channel': config.ota.channel,
          'appVersion': argResults?['app-version'] as String? ?? '1.0.0',
          'platform': argResults?['platform'] as String? ?? 'android',
        },
      );

      final req = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));

      if (res.statusCode == 204) {
        stdout.writeln('✓ Application is up to date (HTTP 204 No Content).');
      } else if (res.statusCode == 200) {
        final body = await res.transform(const Utf8Decoder()).join();
        stdout.writeln('! Update available:\n$body');
      } else {
        stderr.writeln('Server returned unexpected status: ${res.statusCode}');
        return 1;
      }
      client.close();
      return 0;
    } catch (e) {
      stderr.writeln('Failed to connect to OTA server: $e');
      return 1;
    }
  }
}

/// Subcommand `dynbox ota validate <manifest-or-payload-path>`.
class OtaValidateCommand extends Command<int> {
  @override
  final String name = 'validate';

  @override
  final String description =
      'Validate an OTA update manifest or Dynamic UI configuration bundle against security rules.';

  OtaValidateCommand() {
    argParser.addOption(
      'secret-key',
      help: 'Optional secret key to verify or calculate HMAC signature.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      stderr.writeln(
        'Error: Missing file path to validate. Usage: dynbox ota validate <file-path>',
      );
      return 64;
    }

    final file = File(rest.first);
    if (!file.existsSync()) {
      stderr.writeln('Error: File not found at: ${file.path}');
      return 1;
    }

    final content = file.readAsStringSync();
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      stderr.writeln('✗ Invalid JSON syntax: $e');
      return 1;
    }

    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('✗ JSON root must be a map/object.');
      return 1;
    }

    // Check if manifest or Dynamic UI bundle
    if (decoded.containsKey('payloadSha256') ||
        decoded.containsKey('releaseId')) {
      stdout.writeln('Validating DynBox OTA Release Manifest: ${file.path}');
      final errors = <String>[];

      if (decoded['schemaVersion'] != '1.0') {
        errors.add('Invalid schemaVersion (expected "1.0")');
      }
      if (decoded['appId'] == null ||
          (decoded['appId'] as String).trim().isEmpty) {
        errors.add('Missing or empty appId');
      }
      if (decoded['version'] == null || (decoded['version'] as int) < 1) {
        errors.add('version must be >= 1');
      }
      final sha = decoded['payloadSha256'] as String?;
      if (sha == null || sha.length != 64) {
        errors.add('payloadSha256 must be a 64-character hex string');
      }
      final size = decoded['payloadSizeBytes'] as int? ?? 0;
      if (size <= 0 || size > 524288) {
        errors.add('payloadSizeBytes must be between 1 and 524288 bytes');
      }

      if (errors.isNotEmpty) {
        stderr.writeln('✗ Manifest validation failed:');
        for (final err in errors) {
          stderr.writeln('  - $err');
        }
        return 1;
      }
      stdout.writeln(
        '✓ Manifest is syntactically valid and satisfies size & schema constraints.',
      );
      return 0;
    } else {
      stdout.writeln('Validating Dynamic UI Payload: ${file.path}');
      final bytes = utf8.encode(content);
      final sha = crypto.sha256.convert(bytes).toString();

      stdout.writeln('  Size:   ${bytes.length} bytes');
      stdout.writeln('  SHA256: $sha');

      final secret = argResults?['secret-key'] as String?;
      if (secret != null) {
        final hmac = crypto.Hmac(crypto.sha256, utf8.encode(secret));
        final sig = hmac.convert(bytes).toString();
        stdout.writeln('  HMAC-SHA256 Signature: $sig');
      }

      stdout.writeln('✓ Dynamic UI Payload JSON is valid.');
      return 0;
    }
  }
}

/// Subcommand `dynbox ota publish <project-path> --channel <channel>`.
class OtaPublishCommand extends Command<int> {
  @override
  final String name = 'publish';

  @override
  final String description =
      'Explicit authenticated publishing workflow for OTA releases (Requires server configuration).';

  OtaPublishCommand() {
    argParser
      ..addOption('channel', defaultsTo: 'production', help: 'Release channel.')
      ..addOption('payload', help: 'Path to dynamic UI JSON payload file.')
      ..addOption(
        'secret-key',
        help: 'HMAC secret key to sign release manifest.',
      )
      ..addOption(
        'supabase-service-key',
        help: 'Privileged service_role key for publishing to Supabase (never stored in client apps).',
      )
      ..addFlag(
        'confirm',
        defaultsTo: false,
        help: 'Explicit confirmation flag required before publishing to production.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    final targetPath = rest.isNotEmpty ? rest.first : Directory.current.path;
    final projectDir = Directory(targetPath);

    final configFile = File('${projectDir.path}/.dynbox/config.yaml');
    if (!configFile.existsSync()) {
      stderr.writeln(
        'Error: No DynBox configuration found at: ${configFile.path}',
      );
      return 1;
    }

    final config = DynboxConfig.fromFile(
      configFile,
      workspaceRoot: projectDir.path,
    );
    final channel = argResults?['channel'] as String? ?? 'production';
    final payloadPath = argResults?['payload'] as String?;
    final isConfirmed = argResults?['confirm'] == true;

    if (payloadPath == null) {
      stderr.writeln(
        'Error: --payload <path> is required to publish an update.',
      );
      return 64;
    }

    final payloadFile = File(payloadPath);
    if (!payloadFile.existsSync()) {
      stderr.writeln('Error: Payload file not found at: $payloadPath');
      return 1;
    }

    // Explicit confirmation guard for production updates
    if (channel == 'production' && !isConfirmed) {
      stderr.writeln(
        'Safety Warning: You are attempting to publish an OTA update to the "production" channel.',
      );
      stderr.writeln('This update will be activated by live client apps.');
      stderr.writeln(
        'To proceed, pass the explicit confirmation flag: --confirm',
      );
      return 1;
    }

    final payloadBytes = payloadFile.readAsBytesSync();
    if (payloadBytes.length > 524288) {
      stderr.writeln(
        'Error: Payload exceeds maximum allowable OTA size (512 KB). Current size: ${payloadBytes.length} bytes.',
      );
      return 1;
    }

    final sha = crypto.sha256.convert(payloadBytes).toString();
    final secret = argResults?['secret-key'] as String?;

    String? signature;
    if (secret != null) {
      final hmac = crypto.Hmac(crypto.sha256, utf8.encode(secret));
      signature = hmac.convert(payloadBytes).toString();
    }

    // Check if Supabase backend is configured
    final isSupabase = config.backend.provider == BackendProviderKind.supabase;
    final supabaseUrl =
        config.backend.providerConfig['supabase']?['projectUrl'] as String?;

    if (config.ota.serverUrl == null && !isSupabase) {
      stdout.writeln(
        'Notice: No remote OTA server or Supabase backend configured in .dynbox/config.yaml.',
      );
      stdout.writeln('Staging offline release manifest locally:');
      final manifestJson = {
        'schemaVersion': '1.0',
        'appId': config.project.name,
        'releaseId': 'rel_${DateTime.now().millisecondsSinceEpoch}',
        'version': 2,
        'channel': channel,
        'platform': 'all',
        'minAppVersion': '1.0.0',
        'runtimeSchemaVersion': '1.0',
        'payloadSha256': sha,
        'payloadSizeBytes': payloadBytes.length,
        'publishedAt': DateTime.now().toIso8601String(),
        // ignore: use_null_aware_elements
        if (signature != null) 'signature': signature,
      };
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifestJson));
      stdout.writeln('\n✓ Local offline manifest staged successfully.');
      return 0;
    }

    if (isSupabase) {
      final serviceKey =
          (argResults?['supabase-service-key'] as String?) ??
          Platform.environment['DYNBOX_SUPABASE_SERVICE_KEY'];

      if (serviceKey == null || serviceKey.trim().isEmpty) {
        stderr.writeln(
          'Error: Publishing to Supabase requires an authorized service-role key.',
        );
        stderr.writeln(
          'Provide it via --supabase-service-key or DYNBOX_SUPABASE_SERVICE_KEY env var.',
        );
        stderr.writeln(
          'Note: Client apps only use public anon keys. Service keys are strictly for publishing.',
        );
        return 1;
      }

      stdout.writeln('Publishing OTA release to Supabase:');
      stdout.writeln('  Project URL: $supabaseUrl');
      stdout.writeln('  App ID:      ${config.project.name}');
      stdout.writeln('  Channel:     $channel');
      stdout.writeln('  Digest:      $sha');
      stdout.writeln('  Size:        ${payloadBytes.length} bytes');

      final baseUri = Uri.parse(supabaseUrl!);
      final insertUri = Uri(
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null,
        path:
            '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}/rest/v1/ota_releases',
      );

      final client = HttpClient();
      try {
        final req = await client
            .postUrl(insertUri)
            .timeout(const Duration(seconds: 10));
        req.headers.set('apikey', serviceKey);
        req.headers.set('Authorization', 'Bearer $serviceKey');
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Prefer', 'return=representation');

        final releaseId = 'rel_${DateTime.now().millisecondsSinceEpoch}';
        final payloadString = utf8.decode(payloadBytes);

        final postBody = jsonEncode({
          'app_id': config.project.name,
          'release_id': releaseId,
          'version': 2,
          'channel': channel,
          'platform': 'all',
          'min_app_version': '1.0.0',
          'runtime_schema_version': '1.0',
          'payload_sha256': sha,
          'payload_size_bytes': payloadBytes.length,
          'payload_json': payloadString,
          // ignore: use_null_aware_elements
          if (signature != null) 'signature': signature,
          'is_active': true,
          'is_rolled_back': false,
        });

        req.write(postBody);
        final res = await req.close().timeout(const Duration(seconds: 10));

        if (res.statusCode == 201) {
          stdout.writeln(
            '✓ Successfully published release "$releaseId" to Supabase ota_releases table!',
          );
          return 0;
        } else {
          final errBody = await res.transform(const Utf8Decoder()).join();
          stderr.writeln(
            '✗ Supabase returned error (HTTP ${res.statusCode}): $errBody',
          );
          return 1;
        }
      } catch (e) {
        stderr.writeln('✗ Failed to publish to Supabase: $e');
        return 1;
      } finally {
        client.close();
      }
    }

    stderr.writeln(
      'Connecting to remote production server (${config.ota.serverUrl})...',
    );
    stderr.writeln(
      'Publishing requires server credentials and active authentication tokens.',
    );
    stderr.writeln('Server contract is documented in docs/ARCHITECTURE.md.');
    return 1;
  }
}
