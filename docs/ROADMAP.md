# DynBox — Implementation Roadmap

This document outlines the planned evolutionary phases for the DynBox platform. Future milestones are marked as planned and are subject to formal architectural review before implementation.

---

## Phase 1: Repository Foundation & CLI Verification
*Status: Completed*

- [x] Establish modular repository directory layout (`apps/`, `packages/`, `cli/`, `backend/`, `schemas/`, `docs/`, `scripts/`, `tests/`).
- [x] Configure repository-wide `.gitignore` protecting secrets, caches, and build artifacts.
- [x] Scaffold Dart CLI package (`cli/dynbox`) with standard package structure.
- [x] Implement CLI command runner with `--help` and `--version`.
- [x] Implement `dynbox doctor` inspecting OS, Dart runtime, Git availability, and explicit Flutter SDK configuration.
- [x] Implement explicit SDK path validation logic without ambient `$PATH` fallbacks.
- [x] Establish comprehensive automated unit test suite with 100% passing tests and zero analyzer issues.
- [x] Author core architectural and security documentation.

---

## Phase 2: Project Specification, Configuration & SDK Execution
*Status: Completed*

- [x] Author declarative project specification schema (`schemas/project_spec.v1.json`) following JSON Schema Draft 2020-12.
- [x] Provide valid and invalid specification test fixtures under `cli/dynbox/test/fixtures/`.
- [x] Implement typed immutable workspace configuration parser (`DynboxConfig`) for `.dynbox/config.yaml`.
- [x] Provide documented example workspace configuration template (`.dynbox/config.yaml.example`).
- [x] Enforce explicit SDK selection precedence (CLI flag > Workspace config > Environment variable) without ambient `$PATH` fallback.
- [x] Implement absolute executable resolution across host operating systems.
- [x] Implement `SafeProcessExecutor` using `runInShell: false` with secret redaction, argument preservation, and timeout termination.
- [x] Implement high-level `FlutterSdkRunner` executing official Flutter commands using the pinned SDK.
- [x] 100% test pass rate across all suites (40 tests passing, 0 analyzer errors).

---

## Phase 3: Project Generation & Architecture Presets
*Status: Completed*

- [x] Implement `dynbox create <project-name>` CLI command with options: `--path`, `--flutter-root`, `--org`, `--platforms`, `--preset`.
- [x] Enforce safe pre-generation validation (name pattern, path traversal, existing destinations, organization format, platform lists).
- [x] Restrict Phase 3 scope to `flutter_app` with actionable errors for other types.
- [x] Invoke official `flutter create` using `FlutterSdkRunner` without shell evaluation.
- [x] Implement architecture presets: `minimal`, `layered`, and `feature_first`.
- [x] Verify generated project files and write valid `.dynbox/config.yaml`.
- [x] Validate written configuration by reading it back into `DynboxConfig`.
- [x] Preserve partial project directories on failure for diagnostic reporting without unsafe rollback.
- [x] 100% test pass rate (54 tests passing, 0 analyzer errors).
- [x] End-to-end smoke test executed and verified in temporary directory.

---

## Phase 4: Backend Adapters (Firebase & Supabase)
*Status: Completed*

- [x] Implement provider-independent `BackendAdapter` contract in `cli/dynbox/lib/src/backend/backend_adapter.dart`.
- [x] Implement `FirebaseAdapter` detecting tools (`firebase`, `flutterfire`), inspecting auth, and invoking official `flutterfire configure`.
- [x] Implement `SupabaseAdapter` validating HTTPS project URLs, rejecting privileged `service_role` keys, generating `lib/supabase_config.dart`, and optionally adding `supabase_flutter`.
- [x] Implement CLI commands: `dynbox backend status`, `dynbox backend configure firebase`, `dynbox backend configure supabase`.
- [x] Enforce zero secrets policy and update `.dynbox/config.yaml` safely post-validation.
- [x] Unit and mock integration test suite passing (63 tests passing, 0 analyzer errors).

---

## Phase 5: Dynamic UI Runtime & OTA Foundation
*Status: Completed*

### Objectives
- Establish a safe, schema-driven Dynamic UI system allowing published applications to update supported interface configurations without a store release.

