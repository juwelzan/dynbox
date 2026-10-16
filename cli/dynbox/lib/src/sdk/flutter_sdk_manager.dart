import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../sdk/safe_process_executor.dart';
import '../sdk/sdk_validator.dart';

/// Metadata for a single Flutter SDK release from official Flutter infra.
class FlutterRelease {
  final String hash;
  final String channel;
  final String version;
  final String dartSdkVersion;
  final String dartSdkArch;
  final String releaseDate;
  final String archive;
  final String sha256;

  const FlutterRelease({
    required this.hash,
    required this.channel,
    required this.version,
    required this.dartSdkVersion,
    required this.dartSdkArch,
    required this.releaseDate,
    required this.archive,
    required this.sha256,
  });

  factory FlutterRelease.fromJson(Map<String, dynamic> json) {
    return FlutterRelease(
      hash: json['hash'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      version: json['version'] as String? ?? '',
      dartSdkVersion: json['dart_sdk_version'] as String? ?? '',
      dartSdkArch: json['dart_sdk_arch'] as String? ?? 'x64',
      releaseDate: json['release_date'] as String? ?? '',
      archive: json['archive'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
    );
  }
}

/// Metadata list for releases of an operating system.
class FlutterReleasesCatalog {
  final String baseUrl;
  final Map<String, String> currentReleases;
  final List<FlutterRelease> releases;

  const FlutterReleasesCatalog({
    required this.baseUrl,
    required this.currentReleases,
    required this.releases,
  });

  factory FlutterReleasesCatalog.fromJson(Map<String, dynamic> json) {
    final baseUrl =
        json['base_url'] as String? ??
        'https://storage.googleapis.com/flutter_infra_release/releases';
    final current = Map<String, String>.from(
      (json['current_release'] as Map?)?.cast<String, String>() ?? {},
    );
    final rawReleases = json['releases'] as List? ?? [];
    final releases = rawReleases
        .whereType<Map>()
        .map((m) => FlutterRelease.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return FlutterReleasesCatalog(
      baseUrl: baseUrl,
      currentReleases: current,
      releases: releases,
    );
  }

  /// Finds the latest stable release matching the given architecture.
  FlutterRelease? findLatestStable({String? arch}) {
    final targetArch = arch ?? 'x64';
    // 1. Look for stable with exact arch match
    for (final rel in releases) {
      if (rel.channel == 'stable' && rel.dartSdkArch == targetArch) {
        return rel;
      }
    }
    // Fallback: any stable
    for (final rel in releases) {
      if (rel.channel == 'stable') {
        return rel;
      }
    }
    return null;
  }

  /// Finds a specific version.
  FlutterRelease? findVersion(String version, {String? arch}) {
    final targetArch = arch ?? 'x64';
    // Exact match on version and arch
    for (final rel in releases) {
      if (rel.version == version && rel.dartSdkArch == targetArch) {
        return rel;
      }
    }
    // Fallback to version match regardless of arch
    for (final rel in releases) {
      if (rel.version == version) {
        return rel;
      }
    }
    return null;
  }
}

/// Client interface for fetching Flutter release catalog and downloading SDK archives.
abstract class FlutterDownloadClient {
  Future<FlutterReleasesCatalog> fetchCatalog({String? os});
  Future<void> downloadArchive({
    required String url,
    required File destination,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });
}

/// Real HTTP implementation of FlutterDownloadClient.
class HttpFlutterDownloadClient implements FlutterDownloadClient {
  final HttpClient client;

  HttpFlutterDownloadClient({HttpClient? client})
    : client = client ?? HttpClient();

  @override
  Future<FlutterReleasesCatalog> fetchCatalog({String? os}) async {
    final targetOs = os ?? Platform.operatingSystem;
    final osName = switch (targetOs) {
      'macos' => 'macos',
      'linux' => 'linux',
      'windows' => 'windows',
      _ => throw UnsupportedError(
        'Unsupported operating system for Flutter: $targetOs',
      ),
    };

    final url =
        'https://storage.googleapis.com/flutter_infra_release/releases/releases_$osName.json';
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch Flutter releases catalog from $url (HTTP ${response.statusCode})',
        uri: Uri.parse(url),
      );
    }

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return FlutterReleasesCatalog.fromJson(json);
  }

  @override
  Future<void> downloadArchive({
    required String url,
    required File destination,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download Flutter archive from $url (HTTP ${response.statusCode})',
        uri: Uri.parse(url),
      );
    }

    final total = response.contentLength;
    var received = 0;

    final sink = destination.openWrite();
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (onProgress != null && total > 0) {
        onProgress(received, total);
      }
    }
    await sink.close();
  }
}

