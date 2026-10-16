# DynBox — System Architecture

## 1. Architectural Philosophy
DynBox is designed around the principles of developer ownership, transparency, and system modularity. Rather than wrapping Flutter inside a proprietary walled garden or distributing modified binaries, DynBox orchestrates official tooling deterministically on the developer's workstation.

```text
+-------------------------------------------------------------------------+
|                               DynBox CLI                                |
|  [CommandRunner] -> [Commands: doctor, create, backend, build*, ota*]   |
+--------------------+-------------------------------+--------------------+
                     |                               |
                     v                               v
    +----------------------------------+   +------------------------------+
    |         SDK Orchestrator         |   |       Backend Adapters       |
    |  - SdkResolver (Precedence)      |   |  - BackendAdapter (Contract) |
    |  - SdkValidator (Integrity)      |   |  - FirebaseAdapter           |
    |  - SafeProcessExecutor (NoShell) |   |  - SupabaseAdapter           |
    |  - FlutterSdkRunner (Pinned)     |   +------------------------------+
    |  - ProjectGenerator & Presets    |
    +----------------------------------+
                     |
                     v
    +----------------------------------+
    |   Official Flutter & Dart SDKs   |
    |   (Unmodified official binaries) |
    +----------------------------------+
```
*\*Planned future capabilities*

## 2. Core Subsystems

### 2.1 DynBox CLI (`cli/dynbox`)
The command-line interface provides the developer interaction surface:
- **`bin/dynbox.dart`**: Entrypoint responsible for catching unhandled exceptions, formatting syntax usage, and setting OS process exit codes.
- **`lib/src/runner.dart`**: Implements `CommandRunner<int>`, managing global flags (`--help`, `--version`) and delegating subcommands (`doctor`, `create`, `backend`).
- **`lib/src/commands/`**: Command handlers with isolated responsibilities (`doctor_command.dart`, `create_command.dart`, `backend_command.dart`).
- **`lib/src/backend/`**: Provider-independent adapter layer (`backend_adapter.dart`, `firebase_adapter.dart`, `supabase_adapter.dart`).
- **`lib/src/generator/`**: Project generation orchestrator (`project_generator.dart`) and architecture presets (`preset_applier.dart`).
- **`lib/src/doctor/`**: Environment inspectors that inspect host OS, Dart runtime, Git availability, and SDK configuration without side effects.
- **`lib/src/config/dynbox_config.dart`**: Typed immutable workspace configuration parser validating `.dynbox/config.yaml`.
- **`lib/src/sdk/`**: SDK resolution model enforcing explicit path specification and safe subprocess execution.

### 2.2 Backend Adapter Architecture
- **Contract (`BackendAdapter`)**:
  - `inspectStatus(projectDir)`: Inspects CLI installation, versions, active authentication, and configuration consistency.
  - `configure(projectDir, options)`: Configures an existing provider project, generates client configuration, and updates `.dynbox/config.yaml`.
- **Firebase Adapter**:
  - Relies on official `firebase-tools` and `flutterfire_cli`.
  - Invokes `flutterfire configure --project=<id> --platforms=<list> --yes`.
  - Inspects generated `lib/firebase_options.dart` and records `backend.firebase.projectId`.
- **Supabase Adapter**:
  - Validates HTTPS project URL format.
  - Generates `lib/supabase_config.dart` containing non-privileged public client identifiers.
  - Strictly rejects privileged `service_role` and secret keys.
  - Updates `.dynbox/config.yaml` with `backend.supabase.projectUrl`.
- **Clear Separation of Concerns**:
  - DynBox configures existing projects; it never silently creates cloud projects or performs destructive backend modifications.

### 2.3 Project Creation & Architecture Presets
- **Command (`dynbox create <project-name>`)**:
  - Validates project name, destination directories, organization identifiers, and target platforms before creating any files.
  - Generates the standard Flutter app by invoking the official `flutter create` command via `FlutterSdkRunner`.
  - Verifies generated outputs (`pubspec.yaml`).
  - Applies selected architecture presets:
    - `minimal`: Standard Flutter template without modifications.
    - `layered`: Generates structured `lib/app/`, `lib/core/`, `lib/features/`, and `lib/STRUCTURE.md`.
    - `feature_first`: Generates feature-first `lib/app/`, `lib/core/`, `lib/features/home/presentation/`, and `lib/STRUCTURE.md`.
  - Initializes `.dynbox/config.yaml` in the generated workspace and parses it back to guarantee validity.

