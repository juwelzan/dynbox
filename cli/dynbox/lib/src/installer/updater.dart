import 'dart:io';

import '../version.dart';
import 'installer_models.dart';

/// Abstract client for fetching release manifests and artifacts.
abstract class ReleaseClient {
  Future<ReleaseManifest> fetchManifest({String? version});
  Future<void> downloadArtifact({
    required String url,
    required File destination,
  });
}

/// Result of an upgrade or installation check.
class UpgradeCheckResult {
  final String currentVersion;
  final String latestVersion;
  final bool isUpgradeAvailable;
  final ReleaseArtifact? artifact;
  final String? downloadUrl;

  const UpgradeCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.isUpgradeAvailable,
    this.artifact,
    this.downloadUrl,
  });
}

/// Orchestrates checking for updates, atomic binary replacement, and rollbacks.
class DynboxUpdater {
  final ReleaseClient client;
  final File? targetExecutableOverride;

  DynboxUpdater({required this.client, this.targetExecutableOverride});

  /// Resolves the installed DynBox executable currently in use.
  File resolveInstalledExecutable() {
    if (targetExecutableOverride != null) {
      return targetExecutableOverride!;
    }
    return File(Platform.resolvedExecutable);
  }

  /// Checks if an upgrade is available against current version or target [pinnedVersion].
  Future<UpgradeCheckResult> checkForUpgrade({
    String? pinnedVersion,
    String? baseUrlOverride,
  }) async {
    final currentVersion = DynboxVersion.version;
    final manifest = await client.fetchManifest(version: pinnedVersion);
    final targetVersion = manifest.version;

    final isAvailable = pinnedVersion != null
        ? pinnedVersion != currentVersion
        : _isNewerVersion(targetVersion, currentVersion);

    final platform = DistributionPlatform.currentHost();
    if (platform == null) {
      throw UnsupportedError(
        'Host platform/architecture is not supported for standalone distribution.',
      );
    }

    final artifact = manifest.artifacts[platform.identifier];
    if (artifact == null) {
      throw StateError(
        'Release $targetVersion does not contain an artifact for platform "${platform.identifier}".',
      );
    }

    final baseUrl =
        baseUrlOverride ??
        Platform.environment['DYNBOX_RELEASE_URL'] ??
        'https://github.com/juwelzan/dynbox/releases/download/v$targetVersion';
    final downloadUrl = '$baseUrl/${artifact.fileName}';

    return UpgradeCheckResult(
      currentVersion: currentVersion,
      latestVersion: targetVersion,
      isUpgradeAvailable: isAvailable,
      artifact: artifact,
      downloadUrl: downloadUrl,
    );
  }

  /// Performs atomic upgrade to the target version with rollback on failure.
  Future<String> performUpgrade({
    String? pinnedVersion,
    String? baseUrlOverride,
    Directory? tempDirOverride,
  }) async {
    final check = await checkForUpgrade(
      pinnedVersion: pinnedVersion,
      baseUrlOverride: baseUrlOverride,
    );

    if (!check.isUpgradeAvailable && pinnedVersion == null) {
      return 'DynBox is already up to date (version ${check.currentVersion}).';
    }

    final targetExecutable = resolveInstalledExecutable();
    final tempDir =
        tempDirOverride ??
        Directory.systemTemp.createTempSync('dynbox_upgrade_');

    final downloadedArchive = File(
      '${tempDir.path}/${check.artifact!.fileName}',
    );

    try {
      // 1. Download artifact
      await client.downloadArtifact(
        url: check.downloadUrl!,
        destination: downloadedArchive,
      );

      // 2. Cryptographic checksum verification
      final isValid = await IntegrityVerifier.verifyFile(
        downloadedArchive,
        check.artifact!.sha256,
      );
      if (!isValid) {
        throw StateError(
          'Checksum verification failed for ${check.artifact!.fileName}. Expected SHA-256: ${check.artifact!.sha256}.',
        );
      }

      // 3. Backup existing executable
      final backupFile = File('${targetExecutable.path}.dynbox_backup');
      if (targetExecutable.existsSync()) {
        try {
          if (backupFile.existsSync()) backupFile.deleteSync();
          targetExecutable.copySync(backupFile.path);
        } catch (e) {
          throw FileSystemException(
            'Failed to create backup of existing binary: $e',
            targetExecutable.path,
          );
        }
      }

      // 4. Extract and atomically stage new executable
      try {
        final extractedExe = _extractExecutable(
          downloadedArchive,
          tempDir,
          targetExecutable.path.endsWith('.exe') ? 'dynbox.exe' : 'dynbox',
        );

        if (!extractedExe.existsSync()) {
          throw StateError(
            'Extracted archive did not contain executable binary.',
          );
        }

        // Set executable permissions on POSIX
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['+x', extractedExe.path]);
        }

        // Replace target executable
        extractedExe.copySync(targetExecutable.path);

        if (!Platform.isWindows) {
          Process.runSync('chmod', ['+x', targetExecutable.path]);
        }

        // Remove backup on success
        if (backupFile.existsSync()) {
          try {
            backupFile.deleteSync();
          } catch (_) {}
        }

        return 'Successfully upgraded DynBox from ${check.currentVersion} to ${check.latestVersion}.';
      } catch (e) {
        // Rollback from backup if replacement failed
        if (backupFile.existsSync()) {
          try {
            backupFile.copySync(targetExecutable.path);
            backupFile.deleteSync();
          } catch (_) {}
        }
        throw StateError('Upgrade failed: $e. Restored previous version.');
      }
    } finally {
      // Clean up temp directory
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  File _extractExecutable(File archive, Directory tempDir, String exeName) {
    // If the file is directly a binary (in test mocks or raw releases)
    if (archive.path.endsWith('.tar.gz') || archive.path.endsWith('.tgz')) {
      final result = Process.runSync('tar', [
        '-xzf',
        archive.path,
        '-C',
        tempDir.path,
      ]);
      if (result.exitCode != 0) {
        throw StateError('Failed to extract tar archive: ${result.stderr}');
      }
      return File('${tempDir.path}/$exeName');
    } else if (archive.path.endsWith('.zip')) {
      if (Platform.isWindows) {
        final result = Process.runSync('powershell', [
          '-Command',
          'Expand-Archive -Path "${archive.path}" -DestinationPath "${tempDir.path}" -Force',
        ]);
        if (result.exitCode != 0) {
          throw StateError('Failed to extract zip archive: ${result.stderr}');
        }
      } else {
        final result = Process.runSync('unzip', [
          '-o',
          archive.path,
          '-d',
          tempDir.path,
        ]);
        if (result.exitCode != 0) {
          throw StateError('Failed to extract zip archive: ${result.stderr}');
        }
      }
      return File('${tempDir.path}/$exeName');
    } else {
      // Treat as raw binary if no archive extension
      return archive;
    }
  }

  bool _isNewerVersion(String available, String current) {
    if (available == current) return false;
    final avParts = available
        .replaceAll(RegExp(r'^v'), '')
        .split('.')
        .map(int.tryParse)
        .toList();
    final curParts = current
        .replaceAll(RegExp(r'^v'), '')
        .split('.')
        .map(int.tryParse)
        .toList();

    for (var i = 0; i < 3; i++) {
      final a = (i < avParts.length ? avParts[i] : 0) ?? 0;
      final c = (i < curParts.length ? curParts[i] : 0) ?? 0;
      if (a > c) return true;
      if (a < c) return false;
    }
    return false;
  }
}
