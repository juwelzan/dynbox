import 'dart:io';

import 'package:yaml/yaml.dart';

import 'dynbox_config.dart';

/// Represents user-level persistent configuration for DynBox (stored in ~/.dynbox/config.yaml).
class GlobalConfig {
  final String? flutterSdkPath;
  final Map<String, dynamic> rawConfig;

  const GlobalConfig({this.flutterSdkPath, this.rawConfig = const {}});

  /// Resolves the default global DynBox configuration file path.
  /// Honors DYNBOX_GLOBAL_CONFIG_PATH or DYNBOX_CONFIG_DIR if set, otherwise:
  /// - Windows: %LOCALAPPDATA%\DynBox\config.yaml
  /// - macOS/Linux: ~/.dynbox/config.yaml
  static File resolveConfigFile({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;

    final explicitFile = env['DYNBOX_GLOBAL_CONFIG_PATH'];
    if (explicitFile != null && explicitFile.trim().isNotEmpty) {
      return File(explicitFile.trim());
    }

    final explicitDir = env['DYNBOX_CONFIG_DIR'];
    if (explicitDir != null && explicitDir.trim().isNotEmpty) {
      return File('${explicitDir.trim()}/config.yaml');
    }

    if (Platform.isWindows) {
      final localAppData = env['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return File('$localAppData\\DynBox\\config.yaml');
      }
    }

    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return File('$home/.dynbox/config.yaml');
  }

  /// Loads the GlobalConfig from [file]. Returns empty config if file does not exist.
  static GlobalConfig fromFile(File file) {
    if (!file.existsSync()) {
      return const GlobalConfig();
    }

    try {
      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return const GlobalConfig();

      final yaml = loadYaml(content);
      if (yaml is! YamlMap && yaml is! Map) {
        return const GlobalConfig();
      }

      String? sdkPath;
      final sdk = yaml['sdk'];
      if (sdk is Map || sdk is YamlMap) {
        final flutter = sdk['flutter'];
        if (flutter is Map || flutter is YamlMap) {
          final p = flutter['path'];
          if (p is String && p.trim().isNotEmpty) {
            sdkPath = p.trim();
          }
        }
      }

      // Legacy or flat fallback: flutter_root or flutterSdkPath
      if (sdkPath == null) {
        final flatPath = yaml['flutter-root'] ?? yaml['flutter_sdk_path'];
        if (flatPath is String && flatPath.trim().isNotEmpty) {
          sdkPath = flatPath.trim();
        }
      }

      final raw = <String, dynamic>{};
      yaml.forEach((k, v) {
        raw[k.toString()] = v;
      });

      return GlobalConfig(flutterSdkPath: sdkPath, rawConfig: raw);
    } catch (_) {
      // Return safe fallback if file is corrupted/unreadable
      return const GlobalConfig();
    }
  }

  /// Sets a configuration key and persists safely to [file].
  static void setKey({
    required File file,
    required String key,
    required String value,
  }) {
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Read existing content if any
    var content = file.existsSync() ? file.readAsStringSync() : '';
    dynamic existing;
    try {
      existing = content.trim().isNotEmpty ? loadYaml(content) : null;
    } catch (_) {
      existing = null;
    }

    final map = <String, dynamic>{};
    if (existing is Map || existing is YamlMap) {
      existing.forEach((k, v) {
        map[k.toString()] = v;
      });
    }

    if (key == 'flutter-root' ||
        key == 'flutter_root' ||
        key == 'sdk.flutter.path') {
      final sdkMap = Map<String, dynamic>.from(
        (map['sdk'] is Map || map['sdk'] is YamlMap) ? (map['sdk'] as Map) : {},
      );
      final flutterMap = Map<String, dynamic>.from(
        (sdkMap['flutter'] is Map || sdkMap['flutter'] is YamlMap)
            ? (sdkMap['flutter'] as Map)
            : {},
      );
      flutterMap['path'] = value.trim();
      flutterMap['source'] = 'local';
      sdkMap['flutter'] = flutterMap;
      map['sdk'] = sdkMap;
    } else {
      map[key] = value.trim();
    }

    final buffer = StringBuffer();
    buffer.writeln('# DynBox Global Configuration');
    buffer.writeln('configVersion: ${DynboxConfig.currentVersion}');

    // Serialize map safely
    void writeYaml(Map<String, dynamic> m, int indent) {
      final prefix = '  ' * indent;
      for (final entry in m.entries) {
        if (entry.key == 'configVersion') continue;
        if (entry.value is Map) {
          buffer.writeln('$prefix${entry.key}:');
          writeYaml(Map<String, dynamic>.from(entry.value as Map), indent + 1);
        } else {
          buffer.writeln('$prefix${entry.key}: ${entry.value}');
        }
      }
    }

    writeYaml(map, 0);

    // Atomic write
    final tmpFile = File('${file.path}.tmp');
    tmpFile.writeAsStringSync(buffer.toString());
    tmpFile.renameSync(file.path);
  }

  /// Removes a key from [file].
  static void removeKey({required File file, required String key}) {
    if (!file.existsSync()) return;

    final content = file.readAsStringSync();
    dynamic existing;
    try {
      existing = content.trim().isNotEmpty ? loadYaml(content) : null;
    } catch (_) {
      existing = null;
    }

    if (existing is! Map && existing is! YamlMap) return;

    final map = <String, dynamic>{};
    existing.forEach((k, v) {
      map[k.toString()] = v;
    });

    if (key == 'flutter-root' ||
        key == 'flutter_root' ||
        key == 'sdk.flutter.path') {
      if (map.containsKey('sdk')) {
        final sdk = map['sdk'];
        if (sdk is Map || sdk is YamlMap) {
          final sdkMap = Map<String, dynamic>.from(sdk as Map);
          sdkMap.remove('flutter');
          if (sdkMap.isEmpty) {
            map.remove('sdk');
          } else {
            map['sdk'] = sdkMap;
          }
        }
      }
      map.remove('flutter-root');
      map.remove('flutter_root');
    } else {
      map.remove(key);
    }

    final buffer = StringBuffer();
    buffer.writeln('# DynBox Global Configuration');
    buffer.writeln('configVersion: ${DynboxConfig.currentVersion}');

    void writeYaml(Map<String, dynamic> m, int indent) {
      final prefix = '  ' * indent;
      for (final entry in m.entries) {
        if (entry.key == 'configVersion') continue;
        if (entry.value is Map) {
          buffer.writeln('$prefix${entry.key}:');
          writeYaml(Map<String, dynamic>.from(entry.value as Map), indent + 1);
        } else {
          buffer.writeln('$prefix${entry.key}: ${entry.value}');
        }
      }
    }

    writeYaml(map, 0);

    final tmpFile = File('${file.path}.tmp');
    tmpFile.writeAsStringSync(buffer.toString());
    tmpFile.renameSync(file.path);
  }
}