/// Result of an installed managed SDK.
class ManagedSdkInfo {
  final String version;
  final Directory directory;
  final String? dartVersion;
  final bool isValid;

  const ManagedSdkInfo({
    required this.version,
    required this.directory,
    this.dartVersion,
    required this.isValid,
  });
}

/// Manages official Flutter SDK installations in `~/.dynbox/sdks/<version>`.
class FlutterSdkManager {
  final Directory? sdksBaseDirOverride;
  final FlutterDownloadClient downloadClient;
  final SdkValidator sdkValidator;
  final SafeProcessExecutor executor;

  FlutterSdkManager({
    this.sdksBaseDirOverride,
    FlutterDownloadClient? downloadClient,
    SdkValidator? sdkValidator,
    SafeProcessExecutor? executor,
  }) : downloadClient = downloadClient ?? HttpFlutterDownloadClient(),
       sdkValidator = sdkValidator ?? const SdkValidator(),
       executor = executor ?? SafeProcessExecutor();

  /// Resolves the base directory where DynBox manages installed Flutter SDKs.
  /// Default: `~/.dynbox/sdks` (or `%LOCALAPPDATA%\DynBox\sdks` on Windows).
  Directory resolveSdksDirectory({Map<String, String>? environment}) {
    if (sdksBaseDirOverride != null) return sdksBaseDirOverride!;

    final env = environment ?? Platform.environment;
    final explicitDir = env['DYNBOX_SDKS_DIR'];
    if (explicitDir != null && explicitDir.trim().isNotEmpty) {
      return Directory(explicitDir.trim());
    }

    if (Platform.isWindows) {
      final localAppData = env['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory('$localAppData\\DynBox\\sdks');
      }
    }

    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return Directory('$home/.dynbox/sdks');
  }

  /// Lists all locally installed managed SDK versions.
  List<ManagedSdkInfo> listInstalled() {
    final baseDir = resolveSdksDirectory();
    if (!baseDir.existsSync()) return [];

    final list = <ManagedSdkInfo>[];
    for (final entity in baseDir.listSync()) {
      if (entity is Directory) {
        final dirName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        // Avoid temporary download or extraction directories
        if (dirName.startsWith('.') || dirName.startsWith('tmp_')) continue;

        final validation = sdkValidator.validate(entity.path);
        list.add(
          ManagedSdkInfo(
            version: dirName,
            directory: entity,
            dartVersion: validation.dartVersion,
            isValid: validation.isValid,
          ),
        );
      }
    }

    // Sort by version descending or name
    list.sort((a, b) => b.version.compareTo(a.version));
    return list;
  }

  /// Resolves the SDK directory for a specific version.
  Directory getSdkDirectory(String version) {
    final sanitized = version.replaceAll(RegExp(r'[^a-zA-Z0-9_\.\-]'), '_');
    return Directory('${resolveSdksDirectory().path}/$sanitized');
  }

  /// Verifies an archive's SHA256 matches expected checksum.
  static bool verifyChecksum(File file, String expectedSha256) {
    final bytes = file.readAsBytesSync();
    final actual = crypto.sha256.convert(bytes).toString();
    return actual.toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Safely extracts an archive to a target directory.
  /// Strictly prevents path traversal and ensures clean atomic staging.
  Future<void> extractArchive({
    required File archiveFile,
    required Directory destinationDir,
  }) async {
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }

    final isZip = archiveFile.path.endsWith('.zip');
    final isTarXz =
        archiveFile.path.endsWith('.tar.xz') ||
        archiveFile.path.endsWith('.tar.gz');

    if (isZip) {
      // Use unzip command via SafeProcessExecutor
      // unzip -q <archiveFile> -d <destinationDir>
      final result = await executor.execute('unzip', [
        '-q',
        archiveFile.path,
        '-d',
        destinationDir.path,
      ], checkExitCode: true);
      if (result.exitCode != 0) {
        throw ProcessException(
          'unzip',
          ['-q', archiveFile.path],
          result.stderr,
          result.exitCode,
        );
      }
    } else if (isTarXz) {
      // Use tar -xf <archiveFile> -C <destinationDir>
      final result = await executor.execute('tar', [
        '-xf',
        archiveFile.path,
        '-C',
        destinationDir.path,
      ], checkExitCode: true);
      if (result.exitCode != 0) {
        throw ProcessException(
          'tar',
          ['-xf', archiveFile.path],
          result.stderr,
          result.exitCode,
        );
      }
    } else {
      throw UnsupportedError('Unsupported archive format: ${archiveFile.path}');
    }

    // Official flutter archives typically unpack into a top-level "flutter" directory.
    // E.g., destinationDir/flutter/bin/flutter
    // Normalize if destination contains single "flutter" directory:
    final unpackedFlutter = Directory('${destinationDir.path}/flutter');
    if (unpackedFlutter.existsSync() &&
        Directory('${unpackedFlutter.path}/bin').existsSync()) {
      // Move all contents up to destinationDir
      for (final item in unpackedFlutter.listSync()) {
        final targetPath =
            '${destinationDir.path}/${item.uri.pathSegments.where((s) => s.isNotEmpty).last}';
        if (item is Directory) {
          item.renameSync(targetPath);
        } else if (item is File) {
          item.renameSync(targetPath);
        }
      }
      try {
        unpackedFlutter.deleteSync();
      } catch (_) {}
    }
  }

