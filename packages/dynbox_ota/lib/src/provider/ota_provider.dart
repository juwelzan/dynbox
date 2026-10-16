import 'dart:convert';
import 'dart:io';

import '../models/ota_manifest.dart';

/// Contract for update-server communications.
abstract class OtaServerProvider {
  /// Queries the provider for the latest release manifest for the given app and channel.
  /// Returns `null` if no compatible update is available.
  Future<OtaManifest?> checkForUpdate({
    required String appId,
    required String channel,
    required String appVersion,
    required String platform,
  });

  /// Downloads payload bytes from a manifest specification.
  Future<List<int>> downloadPayload(OtaManifest manifest);
}

/// In-memory mock server provider for deterministic offline execution and testing.
class MockOtaServerProvider implements OtaServerProvider {
  OtaManifest? activeManifest;
  String? payloadContent;
  bool shouldFail;
  String failureMessage;

  MockOtaServerProvider({
    this.activeManifest,
    this.payloadContent,
    this.shouldFail = false,
    this.failureMessage = 'Mock server connection error',
  });

  void stageRelease({required OtaManifest manifest, required String payload}) {
    activeManifest = manifest;
    payloadContent = payload;
    shouldFail = false;
  }

  void clearRelease() {
    activeManifest = null;
    payloadContent = null;
  }

  @override
  Future<OtaManifest?> checkForUpdate({
    required String appId,
    required String channel,
    required String appVersion,
    required String platform,
  }) async {
    if (shouldFail) {
      throw HttpException(failureMessage);
    }
    if (activeManifest == null) return null;

    // Verify appId and channel
    if (activeManifest!.appId != appId) return null;
    if (activeManifest!.channel.value != channel) return null;
    if (activeManifest!.platform != OtaPlatform.all &&
        activeManifest!.platform.value != platform) {
      return null;
    }

    return activeManifest;
  }

  @override
  Future<List<int>> downloadPayload(OtaManifest manifest) async {
    if (shouldFail) {
      throw HttpException(failureMessage);
    }
    if (payloadContent != null) {
      return utf8.encode(payloadContent!);
    }
    if (manifest.payloadJson != null) {
      return utf8.encode(manifest.payloadJson!);
    }
    throw const HttpException('Payload not available in mock provider');
  }
}

/// HTTP/REST implementation of [OtaServerProvider] following the DynBox OTA Server specification.
class HttpOtaServerProvider implements OtaServerProvider {
  final String serverBaseUrl;
  final Duration timeout;
  final Map<String, String>? customHeaders;

  HttpOtaServerProvider({
    required this.serverBaseUrl,
    this.timeout = const Duration(seconds: 10),
    this.customHeaders,
  });

  @override
  Future<OtaManifest?> checkForUpdate({
    required String appId,
    required String channel,
    required String appVersion,
    required String platform,
  }) async {
    final queryParams = {
      'appId': appId,
      'channel': channel,
      'appVersion': appVersion,
      'platform': platform,
    };

    final uri = Uri.parse('$serverBaseUrl/api/v1/ota/check')
        .replace(queryParameters: queryParams);

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      customHeaders?.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 204) {
        // 204 No Content -> Up to date
        return null;
      }
      if (response.statusCode != 200) {
        throw HttpException(
          'OTA server returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final body = await response.transform(const Utf8Decoder()).join();
      return OtaManifest.fromString(body);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<int>> downloadPayload(OtaManifest manifest) async {
    if (manifest.payloadJson != null) {
      return utf8.encode(manifest.payloadJson!);
    }

    final urlStr = manifest.payloadUrl;
    if (urlStr == null) {
      throw const HttpException('Manifest missing payloadUrl and payloadJson');
    }

    final uri = Uri.parse(urlStr);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      customHeaders?.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download OTA payload (HTTP ${response.statusCode})',
          uri: uri,
        );
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > manifest.payloadSizeBytes) {
          throw const HttpException(
            'Downloaded payload exceeded manifest sizeBytes limit',
          );
        }
      }
      return bytes;
    } finally {
      client.close();
    }
  }
}
