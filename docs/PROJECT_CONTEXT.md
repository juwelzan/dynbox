# DynBox — Project Context

## 1. Product Goals
DynBox is a developer-owned Flutter project orchestration platform. It is engineered to give developers complete sovereignty over their Flutter project lifecycles, configuration generation, and platform targets without vendor lock-in or fragile shell scripts.

The platform's pillars include:
- A custom developer CLI named `dynbox`.
- Isolated, explicitly selected official Flutter SDK versions per workspace/project.
- Declarative versioned project specification schema (`schemas/project_spec.v1.json`).
- Typed workspace configuration (`.dynbox/config.yaml`).
- Safe subprocess execution for official Flutter CLI toolchains with secret redaction and no shell evaluation.
- Deterministic project creation (`dynbox create <project-name>`) with curated architecture presets (`minimal`, `layered`, `feature_first`).
- Provider-agnostic backend adapter architecture with official integrations:
  - `dynbox backend status`
  - `dynbox backend configure firebase` (via official FlutterFire CLI)
  - `dynbox backend configure supabase` (via official HTTPS client configuration and `lib/supabase_config.dart`)
- Dynamic UI Over-The-Air (OTA) schema system (pure Dart declarative UI models; no claims of updating arbitrary compiled native code).
- Android and iOS build orchestration pipeline.

## 2. Current Status
- **Phase 1 (Repository Foundation & CLI Verification)**: Complete and verified.
- **Phase 2 (Project Specification, Configuration & SDK Execution)**: Complete and verified.
- **Phase 3 (Project Generation & Architecture Presets)**: Complete and verified.
- **Phase 4 (Backend Adapter Architecture: Firebase & Supabase)**: Complete and verified.
- **Phase 5 (Dynamic UI Runtime & OTA Foundation)**: Complete and verified.
- **Phase 6 & 6.1 (Native Build Orchestration & Hardening)**: Complete and verified.
- **Phase 6.2 (Standalone Cross-Platform Installer & Upgrader)**: Complete and verified.
- **DynBox First-Party OTA Update System (No Shorebird)**: Complete and verified.

## 3. Approved Architecture Decisions
1. **Official SDKs**: Only official, unmodified Flutter and Dart SDK releases are used. The platform never forks or modifies the Flutter engine, embedder, or Dart compiler.
2. **Explicit SDK Selection Precedence**: DynBox strictly invokes explicitly configured SDK paths according to a documented hierarchy:
   - CLI argument (`--flutter-root <path>`)
   - Workspace configuration (`.dynbox/config.yaml` -> `sdk.flutter.path`)
   - Environment variable (`DYNBOX_FLUTTER_ROOT`)
   - *Never* silently falls back to arbitrary ambient `flutter` binaries on system `$PATH`.
3. **No Hidden Shell Modifications**: DynBox will not edit `PATH`, `.zshrc`, `.bashrc`, or system environment startup files.
4. **Safe Subprocess Execution**: External tools (`flutter`, `dart`, `git`, `flutterfire`, `firebase`, `supabase`) are invoked using structured argument lists with `runInShell: false`. Command strings are never concatenated for shell evaluation.
5. **Secret Redaction & Protection**: Service-account keys, Supabase service-role keys, database passwords, and OAuth tokens are never committed to source control or embedded in schemas. Process execution logs redact known sensitive credentials.
6. **Provider Boundary**:
   - Distinct separation between detecting a provider, configuring an existing project, creating a cloud project, and deploying production resources.
   - DynBox supports detection and local client configuration of existing cloud projects.
   - Cloud project creation, billing activation, database migrations, and deployments are explicitly left to the user's manual cloud workflows or later phases.
7. **Public Identifier vs. Privileged Credential**:
   - Firebase Project IDs, Supabase Project URLs, and client anon keys (both legacy JWTs and newer `sb_publishable_...` keys) are treated as public identifiers and configured into client applications subject to backend security rules (Firebase Security Rules, Supabase Row-Level Security).
   - Privileged service-role and secret keys are strictly forbidden and rejected if entered.
