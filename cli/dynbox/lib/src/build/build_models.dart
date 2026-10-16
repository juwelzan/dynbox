import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Target build platform.
enum BuildPlatform {
  android('android'),
  ios('ios');

  final String value;
  const BuildPlatform(this.value);

  static BuildPlatform parse(String val) {
    for (final p in BuildPlatform.values) {
      if (p.value == val.toLowerCase().trim()) return p;
    }
    throw ArgumentError(
      'Unsupported platform "$val". Supported platforms: ${BuildPlatform.values.map((p) => p.value).join(', ')}',
    );
  }
}

/// Target artifact type.
enum BuildTarget {
  apk('apk'),
  appbundle('appbundle'),
  ipa('ipa'),
  archive('archive');

  final String value;
  const BuildTarget(this.value);

  static BuildTarget parse(String val) {
    for (final t in BuildTarget.values) {
      if (t.value == val.toLowerCase().trim()) return t;
    }
    throw ArgumentError(
      'Unsupported target "$val". Supported targets: ${BuildTarget.values.map((t) => t.value).join(', ')}',
    );
  }
}

/// Flutter compilation mode.
enum BuildMode {
  debug('debug'),
  profile('profile'),
  release('release');

  final String value;
  const BuildMode(this.value);

  static BuildMode parse(String val) {
    for (final m in BuildMode.values) {
      if (m.value == val.toLowerCase().trim()) return m;
    }
    throw ArgumentError(
      'Unsupported build mode "$val". Supported modes: ${BuildMode.values.map((m) => m.value).join(', ')}',
    );
  }
}

/// Build specification and validation options.
class BuildOptions {
  final Directory projectDir;
  final BuildPlatform platform;
  final BuildTarget target;
  final BuildMode mode;
  final String? flutterRoot;
  final bool dryRun;
  final bool codesign;
  final String? exportMethod;
  final bool verbose;
  final bool json;
  final bool generateManifest;

  const BuildOptions({
    required this.projectDir,
    required this.platform,
    required this.target,
    this.mode = BuildMode.release,
    this.flutterRoot,
    this.dryRun = false,
    this.codesign = true,
    this.exportMethod,
    this.verbose = false,
    this.json = false,
    this.generateManifest = false,
  });

