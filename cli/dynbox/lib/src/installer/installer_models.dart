import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Represents platform and architecture for standalone distribution.
enum DistributionPlatform {
  macosArm64('macos-arm64'),
  macosX64('macos-x64'),
  linuxX64('linux-x64'),
  linuxArm64('linux-arm64'),
  windowsX64('windows-x64');

  final String identifier;
  const DistributionPlatform(this.identifier);

  /// Resolves the current host platform and architecture.
  static DistributionPlatform? currentHost() {
    if (Platform.isMacOS) {
      final arch = _detectArchitecture();
      if (arch == 'arm64' || arch == 'aarch64') {
        return DistributionPlatform.macosArm64;
      }
      if (arch == 'x86_64' || arch == 'x64') {
        return DistributionPlatform.macosX64;
      }
    } else if (Platform.isLinux) {
      final arch = _detectArchitecture();
      if (arch == 'x86_64' || arch == 'x64') {
        return DistributionPlatform.linuxX64;
      }
      if (arch == 'arm64' || arch == 'aarch64') {
        return DistributionPlatform.linuxArm64;
      }
    } else if (Platform.isWindows) {
      final arch = _detectArchitecture();
      if (arch == 'x86_64' || arch == 'x64' || arch == 'amd64') {
        return DistributionPlatform.windowsX64;
      }
    }
    return null;
  }

  static String _detectArchitecture() {
    final osArch = Platform.version.toLowerCase();
    if (osArch.contains('arm64') || osArch.contains('aarch64')) return 'arm64';
    if (osArch.contains('x64') || osArch.contains('x86_64')) return 'x64';
    return 'unknown';
  }
}

/// Metadata for a single platform artifact in a release manifest.
class ReleaseArtifact {
  final String fileName;
  final String sha256;
  final int sizeBytes;

  const ReleaseArtifact({
    required this.fileName,
    required this.sha256,
    required this.sizeBytes,
  });

  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) {
    return ReleaseArtifact(
      fileName: json['fileName'] as String,
      sha256: json['sha256'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };
}

/// Complete machine-readable release manifest describing an official DynBox release.
class ReleaseManifest {
  final String schemaVersion;
  final String version;
  final DateTime publishedAt;
  final Map<String, ReleaseArtifact> artifacts;

  const ReleaseManifest({
    required this.schemaVersion,
    required this.version,
    required this.publishedAt,
    required this.artifacts,
  });

  factory ReleaseManifest.fromJson(Map<String, dynamic> json) {
    final artifactsMap = <String, ReleaseArtifact>{};
    final rawArtifacts = json['artifacts'] as Map<String, dynamic>? ?? {};
    for (final entry in rawArtifacts.entries) {
      if (entry.value is Map<String, dynamic>) {
        artifactsMap[entry.key] = ReleaseArtifact.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return ReleaseManifest(
      schemaVersion: json['schemaVersion'] as String? ?? '1.0',
      version: json['version'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      artifacts: artifactsMap,
    );
  }

  factory ReleaseManifest.fromString(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Release manifest must be a JSON object');
    }
    return ReleaseManifest.fromJson(decoded);
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'version': version,
    'publishedAt': publishedAt.toIso8601String(),
    'artifacts': artifacts.map((k, v) => MapEntry(k, v.toJson())),
  };
}

/// Utility for verifying cryptographic SHA-256 digests of downloaded files.
class IntegrityVerifier {
  /// Computes SHA-256 of [file] and verifies equality with [expectedSha256].
  static Future<bool> verifyFile(File file, String expectedSha256) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final digest = crypto.sha256.convert(bytes).toString().toLowerCase();
    return digest == expectedSha256.toLowerCase().trim();
  }
}
