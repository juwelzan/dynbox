import 'dart:convert';
import 'dart:io';

import '../models/ota_manifest.dart';

/// State of local cache including active version and rollback metadata.
class OtaCacheState {
  final int activeVersion;
  final String? activeReleaseId;
  final String? activePayloadJson;
  final int? lkgVersion;
  final String? lkgReleaseId;
  final String? lkgPayloadJson;

  const OtaCacheState({
    required this.activeVersion,
    this.activeReleaseId,
    this.activePayloadJson,
    this.lkgVersion,
    this.lkgReleaseId,
    this.lkgPayloadJson,
  });

  Map<String, dynamic> toJson() => {
    'activeVersion': activeVersion,
    if (activeReleaseId != null) 'activeReleaseId': activeReleaseId,
    if (activePayloadJson != null) 'activePayloadJson': activePayloadJson,
    if (lkgVersion != null) 'lkgVersion': lkgVersion,
    if (lkgReleaseId != null) 'lkgReleaseId': lkgReleaseId,
    if (lkgPayloadJson != null) 'lkgPayloadJson': lkgPayloadJson,
  };

  factory OtaCacheState.fromJson(Map<String, dynamic> json) => OtaCacheState(
    activeVersion: json['activeVersion'] as int? ?? 0,
    activeReleaseId: json['activeReleaseId'] as String?,
    activePayloadJson: json['activePayloadJson'] as String?,
    lkgVersion: json['lkgVersion'] as int?,
    lkgReleaseId: json['lkgReleaseId'] as String?,
    lkgPayloadJson: json['lkgPayloadJson'] as String?,
  );
}

/// Manages on-disk caching, atomic staging, verification, and rollback of OTA payloads.
class OtaCache {
  final Directory storageDir;
  late final File _stateFile;
  late final Directory _payloadsDir;

  OtaCacheState _state = const OtaCacheState(activeVersion: 0);
  OtaCacheState get state => _state;

  OtaCache({required this.storageDir}) {
    _stateFile = File('${storageDir.path}/ota_state.json');
    _payloadsDir = Directory('${storageDir.path}/payloads');
  }

  /// Initializes the cache directory and reads stored state.
  Future<void> init() async {
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    if (!await _payloadsDir.exists()) {
      await _payloadsDir.create(recursive: true);
    }

    if (await _stateFile.exists()) {
      try {
        final content = await _stateFile.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        _state = OtaCacheState.fromJson(decoded);
      } catch (_) {
        // Fall back to clean state on corruption
        _state = const OtaCacheState(activeVersion: 0);
      }
    }
  }

  /// Stages and writes payload bytes atomically to disk.
  Future<File> stagePayload({
    required String releaseId,
    required List<int> payloadBytes,
  }) async {
    final tempFile = File('${_payloadsDir.path}/stage_$releaseId.tmp');
    final targetFile = File('${_payloadsDir.path}/release_$releaseId.json');

    await tempFile.writeAsBytes(payloadBytes, flush: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetFile.path);
    return targetFile;
  }

  /// Promotes a verified staged release to active state and retains previous active as LKG (Last-Known-Good).
  Future<void> activateRelease({
    required OtaManifest manifest,
    required String payloadJson,
  }) async {
    // Current active becomes LKG if it was a valid version > 0
    final newLkgVersion = _state.activeVersion > 0
        ? _state.activeVersion
        : _state.lkgVersion;
    final newLkgReleaseId = _state.activeReleaseId ?? _state.lkgReleaseId;
    final newLkgPayload = _state.activePayloadJson ?? _state.lkgPayloadJson;

    _state = OtaCacheState(
      activeVersion: manifest.version,
      activeReleaseId: manifest.releaseId,
      activePayloadJson: payloadJson,
      lkgVersion: newLkgVersion,
      lkgReleaseId: newLkgReleaseId,
      lkgPayloadJson: newLkgPayload,
    );

    await _saveState();
  }

  /// Rolls back active release to the Last-Known-Good (LKG) release, or version 0 (bundled default).
  Future<bool> rollbackToLkg() async {
    if (_state.lkgVersion == null && _state.activeVersion == 0) {
      return false; // Nothing to rollback to
    }

    _state = OtaCacheState(
      activeVersion: _state.lkgVersion ?? 0,
      activeReleaseId: _state.lkgReleaseId,
      activePayloadJson: _state.lkgPayloadJson,
      lkgVersion: null,
      lkgReleaseId: null,
      lkgPayloadJson: null,
    );

    await _saveState();
    return true;
  }

  /// Resets OTA cache completely to bundled state.
  Future<void> clear() async {
    _state = const OtaCacheState(activeVersion: 0);
    if (await _stateFile.exists()) {
      await _stateFile.delete();
    }
    if (await _payloadsDir.exists()) {
      await _payloadsDir.delete(recursive: true);
    }
    await init();
  }

  Future<void> _saveState() async {
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(_state.toJson()), flush: true);
    if (await _stateFile.exists()) {
      await _stateFile.delete();
    }
    await tmp.rename(_stateFile.path);
  }
}
