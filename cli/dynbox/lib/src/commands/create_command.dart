import 'dart:io';

import 'package:args/command_runner.dart';

import '../generator/preset_applier.dart';
import '../generator/project_generator.dart';

class CreateCommand extends Command<int> {
  @override
  final String name = 'create';

  @override
  final String description =
      'Create a new Flutter application using the explicitly pinned Flutter SDK and architecture preset.';

  final ProjectGenerator generator;

  CreateCommand({ProjectGenerator? generator})
    : generator = generator ?? ProjectGenerator() {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Parent directory where the project will be created (defaults to current directory).',
      )
      ..addOption(
        'flutter-root',
        help: 'Explicit Flutter SDK directory override for this command.',
      )
      ..addOption(
        'org',
        defaultsTo: 'com.example',
        help: 'Organization reverse-domain identifier (e.g. com.example).',
      )
      ..addOption(
        'platforms',
        defaultsTo: 'android,ios',
        help: 'Comma-separated target platforms (android,ios,web,linux,macos,windows).',
      )
      ..addOption(
        'preset',
        defaultsTo: 'minimal',
        allowed: ArchitecturePreset.values.map((p) => p.name).toList(),
        help: 'Architecture preset to apply (minimal, layered, feature_first).',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException(
        'Missing project name. Usage: dynbox create <project-name>',
        usage,
      );
    }

    final projectName = rest.first.trim();
    final parentDir = argResults?['path'] as String?;
    final flutterRoot = argResults?['flutter-root'] as String?;
    final org = argResults?['org'] as String? ?? 'com.example';
    final platformsRaw = argResults?['platforms'] as String? ?? 'android,ios';
    final presetName = argResults?['preset'] as String? ?? 'minimal';

    final platforms = platformsRaw
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    ArchitecturePreset preset;
    try {
      preset = ArchitecturePreset.parse(presetName);
    } catch (e) {
      stderr.writeln('Error: $e');
      return 64;
    }

    final options = CreateProjectOptions(
      projectName: projectName,
      parentDirectory: parentDir,
      organization: org,
      platforms: platforms,
      preset: preset,
      explicitSdkPath: flutterRoot,
    );

    stdout.writeln('Creating DynBox project "$projectName"...');
    stdout.writeln('  Preset: ${preset.name}');
    stdout.writeln('  Platforms: ${platforms.join(', ')}');
    stdout.writeln('  Organization: $org');

    try {
      final targetDir = await generator.generate(options);

      stdout.writeln();
      stdout.writeln('✓ Successfully created project at: ${targetDir.path}');
      stdout.writeln();
      stdout.writeln('Next steps:');
      stdout.writeln('  cd ${targetDir.path}');
      stdout.writeln('  dynbox doctor');
      return 0;
    } on ProjectCreationException catch (e) {
      stderr.writeln();
      stderr.writeln('✗ Project creation failed during stage [${e.stage}]:');
      stderr.writeln('  ${e.message}');
      if (e.projectPath != null) {
        stderr.writeln('  Location: ${e.projectPath}');
      }
      if (e.details != null && e.details!.isNotEmpty) {
        stderr.writeln('  Details:\n${e.details}');
      }
      return 1;
    } catch (e) {
      stderr.writeln('✗ Unexpected error: $e');
      return 1;
    }
  }
}
