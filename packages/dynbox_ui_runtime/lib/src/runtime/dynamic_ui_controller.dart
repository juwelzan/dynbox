import 'dart:async';

import '../models/dynamic_ui_models.dart';
import '../parser/dynamic_ui_parser.dart';
import '../source/dynamic_ui_config_source.dart';

/// Semantic version helper for minimum app version checks.
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;

  const SemanticVersion(this.major, this.minor, this.patch);

  static SemanticVersion? tryParse(String version) {
    final clean = version.trim().replaceFirst(RegExp(r'^v'), '');
    final parts = clean.split('.');
    if (parts.length < 2 || parts.length > 3) return null;
    final maj = int.tryParse(parts[0]);
    final min = int.tryParse(parts[1]);
    final pat = parts.length == 3
        ? int.tryParse(parts[2].split('-')[0].split('+')[0])
        : 0;
    if (maj == null || min == null || pat == null) return null;
    return SemanticVersion(maj, min, pat);
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// Status of the active dynamic UI configuration.
enum DynamicUiStatus {
  uninitialized,
  bundledDefault,
  cachedKnownGood,
  activeRemote,
  rolledBack,
  error,
}

/// Abstract storage provider interface for persisting the last known-good configuration.
abstract class DynamicUiStorage {
  Future<String?> readLastKnownGood();
  Future<void> writeLastKnownGood(String jsonContent);
  Future<void> clear();
}

/// In-memory storage for testing and stateless environments.
class MemoryDynamicUiStorage implements DynamicUiStorage {
  String? _storedJson;

  MemoryDynamicUiStorage([this._storedJson]);

  @override
  Future<String?> readLastKnownGood() async => _storedJson;

  @override
  Future<void> writeLastKnownGood(String jsonContent) async {
    _storedJson = jsonContent;
  }

  @override
  Future<void> clear() async {
    _storedJson = null;
  }
}

/// Controller managing Dynamic UI lifecycle, validation, updates, fallback, and rollback.
class DynamicUiController {
  final DynamicUiParser parser;
  final DynamicUiConfigSource? remoteSource;
  final DynamicUiStorage? storage;
  final String appVersion;
  final Duration fetchTimeout;

  DynamicUiDocument? _bundledDefault;
  DynamicUiDocument? _lastKnownGood;
  DynamicUiDocument? _activeDocument;
  DynamicUiStatus _status = DynamicUiStatus.uninitialized;
  String? _lastError;

  final _updateController = StreamController<DynamicUiDocument>.broadcast();

  DynamicUiController({
    this.parser = const DynamicUiParser(),
    this.remoteSource,
    this.storage,
    this.appVersion = '1.0.0',
    this.fetchTimeout = const Duration(seconds: 5),
  });

  DynamicUiDocument? get activeDocument => _activeDocument;
  DynamicUiDocument? get lastKnownGood => _lastKnownGood;
  DynamicUiDocument? get bundledDefault => _bundledDefault;
  DynamicUiStatus get status => _status;
  String? get lastError => _lastError;
  int? get activeRevision => _activeDocument?.revision;
  String? get activeConfigId => _activeDocument?.configId;

  Stream<DynamicUiDocument> get updates => _updateController.stream;

  /// Initializes the controller:
  /// 1. Validates and loads [bundledDefaultJson].
  /// 2. Attempts to restore the cached last-known-good configuration from [storage] if present.
  /// 3. Returns the active document.
  Future<DynamicUiDocument> initialize({
    required String bundledDefaultJson,
  }) async {
    try {
      _bundledDefault = parser.parseJsonString(bundledDefaultJson);
      _validateAppCompatibility(_bundledDefault!);
      _activeDocument = _bundledDefault;
      _lastKnownGood = _bundledDefault;
      _status = DynamicUiStatus.bundledDefault;
      _lastError = null;
    } catch (e) {
      _status = DynamicUiStatus.error;
      _lastError = 'Bundled default configuration is invalid: $e';
      throw DynamicUiException(_lastError!);
    }

    // Try loading cached last known-good configuration if storage is provided
    if (storage != null) {
      try {
        final cachedJson = await storage!.readLastKnownGood();
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final cachedDoc = parser.parseJsonString(cachedJson);
          _validateAppCompatibility(cachedDoc);
          if (cachedDoc.revision >= _bundledDefault!.revision) {
            _lastKnownGood = cachedDoc;
            _activeDocument = cachedDoc;
            _status = DynamicUiStatus.cachedKnownGood;
          }
        }
      } catch (e) {
        // Corrupted cache shouldn't break startup; fallback to bundled default
        _lastError =
            'Warning: Cached last-known-good failed validation ($e); falling back to bundled default.';
      }
    }

    return _activeDocument!;
  }

  /// Fetches candidate configuration from [remoteSource], validates it, and activates it.
  ///
  /// If fetching fails, validation fails, or version is incompatible:
  /// - The candidate is rejected.
  /// - The active configuration remains unchanged (or reverts to last known-good).
  /// - Returns false and populates [lastError].
  Future<bool> checkForUpdates() async {
    if (remoteSource == null) {
      _lastError = 'No configuration source configured.';
      return false;
    }

    try {
      final rawJson = await remoteSource!.fetchConfiguration().timeout(
        fetchTimeout,
      );
      final candidate = parser.parseJsonString(rawJson);
      _validateAppCompatibility(candidate);

      // Verify revision monotonicity if active exists
      if (_activeDocument != null &&
          candidate.revision < _activeDocument!.revision) {
        throw DynamicUiException(
          'Candidate revision (${candidate.revision}) is older than active revision (${_activeDocument!.revision}).',
        );
      }

      // Activate candidate
      _lastKnownGood = _activeDocument;
      _activeDocument = candidate;
      _status = DynamicUiStatus.activeRemote;
      _lastError = null;

      // Persist new known-good configuration
      if (storage != null) {
        await storage!.writeLastKnownGood(rawJson);
      }

      _updateController.add(candidate);
      return true;
    } catch (e) {
      _lastError = 'Update check failed: $e';
      // Ensure we remain on a known good configuration
      if (_activeDocument == null && _bundledDefault != null) {
        _activeDocument = _bundledDefault;
        _status = DynamicUiStatus.bundledDefault;
      }
      return false;
    }
  }

  /// Directly validates and activates an externally-verified JSON configuration payload.
  ///
  /// Used by the DynBox OTA engine after cryptographic signature and digest verification.
  Future<bool> activateConfigurationJson(String rawJson) async {
    try {
      final candidate = parser.parseJsonString(rawJson);
      _validateAppCompatibility(candidate);

      if (_activeDocument != null &&
          candidate.revision < _activeDocument!.revision) {
        throw DynamicUiException(
          'Candidate revision (${candidate.revision}) is older than active revision (${_activeDocument!.revision}).',
        );
      }

      _lastKnownGood = _activeDocument;
      _activeDocument = candidate;
      _status = DynamicUiStatus.activeRemote;
      _lastError = null;

      if (storage != null) {
        await storage!.writeLastKnownGood(rawJson);
      }

      _updateController.add(candidate);
      return true;
    } catch (e) {
      _lastError = 'Failed to activate configuration: $e';
      return false;
    }
  }

  /// Explicit rollback to the last known-good configuration or bundled default.
  bool rollbackToLastKnownGood() {
    if (_lastKnownGood != null && _lastKnownGood != _activeDocument) {
      _activeDocument = _lastKnownGood;
      _status = DynamicUiStatus.rolledBack;
      _updateController.add(_activeDocument!);
      return true;
    } else if (_bundledDefault != null && _bundledDefault != _activeDocument) {
      _activeDocument = _bundledDefault;
      _status = DynamicUiStatus.bundledDefault;
      _updateController.add(_activeDocument!);
      return true;
    }
    return false;
  }

  void _validateAppCompatibility(DynamicUiDocument doc) {
    if (doc.minAppVersion == null) return;
    final minVer = SemanticVersion.tryParse(doc.minAppVersion!);
    final currentVer = SemanticVersion.tryParse(appVersion);
    if (minVer != null && currentVer != null) {
      if (currentVer.compareTo(minVer) < 0) {
        throw DynamicUiException(
          'Incompatible app version: Current app is $appVersion, but configuration requires minimum $minVer.',
        );
      }
    }
  }

  void dispose() {
    _updateController.close();
  }
}
