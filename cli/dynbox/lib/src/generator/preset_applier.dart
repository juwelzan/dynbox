import 'dart:io';

/// Architecture presets supported by DynBox during project creation.
enum ArchitecturePreset {
  minimal('minimal'),
  layered('layered'),
  featureFirst('feature_first');

  final String name;
  const ArchitecturePreset(this.name);

  static ArchitecturePreset parse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final preset in ArchitecturePreset.values) {
      if (preset.name == normalized) {
        return preset;
      }
    }
    throw ArgumentError.value(
      value,
      'preset',
      'Unknown preset "$value". Supported presets: ${ArchitecturePreset.values.map((p) => p.name).join(', ')}',
    );
  }
}

/// Applies an architecture preset to a newly scaffolded Flutter project directory.
class PresetApplier {
  const PresetApplier();

  /// Applies the specified preset to [projectDir].
  Future<void> applyPreset({
    required Directory projectDir,
    required ArchitecturePreset preset,
    required String projectName,
  }) async {
    final libDir = Directory('${projectDir.path}/lib');
    if (!libDir.existsSync()) {
      throw StateError(
        'Cannot apply preset: "lib/" directory does not exist in ${projectDir.path}',
      );
    }

    switch (preset) {
      case ArchitecturePreset.minimal:
        // Keep official Flutter starter structure without modification
        break;

      case ArchitecturePreset.layered:
        await _applyLayered(libDir, projectName);
        break;

      case ArchitecturePreset.featureFirst:
        await _applyFeatureFirst(libDir, projectName);
        break;
    }
  }

  Future<void> _applyLayered(Directory libDir, String projectName) async {
    Directory('${libDir.path}/app').createSync(recursive: true);
    Directory('${libDir.path}/core').createSync(recursive: true);
    Directory('${libDir.path}/features').createSync(recursive: true);

    // Documented structure indicator
    final readme = File('${libDir.path}/STRUCTURE.md');
    readme.writeAsStringSync('''# Layered Architecture ($projectName)

This project follows DynBox's `layered` architecture preset:

- `lib/app/`: Application entry, routing, and top-level theme configurations.
- `lib/core/`: Reusable utilities, shared constants, network clients, and foundation logic.
- `lib/features/`: Domain-oriented feature modules containing UI, state, and domain entities.
''');
  }

  Future<void> _applyFeatureFirst(Directory libDir, String projectName) async {
    Directory('${libDir.path}/app').createSync(recursive: true);
    Directory('${libDir.path}/core').createSync(recursive: true);
    Directory('${libDir.path}/features/home/presentation')
        .createSync(recursive: true);

    final readme = File('${libDir.path}/STRUCTURE.md');
    readme.writeAsStringSync('''# Feature-First Architecture ($projectName)

This project follows DynBox's `feature_first` architecture preset:

- `lib/app/`: Core application setup and global configuration.
- `lib/core/`: Application-wide cross-cutting logic and utilities.
- `lib/features/`: Self-contained features (e.g. `features/home/presentation/`) bundling their own domain, state, and UI.
''');
  }
}
