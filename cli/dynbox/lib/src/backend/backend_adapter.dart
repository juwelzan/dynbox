import 'dart:io';

/// Supported backend provider types.
enum BackendProviderType {
  none('none'),
  firebase('firebase'),
  supabase('supabase');

  final String value;
  const BackendProviderType(this.value);

  static BackendProviderType parse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final p in BackendProviderType.values) {
      if (p.value == normalized) return p;
    }
    throw ArgumentError.value(
      value,
      'provider',
      'Unknown provider "$value". Supported providers: ${BackendProviderType.values.map((p) => p.value).join(', ')}',
    );
  }
}

/// Status of an external CLI tool.
class CliToolStatus {
  final String name;
  final bool isInstalled;
  final String? version;
  final String? executablePath;
  final String installGuide;

  const CliToolStatus({
    required this.name,
    required this.isInstalled,
    this.version,
    this.executablePath,
    required this.installGuide,
  });
}

/// Authentication state for a provider tool.
class AuthStatus {
  final bool isAuthenticated;
  final String? accountEmail;
  final String? details;
  final String loginGuide;

  const AuthStatus({
    required this.isAuthenticated,
    this.accountEmail,
    this.details,
    required this.loginGuide,
  });
}

/// Detailed status of a backend provider for a workspace.
class ProviderStatusReport {
  final BackendProviderType provider;
  final bool isConfigured;
  final String? projectId;
  final List<CliToolStatus> tools;
  final AuthStatus auth;
  final List<String> supportedCapabilities;
  final List<String> warnings;

  const ProviderStatusReport({
    required this.provider,
    required this.isConfigured,
    this.projectId,
    required this.tools,
    required this.auth,
    required this.supportedCapabilities,
    this.warnings = const [],
  });

  bool get hasMissingTools => tools.any((t) => !t.isInstalled);
}

/// Result of a provider configuration workflow.
class ProviderConfigureResult {
  final bool isSuccess;
  final BackendProviderType provider;
  final String message;
  final List<String> modifiedFiles;
  final String? details;
  final String? actionableError;

  const ProviderConfigureResult({
    required this.isSuccess,
    required this.provider,
    required this.message,
    this.modifiedFiles = const [],
    this.details,
    this.actionableError,
  });

  factory ProviderConfigureResult.success({
    required BackendProviderType provider,
    required String message,
    List<String> modifiedFiles = const [],
    String? details,
  }) {
    return ProviderConfigureResult(
      isSuccess: true,
      provider: provider,
      message: message,
      modifiedFiles: modifiedFiles,
      details: details,
    );
  }

  factory ProviderConfigureResult.failure({
    required BackendProviderType provider,
    required String message,
    String? actionableError,
    String? details,
    List<String> modifiedFiles = const [],
  }) {
    return ProviderConfigureResult(
      isSuccess: false,
      provider: provider,
      message: message,
      actionableError: actionableError,
      details: details,
      modifiedFiles: modifiedFiles,
    );
  }
}

/// Abstract contract for a DynBox backend provider adapter.
abstract class BackendAdapter {
  BackendProviderType get provider;

  /// Inspects the local environment, external tools, and authentication.
  Future<ProviderStatusReport> inspectStatus(Directory projectDir);

  /// Configures an existing backend project for the Flutter workspace.
  Future<ProviderConfigureResult> configure(
    Directory projectDir,
    Map<String, dynamic> options,
  );
}