  /// Validates compatibility between platform and target.
  void validatePlatformCompatibility() {
    if (platform == BuildPlatform.android) {
      if (target != BuildTarget.apk && target != BuildTarget.appbundle) {
        throw ArgumentError(
          'Target "${target.value}" is not valid for Android. Android supports "apk" and "appbundle".',
        );
      }
    } else if (platform == BuildPlatform.ios) {
      if (target != BuildTarget.ipa && target != BuildTarget.archive) {
        throw ArgumentError(
          'Target "${target.value}" is not valid for iOS. iOS supports "ipa" and "archive".',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'projectPath': projectDir.path,
    'platform': platform.value,
    'target': target.value,
    'mode': mode.value,
    if (flutterRoot != null) 'flutterRoot': flutterRoot,
    'dryRun': dryRun,
    'codesign': codesign,
    if (exportMethod != null) 'exportMethod': exportMethod,
    'verbose': verbose,
    'json': json,
    'generateManifest': generateManifest,
  };
}

/// Status of cryptographic artifact signature verification.
enum SignatureStatus {
  /// Confirmed valid cryptographic signature by platform tooling (apksigner/codesign).
  verifiedSigned('verified_signed'),

  /// Confirmed unsigned artifact (e.g. unsigned release build or unsigned APK).
  verifiedUnsigned('verified_unsigned'),

  /// Signature verification failed due to bad signature or corrupted digest.
  verificationFailed('verification_failed'),

  /// Signature could not be verified (missing host platform tooling, unverified bundle format, etc.).
  unknown('unknown');

  final String value;
  const SignatureStatus(this.value);
}

/// Verification details for a generated build artifact.
class ArtifactVerification {
  final File file;
  final int sizeBytes;
  final String sha256;
  final DateTime modifiedAt;
  final SignatureStatus signatureStatus;
  final String? signatureDetails;

  /// Backwards-compatible getter: returns true only if [signatureStatus] is [SignatureStatus.verifiedSigned].
  bool get isSigned => signatureStatus == SignatureStatus.verifiedSigned;

  const ArtifactVerification({
    required this.file,
    required this.sizeBytes,
    required this.sha256,
    required this.modifiedAt,
    this.signatureStatus = SignatureStatus.unknown,
    this.signatureDetails,
  });

  static Future<ArtifactVerification> verify(
    File file, {
    SignatureStatus signatureStatus = SignatureStatus.unknown,
    String? signatureDetails,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('Artifact file does not exist', file.path);
    }
    final length = await file.length();
    final bytes = await file.readAsBytes();
    final digest = crypto.sha256.convert(bytes);

    return ArtifactVerification(
      file: file,
      sizeBytes: length,
      sha256: digest.toString(),
      modifiedAt: await file.lastModified(),
      signatureStatus: signatureStatus,
      signatureDetails: signatureDetails,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': file.path,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'modifiedAt': modifiedAt.toIso8601String(),
    'isSigned': isSigned,
    'signatureStatus': signatureStatus.value,
    if (signatureDetails != null) 'signatureDetails': signatureDetails,
  };
}

/// Comprehensive plan generated during preflight and dry-runs.
class BuildPlan {
  final String sdkDirectory;
  final String? sdkVersion;
  final String sdkSource;
  final BuildPlatform platform;
  final BuildTarget target;
  final BuildMode mode;
  final List<String> plannedCommand;
  final String expectedArtifactPath;
  final Map<String, bool> toolchainPrerequisites;
  final String verificationCapability;
  final bool signingConfigured;

  const BuildPlan({
    required this.sdkDirectory,
    this.sdkVersion,
    required this.sdkSource,
    required this.platform,
    required this.target,
    required this.mode,
    required this.plannedCommand,
    required this.expectedArtifactPath,
    required this.toolchainPrerequisites,
    required this.verificationCapability,
    required this.signingConfigured,
  });

  Map<String, dynamic> toJson() => {
    'sdkDirectory': sdkDirectory,
    if (sdkVersion != null) 'sdkVersion': sdkVersion,
    'sdkSource': sdkSource,
    'platform': platform.value,
    'target': target.value,
    'mode': mode.value,
    'plannedCommand': plannedCommand,
    'expectedArtifactPath': expectedArtifactPath,
    'toolchainPrerequisites': toolchainPrerequisites,
    'verificationCapability': verificationCapability,
    'signingConfigured': signingConfigured,
  };
}

/// Immutable, machine-readable build manifest written to disk.
class BuildManifest {
  final String dynboxVersion;
  final String platform;
  final String target;
  final String mode;
  final String sdkVersion;
  final String artifactPath;
  final int sizeBytes;
  final String sha256;
  final DateTime startedAt;
  final DateTime completedAt;
  final int durationMs;
  final String signatureStatus;
  final String? signatureDetails;

  const BuildManifest({
    required this.dynboxVersion,
    required this.platform,
    required this.target,
    required this.mode,
    required this.sdkVersion,
    required this.artifactPath,
    required this.sizeBytes,
    required this.sha256,
    required this.startedAt,
    required this.completedAt,
    required this.durationMs,
    required this.signatureStatus,
    this.signatureDetails,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': '1.0',
    'dynboxVersion': dynboxVersion,
    'platform': platform,
    'target': target,
    'mode': mode,
    'sdkVersion': sdkVersion,
    'artifact': {
      'path': artifactPath,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'signatureStatus': signatureStatus,
      if (signatureDetails != null) 'signatureDetails': signatureDetails,
    },
    'timing': {
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt.toIso8601String(),
      'durationMs': durationMs,
    },
  };
}

/// Overall result of a build execution or dry-run.
class BuildResult {
  final bool isSuccess;
  final BuildOptions options;
  final String message;
  final ArtifactVerification? artifact;
  final String? actionableError;
  final List<String> executedArguments;
  final bool isDryRun;
  final BuildPlan? plan;
  final BuildManifest? manifest;
  final File? manifestFile;
  final List<String> diagnostics;

  const BuildResult({
    required this.isSuccess,
    required this.options,
    required this.message,
    this.artifact,
    this.actionableError,
    this.executedArguments = const [],
    this.isDryRun = false,
    this.plan,
    this.manifest,
    this.manifestFile,
    this.diagnostics = const [],
  });

  factory BuildResult.failure({
    required BuildOptions options,
    required String message,
    String? actionableError,
    List<String> executedArguments = const [],
    BuildPlan? plan,
    List<String> diagnostics = const [],
  }) {
    return BuildResult(
      isSuccess: false,
      options: options,
      message: message,
      actionableError: actionableError,
      executedArguments: executedArguments,
      plan: plan,
      diagnostics: diagnostics,
    );
  }

  factory BuildResult.success({
    required BuildOptions options,
    required String message,
    ArtifactVerification? artifact,
    List<String> executedArguments = const [],
    bool isDryRun = false,
    BuildPlan? plan,
    BuildManifest? manifest,
    File? manifestFile,
    List<String> diagnostics = const [],
  }) {
    return BuildResult(
      isSuccess: true,
      options: options,
      message: message,
      artifact: artifact,
      executedArguments: executedArguments,
      isDryRun: isDryRun,
      plan: plan,
      manifest: manifest,
      manifestFile: manifestFile,
      diagnostics: diagnostics,
    );
  }

  Map<String, dynamic> toJson() => {
    'isSuccess': isSuccess,
    'message': message,
    'isDryRun': isDryRun,
    'options': options.toJson(),
    if (plan != null) 'plan': plan!.toJson(),
    if (artifact != null) 'artifact': artifact!.toJson(),
    if (manifest != null) 'manifest': manifest!.toJson(),
    if (manifestFile != null) 'manifestPath': manifestFile!.path,
    if (actionableError != null) 'actionableError': actionableError,
    'executedArguments': executedArguments,
    if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
  };
}