### 2.4 SDK Selection & Precedence Subsystem
A core requirement of DynBox is reproducible and isolated builds:
- **Explicit Resolution Hierarchy**:
  1. **CLI parameter**: `--flutter-root <path>`
  2. **Workspace configuration**: `.dynbox/config.yaml` (`sdk.flutter.path` or `flutter_sdk_path`)
  3. **Persistent global configuration**: `~/.dynbox/config.yaml` (`dynbox config set flutter-root <path>`)
  4. **Environment variable**: `DYNBOX_FLUTTER_ROOT`
- **No Ambient Fallback**: If an explicit path is omitted across all sources, DynBox refuses to execute project operations against an arbitrary `flutter` found in `$PATH`.
- **Host OS Path Resolution**: Automatically resolves absolute executable binaries based on the host OS (`bin/flutter` on macOS/Linux, `bin/flutter.bat` on Windows).

### 2.5 Safe Subprocess Execution Subsystem
- **No Shell Interpolation**: Subprocesses are spawned using `Process.start` directly with `runInShell: false`. Arguments are passed as discrete tokens in a `List<String>`, neutralizing command injection risks.
- **Output Sanitization & Secret Redaction**: Configurable masking engine redacts known authentication tokens, passwords, and sensitive keys from `stdout` and `stderr` before logging.
- **Timeout & Process Lifecycle**: Manages process execution lifetimes, cleanly terminating orphaned child processes when timeouts occur.

### 2.6 Dynamic UI Runtime Subsystem (`packages/dynbox_ui_runtime`)
- **Versioned JSON Schema (`schemas/dynamic_ui.v1.json`)**:
  - Declarative UI specification following JSON Schema Draft 2020-12.
  - Enforces component bounds (max 50 children, max 20 nesting levels, max 512 KB payload).
- **Typed AST & Parser (`DynamicUiParser`)**:
  - Pure Dart models (`DynamicUiDocument`, `DynamicScreen`, `DynamicComponent`, `ComponentProperties`, `DynamicAction`, `DynamicAnimation`, `DynamicTheme`).
  - Strict validation of color formats, numeric dimensions, animation durations, and required component properties.
- **Allowlisted Widget Registry (`WidgetRegistry`)**:
  - Explicit registry of 12 built-in widgets: `text`, `container`, `row`, `column`, `padding`, `image`, `icon`, `button`, `sized_box`, `card`, `divider`, `visibility`.
  - Blocks dynamic class reflection and unauthorized widget instantiation.
- **Controlled Action Dispatcher (`RenderContext`)**:
  - Supports closed action types: `navigate` (restricted to pre-registered route allowlist), `show_dialog`, `open_url` (strictly HTTPS), `toggle_flag`.
- **Configuration Source Abstraction (`DynamicUiConfigSource`)**:
  - Pluggable source interface with deterministic `LocalFileConfigSource` and `MemoryConfigSource`.
- **Runtime Lifecycle & Rollback (`DynamicUiController`)**:
  - Multi-tier fallback: bundled default -> cached last-known-good -> candidate activation.
  - Offline startup resiliency and explicit programmatic rollback (`rollbackToLastKnownGood`).

### 2.7 Native Build & Release Orchestration Subsystem (`cli/dynbox/lib/src/build/`) (Phase 6 & 6.1)
- **CLI Command (`BuildCommand`)**:
  - `dynbox build <project-path> --platform <android|ios> --target <apk|appbundle|ipa|archive> [--mode debug|profile|release] [--dry-run] [--manifest] [--verbose] [--json]`
  - Validates project type (`kind: flutter_app`) and parameters prior to execution.
  - Implements `--dry-run` producing a comprehensive `BuildPlan` with toolchain prerequisites, resolved SDK details, planned commands, and verification capabilities without compiling.
  - Separate archive (`Runner.xcarchive`) and IPA (`app.ipa`) target workflows.
  - Structured CLI diagnostics: emits `--json` to `stdout` with stable schema and `--verbose` diagnostics to `stderr` with secret redaction.
