import 'dart:io';

import 'package:yaml/yaml.dart';

/// Exception thrown when DynBox configuration is malformed or invalid.
class ConfigException implements Exception {
  final String message;
  final String? path;

  const ConfigException(this.message, [this.path]);

  @override
  String toString() {
    if (path != null) {
      return 'ConfigException at $path: $message';
    }
    return 'ConfigException: $message';
  }
}

/// Project kinds supported by DynBox.
enum ProjectKind {
  flutterApp('flutter_app'),
  flutterPackage('flutter_package'),
  flutterPlugin('flutter_plugin');

  final String value;
  const ProjectKind(this.value);

  static ProjectKind parse(String val) {
    for (final kind in ProjectKind.values) {
      if (kind.value == val) return kind;
    }
    throw ConfigException(
      'Unsupported project kind "$val". Supported kinds: ${ProjectKind.values.map((k) => k.value).join(', ')}',
    );
  }
}

/// Backend provider kinds supported by DynBox.
enum BackendProviderKind {
  none('none'),
  firebase('firebase'),
  supabase('supabase');

  final String value;
  const BackendProviderKind(this.value);

  static BackendProviderKind parse(String val) {
    for (final p in BackendProviderKind.values) {
      if (p.value == val) return p;
    }
    throw ConfigException(
      'Unsupported backend provider "$val". Supported providers: ${BackendProviderKind.values.map((k) => k.value).join(', ')}',
    );
  }
}

/// Immutable typed model for project metadata.
class ProjectConfig {
  final String name;
  final ProjectKind kind;
  final String? description;

  const ProjectConfig({
    required this.name,
    required this.kind,
    this.description,
  });

  static final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  factory ProjectConfig.fromYaml(dynamic yaml) {
    if (yaml is! YamlMap && yaml is! Map) {
      throw const ConfigException(
        'Expected "project" section to be a map/dictionary.',
      );
    }

    final name = yaml['name'];
    if (name == null || name is! String || name.trim().isEmpty) {
      throw const ConfigException('Missing or invalid "project.name".');
    }
    if (!_namePattern.hasMatch(name.trim())) {
      throw ConfigException(
        'Invalid "project.name": "$name". Must match ${_namePattern.pattern} (lowercase alphanumeric and underscores, beginning with a letter).',
      );
    }

    final kindStr = yaml['kind'];
    if (kindStr == null || kindStr is! String) {
      throw const ConfigException('Missing or invalid "project.kind".');
    }
    final kind = ProjectKind.parse(kindStr.trim());

    final description = yaml['description'] as String?;

    return ProjectConfig(
      name: name.trim(),
      kind: kind,
      description: description?.trim(),
    );
  }
}

/// Immutable typed model for Flutter SDK configuration.
class FlutterSdkConfig {
  final String source;
  final String path;
  final String? versionConstraint;

  const FlutterSdkConfig({
    required this.source,
    required this.path,
    this.versionConstraint,
  });

  factory FlutterSdkConfig.fromYaml(
    dynamic yaml, {
    required String workspaceRoot,
  }) {
    if (yaml is! YamlMap && yaml is! Map) {
      throw const ConfigException(
        'Expected "sdk.flutter" section to be a map/dictionary.',
      );
    }

    final source = yaml['source'];
    if (source == null || source != 'local') {
      throw const ConfigException(
        'Invalid or missing "sdk.flutter.source". Only "local" is currently supported.',
      );
    }

    final rawPath = yaml['path'];
    if (rawPath == null || rawPath is! String || rawPath.trim().isEmpty) {
      throw const ConfigException(
        'Missing or empty "sdk.flutter.path". An explicit path is required.',
      );
    }

    final trimmedPath = rawPath.trim();
    // Resolve relative path against workspaceRoot
    String resolvedPath;
    if (trimmedPath.startsWith('/') ||
        (Platform.isWindows && RegExp(r'^[a-zA-Z]:\\').hasMatch(trimmedPath))) {
      resolvedPath = trimmedPath;
    } else {
      resolvedPath = '$workspaceRoot/$trimmedPath';
    }

    final versionConstraint = yaml['versionConstraint'] as String?;

    return FlutterSdkConfig(
      source: source as String,
      path: resolvedPath,
      versionConstraint: versionConstraint?.trim(),
    );
  }
}

/// Immutable typed model for backend configuration.
class BackendConfig {
  final BackendProviderKind provider;
  final Map<String, dynamic> providerConfig;

  const BackendConfig({required this.provider, this.providerConfig = const {}});

