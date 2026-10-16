import 'dart:async';
import 'dart:convert';

import '../cache/ota_cache.dart';
import '../models/ota_manifest.dart';
import '../provider/ota_provider.dart';
import '../security/ota_verifier.dart';

/// Status of the DynBox OTA engine.
enum OtaStatus {
  unconfigured,
  idle,
  checking,
  updateAvailable,
  downloading,
  verifying,
  readyToActivate,
  applying,
  upToDate,
  failed,
}

/// Snapshot of the OTA client state.
class OtaState {
  final OtaStatus status;
  final int activeVersion;
  final String? activeReleaseId;
  final OtaManifest? availableManifest;
  final double downloadProgress;
  final String? errorMessage;
  final DateTime lastCheckedAt;

  const OtaState({
    required this.status,
    required this.activeVersion,
    this.activeReleaseId,
    this.availableManifest,
    this.downloadProgress = 0.0,
    this.errorMessage,
    required this.lastCheckedAt,
  });

  OtaState copyWith({
    OtaStatus? status,
    int? activeVersion,
    String? activeReleaseId,
    OtaManifest? availableManifest,
    double? downloadProgress,
    String? errorMessage,
    DateTime? lastCheckedAt,
  }) {
    return OtaState(
      status: status ?? this.status,
      activeVersion: activeVersion ?? this.activeVersion,
      activeReleaseId: activeReleaseId ?? this.activeReleaseId,
      availableManifest: availableManifest ?? this.availableManifest,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// Configuration options for the OTA Client.
class OtaClientConfig {
  final String appId;
  final String appVersion;
  final String channel;
  final String platform;
  final String? verificationKey;
  final bool autoActivate;

  const OtaClientConfig({
    required this.appId,
    required this.appVersion,
    this.channel = 'production',
    this.platform = 'all',
    this.verificationKey,
    this.autoActivate = true,
  });
}

/// Core OTA Client engine managing updates, verification, and persistence.
class DynboxOtaClient {
  final OtaClientConfig config;
  final OtaServerProvider? provider;
  final OtaCache cache;

  final _stateController = StreamController<OtaState>.broadcast();
  Stream<OtaState> get stateStream => _stateController.stream;

  late OtaState _currentState;
  OtaState get currentState => _currentState;

  // Staged payload waiting for activation
  String? _stagedPayloadJson;
  OtaManifest? _stagedManifest;

  DynboxOtaClient({required this.config, this.provider, required this.cache}) {
    _currentState = OtaState(
      status: provider == null ? OtaStatus.unconfigured : OtaStatus.idle,
      activeVersion: cache.state.activeVersion,
      activeReleaseId: cache.state.activeReleaseId,
      lastCheckedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Initializes cache and emits current state.
  Future<void> init() async {
    await cache.init();
    _currentState = _currentState.copyWith(
      activeVersion: cache.state.activeVersion,
      activeReleaseId: cache.state.activeReleaseId,
    );
    _emit(_currentState);
  }

  void _emit(OtaState state) {
    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  /// Checks for available updates asynchronously.
  Future<OtaState> checkForUpdate() async {
    if (provider == null) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.unconfigured,
          errorMessage: 'No OTA server provider configured',
          lastCheckedAt: DateTime.now(),
        ),
      );
      return _currentState;
    }

    _emit(
      _currentState.copyWith(
        status: OtaStatus.checking,
        errorMessage: null,
        lastCheckedAt: DateTime.now(),
      ),
    );

    try {
      final manifest = await provider!.checkForUpdate(
        appId: config.appId,
        channel: config.channel,
        appVersion: config.appVersion,
        platform: config.platform,
      );

      if (manifest == null) {
        _emit(
          _currentState.copyWith(
            status: OtaStatus.upToDate,
            availableManifest: null,
          ),
        );
        return _currentState;
      }

      // Check version progression (must be strictly greater than current active)
      if (manifest.version <= _currentState.activeVersion) {
        _emit(
          _currentState.copyWith(
            status: OtaStatus.upToDate,
            availableManifest: null,
          ),
        );
        return _currentState;
      }

      // Check app version compatibility (simple semver check or minAppVersion)
      if (!_isVersionCompatible(config.appVersion, manifest.minAppVersion)) {
        _emit(
          _currentState.copyWith(
            status: OtaStatus.failed,
            errorMessage:
                'Update requires app version ${manifest.minAppVersion} (current: ${config.appVersion})',
          ),
        );
        return _currentState;
      }

      // Check expiry if set
      if (manifest.expiresAt != null &&
          manifest.expiresAt!.isBefore(DateTime.now())) {
        _emit(
          _currentState.copyWith(
            status: OtaStatus.failed,
            errorMessage: 'Manifest expired at ${manifest.expiresAt}',
          ),
        );
        return _currentState;
      }

      _emit(
        _currentState.copyWith(
          status: OtaStatus.updateAvailable,
          availableManifest: manifest,
        ),
      );
      return _currentState;
    } catch (e) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.failed,
          errorMessage: 'Check update failed: $e',
        ),
      );
      return _currentState;
    }
  }

