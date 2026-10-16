import 'dart:convert';
import 'dart:io';

import '../models/ota_manifest.dart';
import 'ota_provider.dart';

/// Supabase PostgREST & Storage implementation of [OtaServerProvider].
///
/// Communicates securely using the public anonymous key (`anonKey`), respecting
/// Row Level Security (RLS) policies.
///
/// Never requires or accepts `service_role` keys on client mobile apps.
class SupabaseOtaServerProvider implements OtaServerProvider {
  final String supabaseUrl;
  final String anonKey;
  final Duration timeout;
  final HttpClient Function()? clientFactory;

  SupabaseOtaServerProvider({
    required this.supabaseUrl,
    required this.anonKey,
    this.timeout = const Duration(seconds: 10),
    this.clientFactory,
  }) {
    final clean = anonKey.toLowerCase();
    if (clean.contains('service_role') || clean.contains('secret')) {
      throw ArgumentError(
        'Privileged service-role or secret keys are strictly forbidden in client SupabaseOtaServerProvider.',
      );
    }
  }

  HttpClient _createClient() => clientFactory != null ? clientFactory!() : HttpClient();

  @override
  Future<OtaManifest?> checkForUpdate({
    required String appId,
    required String channel,
    required String appVersion,
    required String platform,
  }) async {
    final baseUri = Uri.parse(supabaseUrl);
    // PostgREST query on ota_releases table:
    // GET /rest/v1/ota_releases?app_id=eq.{appId}&channel=eq.{channel}&is_active=eq.true&is_rolled_back=eq.false&order=version.desc&limit=1
    final queryParams = {
      'app_id': 'eq.$appId',
      'channel': 'eq.$channel',
      'is_active': 'eq.true',
      'is_rolled_back': 'eq.false',
      'order': 'version.desc',
      'limit': '1',
    };

    final uri = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}/rest/v1/ota_releases',
      queryParameters: queryParams,
    );

    final client = _createClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set('apikey', anonKey);
      request.headers.set('Authorization', 'Bearer $anonKey');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        throw HttpException(
          'Supabase PostgREST returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final body = await response.transform(const Utf8Decoder()).join();
      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.isEmpty) {
        // No active release found for this app and channel
        return null;
      }

      final record = decoded.first as Map<String, dynamic>;

      // Map Supabase snake_case columns to OtaManifest JSON structure
      final manifestJson = <String, dynamic>{
        'schemaVersion': record['runtime_schema_version'] ?? '1.0',
        'appId': record['app_id'],
        'releaseId': record['release_id'],
        'version': record['version'],
        'channel': record['channel'],
        'platform': record['platform'] ?? 'all',
        'minAppVersion': record['min_app_version'] ?? '1.0.0',
        'runtimeSchemaVersion': record['runtime_schema_version'] ?? '1.0',
        'payloadSha256': record['payload_sha256'],
        'payloadSizeBytes': record['payload_size_bytes'],
        'publishedAt': record['published_at'] ?? DateTime.now().toIso8601String(),
      };

      if (record['payload_url'] != null) {
        manifestJson['payloadUrl'] = record['payload_url'];
      } else if (record['payload_storage_path'] != null) {
        // Construct public Supabase Storage URL: /storage/v1/object/public/ota-payloads/{path}
        final path = record['payload_storage_path'] as String;
        final cleanBase = supabaseUrl.replaceAll(RegExp(r'/+$'), '');
        manifestJson['payloadUrl'] = '$cleanBase/storage/v1/object/public/ota-payloads/$path';
      }

      if (record['payload_json'] != null) {
        manifestJson['payloadJson'] = record['payload_json'];
      }
      if (record['signature'] != null) {
        manifestJson['signature'] = record['signature'];
      }

      final manifest = OtaManifest.fromJson(manifestJson);

      // Verify platform compatibility
      if (manifest.platform != OtaPlatform.all && manifest.platform.value != platform) {
        return null;
      }

      return manifest;
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
    final client = _createClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set('apikey', anonKey);
      request.headers.set('Authorization', 'Bearer $anonKey');

      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download OTA payload from Supabase Storage (HTTP ${response.statusCode})',
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
