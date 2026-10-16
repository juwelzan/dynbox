import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../build/build_models.dart';
import '../build/build_orchestrator.dart';

/// CLI Command for orchestrating native Android & iOS builds.
class BuildCommand extends Command<int> {
  @override
  final String name = 'build';

  @override
  final String description =
      'Build native release artifacts (APK, AAB, IPA, archive) for a DynBox Flutter project.';

  final BuildOrchestrator orchestrator;

  BuildCommand({BuildOrchestrator? orchestrator})
    : orchestrator = orchestrator ?? BuildOrchestrator() {
    argParser
      ..addOption(
        'platform',
        abbr: 'p',
        mandatory: true,
        allowed: BuildPlatform.values.map((p) => p.value).toList(),
        help: 'Target operating system platform (android, ios).',
      )
      ..addOption(
        'target',
        abbr: 't',
        mandatory: true,
        allowed: BuildTarget.values.map((t) => t.value).toList(),
        help: 'Target artifact format (apk, appbundle, ipa, archive).',
      )
      ..addOption(
        'mode',
        abbr: 'm',
        defaultsTo: 'release',
        allowed: BuildMode.values.map((m) => m.value).toList(),
        help: 'Build compilation mode (debug, profile, release).',
      )
      ..addOption(
        'flutter-root',
        help: 'Explicit Flutter SDK directory override for this build command.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Validate project, toolchain, and command structure without running the build.',
      )
      ..addFlag(
        'codesign',
        defaultsTo: true,
        help: 'Whether to codesign the output artifact (iOS builds).',
      )
      ..addOption(
        'export-method',
        allowed: ['app-store', 'ad-hoc', 'development', 'enterprise'],
        help: 'iOS IPA export distribution method.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show detailed diagnostic output without exposing secrets.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Output result and diagnostics in structured JSON format.',
      )
      ..addFlag(
        'manifest',
        negatable: false,
        help: 'Generate a machine-readable build manifest (build/dynbox_manifest.json) on successful build.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    final projectPath = rest.isNotEmpty
        ? rest.first.trim()
        : Directory.current.path;
    final projectDir = Directory(projectPath);

    final String platformStr;
    final String targetStr;
    try {
      final p = argResults?['platform'] as String?;
      final t = argResults?['target'] as String?;
      if (p == null || t == null) {
        throw UsageException(
          'Options --platform and --target are mandatory.',
          usage,
        );
      }
      platformStr = p;
      targetStr = t;
    } on ArgumentError catch (e) {
      throw UsageException(e.message.toString(), usage);
    }
    final modeStr = argResults!['mode'] as String;
    final flutterRoot = argResults?['flutter-root'] as String?;
    final dryRun = argResults?['dry-run'] as bool? ?? false;
    final codesign = argResults?['codesign'] as bool? ?? true;
    final exportMethod = argResults?['export-method'] as String?;
    final verbose = argResults?['verbose'] as bool? ?? false;
    final json = argResults?['json'] as bool? ?? false;
    final manifest = argResults?['manifest'] as bool? ?? false;

    final BuildPlatform platform;
    final BuildTarget target;
    final BuildMode mode;

    try {
      platform = BuildPlatform.parse(platformStr);
      target = BuildTarget.parse(targetStr);
      mode = BuildMode.parse(modeStr);
    } catch (e) {
      throw UsageException(e.toString(), usage);
    }

    final options = BuildOptions(
      projectDir: projectDir,
      platform: platform,
      target: target,
      mode: mode,
      flutterRoot: flutterRoot,
      dryRun: dryRun,
      codesign: codesign,
      exportMethod: exportMethod,
      verbose: verbose,
      json: json,
      generateManifest: manifest,
    );

    if (!json) {
      stdout.writeln('DynBox Native Build Orchestrator');
      stdout.writeln('  Project:   ${projectDir.path}');
      stdout.writeln('  Platform:  ${platform.value}');
      stdout.writeln('  Target:    ${target.value}');
      stdout.writeln('  Mode:      ${mode.value}');
      if (dryRun) stdout.writeln('  Dry-run:   Enabled');
      if (manifest) stdout.writeln('  Manifest:  Enabled');
      stdout.writeln('');
    }

    final result = await orchestrator.build(options);

    // If JSON output requested, emit structured JSON directly to stdout
    if (json) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
      return result.isSuccess ? 0 : 1;
    }

    // Verbose diagnostics sent to stderr if requested
    if (verbose && result.diagnostics.isNotEmpty) {
      stderr.writeln('Diagnostics:');
      for (final diag in result.diagnostics) {
        stderr.writeln('  $diag');
      }
      stderr.writeln('');
    }

    if (result.isSuccess) {
      stdout.writeln('✅ ${result.message}');
      if (result.isDryRun) {
        final plan = result.plan;
        if (plan != null) {
          stdout.writeln('   SDK Directory:   ${plan.sdkDirectory}');
          if (plan.sdkVersion != null) {
            stdout.writeln('   SDK Version:     ${plan.sdkVersion}');
          }
          stdout.writeln('   SDK Source:      ${plan.sdkSource}');
          stdout.writeln('   Target Artifact: ${plan.expectedArtifactPath}');
          stdout.writeln(
            '   Planned Command: ${plan.plannedCommand.join(' ')}',
          );
          stdout.writeln(
            '   Signing Config:  ${plan.signingConfigured ? "Configured" : "None"}',
          );
          stdout.writeln('   Verification:    ${plan.verificationCapability}');
        } else {
          stdout.writeln('   Command: ${result.executedArguments.join(' ')}');
        }
      } else if (result.artifact != null) {
        final art = result.artifact!;
        stdout.writeln('   Artifact:   ${art.file.path}');
        stdout.writeln(
          '   Size:       ${(art.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB',
        );
        stdout.writeln('   SHA-256:    ${art.sha256}');
        final sigStatusStr = switch (art.signatureStatus) {
          SignatureStatus.verifiedSigned => 'Verified Signed',
          SignatureStatus.verifiedUnsigned => 'Verified Unsigned',
          SignatureStatus.verificationFailed => 'Verification Failed',
          SignatureStatus.unknown => 'Unknown / Not Verified',
        };
        stdout.writeln(
          '   Signature:  $sigStatusStr${art.signatureDetails != null ? " (${art.signatureDetails})" : ""}',
        );
        stdout.writeln('   Built at:   ${art.modifiedAt.toLocal()}');
        if (result.manifestFile != null) {
          stdout.writeln('   Manifest:   ${result.manifestFile!.path}');
        }
      }
      return 0;
    } else {
      stderr.writeln('❌ Build failed: ${result.message}');
      if (result.actionableError != null) {
        stderr.writeln('');
        stderr.writeln('Details:');
        stderr.writeln(result.actionableError);
      }
      return 1;
    }
  }
}