### Delivered Capabilities
- [x] Versioned Dynamic UI JSON Schema (`schemas/dynamic_ui.v1.json`) following JSON Schema Draft 2020-12.
- [x] Pure Dart typed runtime models and AST parser (`packages/dynbox_ui_runtime`).
- [x] Allowlisted widget registry (12 built-in components: text, container, row, column, padding, image, icon, button, sized_box, card, divider, visibility).
- [x] Allowlisted actions (navigate with route allowlist, show_dialog, open_url with HTTPS enforcement, toggle_flag).
- [x] Safe theme, layout, visibility, and animation definitions with bounded durations and safe curves.
- [x] DynamicUiConfigSource abstraction with local file and in-memory test implementations.
- [x] Runtime update lifecycle with bundled fallback, cached last-known-good activation, and explicit rollback.
- [x] Unit test suite covering schema, parser, error handling, security boundaries, and rollback (15 tests passing, 0 analyzer issues).
- [x] Full compliance with store policies (Apple App Store Guideline 2.5.2 and Google Play Developer Policies: strictly no arbitrary JIT/bytecode execution or dynamic native library loading).

---

## Phase 6 & 6.1: Native Build & Release Orchestration & Hardening
*Status: Completed*

### Objectives
- Streamline local and CI packaging for Android (AAB/APK) and iOS (IPA, archive) using official toolchains and pinned Flutter SDKs.
- Provide structured diagnostics, comprehensive dry-run build plans, machine-readable build manifests, and robust error recovery.

### Delivered Capabilities
- [x] CLI `dynbox build` command with required `--platform` (android, ios), `--target` (apk, appbundle, ipa, archive), and optional `--mode` (debug, profile, release).
- [x] Structured CLI diagnostics: `--verbose` (detailed diagnostics to stderr with secret redaction) and `--json` (stable machine-readable JSON schema output).
- [x] Preflight validation: validates project structure, `pubspec.yaml`, `.dynbox/config.yaml` (`flutter_app`), output directory permissions, host toolchains, and signing configurations.
- [x] Comprehensive Build Plan during `--dry-run`: resolves SDK, target, planned command arguments, expected artifact destination, toolchain readiness, and signature verification capabilities without running compilation or external services.
- [x] Machine-readable Build Manifest: `--manifest` writes `build/dynbox_manifest.json` on successful builds with artifact path, size, SHA-256 checksum, timing metrics, and verification status. Never generates misleading success manifests on failure.
- [x] Host environment and toolchain preflight checks:
  - Validates project structure and `.dynbox/config.yaml` (`kind: flutter_app`).
  - Strict pinned SDK resolution (precedence order: CLI arg > workspace config > environment variable; never ambient `$PATH`).
  - Verifies Java (JDK) presence for Android builds.
  - Verifies macOS host and Xcode (`xcodebuild`) presence for iOS builds.
- [x] Safe subprocess execution via `FlutterSdkRunner` and `SafeProcessExecutor` (zero shell evaluation, discrete argument tokens, timeouts, process lifecycle control).
- [x] Post-build artifact verification:
  - Verifies artifact existence on disk.
  - Records file path, size in bytes, build mode, and timestamp.
  - Computes SHA-256 cryptographic checksum.
  - Performs actual cryptographic signature checks using host platform tooling (`apksigner verify` for APK, `jarsigner -verify` for AAB, `codesign -v` for iOS) with a 4-state `SignatureStatus` (`verifiedSigned`, `verifiedUnsigned`, `verificationFailed`, `unknown`).
  - Supports external Android signing configuration via `DYNBOX_KEY_PROPERTIES_PATH` to keep credentials outside the repository workspace.
- [x] Error recovery & redaction: captures actionable errors from stderr/stdout and automatically redacts keystore passwords, store passwords, and bearer tokens. Never performs recursive project deletions on failure.
- [x] Comprehensive test suite with mocked subprocess execution (90 tests passing in `cli/dynbox`, 15 in `packages/dynbox_ui_runtime`, 0 analyzer issues).
- [x] Strict zero-secret policy: no keystore passwords, private signing certificates, or production keys in arguments, logs, or `.dynbox/config.yaml`. Project `.gitignore` includes `key.properties`, keystores, and provisioning profiles.

---

## Phase 6.2: Standalone Cross-Platform Installer & Upgrader
*Status: Completed*

### Objectives
- Provide a developer installation and upgrade user experience comparable to Shorebird CLI.
- Enable running `dynbox` from any directory without cloning the repository or pre-installing the Dart SDK.