- **Preflight & Toolchain Validation (`BuildValidator`)**:
  - Ensures host machine has Java (JDK) installed for Android builds.
  - Ensures host OS is macOS and Xcode (`xcodebuild`) is installed for iOS builds.
  - Validates output directory write permissions (`build/`) before starting the build.
  - Evaluates Android signing configuration from external secret paths (`DYNBOX_KEY_PROPERTIES_PATH`) or project-local `android/key.properties`.
- **Orchestration & Subprocess Safety (`BuildOrchestrator`)**:
  - Leverages `FlutterSdkRunner` with `SafeProcessExecutor` (zero shell evaluation, discrete argument tokens).
  - Pinned SDK resolution adheres to strict precedence without system `$PATH` leakage.
  - Correct mode-based AAB bundle path resolution (`build/app/outputs/bundle/<mode>/app-<mode>.aab`).
  - Error recovery with automatic credential redaction (keystore passwords, store passwords, bearer tokens).
- **Post-Build Artifact Verification & Manifest (`ArtifactVerification`, `BuildManifest`)**:
  - Verifies artifact existence on disk.
  - Computes cryptographic SHA-256 hash and file size.
  - Performs active platform tool verification via `apksigner verify` (Android APK), `jarsigner -verify` (Android AAB), or `codesign -v` (iOS).
  - Employs a 4-state `SignatureStatus` (`verifiedSigned`, `verifiedUnsigned`, `verificationFailed`, `unknown`).
  - When `--manifest` is requested, outputs `build/dynbox_manifest.json` on successful verified builds; failed builds never write misleading manifests.

### 2.8 Standalone Installer & Upgrader Subsystem (`cli/dynbox/lib/src/installer/`) (Phase 6.2)
- **Standalone Native Compilation**: Compiles `bin/dynbox.dart` into single-file Mach-O/ELF/PE binaries via `dart compile exe` with embedded Dart AOT runtime, eliminating external Dart runtime dependencies for end-users.
- **Cross-Platform Installers**:
  - `scripts/install.sh`: POSIX shell script supporting macOS (arm64, x64) and Linux (x64, arm64). Resolves latest or pinned release, verifies SHA-256 against `release_manifest.json`, and updates user PATH idempotently with profile backup.
  - `scripts/install.ps1`: Windows PowerShell script supporting Windows x64 and arm64. Performs download, SHA-256 validation via `Get-FileHash`, and updates User PATH environment variables.
- **Dedicated User-Owned Installation Directory**:
  - macOS/Linux: `~/.dynbox/bin`
  - Windows: `%LOCALAPPDATA%\DynBox\bin`
  - Requires no administrator/root privileges and does not alter system directories.
- **Atomic Upgrades & Rollback (`DynboxUpdater`, `dynbox upgrade`)**:
  - Compares running version with release metadata.
  - Downloads candidate binary to temporary staging.
  - Verifies cryptographic checksum before touching active executable.
  - Backs up existing binary, stages new binary, and performs rollback if replacement fails.
- **Scoped Uninstallation (`DynboxUninstaller`, `dynbox uninstall`)**:
  - Deletes only DynBox-owned binaries in the designated bin directory.
  - Preserves user projects, workspace configuration, and Flutter SDKs.
- **Flutter SDK Isolation Boundary**:
  - DynBox installs independently from Flutter and never bundles Flutter or alters Flutter PATH.
  - Resolves Flutter SDKs purely via explicit configuration hierarchy (CLI flag > config.yaml > environment variable).

### 2.9 First-Party DynBox OTA Subsystem (`packages/dynbox_ota`)
- **No-Shorebird Architecture**:
  - DynBox provides its own first-party code update system strictly without Shorebird CLI, Shorebird code push plugins, or custom engine forks.
  - Operates on top of the schema-driven Dynamic UI runtime (`packages/dynbox_ui_runtime`). Updates declarative UI structure, styling, text, layouts, allowlisted animations, and allowlisted actions.
  - Strictly prohibits arbitrary downloaded Dart bytecode execution or native library loading.