8. **Sandboxed Declarative Dynamic UI AST**:
   - The Dynamic UI runtime operates on a closed, allowlisted widget AST (`packages/dynbox_ui_runtime`).
   - Strictly prohibits arbitrary executable expressions, dynamic reflection, remote code execution, or downloading native libraries.
   - Fully complies with App Store and Google Play code execution review guidelines.

## 4. Implemented Features

### Phase 1: Repository Foundation & CLI Verification
- Verified directory layout (`apps/`, `packages/`, `cli/dynbox/`, `backend/`, `schemas/`, `docs/`, `scripts/`, `tests/`).
- Root `.gitignore` safeguarding against secrets and build artifacts.
- Dart CLI foundation with `--help`, `--version`, and `doctor`.
- Terminal output formatting and semantic exit codes.

### Phase 2: Project Specification, Configuration & SDK Execution
- Project specification schema (`schemas/project_spec.v1.json`).
- Typed workspace configuration (`cli/dynbox/lib/src/config/dynbox_config.dart`) for `.dynbox/config.yaml`.
- Explicit SDK Resolver (`cli/dynbox/lib/src/sdk/sdk_resolver.dart`) with absolute path resolution.
- Safe process executor (`cli/dynbox/lib/src/sdk/safe_process_executor.dart`) and `FlutterSdkRunner`.

### Phase 3: Project Generation & Architecture Presets
- Project creation command (`dynbox create <project-name>`) with options (`--path`, `--flutter-root`, `--org`, `--platforms`, `--preset`).
- Architecture presets: `minimal`, `layered`, `feature_first`.
- Automatic `.dynbox/config.yaml` initialization.

### Phase 4: Backend Adapter Architecture (Firebase & Supabase)
- **Typed Adapter Contract (`cli/dynbox/lib/src/backend/backend_adapter.dart`)**:
  - `BackendAdapter` abstraction with `inspectStatus` and `configure`.
  - Immutable typed status models: `CliToolStatus`, `AuthStatus`, `ProviderStatusReport`, `ProviderConfigureResult`.
- **Firebase Adapter (`cli/dynbox/lib/src/backend/firebase_adapter.dart`)**:
  - Detects Firebase CLI (`firebase`) and FlutterFire CLI (`flutterfire`).
  - Verifies authentication status via `firebase login:list`.
  - Configures existing Firebase projects using official `flutterfire configure`.
  - Updates `.dynbox/config.yaml` with the configured project ID after verification.
- **Supabase Adapter (`cli/dynbox/lib/src/backend/supabase_adapter.dart`)**:
  - Validates HTTPS project URL format.
  - Accepts both legacy JWT anon keys and modern `sb_publishable_...` tokens while explicitly rejecting privileged `service_role` or secret keys.
  - Generates `lib/supabase_config.dart` with clear RLS security notices.
  - Updates `.dynbox/config.yaml` with `backend.supabase.projectUrl`.
- **CLI Commands (`cli/dynbox/lib/src/commands/backend_command.dart`)**:
  - `dynbox backend status`
  - `dynbox backend configure firebase --project-id <id>`
  - `dynbox backend configure supabase --project-url <url> --anon-key <key>`

### Phase 5: Dynamic UI Runtime & OTA Foundation
- **Versioned JSON Schema (`schemas/dynamic_ui.v1.json`)**:
  - JSON Schema Draft 2020-12 defining constrained, declarative UI configurations.
  - Validates revision monotonicity, app semver compatibility, max tree depth, max 50 children, bounded size limits (512 KB), and closed enums.
- **Typed Dart AST & Parser (`packages/dynbox_ui_runtime/lib/src/models/`, `lib/src/parser/`)**:
  - Pure Dart models for screens, components, properties, actions, themes, and animations.
  - Rejects unsupported schema versions, unknown widgets, malformed JSON, unapproved icons, and non-HTTPS image URLs.
