import 'dart:convert';

/// Deployment channel for DynBox OTA updates.
enum OtaChannel {
  development('development'),
  staging('staging'),
  production('production');

  final String value;
  const OtaChannel(this.value);

  static OtaChannel parse(String val) {
    final lower = val.toLowerCase().trim();
    for (final ch in OtaChannel.values) {
      if (ch.value == lower) return ch;
    }
    throw ArgumentError(
      'Unsupported OTA channel "$val". Supported channels: development, staging, production',
    );
  }
}

/// Target operating system platform for an update.
enum OtaPlatform {
  all('all'),
  android('android'),
  ios('ios'),
  macos('macos'),
  linux('linux'),
  windows('windows'),
  web('web');

  final String value;
  const OtaPlatform(this.value);

  static OtaPlatform parse(String val) {
    final lower = val.toLowerCase().trim();
    for (final p in OtaPlatform.values) {
      if (p.value == lower) return p;
    }
    return OtaPlatform.all;
  }
}

/// Exception thrown when manifest parsing or validation fails.
class OtaManifestException implements Exception {
  final String message;
  const OtaManifestException(this.message);

  @override
  String toString() => 'OtaManifestException: $message';
}

/// Versioned DynBox OTA release manifest.
class OtaManifest {
  final String schemaVersion;
  final String appId;
  final String releaseId;
  final int version;
  final OtaChannel channel;
  final OtaPlatform platform;
  final String minAppVersion;
  final String runtimeSchemaVersion;
  final String? payloadUrl;
  final String? payloadJson;
  final String payloadSha256;
  final int payloadSizeBytes;
  final DateTime publishedAt;
  final DateTime? expiresAt;
  final String? keyId;
  final String? signature;

  const OtaManifest({
    required this.schemaVersion,
    required this.appId,
    required this.releaseId,
    required this.version,
    required this.channel,
    required this.platform,
    required this.minAppVersion,
    required this.runtimeSchemaVersion,
    this.payloadUrl,
    this.payloadJson,
    required this.payloadSha256,
    required this.payloadSizeBytes,
    required this.publishedAt,
    this.expiresAt,
    this.keyId,
    this.signature,
  });

  factory OtaManifest.fromJson(Map<String, dynamic> json) {
    final schemaVer = json['schemaVersion'] as String? ?? '1.0';
    if (schemaVer != '1.0') {
      throw OtaManifestException(
        'Unsupported manifest schemaVersion "$schemaVer"',
      );
    }

    final appId = json['appId'] as String?;
    if (appId == null || appId.trim().isEmpty) {
      throw const OtaManifestException('Missing or empty "appId" in manifest');
    }

    final releaseId = json['releaseId'] as String?;
    if (releaseId == null || releaseId.trim().isEmpty) {
      throw const OtaManifestException(
        'Missing or empty "releaseId" in manifest',
      );
    }

    final version = json['version'] as int?;
    if (version == null || version < 1) {
      throw const OtaManifestException(
        'Missing or invalid "version" (must be >= 1)',
      );
    }

    final channelStr = json['channel'] as String? ?? 'production';
    final platformStr = json['platform'] as String? ?? 'all';
    final minAppVer = json['minAppVersion'] as String? ?? '1.0.0';
    final runtimeSchema = json['runtimeSchemaVersion'] as String? ?? '1.0';

    final payloadSha256 = (json['payloadSha256'] as String?)
        ?.toLowerCase()
        .trim();
    if (payloadSha256 == null || payloadSha256.length != 64) {
      throw const OtaManifestException(
        'Invalid or missing "payloadSha256" (must be 64-char hex)',
      );
    }

    final payloadSize = json['payloadSizeBytes'] as int? ?? 0;
    if (payloadSize <= 0 || payloadSize > 524288) {
      throw const OtaManifestException(
        'Invalid "payloadSizeBytes" (must be 1..524288 bytes)',
      );
    }

    final publishedAtStr = json['publishedAt'] as String?;
    if (publishedAtStr == null) {
      throw const OtaManifestException('Missing "publishedAt" timestamp');
    }
    final publishedAt = DateTime.parse(publishedAtStr);

    DateTime? expiresAt;
    if (json['expiresAt'] != null) {
      expiresAt = DateTime.parse(json['expiresAt'] as String);
    }

    return OtaManifest(
      schemaVersion: schemaVer,
      appId: appId,
      releaseId: releaseId,
      version: version,
      channel: OtaChannel.parse(channelStr),
      platform: OtaPlatform.parse(platformStr),
      minAppVersion: minAppVer,
      runtimeSchemaVersion: runtimeSchema,
      payloadUrl: json['payloadUrl'] as String?,
      payloadJson: json['payloadJson'] as String?,
      payloadSha256: payloadSha256,
      payloadSizeBytes: payloadSize,
      publishedAt: publishedAt,
      expiresAt: expiresAt,
      keyId: json['keyId'] as String?,
      signature: json['signature'] as String?,
    );
  }

  factory OtaManifest.fromString(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const OtaManifestException(
        'Manifest content must be a JSON object',
      );
    }
    return OtaManifest.fromJson(decoded);
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'appId': appId,
    'releaseId': releaseId,
    'version': version,
    'channel': channel.value,
    'platform': platform.value,
    'minAppVersion': minAppVersion,
    'runtimeSchemaVersion': runtimeSchemaVersion,
    if (payloadUrl != null) 'payloadUrl': payloadUrl,
    if (payloadJson != null) 'payloadJson': payloadJson,
    'payloadSha256': payloadSha256,
    'payloadSizeBytes': payloadSizeBytes,
    'publishedAt': publishedAt.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (keyId != null) 'keyId': keyId,
    if (signature != null) 'signature': signature,
  };
}