  /// Downloads and verifies the payload for [manifest].
  Future<bool> downloadAndVerifyUpdate({OtaManifest? targetManifest}) async {
    final manifest = targetManifest ?? _currentState.availableManifest;
    if (manifest == null) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.failed,
          errorMessage: 'No manifest available to download',
        ),
      );
      return false;
    }

    if (provider == null) {
      _emit(_currentState.copyWith(status: OtaStatus.unconfigured));
      return false;
    }

    _emit(
      _currentState.copyWith(
        status: OtaStatus.downloading,
        downloadProgress: 0.1,
      ),
    );

    try {
      final bytes = await provider!.downloadPayload(manifest);
      _emit(
        _currentState.copyWith(
          status: OtaStatus.downloading,
          downloadProgress: 1.0,
        ),
      );

      _emit(_currentState.copyWith(status: OtaStatus.verifying));

      // 1. Verify size limit
      if (bytes.length > manifest.payloadSizeBytes) {
        throw const OtaManifestException(
          'Payload size exceeds manifest declared payloadSizeBytes',
        );
      }

      // 2. Verify SHA-256 Digest
      if (!OtaVerifier.verifyDigest(bytes, manifest.payloadSha256)) {
        throw const OtaManifestException(
          'Payload SHA-256 digest mismatch. Potential tampering detected.',
        );
      }

      // 3. Verify Signature if key is configured
      if (config.verificationKey != null && manifest.signature != null) {
        final payloadString = utf8.decode(bytes);
        final isValid = OtaVerifier.verifySignature(
          data: payloadString,
          signature: manifest.signature!,
          secretOrPublicKey: config.verificationKey!,
        );
        if (!isValid) {
          throw const OtaManifestException(
            'Cryptographic signature verification failed.',
          );
        }
      }

      final payloadString = utf8.decode(bytes);
      // 4. Verify JSON schema syntax
      final decoded = jsonDecode(payloadString);
      if (decoded is! Map<String, dynamic>) {
        throw const OtaManifestException('Payload is not valid JSON map');
      }

      // Stage in cache
      await cache.stagePayload(
        releaseId: manifest.releaseId,
        payloadBytes: bytes,
      );

      _stagedPayloadJson = payloadString;
      _stagedManifest = manifest;

      if (config.autoActivate) {
        return await activateUpdate();
      } else {
        _emit(_currentState.copyWith(status: OtaStatus.readyToActivate));
        return true;
      }
    } catch (e) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.failed,
          errorMessage: 'Download/verify failed: $e',
        ),
      );
      return false;
    }
  }

  /// Activates the staged release.
  Future<bool> activateUpdate() async {
    if (_stagedPayloadJson == null || _stagedManifest == null) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.failed,
          errorMessage: 'No staged update to activate',
        ),
      );
      return false;
    }

    _emit(_currentState.copyWith(status: OtaStatus.applying));

    try {
      await cache.activateRelease(
        manifest: _stagedManifest!,
        payloadJson: _stagedPayloadJson!,
      );

      _emit(
        _currentState.copyWith(
          status: OtaStatus.upToDate,
          activeVersion: _stagedManifest!.version,
          activeReleaseId: _stagedManifest!.releaseId,
          availableManifest: null,
        ),
      );

      _stagedPayloadJson = null;
      _stagedManifest = null;
      return true;
    } catch (e) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.failed,
          errorMessage: 'Activation failed: $e',
        ),
      );
      return false;
    }
  }

  /// Rolls back to Last-Known-Good version.
  Future<bool> rollback() async {
    _emit(_currentState.copyWith(status: OtaStatus.applying));
    final ok = await cache.rollbackToLkg();
    if (ok) {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.idle,
          activeVersion: cache.state.activeVersion,
          activeReleaseId: cache.state.activeReleaseId,
          availableManifest: null,
        ),
      );
      return true;
    } else {
      _emit(
        _currentState.copyWith(
          status: OtaStatus.failed,
          errorMessage: 'No previous Last-Known-Good release to rollback to',
        ),
      );
      return false;
    }
  }

  /// Retries the last operation (check or download).
  Future<void> retry() async {
    if (_currentState.availableManifest != null) {
      await downloadAndVerifyUpdate();
    } else {
      await checkForUpdate();
    }
  }

  String? get activePayloadJson => cache.state.activePayloadJson;

  bool _isVersionCompatible(String currentAppVersion, String minAppVersion) {
    // Basic comparison; assumes clean semver "x.y.z"
    try {
      final currentParts = currentAppVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final minParts = minAppVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      while (currentParts.length < 3) currentParts.add(0);
      while (minParts.length < 3) minParts.add(0);

      for (var i = 0; i < 3; i++) {
        if (currentParts[i] > minParts[i]) return true;
        if (currentParts[i] < minParts[i]) return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  void dispose() {
    _stateController.close();
  }
}