- **Allowlisted Widget Registry (`packages/dynbox_ui_runtime/lib/src/registry/`)**:
  - Closed set of 12 built-in widgets: `text`, `container`, `row`, `column`, `padding`, `image`, `icon`, `button`, `sized_box`, `card`, `divider`, `visibility`.
  - Prohibits reflection, dynamic class instantiation, and arbitrary code execution.
- **Closed Action Dispatcher**:
  - Permitted actions: `navigate` (restricted to declared/allowlisted routes), `show_dialog`, `open_url` (strictly HTTPS), and `toggle_flag`.
- **Configuration Source Abstraction (`packages/dynbox_ui_runtime/lib/src/source/`)**:
  - `DynamicUiConfigSource` interface with `LocalFileConfigSource` and `MemoryConfigSource`.
- **Runtime Lifecycle & Rollback Controller (`packages/dynbox_ui_runtime/lib/src/runtime/`)**:
  - Step 1: Loads bundled default configuration.
  - Step 2: Loads cached last-known-good configuration if available.
  - Step 3: Fetches candidate configuration from selected source with timeouts.
  - Step 4: Validates complete candidate document and app version constraints.
  - Step 5: Activates valid candidate and stores to `DynamicUiStorage`.
  - Step 6: On candidate failure or network outage, retains or falls back to last known-good configuration without blank screen degradation.
  - Step 7: Supports explicit programmatic rollback (`rollbackToLastKnownGood`).
- **Comprehensive Verification**:
  - 15 unit tests in `packages/dynbox_ui_runtime` passing with 0 analyzer issues.
  - 64 unit tests in `cli/dynbox` passing with 0 analyzer issues.

### Phase 6: Native Build & Release Orchestration
- **CLI Build Command (`cli/dynbox/lib/src/commands/build_command.dart`)**:
  - `dynbox build <project-path> --platform <android|ios> --target <apk|appbundle|ipa|archive> [--mode debug|profile|release] [--dry-run]`
  - Validates project structure, `.dynbox/config.yaml`, and strict `kind: flutter_app`.
  - Non-mutating `--dry-run` flag validates host toolchain and arguments without running full compilation.
  - Distinct handling of archive (`Runner.xcarchive`) and IPA (`app.ipa`) targets.
- **Host Toolchain & SDK Validation (`BuildValidator`)**:
  - Validates pinned SDK via explicit precedence without ambient `$PATH` fallback.
  - Verifies Java (JDK) presence for Android builds.
  - Verifies macOS host and Xcode (`xcodebuild`) presence for iOS builds.
  - Supports external Android signing configuration via `DYNBOX_KEY_PROPERTIES_PATH` to isolate secrets outside the workspace.
- **Safe Subprocess Execution**:
  - Delegates strictly to `FlutterSdkRunner` and `SafeProcessExecutor`.
  - Zero shell evaluation (`runInShell: false`), discrete argument tokenization, and timeout protection.
  - Mode-accurate AAB bundle path resolution (`build/app/outputs/bundle/<mode>/app-<mode>.aab`).
- **Post-Build Artifact Verification (`ArtifactVerification`)**:
  - Confirms physical artifact existence on disk before reporting success.
  - Computes cryptographic SHA-256 checksum and records file size in bytes and build timestamp.
  - Performs active platform tool verification via `apksigner verify` (Android APK), `jarsigner -verify` (Android AAB), or `codesign -v` (iOS) with 4-state `SignatureStatus` (`verifiedSigned`, `verifiedUnsigned`, `verificationFailed`, `unknown`).
- **Comprehensive Verification**:
  - 21 automated unit tests (85 total passing in `cli/dynbox`, 0 analyzer warnings).

