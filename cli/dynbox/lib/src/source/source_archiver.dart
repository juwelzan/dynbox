import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Result metadata of a source archiving operation.
class SourceArchiveResult {
  final File archiveFile;
  final String sha256Digest;
  final int fileCount;
  final int totalSizeBytes;
  final List<String> includedFiles;

  const SourceArchiveResult({
    required this.archiveFile,
    required this.sha256Digest,
    required this.fileCount,
    required this.totalSizeBytes,
    required this.includedFiles,
  });
}

/// Safely archives a Flutter project source tree for remote build synchronization
/// while strictly excluding build artifacts, local secrets, signing keys, and VCS directories.
class SourceArchiver {
  /// Default forbidden directory names.
  static const Set<String> defaultExcludedDirs = {
    '.git',
    '.github',
    '.dart_tool',
    'build',
    '.idea',
    '.vscode',
    'ios/Pods',
    '.gradle',
    'android/.gradle',
    'android/app/build',
  };

  /// File patterns and names that must never be packaged into source archives.
  static const Set<String> forbiddenFileNames = {
    'key.properties',
    'local.properties',
    '.env',
    '.env.local',
    '.env.production',
    'id_rsa',
    'id_ed25519',
  };

  static const List<String> forbiddenExtensions = [
    '.keystore',
    '.jks',
    '.p12',
    '.mobileprovision',
    '.pem',
    '.key',
  ];

  /// Scans [projectDir] and returns a list of relative file paths that are safe to include in a source release snapshot.
  static List<String> getSafeSourceFiles({
    required Directory projectDir,
    Set<String>? customExcludedDirs,
  }) {
    final excludedDirs = customExcludedDirs ?? defaultExcludedDirs;
    final includedFiles = <String>[];

    final entities = projectDir.listSync(recursive: true, followLinks: false);

    for (final entity in entities) {
      if (entity is! File) continue;

      final relativePath = entity.path
          .substring(projectDir.path.length)
          .replaceAll(r'\', '/')
          .replaceFirst(RegExp(r'^/'), '');

      // Check if file is inside an excluded directory
      final segments = relativePath.split('/');
      final isExcluded = segments.any((seg) => excludedDirs.contains(seg));
      if (isExcluded) continue;

      final fileName = segments.last.toLowerCase();

      // Check forbidden file names
      if (forbiddenFileNames.contains(fileName) ||
          fileName.startsWith('.env')) {
        continue;
      }

      // Check forbidden extensions
      if (forbiddenExtensions.any((ext) => fileName.endsWith(ext))) {
        continue;
      }

      includedFiles.add(relativePath);
    }

    includedFiles.sort();
    return includedFiles;
  }

  /// Creates a deterministic, secret-free source manifest with per-file SHA256 checksums.
  static Map<String, dynamic> generateSourceManifest({
    required Directory projectDir,
    required String appId,
    required String appVersion,
    Set<String>? customExcludedDirs,
  }) {
    final files = getSafeSourceFiles(
      projectDir: projectDir,
      customExcludedDirs: customExcludedDirs,
    );

    final fileManifest = <String, dynamic>{};
    var totalBytes = 0;

    for (final relPath in files) {
      final file = File('${projectDir.path}/$relPath');
      final bytes = file.readAsBytesSync();
      totalBytes += bytes.length;
      final fileSha = crypto.sha256.convert(bytes).toString();
      fileManifest[relPath] = {'sizeBytes': bytes.length, 'sha256': fileSha};
    }

    final manifestBytes = utf8.encode(jsonEncode(fileManifest));
    final overallDigest = crypto.sha256.convert(manifestBytes).toString();

    return {
      'schemaVersion': '1.0',
      'appId': appId,
      'appVersion': appVersion,
      'snapshotSha256': overallDigest,
      'totalSizeBytes': totalBytes,
      'fileCount': files.length,
      'files': fileManifest,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}