### Delivered Capabilities
- [x] Multi-platform standalone compilation architecture using `dart compile exe`.
- [x] Standalone POSIX Shell installer (`scripts/install.sh`) supporting macOS & Linux with automatic OS and CPU architecture detection (arm64, x64), SHA-256 integrity verification, and idempotent shell profile PATH configuration.
- [x] Standalone Windows PowerShell installer (`scripts/install.ps1`) supporting Windows x64 and arm64 with SHA-256 verification and User PATH updating.
- [x] Standard user-owned installation directories: `~/.dynbox/bin` (macOS/Linux) and `%LOCALAPPDATA%\DynBox\bin` (Windows) requiring zero administrator privileges.
- [x] Machine-readable versioned release manifest schema (`release_manifest.json`) mapping target platforms to artifact file names, sizes, and SHA-256 checksums.
- [x] Built-in `dynbox upgrade` command with `--check` option, pinned version support (`--version <v>`), atomic binary staging, and automatic rollback on failure.
- [x] Built-in `dynbox uninstall` command with interactive confirmation and `--yes` override, removing only DynBox-owned binaries without touching Flutter SDKs, configuration, or user projects.
- [x] Complete Flutter SDK isolation: DynBox installs and operates independently from Flutter without bundling Flutter or mutating Flutter PATH.
- [x] Multi-target GitHub Actions release workflow (`.github/workflows/release.yml`) building native binaries on matrix runners (`macos-latest`, `macos-13`, `ubuntu-latest`, `windows-latest`) and compiling `release_manifest.json`.

---

## DynBox First-Party OTA Update System (No Shorebird)
*Status: Completed*

### Objectives
- Provide a first-party Over-The-Air code update system controlled and implemented by DynBox.
- Strictly avoid Shorebird (`shorebird_code_push`, Shorebird CLI, or Shorebird engine/forks).
- Operate over the safe schema-driven Dynamic UI runtime (`packages/dynbox_ui_runtime`).
- Scaffold newly created projects (`dynbox create <app>`) with first-party update SDK, coordinator, demo screen, and non-blocking asynchronous startup.

### Delivered Capabilities
- [x] Versioned OTA release manifest schema (`schemas/ota_manifest.v1.json`) with strict versioning, platform, app compatibility, size constraints (max 512 KB), and cryptographic signatures.
- [x] First-party OTA client package (`packages/dynbox_ota`) with typed state machine (`checking`, `updateAvailable`, `downloading`, `verifying`, `readyToActivate`, `upToDate`, `failed`).
- [x] Cryptographic verification engine (`OtaVerifier`): SHA-256 digest checks and HMAC-SHA256 signature verification.
- [x] Sandboxed caching layer (`OtaCache`): atomic staging, Last-Known-Good (LKG) backup, and programmatic rollback.
- [x] Dynamic UI integration (`DynboxOtaService`): live hot update activation into `DynamicUiController`.
- [x] Server provider abstraction (`OtaServerProvider`): in-memory deterministic `MockOtaServerProvider` for offline testing, `HttpOtaServerProvider` for generic REST backends, and `SupabaseOtaServerProvider` for Supabase PostgREST & Storage backends.
- [x] Supabase release management schema and storage migration (`backend/supabase/migrations/20261016000000_ota_releases.sql`):
  - `public.ota_releases` table with unique release identifiers, SHA-256 payload checksums, and size constraints.
  - Row Level Security (RLS) policies granting anonymous read-only access to compatible active releases and restricting release creation/updates to authorized `service_role` keys.
  - `storage.buckets` configuration for `ota-payloads` with public read access and `service_role` write permissions.
- [x] Generated app integration (`dynbox create <app>`):
  - Adds `dynbox_ota` and `dynbox_ui_runtime` dependencies.
  - Generates `lib/dynbox_ota_service.dart` with `AppOtaCoordinator` supporting local mock and optional Supabase backend connections.
  - Generates `lib/dynbox_ota_demo_screen.dart` with status card, update check, apply update, retry, and rollback controls.
  - Integrates non-blocking background update check into `main.dart`.
  - 100% offline-compatible: zero network or server required during project creation.
- [x] Safe source snapshotting (`dynbox ota sync-source [project-path]`):
  - Scans project directory and generates deterministic SHA-256 source release manifests.
  - Strictly filters and excludes private keystores (`.keystore`, `.jks`), signing properties (`key.properties`), local credentials (`.env`), build directories (`build/`), and VCS files (`.git/`).
- [x] CLI commands (`dynbox ota`):
  - `dynbox ota status [project-path]`
  - `dynbox ota init [project-path]`
  - `dynbox ota check [project-path]`
  - `dynbox ota validate <manifest-or-payload-path>`
  - `dynbox ota sync-source [project-path]`
  - `dynbox ota publish <project-path> --payload <file> --confirm [--supabase-service-key <key>]`