### First-Party DynBox OTA System (No Shorebird)
- **OTA Manifest Schema (`schemas/ota_manifest.v1.json`)**:
  - Versioned release manifest with `appId`, `releaseId`, `version`, `channel`, `platform`, `minAppVersion`, `runtimeSchemaVersion`, `payloadSha256`, `payloadSizeBytes`, and `signature`.
- **OTA Client Package (`packages/dynbox_ota`)**:
  - `DynboxOtaClient` with typed state machine (`checking`, `updateAvailable`, `downloading`, `verifying`, `readyToActivate`, `upToDate`, `failed`).
  - Cryptographic verification via `OtaVerifier`: SHA-256 digest validation and HMAC-SHA256 signature verification.
  - `OtaCache` providing sandbox filesystem caching, atomic temp-file swaps, and Last-Known-Good (LKG) rollback support.
  - `DynboxOtaService` bridging OTA downloads into `DynamicUiController` for live UI hot replacement.
  - Provider contract `OtaServerProvider` with `MockOtaServerProvider` for deterministic offline testing, `HttpOtaServerProvider` for standard REST servers, and `SupabaseOtaServerProvider` for Supabase PostgREST & Storage backends.
- **Supabase Release Management & Migration (`backend/supabase/migrations/20261016000000_ota_releases.sql`)**:
  - `public.ota_releases` table storing release identity, cryptographic hash, size, and signature metadata.
  - Strict Row Level Security: public clients use public `anonKey` for read-only access to compatible active releases; mutations restricted to `service_role`.
  - Supabase Storage bucket `ota-payloads` for public asset downloads with administrative upload protections.
- **Source Synchronization & Safe Snapshotting (`SourceArchiver`)**:
  - CLI `dynbox ota sync-source` scans project files and outputs deterministic SHA-256 source release manifests.
  - Strictly audits and excludes keystores, signing configs (`key.properties`), local credentials (`.env*`), and VCS directories (`.git/`).
- **Generated App Integration (`dynbox create <app>`)**:
  - Scaffolded apps include `dynbox_ota` and `dynbox_ui_runtime` dependencies.
  - Includes `lib/dynbox_ota_service.dart` with `AppOtaCoordinator` (supporting local mock and optional Supabase backend connections).
  - Includes `lib/dynbox_ota_demo_screen.dart` with real update states, "Check for Updates", "Download & Apply", and "Rollback to LKG" actions.
  - `lib/main.dart` starts OTA update check in background asynchronously without blocking initial render.
  - Completely offline-compatible: zero network or cloud resources needed during creation.
- **CLI Workflow (`dynbox ota`)**:
  - `dynbox ota status [project-path]`
  - `dynbox ota init [project-path]`
  - `dynbox ota check [project-path]`
  - `dynbox ota validate <manifest-or-payload-path>`
  - `dynbox ota sync-source [project-path]`
  - `dynbox ota publish <project-path> --channel <channel> --payload <path> --confirm [--supabase-service-key <key>]`

## 5. Unimplemented Features & Future Architecture Boundaries
- **Remote Cloud Compilation Workers**: Supabase serves as a release metadata and asset storage layer, not a compiler. Cloud builds require dedicated, isolated containerized build workers with pinned Flutter/Android/Xcode toolchains.
- **Dart Code Hot Patching**: OTA updates modify declarative Dynamic UI layouts and configurations. Arbitrary downloaded Dart bytecode / native executable loading is prohibited by store guidelines and not supported.
- Remote cloud project creation and billing mutations.
- Database migrations, schema synchronizations, and Edge Function deployment.
- Web or desktop administration dashboard and visual editor.
- Automated store publishing / upload services (App Store Connect API / Google Play Developer API).

## 6. Next Recommended Task
- **Phase 7 — Automated Store Publishing & Release Management**:
  - Implement secure API token validation for App Store Connect and Google Play Developer API.
  - Build automated artifact uploaders with release track management.
