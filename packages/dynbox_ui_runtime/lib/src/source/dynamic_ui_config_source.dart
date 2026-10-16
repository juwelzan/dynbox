import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Metadata for a Dynamic UI configuration bundle.
class DynamicUiConfigMetadata {
  final String configId;
  final int revision;
  final String schemaVersion;
  final String? minAppVersion;
  final DateTime? fetchedAt;

  const DynamicUiConfigMetadata({
    required this.configId,
    required this.revision,
    required this.schemaVersion,
    this.minAppVersion,
    this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
    'configId': configId,
    'revision': revision,
    'schemaVersion': schemaVersion,
    if (minAppVersion != null) 'minAppVersion': minAppVersion,
    if (fetchedAt != null) 'fetchedAt': fetchedAt!.toIso8601String(),
  };

  @override
  String toString() =>
      'DynamicUiConfigMetadata(id: $configId, rev: $revision, v: $schemaVersion)';
}

/// Abstract contract for configuration sources providing Dynamic UI JSON.
///
/// Sources can be local file bundles, in-memory test mocks, or remote endpoints.
/// A source implementation must never execute arbitrary code or bypass security rules.
abstract class DynamicUiConfigSource {
  /// Unique identifier of the configuration source (e.g. 'local', 'memory', 'firebase_rc').
  String get sourceName;

  /// Fetches raw JSON configuration string from the source.
  ///
  /// Throws [DynamicUiSourceException] on network or IO failure.
  Future<String> fetchConfiguration();

  /// Optional fast metadata probe without full document download if supported.
  Future<DynamicUiConfigMetadata?> fetchMetadata() async => null;
}

/// Exception thrown when configuration fetching from a [DynamicUiConfigSource] fails.
class DynamicUiSourceException implements Exception {
  final String message;
  final Object? cause;

  const DynamicUiSourceException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'DynamicUiSourceException: $message (cause: $cause)';
    }
    return 'DynamicUiSourceException: $message';
  }
}

/// In-memory implementation of [DynamicUiConfigSource] for testing and deterministic environments.
class MemoryConfigSource implements DynamicUiConfigSource {
  @override
  final String sourceName;
  String jsonPayload;
  bool shouldFail;
  String failureMessage;

  MemoryConfigSource({
    required this.jsonPayload,
    this.sourceName = 'memory',
    this.shouldFail = false,
    this.failureMessage = 'Simulated memory source failure',
  });

  void updatePayload(String newJson) {
    jsonPayload = newJson;
  }

  @override
  Future<String> fetchConfiguration() async {
    if (shouldFail) {
      throw DynamicUiSourceException(failureMessage);
    }
    return jsonPayload;
  }

  @override
  Future<DynamicUiConfigMetadata?> fetchMetadata() async {
    try {
      final decoded = jsonDecode(jsonPayload);
      if (decoded is Map<String, dynamic>) {
        return DynamicUiConfigMetadata(
          configId: decoded['configId']?.toString() ?? 'memory',
          revision: decoded['revision'] is int ? decoded['revision'] as int : 0,
          schemaVersion: decoded['schemaVersion']?.toString() ?? '1.0.0',
          minAppVersion: decoded['minAppVersion']?.toString(),
          fetchedAt: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }
}

/// Local file system implementation of [DynamicUiConfigSource].
///
/// Reads a bundled or locally cached JSON configuration file.
class LocalFileConfigSource implements DynamicUiConfigSource {
  @override
  final String sourceName;
  final File file;

  LocalFileConfigSource(this.file, {this.sourceName = 'local_file'});

  @override
  Future<String> fetchConfiguration() async {
    try {
      if (!await file.exists()) {
        throw DynamicUiSourceException(
          'Configuration file does not exist: ${file.path}',
        );
      }
      return await file.readAsString();
    } catch (e) {
      if (e is DynamicUiSourceException) rethrow;
      throw DynamicUiSourceException(
        'Failed to read local configuration file at ${file.path}',
        e,
      );
    }
  }

  @override
  Future<DynamicUiConfigMetadata?> fetchMetadata() async {
    try {
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return DynamicUiConfigMetadata(
          configId: decoded['configId']?.toString() ?? 'unknown',
          revision: decoded['revision'] is int ? decoded['revision'] as int : 0,
          schemaVersion: decoded['schemaVersion']?.toString() ?? 'unknown',
          minAppVersion: decoded['minAppVersion']?.toString(),
          fetchedAt: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }
}