  /// Downloads, verifies, and installs an official Flutter SDK release.
  Future<ManagedSdkInfo> installRelease({
    required FlutterRelease release,
    required String baseUrl,
    void Function(String message)? onStatus,
  }) async {
    final finalSdkDir = getSdkDirectory(release.version);
    if (finalSdkDir.existsSync()) {
      final validation = sdkValidator.validate(finalSdkDir.path);
      if (validation.isValid) {
        onStatus?.call('SDK version ${release.version} is already installed.');
        return ManagedSdkInfo(
          version: release.version,
          directory: finalSdkDir,
          dartVersion: validation.dartVersion,
          isValid: true,
        );
      }
    }

    final sdksDir = resolveSdksDirectory();
    if (!sdksDir.existsSync()) {
      sdksDir.createSync(recursive: true);
    }

    final downloadUrl = baseUrl.endsWith('/')
        ? '$baseUrl${release.archive}'
        : '$baseUrl/${release.archive}';

    final tempArchive = File(
      '${sdksDir.path}/tmp_${DateTime.now().millisecondsSinceEpoch}_${release.archive.split('/').last}',
    );
    final tempExtractDir = Directory(
      '${sdksDir.path}/tmp_extract_${DateTime.now().millisecondsSinceEpoch}_${release.version}',
    );

    try {
      onStatus?.call(
        'Downloading official Flutter ${release.version} (${release.channel})...',
      );
      onStatus?.call('  URL: $downloadUrl');

      await downloadClient.downloadArchive(
        url: downloadUrl,
        destination: tempArchive,
      );

      onStatus?.call('Verifying SHA-256 integrity checksum...');
      if (!verifyChecksum(tempArchive, release.sha256)) {
        throw StateError(
          'Checksum verification failed for ${tempArchive.path}.\n'
          'Expected: ${release.sha256}',
        );
      }
      onStatus?.call('✓ Cryptographic checksum verified.');

      onStatus?.call('Extracting SDK archive safely...');
      await extractArchive(
        archiveFile: tempArchive,
        destinationDir: tempExtractDir,
      );

      final validation = sdkValidator.validate(tempExtractDir.path);
      if (!validation.isValid) {
        throw StateError(
          'Extracted SDK validation failed: ${validation.message}',
        );
      }

      onStatus?.call('Finalizing installation to ${finalSdkDir.path}...');
      if (finalSdkDir.existsSync()) {
        finalSdkDir.deleteSync(recursive: true);
      }
      tempExtractDir.renameSync(finalSdkDir.path);

      onStatus?.call('✓ Successfully installed Flutter ${release.version}!');

      return ManagedSdkInfo(
        version: release.version,
        directory: finalSdkDir,
        dartVersion: validation.dartVersion,
        isValid: true,
      );
    } finally {
      if (tempArchive.existsSync()) {
        try {
          tempArchive.deleteSync();
        } catch (_) {}
      }
      if (tempExtractDir.existsSync()) {
        try {
          tempExtractDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Removes an installed managed SDK.
  /// Strictly prevents deletion of directories outside DynBox's managed SDK folder.
  Future<void> removeSdk(String version) async {
    final sdkDir = getSdkDirectory(version);
    final baseDir = resolveSdksDirectory();

    // Safety checks:
    final canonicalBase = baseDir.absolute.resolveSymbolicLinksSync();
    if (!sdkDir.existsSync()) {
      throw FileSystemException('SDK directory not found: ${sdkDir.path}');
    }

    final canonicalTarget = sdkDir.absolute.resolveSymbolicLinksSync();
    if (!canonicalTarget.startsWith(canonicalBase)) {
      throw StateError(
        'Security Violation: Cannot delete SDK outside managed directory: ${sdkDir.path}',
      );
    }

    sdkDir.deleteSync(recursive: true);
  }
}
