import 'dart:convert';
import 'dart:io';

import '../sdk/flutter_sdk_runner.dart';
import '../sdk/safe_process_executor.dart';
import '../sdk/sdk_resolver.dart';
import 'build_models.dart';
import 'build_validator.dart';

/// Orchestrates Flutter native build execution without arbitrary shell commands.
class BuildOrchestrator {
  final BuildValidator validator;
  final SdkResolver sdkResolver;
  final SafeProcessExecutor executor;

  BuildOrchestrator({
    BuildValidator? validator,
    SdkResolver? sdkResolver,
    SafeProcessExecutor? executor,
  }) : validator = validator ?? BuildValidator(executor: executor),
       sdkResolver = sdkResolver ?? SdkResolver(),
       executor = executor ?? SafeProcessExecutor();

  /// Executes or simulates a build based on [options].
  Future<BuildResult> build(BuildOptions options) async {
    final startTime = DateTime.now();
    final diagnostics = <String>[];
    void logDiag(String msg) {
      if (options.verbose) {
        diagnostics.add('[${DateTime.now().toIso8601String()}] $msg');
      }
    }

    logDiag(
      'Starting build orchestration for ${options.platform.value} ${options.target.value} (${options.mode.value}).',
    );

    // 1. Target and platform compatibility check
    try {
      options.validatePlatformCompatibility();
      logDiag('Platform/target compatibility validated.');
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Invalid platform/target configuration: $e',
        actionableError: 'Specify a compatible --platform and --target (Android: apk, appbundle; iOS: ipa, archive).',
        diagnostics: diagnostics,
      );
    }

