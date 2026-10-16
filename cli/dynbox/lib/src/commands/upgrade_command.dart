import 'dart:io';

import 'package:args/command_runner.dart';

import '../installer/installer_models.dart';
import '../installer/updater.dart';
import '../version.dart';

/// Default HTTP implementation of ReleaseClient using dart:io HttpClient.
class HttpReleaseClient implements ReleaseClient {
  final String? releaseBaseUrl;

  HttpReleaseClient({this.releaseBaseUrl});

  @override
  Future<ReleaseManifest> fetchManifest({String? version}) async {
    final baseUrl =
        releaseBaseUrl ??
        Platform.environment['DYNBOX_RELEASE_URL'] ??
        (version != null
            ? 'https://github.com/juwelzan/dynbox/releases/download/v$version'
            : 'https://github.com/juwelzan/dynbox/releases/latest/download');

    final manifestUrl = Uri.parse('$baseUrl/release_manifest.json');
    final client = HttpClient();
    try {
      final request = await client.getUrl(manifestUrl);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to fetch release manifest (HTTP ${response.statusCode}) from $manifestUrl',
          uri: manifestUrl,
        );
      }
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join();
      return ReleaseManifest.fromString(body);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> downloadArtifact({
    required String url,
    required File destination,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download release artifact (HTTP ${response.statusCode}) from $url',
          uri: Uri.parse(url),
        );
      }
      final sink = destination.openWrite();
      await response.pipe(sink);
    } finally {
      client.close();
    }
  }
}

/// CLI command for checking and upgrading the installed DynBox CLI binary.
class UpgradeCommand extends Command<int> {
  @override
  final String name = 'upgrade';

  @override
  final String description =
      'Upgrade DynBox CLI to the latest or a pinned version.';

  final DynboxUpdater? updaterOverride;

  UpgradeCommand({this.updaterOverride}) {
    argParser
      ..addOption(
        'version',
        abbr: 'v',
        help: 'Upgrade (or downgrade) to an explicit pinned version (e.g. 0.1.0).',
      )
      ..addFlag(
        'check',
        negatable: false,
        help: 'Check for available updates without applying them.',
      );
  }

  @override
  Future<int> run() async {
    final updater =
        updaterOverride ?? DynboxUpdater(client: HttpReleaseClient());
    final targetVersion = argResults?['version'] as String?;
    final checkOnly = argResults?['check'] as bool? ?? false;

    stdout.writeln('DynBox Upgrade Manager');
    stdout.writeln('  Current Version: ${DynboxVersion.version}');
    if (targetVersion != null) {
      stdout.writeln('  Target Version:  $targetVersion');
    }
    stdout.writeln('');

    if (checkOnly) {
      stdout.writeln('Checking for updates...');
      try {
        final check = await updater.checkForUpgrade(
          pinnedVersion: targetVersion,
        );
        if (check.isUpgradeAvailable) {
          stdout.writeln(
            'An update is available: ${check.latestVersion} (current: ${check.currentVersion})',
          );
          stdout.writeln('Artifact: ${check.artifact?.fileName}');
          stdout.writeln('Run "dynbox upgrade" to install.');
        } else {
          stdout.writeln('DynBox is up to date (${check.currentVersion}).');
        }
        return 0;
      } catch (e) {
        stderr.writeln('Failed to check for updates: $e');
        return 1;
      }
    }

    stdout.writeln('Upgrading DynBox...');
    try {
      final message = await updater.performUpgrade(
        pinnedVersion: targetVersion,
      );
      stdout.writeln('✅ $message');
      return 0;
    } catch (e) {
      stderr.writeln('❌ Upgrade failed: $e');
      return 1;
    }
  }
}
