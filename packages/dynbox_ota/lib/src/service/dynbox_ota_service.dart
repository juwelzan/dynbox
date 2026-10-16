import 'dart:async';
import 'dart:io';

import 'package:dynbox_ui_runtime/dynbox_ui_runtime.dart';

import '../cache/ota_cache.dart';
import '../client/dynbox_ota_client.dart';
import '../provider/ota_provider.dart';

/// Top-level facade service connecting DynBox OTA update cycles to the Dynamic UI Runtime.
class DynboxOtaService {
  final DynboxOtaClient client;
  final DynamicUiController uiController;

  StreamSubscription<OtaState>? _subscription;

  DynboxOtaService({required this.client, required this.uiController});

  /// Factory creating an OTA service with default or configured storage.
  static Future<DynboxOtaService> create({
    required OtaClientConfig config,
    required DynamicUiController uiController,
    OtaServerProvider? provider,
    Directory? storageDir,
  }) async {
    final effectiveDir =
        storageDir ?? Directory.systemTemp.createTempSync('dynbox_ota_');
    final cache = OtaCache(storageDir: effectiveDir);
    await cache.init();

    final client = DynboxOtaClient(
      config: config,
      provider: provider,
      cache: cache,
    );
    await client.init();

    final service = DynboxOtaService(
      client: client,
      uiController: uiController,
    );
    service._listen();

    // If an active payload exists in cache, activate it into DynamicUiController
    if (client.activePayloadJson != null) {
      await uiController.activateConfigurationJson(client.activePayloadJson!);
    }

    return service;
  }

  void _listen() {
    _subscription = client.stateStream.listen((state) {
      // Stream monitoring for external listeners
    });
  }

  /// Triggers a non-blocking background update check.
  void startBackgroundCheck() {
    // Schedule asynchronously on next microtask so first render is never blocked
    scheduleMicrotask(() async {
      final state = await client.checkForUpdate();
      if (state.status == OtaStatus.updateAvailable) {
        await client.downloadAndVerifyUpdate();
      }
    });
  }

  /// Manual update check.
  Future<OtaState> checkForUpdate() => client.checkForUpdate();

  /// Manual download and verify.
  Future<bool> downloadAndVerify() async {
    final ok = await client.downloadAndVerifyUpdate();
    if (ok && client.activePayloadJson != null) {
      await uiController.activateConfigurationJson(client.activePayloadJson!);
    }
    return ok;
  }

  /// Manual rollback to Last-Known-Good or bundled default.
  Future<bool> rollback() async {
    final ok = await client.rollback();
    if (ok) {
      if (client.activePayloadJson != null) {
        await uiController.activateConfigurationJson(client.activePayloadJson!);
      } else {
        uiController.rollbackToLastKnownGood();
      }
    }
    return ok;
  }

  void dispose() {
    _subscription?.cancel();
    client.dispose();
  }
}