    // 2. Validate project structure and .dynbox/config.yaml
    final projectDir = options.projectDir;
    try {
      validator.validateProject(projectDir);
      logDiag('Project directory structure and .dynbox/config.yaml validated.');
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Project validation failed: $e',
        actionableError: 'Ensure the project directory exists and contains pubspec.yaml and a valid .dynbox/config.yaml.',
        diagnostics: diagnostics,
      );
    }

    // 3. Output directory write permission check
    try {
      validator.validateOutputDirectory(projectDir);
      logDiag('Output directory permissions validated.');
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Output directory permission failure: $e',
        actionableError:
            'Ensure user has write permissions to "${projectDir.path}/build".',
        diagnostics: diagnostics,
      );
    }

    // 4. Resolve pinned SDK
    PinnedSdk pinnedSdk;
    try {
      final configFile = File('${projectDir.path}/.dynbox/config.yaml');
      pinnedSdk = sdkResolver.resolve(
        cliArgument: options.flutterRoot,
        configFile: configFile,
        workspaceRoot: projectDir.path,
      );
      logDiag(
        'Resolved pinned Flutter SDK: ${pinnedSdk.sdkDirectory} (source: ${pinnedSdk.source}, version: ${pinnedSdk.version ?? "unknown"}).',
      );
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Failed to resolve pinned Flutter SDK: $e',
        actionableError: 'Specify --flutter-root or configure sdk.flutter.path in .dynbox/config.yaml.',
        diagnostics: diagnostics,
      );
    }

    // 5. Validate host platform and tools
    try {
      await validator.validateHostTools(options.platform);
      logDiag('Host platform and primary build tools validated.');
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Host build environment validation failed: $e',
        actionableError: options.platform == BuildPlatform.android
            ? 'Install Java Development Kit (JDK) and ensure "java" is available in PATH.'
            : 'Ensure you are running on macOS with Xcode and "xcodebuild" installed.',
        diagnostics: diagnostics,
      );
    }

    // 6. Inspect toolchain prerequisites, signing configuration, and verification capabilities
    final toolchainPrerequisites = <String, bool>{};
    bool signingConfigured = false;
    String verificationCapability = 'unknown';

    if (options.platform == BuildPlatform.android) {
      toolchainPrerequisites['java'] = true;
      final apksignerPath = _findApksigner();
      final hasApksigner = apksignerPath != null;
      final hasJarsigner = await validator.checkToolAvailable('jarsigner', [
        '-version',
      ]);
      toolchainPrerequisites['apksigner'] = hasApksigner;
      toolchainPrerequisites['jarsigner'] = hasJarsigner;

      signingConfigured = validator.isAndroidSigningConfigured(projectDir);

      if (options.target == BuildTarget.apk) {
        verificationCapability = hasApksigner
            ? 'apksigner'
            : 'none (apksigner missing)';
      } else if (options.target == BuildTarget.appbundle) {
        verificationCapability = hasJarsigner
            ? 'jarsigner'
            : 'none (jarsigner missing)';
      }
    } else if (options.platform == BuildPlatform.ios) {
      toolchainPrerequisites['xcodebuild'] = true;
      final hasCodesign = await validator.checkToolAvailable('codesign', [
        '--version',
      ]);
      toolchainPrerequisites['codesign'] = hasCodesign;
      signingConfigured = options.codesign;
      verificationCapability = hasCodesign
          ? 'codesign'
          : 'none (codesign missing)';
    }

    // 7. Construct official Flutter command arguments and expected artifact
    final flutterArgs = _constructFlutterArgs(options);
    final expectedFile = _resolveArtifactFile(options);

    // Build the planned command with sensitive flags redacted if present
    final plannedCommand = [pinnedSdk.executablePath, ...flutterArgs];

    final plan = BuildPlan(
      sdkDirectory: pinnedSdk.sdkDirectory,
      sdkVersion: pinnedSdk.version,
      sdkSource: pinnedSdk.source,
      platform: options.platform,
      target: options.target,
      mode: options.mode,
      plannedCommand: plannedCommand,
      expectedArtifactPath: expectedFile.path,
      toolchainPrerequisites: toolchainPrerequisites,
      verificationCapability: verificationCapability,
      signingConfigured: signingConfigured,
    );

    // 8. Handle dry run
    if (options.dryRun) {
      logDiag('Dry-run requested. Returning planned build without execution.');
      return BuildResult.success(
        options: options,
        message: 'Dry run successful. Build plan verified.',
        executedArguments: plannedCommand,
        isDryRun: true,
        plan: plan,
        diagnostics: diagnostics,
      );
    }

    // 9. Execute official Flutter build
    final runner = FlutterSdkRunner(pinnedSdk: pinnedSdk, executor: executor);
    logDiag('Executing Flutter build: ${plannedCommand.join(' ')}');
    ProcessExecutionResult result;
    try {
      result = await runner.run(flutterArgs, workingDirectory: projectDir.path);
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Build process execution encountered an error: $e',
        executedArguments: plannedCommand,
        plan: plan,
        diagnostics: diagnostics,
      );
    }

    if (!result.isSuccess) {
      final stderrText = _redactSecrets(result.stderr.trim());
      final stdoutText = _redactSecrets(result.stdout.trim());
      logDiag('Build process exited with code ${result.exitCode}.');
      return BuildResult.failure(
        options: options,
        message: 'Flutter build failed with exit code ${result.exitCode}.',
        actionableError: stderrText.isNotEmpty ? stderrText : stdoutText,
        executedArguments: plannedCommand,
        plan: plan,
        diagnostics: diagnostics,
      );
    }
    logDiag('Flutter build process exited successfully (0).');

    // 10. Locate and verify expected output artifact
    if (!expectedFile.existsSync()) {
      return BuildResult.failure(
        options: options,
        message:
            'Build succeeded but expected artifact was not found at ${expectedFile.path}.',
        actionableError: 'Inspect Flutter build logs to determine artifact output destination.',
        executedArguments: plannedCommand,
        plan: plan,
        diagnostics: diagnostics,
      );
    }
    logDiag('Found expected artifact at: ${expectedFile.path}');

    // 11. Inspect signing status via platform tools
    final verificationResult = await _verifyArtifactSignature(
      expectedFile,
      options,
    );
    logDiag(
      'Signature verification result: ${verificationResult.status.value} (${verificationResult.details ?? "no details"})',
    );

    ArtifactVerification verification;
    try {
      verification = await ArtifactVerification.verify(
        expectedFile,
        signatureStatus: verificationResult.status,
        signatureDetails: verificationResult.details,
      );
      logDiag(
        'Computed artifact SHA-256: ${verification.sha256} (${verification.sizeBytes} bytes).',
      );
    } catch (e) {
      return BuildResult.failure(
        options: options,
        message: 'Failed to compute artifact checksum or verify file: $e',
        executedArguments: plannedCommand,
        plan: plan,
        diagnostics: diagnostics,
      );
    }

    // 12. Generate manifest if requested
    BuildManifest? manifest;
    File? manifestFile;
    if (options.generateManifest) {
      final completedTime = DateTime.now();
      final durationMs = completedTime.difference(startTime).inMilliseconds;
      manifest = BuildManifest(
        dynboxVersion: '0.1.0',
        platform: options.platform.value,
        target: options.target.value,
        mode: options.mode.value,
        sdkVersion: pinnedSdk.version ?? 'unknown',
        artifactPath: verification.file.path,
        sizeBytes: verification.sizeBytes,
        sha256: verification.sha256,
        startedAt: startTime,
        completedAt: completedTime,
        durationMs: durationMs,
        signatureStatus: verification.signatureStatus.value,
        signatureDetails: verification.signatureDetails,
      );

      final buildDir = Directory('${projectDir.path}/build');
      if (!buildDir.existsSync()) {
        buildDir.createSync(recursive: true);
      }
      manifestFile = File('${buildDir.path}/dynbox_manifest.json');
      try {
        manifestFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        );
        logDiag('Build manifest successfully written to: ${manifestFile.path}');
      } catch (e) {
        logDiag('Warning: Failed to write build manifest: $e');
      }
    }

    return BuildResult.success(
      options: options,
      message:
          'Successfully built ${options.platform.value} ${options.target.value} (${options.mode.value}).',
      artifact: verification,
      executedArguments: plannedCommand,
      plan: plan,
      manifest: manifest,
      manifestFile: manifestFile,
      diagnostics: diagnostics,
    );
  }

  String _redactSecrets(String text) {
    if (text.isEmpty) return text;
    // Redact password=..., keystore password, Bearer tokens, etc.
    return text
        .replaceAllMapped(
          RegExp(r'(password[:=]\s*)([^\s]+)', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]',
        )
        .replaceAllMapped(
          RegExp(r'(keyPassword[:=]\s*)([^\s]+)', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]',
        )
        .replaceAllMapped(
          RegExp(r'(storePassword[:=]\s*)([^\s]+)', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]',
        )
        .replaceAllMapped(
          RegExp(r'(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]',
        );
  }

  List<String> _constructFlutterArgs(BuildOptions options) {
    final args = <String>['build'];

    if (options.platform == BuildPlatform.android) {
      if (options.target == BuildTarget.apk) {
        args.add('apk');
      } else if (options.target == BuildTarget.appbundle) {
        args.add('appbundle');
      }
    } else if (options.platform == BuildPlatform.ios) {
      if (options.target == BuildTarget.ipa) {
        args.add('ipa');
        if (!options.codesign) {
          args.add('--no-codesign');
        }
        if (options.exportMethod != null) {
          args.add('--export-method=${options.exportMethod}');
        }
      } else if (options.target == BuildTarget.archive) {
        // Build archive bundle without forcing an IPA export method
        args.add('ipa');
        if (!options.codesign) {
          args.add('--no-codesign');
        }
      }
    }

    // Add build mode flag
    switch (options.mode) {
      case BuildMode.debug:
        args.add('--debug');
        break;
      case BuildMode.profile:
        args.add('--profile');
        break;
      case BuildMode.release:
        args.add('--release');
        break;
    }

    return args;
  }

  File _resolveArtifactFile(BuildOptions options) {
    final root = options.projectDir.path;
    final modeName = options.mode.value;

    if (options.platform == BuildPlatform.android) {
      if (options.target == BuildTarget.apk) {
        return File('$root/build/app/outputs/flutter-apk/app-$modeName.apk');
      } else if (options.target == BuildTarget.appbundle) {
        // Standard Gradle bundle output path: build/app/outputs/bundle/<mode>/app-<mode>.aab
        // with fallback to legacy bundle/<mode>Release/app-<mode>.aab if present
        final standardPath = File(
          '$root/build/app/outputs/bundle/$modeName/app-$modeName.aab',
        );
        if (standardPath.existsSync()) return standardPath;

        final legacyPath = File(
          '$root/build/app/outputs/bundle/${modeName}Release/app-$modeName.aab',
        );
        if (legacyPath.existsSync()) return legacyPath;

        return standardPath;
      }
    } else if (options.platform == BuildPlatform.ios) {
      if (options.target == BuildTarget.ipa) {
        return File('$root/build/ios/ipa/app.ipa');
      } else if (options.target == BuildTarget.archive) {
        return File('$root/build/ios/archive/Runner.xcarchive');
      }
    }

    return File('$root/build/app/outputs/unknown');
  }

  Future<({SignatureStatus status, String? details})> _verifyArtifactSignature(
    File artifact,
    BuildOptions options,
  ) async {
    if (options.platform == BuildPlatform.android) {
      if (options.target == BuildTarget.apk) {
        return _verifyAndroidApk(artifact);
      } else if (options.target == BuildTarget.appbundle) {
        return _verifyAndroidAab(artifact);
      }
    } else if (options.platform == BuildPlatform.ios) {
      return _verifyIosArtifact(artifact);
    }
    return (
      status: SignatureStatus.unknown,
      details: 'Unsupported verification target',
    );
  }

  Future<({SignatureStatus status, String? details})> _verifyAndroidApk(
    File apkFile,
  ) async {
    final apksignerTool = _findApksigner();
    if (apksignerTool == null) {
      return (
        status: SignatureStatus.unknown,
        details: 'apksigner tool not found in PATH or Android SDK build-tools',
      );
    }

    try {
      final result = await executor.execute(apksignerTool, [
        'verify',
        '--verbose',
        apkFile.path,
      ], timeout: const Duration(seconds: 15));
      if (result.exitCode == 0) {
        return (
          status: SignatureStatus.verifiedSigned,
          details: 'Verified by apksigner',
        );
      } else if (result.stderr.contains('DOES NOT VERIFY') ||
          result.stdout.contains('DOES NOT VERIFY') ||
          result.stderr.contains('No signature found') ||
          result.stdout.contains('No signature found')) {
        return (
          status: SignatureStatus.verifiedUnsigned,
          details: 'Artifact contains no valid APK signature',
        );
      } else {
        return (
          status: SignatureStatus.verificationFailed,
          details: result.stderr.trim(),
        );
      }
    } catch (e) {
      return (
        status: SignatureStatus.unknown,
        details: 'Error running apksigner: $e',
      );
    }
  }

  Future<({SignatureStatus status, String? details})> _verifyAndroidAab(
    File aabFile,
  ) async {
    // AABs are not APKs and cannot be verified with apksigner directly.
    // They are signed with JAR signing (META-INF/*.SF and *.RSA/DSA/EC).
    // Use jarsigner -verify if available.
    try {
      final result = await executor.execute('jarsigner', [
        '-verify',
        aabFile.path,
      ], timeout: const Duration(seconds: 15));
      if (result.exitCode == 0 && result.stdout.contains('jar verified')) {
        return (
          status: SignatureStatus.verifiedSigned,
          details: 'AAB bundle verified by jarsigner',
        );
      } else if (result.stdout.contains('jar is unsigned')) {
        return (
          status: SignatureStatus.verifiedUnsigned,
          details: 'AAB bundle is unsigned',
        );
      } else {
        return (
          status: SignatureStatus.verificationFailed,
          details: result.stderr.trim().isNotEmpty
              ? result.stderr.trim()
              : result.stdout.trim(),
        );
      }
    } catch (_) {
      return (
        status: SignatureStatus.unknown,
        details: 'jarsigner tool unavailable to verify AAB bundle signature',
      );
    }
  }

  Future<({SignatureStatus status, String? details})> _verifyIosArtifact(
    File artifact,
  ) async {
    if (!Platform.isMacOS) {
      return (
        status: SignatureStatus.unknown,
        details: 'iOS codesign verification is only supported on macOS host',
      );
    }

    try {
      final result = await executor.execute('codesign', [
        '-v',
        '--deep',
        artifact.path,
      ], timeout: const Duration(seconds: 15));
      if (result.exitCode == 0) {
        return (
          status: SignatureStatus.verifiedSigned,
          details: 'Verified by codesign',
        );
      } else if (result.stderr.contains('code object is not signed at all')) {
        return (
          status: SignatureStatus.verifiedUnsigned,
          details: 'Artifact is not signed',
        );
      } else {
        return (
          status: SignatureStatus.verificationFailed,
          details: result.stderr.trim(),
        );
      }
    } catch (e) {
      return (
        status: SignatureStatus.unknown,
        details: 'Error running codesign: $e',
      );
    }
  }

  String? _findApksigner() {
    // 1. Check if apksigner is directly executable in PATH
    // 2. Check ANDROID_HOME / ANDROID_SDK_ROOT build-tools
    final envSdk =
        Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'];
    final home = Platform.environment['HOME'];
    final candidateDirs = <Directory>[
      if (envSdk != null) Directory('$envSdk/build-tools'),
      if (home != null) Directory('$home/Library/Android/sdk/build-tools'),
    ];

    for (final baseDir in candidateDirs) {
      if (baseDir.existsSync()) {
        try {
          final entries = baseDir.listSync().whereType<Directory>().toList()
            ..sort((a, b) => b.path.compareTo(a.path)); // sort newest first
          for (final dir in entries) {
            final candidate = File('${dir.path}/apksigner');
            if (candidate.existsSync()) {
              return candidate.path;
            }
          }
        } catch (_) {}
      }
    }

    return 'apksigner'; // fallback to PATH lookup
  }
}