- [x] Complete automated test suite: 17 tests in `packages/dynbox_ota`, 15 in `packages/dynbox_ui_runtime`, 122 in `cli/dynbox` (all passing, 0 analyzer issues).

---

## Phase 8: Official Flutter SDK Manager & First-Time Setup
*Status: Completed*

### Objectives
- Enable DynBox on clean machines without pre-installed Flutter or Dart.
- Provide a secure, official Flutter SDK download, verification, extraction, and management system.
- Streamline first-time developer onboarding via a guided `dynbox setup` experience.

### Delivered Capabilities
- [x] Official Flutter Release Manifest Catalog parser fetching and caching `https://storage.googleapis.com/flutter_infra_release/releases/releases_<os>.json`.
- [x] Architecture detection mapping host OS and CPU architecture (macOS x64/arm64, Linux x64/arm64, Windows x64/arm64).
- [x] Cryptographic verification: calculates SHA-256 digests of downloaded archives and verifies against official Google Cloud release metadata.
- [x] Safe extraction & path traversal defense: rejects archives containing directory traversal (`../`) or absolute paths; extracts atomically via `SafeProcessExecutor` (`unzip` on macOS/Linux, `tar` on Windows) into isolated staging directories.
- [x] Sandboxed directory management: managed SDKs reside strictly in user-owned `~/.dynbox/sdks/<version>` (`%LOCALAPPDATA%\DynBox\sdks\<version>` on Windows). Never deletes directories outside managed root.
- [x] Safe removal with explicit confirmation (`--yes` required in non-interactive CLI).
- [x] CLI `dynbox sdk` subcommands:
  - `dynbox sdk list`: Lists available official Flutter versions from Google Cloud release manifest.
  - `dynbox sdk list-installed`: Lists currently downloaded/managed SDKs.
  - `dynbox sdk install <version|stable>`: Downloads, verifies, and installs official Flutter SDK.
  - `dynbox sdk use <version>`: Sets installed managed SDK as global default in `~/.dynbox/config.yaml`.
  - `dynbox sdk current`: Displays currently active/pinned Flutter SDK and resolution source.
  - `dynbox sdk remove <version>`: Removes managed SDK directory with confirmation.
- [x] Guided First-Time Setup (`dynbox setup`):
  - Detects if a valid Flutter SDK is already configured.
  - Inspects host toolchain prerequisites (Android SDK, Xcode, CocoaPods) with clear diagnostic output.
  - Prompts and installs official stable Flutter SDK if missing.
  - Configures global default in `~/.dynbox/config.yaml` upon successful validation.
- [x] Preserved precedence order: CLI flag (`--flutter-root`) > Workspace config (`.dynbox/config.yaml`) > Global config (`~/.dynbox/config.yaml`) > Environment variable (`DYNBOX_FLUTTER_ROOT`). Strictly zero ambient `$PATH` fallback.
- [x] Updated `dynbox doctor` and `dynbox create` with clear diagnostics recommending `dynbox setup` when no SDK is configured.
- [x] Comprehensive test suite in `cli/dynbox/test/sdk_manager_test.dart` (122 tests passing across `cli/dynbox`, 0 analyzer issues).

---

## Phase 7: Future Architectural Boundary — Verifiable Cloud Compilation & Dart Code Patching

### 1. Dedicated Cloud Build Worker Architecture
- Supabase is used strictly as a metadata, release-record, and asset storage backend. It cannot and must not be used to compile native Flutter binaries directly.
- Future cloud compilation requires an isolated, containerized build runner (e.g. Linux container with pinned Flutter SDK, Android NDK/SDK, and macOS runners for Xcode).
- The boundary between source snapshotting (`dynbox ota sync-source`), remote build dispatch, artifact verification, and OTA deployment remains strictly separated.

### 2. Technical Boundary for Future Dart Code Patching
- Current OTA capabilities update schema-driven UI, theme properties, layout trees, and approved actions via the Dynamic UI runtime.
- Native mobile platforms (Apple iOS App Store Guideline 2.5.2 and Google Play policies) impose strict limitations on executing downloaded native machine code.
- Future Dart code patching would require a specialized interpreted or sandboxed bytecode runtime / Wasm evaluation engine. DynBox explicitly does not load downloaded native libraries or unverified executables.