- **Release Manifest (`schemas/ota_manifest.v1.json`)**:
  - Versioned release manifest with `appId`, `releaseId`, monotonic integer `version`, `channel` (`development`, `staging`, `production`), `platform`, `minAppVersion`, `runtimeSchemaVersion`, `payloadSha256`, `payloadSizeBytes`, and `signature`.
- **Integrity & Cryptographic Security (`OtaVerifier`)**:
  - Double verification: SHA-256 digest validation and HMAC-SHA256 signature verification.
  - Rejects malformed, expired, oversized (>512 KB), incompatible, or tampered payloads before staging.
- **Resilient Cache & Atomic Staging (`OtaCache`)**:
  - Sandboxed cache directory with atomic staging (`stage_<releaseId>.tmp` renamed to `release_<releaseId>.json`).
  - Automatic Last-Known-Good (LKG) preservation and programmatic rollback support (`rollbackToLkg`).
- **Server Provider Contract & Mocking (`OtaServerProvider`)**:
  - Contract defines `checkForUpdate` and `downloadPayload`.
  - `MockOtaServerProvider`: deterministic, in-memory offline implementation for testing and development.
  - `HttpOtaServerProvider`: generic REST client communicating with compliant update servers (supporting HTTP 204 No Content for up-to-date checks).
  - `SupabaseOtaServerProvider`: official Supabase implementation querying PostgREST `ota_releases` endpoint and downloading payloads from Supabase Storage `ota-payloads` bucket using public `anonKey` under Row Level Security.
- **Supabase Release Backend Integration**:
  - `backend/supabase/migrations/20261016000000_ota_releases.sql` establishes:
    - `public.ota_releases` table tracking release ID, semantic version, channel, platform, payload SHA256, payload size, and signatures.
    - Row Level Security (RLS): client apps use public `anonKey` for read-only access to active compatible releases.
    - Release creation and updating requires elevated `service_role` credentials (never bundled in client apps).
    - Supabase Storage bucket `ota-payloads` with public read and service_role write rules.
- **Safe Source Snapshotting (`SourceArchiver`)**:
  - Scans project directory and builds an immutable manifest of tracked source files with SHA-256 digests.
  - Automatically filters and excludes private keystores (`.keystore`, `.jks`), signing properties (`key.properties`), local credentials (`.env`), build directories (`build/`), and VCS directories (`.git/`).
- **Generated App Integration**:
  - Newly generated projects (`dynbox create <app>`) automatically include `dynbox_ota`, `AppOtaCoordinator`, `DynboxOtaDemoScreen`, and asynchronous non-blocking background update checks in `main.dart`.
- **CLI Management (`dynbox ota`)**:
  - `dynbox ota status [project-path]`: inspect active OTA parameters.
  - `dynbox ota init [project-path]`: initialize or update `.dynbox/config.yaml` OTA block.
  - `dynbox ota check [project-path]`: query update status against local mock, remote HTTP server, or Supabase.
  - `dynbox ota validate <path>`: validate release manifest or Dynamic UI configuration bundle.
  - `dynbox ota sync-source [project-path]`: generate an immutable, secret-free source snapshot.
  - `dynbox ota publish <project-path>`: explicit user-driven publishing flow with mandatory `--confirm` for production and `--supabase-service-key` support.

### 2.10 Future Subsystems & Boundaries (Phase 7)
- **Dedicated Cloud Build Worker Architecture**:
  - Supabase provides metadata and asset storage, not native compilation. Cloud builds require dedicated containerized build runners with pinned Flutter SDK, Android NDK/SDK, and macOS runners for Xcode.
- **Dart Code Patching Extension Boundary**:
  - Current OTA updates schema-driven Dynamic UI configurations.
  - Store policies (Apple Guideline 2.5.2) prohibit executing arbitrary downloaded native code. Future Dart code patching requires a specialized sandboxed runtime/Wasm interpreter rather than loading arbitrary binary executables.