  factory BackendConfig.fromYaml(dynamic yaml) {
    if (yaml is! YamlMap && yaml is! Map) {
      throw const ConfigException(
        'Expected "backend" section to be a map/dictionary.',
      );
    }

    final providerStr = yaml['provider'];
    if (providerStr == null || providerStr is! String) {
      throw const ConfigException('Missing or invalid "backend.provider".');
    }
    final provider = BackendProviderKind.parse(providerStr.trim());

    final configMap = <String, dynamic>{};
    if (provider == BackendProviderKind.firebase && yaml['firebase'] is Map) {
      configMap['firebase'] = Map<String, dynamic>.from(
        yaml['firebase'] as Map,
      );
    } else if (provider == BackendProviderKind.supabase &&
        yaml['supabase'] is Map) {
      configMap['supabase'] = Map<String, dynamic>.from(
        yaml['supabase'] as Map,
      );
    }

    return BackendConfig(provider: provider, providerConfig: configMap);
  }
}

/// Immutable typed model for OTA configuration.
class OtaConfig {
  final bool enabled;
  final String channel;
  final String? serverUrl;
  final String? publicKey;
  final bool autoActivate;

  const OtaConfig({
    this.enabled = true,
    this.channel = 'production',
    this.serverUrl,
    this.publicKey,
    this.autoActivate = true,
  });

  factory OtaConfig.fromYaml(dynamic yaml) {
    if (yaml == null) return const OtaConfig();
    if (yaml is! YamlMap && yaml is! Map) {
      throw const ConfigException(
        'Expected "ota" section to be a map/dictionary.',
      );
    }

    final enabled = yaml['enabled'] as bool? ?? true;
    final channel = (yaml['channel'] as String?)?.trim() ?? 'production';
    final serverUrl = (yaml['serverUrl'] as String?)?.trim();
    final publicKey = (yaml['publicKey'] as String?)?.trim();
    final autoActivate = yaml['autoActivate'] as bool? ?? true;

    return OtaConfig(
      enabled: enabled,
      channel: channel,
      serverUrl: serverUrl,
      publicKey: publicKey,
      autoActivate: autoActivate,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'channel': channel,
    if (serverUrl != null) 'serverUrl': serverUrl,
    if (publicKey != null) 'publicKey': publicKey,
    'autoActivate': autoActivate,
  };
}

/// Immutable root configuration model for a DynBox workspace.
class DynboxConfig {
  final int configVersion;
  final ProjectConfig project;
  final FlutterSdkConfig flutterSdk;
  final BackendConfig backend;
  final OtaConfig ota;
  final String workspaceRoot;

  const DynboxConfig({
    required this.configVersion,
    required this.project,
    required this.flutterSdk,
    required this.backend,
    this.ota = const OtaConfig(),
    required this.workspaceRoot,
  });

  /// Supported schema / configuration version.
  static const int currentVersion = 1;

  /// Parses and validates a DynBox YAML string.
  factory DynboxConfig.fromYamlString(
    String yamlContent, {
    required String workspaceRoot,
  }) {
    dynamic yaml;
    try {
      yaml = loadYaml(yamlContent);
    } catch (e) {
      throw ConfigException('Failed to parse YAML content: $e');
    }

    if (yaml is! YamlMap && yaml is! Map) {
      throw const ConfigException('Root configuration must be a YAML mapping.');
    }

    // 1. Version check
    final version = yaml['configVersion'];
    if (version == null || version is! int) {
      throw const ConfigException(
        'Missing or invalid "configVersion". Must be an integer.',
      );
    }
    if (version != currentVersion) {
      throw ConfigException(
        'Unsupported configVersion $version. Current supported version is $currentVersion.',
      );
    }

    // 2. Project section
    final project = ProjectConfig.fromYaml(yaml['project']);

    // 3. SDK section
    final sdk = yaml['sdk'];
    if (sdk is! YamlMap && sdk is! Map) {
      throw const ConfigException(
        'Missing or invalid "sdk" section in config.',
      );
    }
    final flutterSdk = FlutterSdkConfig.fromYaml(
      sdk['flutter'],
      workspaceRoot: workspaceRoot,
    );

    // 4. Backend section
    final backendYaml = yaml['backend'];
    final backend = backendYaml != null
        ? BackendConfig.fromYaml(backendYaml)
        : const BackendConfig(provider: BackendProviderKind.none);

    // 5. OTA section
    final otaYaml = yaml['ota'];
    final ota = otaYaml != null
        ? OtaConfig.fromYaml(otaYaml)
        : const OtaConfig();

    return DynboxConfig(
      configVersion: version,
      project: project,
      flutterSdk: flutterSdk,
      backend: backend,
      ota: ota,
      workspaceRoot: workspaceRoot,
    );
  }

  /// Loads and validates configuration from a file.
  static DynboxConfig fromFile(File configFile, {String? workspaceRoot}) {
    if (!configFile.existsSync()) {
      throw ConfigException(
        'Configuration file not found at: ${configFile.path}',
      );
    }

    final root = workspaceRoot ?? configFile.parent.parent.path;
    final content = configFile.readAsStringSync();
    return DynboxConfig.fromYamlString(content, workspaceRoot: root);
  }
}
