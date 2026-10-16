# DynBox

DynBox is a developer-owned Flutter project orchestration platform designed to provide sovereign, reproducible, and modular Flutter development workflows.

---

## Standalone Installation (Recommended)

Install the standalone DynBox native CLI directly on your machine without cloning the repository or pre-installing Dart.

### macOS & Linux

Using official one-liner installation:
```bash
curl -fsSL https://raw.githubusercontent.com/juwelzan/dynbox/master/scripts/install.sh | sh
```

Safer alternative (inspect before running):
```bash
curl -fsSL https://raw.githubusercontent.com/juwelzan/dynbox/master/scripts/install.sh -o install.sh
cat install.sh # inspect the script
sh install.sh
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/juwelzan/dynbox/master/scripts/install.ps1 | iex
```

### Installation Details & PATH Setup
- **Install Directory**:
  - macOS / Linux: `~/.dynbox/bin/dynbox`
  - Windows: `%LOCALAPPDATA%\DynBox\bin\dynbox.exe`
- **PATH Configuration**: The installer adds the installation directory to your shell configuration (`~/.zshrc`, `~/.bashrc`, or Windows User PATH) idempotently after creating a timestamped backup of the profile.
- **Manual PATH Setup (if preferred)**:
  ```bash
  export PATH="$PATH:$HOME/.dynbox/bin"
  ```
- **Verification & First-Time Setup**:
  ```bash
  dynbox --version
  dynbox setup
  dynbox doctor
  ```

---

## First-Time Environment Setup (`dynbox setup`)

On a new machine where Flutter is not yet configured, run the interactive guided setup:

```bash
dynbox setup
```

This will:
1. Detect if a valid Flutter SDK is already configured.
2. If missing, fetch official release metadata and offer to download and verify the latest official stable Flutter SDK.
3. Verify downloaded archives using official SHA-256 integrity checksums.
4. Extract safely to `~/.dynbox/sdks/<version>` without touching PATH or ambient software.
5. Set the installed managed SDK as your persistent global default.
6. Report platform build prerequisites (Android JDK, Android SDK, and Xcode on macOS).

---

## Official Flutter SDK Management (`dynbox sdk`)

Manage official Flutter SDK installations deterministically:

```bash
# List available official releases for your host OS/architecture
dynbox sdk list

# List locally installed managed Flutter SDKs
dynbox sdk list-installed

# Download, verify, and install official stable Flutter SDK
dynbox sdk install stable

# Install a specific pinned version (e.g. 3.47.7)
dynbox sdk install 3.47.7

# Inspect the active Flutter SDK
dynbox sdk current

# Switch the global default SDK to an installed version
dynbox sdk use 3.47.7

# Remove an installed managed SDK (with confirmation)
dynbox sdk remove 3.47.7
```

Managed SDKs are stored safely in:
- macOS & Linux: `~/.dynbox/sdks/<version>`
- Windows: `%LOCALAPPDATA%\DynBox\sdks\<version>`

---

### Upgrading DynBox
Check for updates or perform an atomic in-place upgrade with automatic rollback on failure:
```bash
# Check if a new version is available
dynbox upgrade --check

# Upgrade to latest release
dynbox upgrade

# Upgrade (or downgrade) to a pinned version
dynbox upgrade --version 0.2.0
```

### Uninstalling DynBox
Safely removes only DynBox-owned binaries without touching your Flutter SDKs, configuration, or user projects:
```bash
dynbox uninstall
```

---

## Prerequisites

- **Dart SDK**: 3.13.4 or higher
- **Flutter SDK**: Official Flutter SDK release (unmodified)
- **Git**: 2.x+
- **macOS / Linux / Windows**
- *(Optional for Backend)*:
  - **Firebase CLI** (`firebase-tools`) & **FlutterFire CLI** (`flutterfire_cli`)
  - **Supabase CLI** (`supabase`)

---

## Repository Structure

```text
dynbox/
├── apps/               # Future generated or managed application workspaces
├── packages/           # Shared core packages and client libraries
├── cli/
│   └── dynbox/         # DynBox developer CLI (Dart package)
├── backend/
│   ├── adapters/       # Provider backend adapters (Firebase, Supabase)
│   └── templates/      # Project generation templates
├── schemas/            # Declarative workspace and project specification schemas
│   └── project_spec.v1.json
├── docs/
│   ├── PROJECT_CONTEXT.md
│   ├── ARCHITECTURE.md
│   ├── ROADMAP.md
│   └── SECURITY.md
├── scripts/            # Repository management and automation scripts
├── tests/              # End-to-end and cross-subsystem test suites
├── .gitignore
└── README.md
```

---

## Local CLI Development & Verification

### 1. Install CLI Dependencies
```bash
cd cli/dynbox
dart pub get
```

### 2. Run Code Analysis & Formatting
```bash
cd cli/dynbox
dart format --output=none --set-exit-if-changed .
dart analyze .
```

### 3. Run Automated Tests
```bash
cd cli/dynbox
dart test
```

### 4. Running DynBox CLI Commands
From `cli/dynbox`:

- **Display General Help:**
  ```bash
  dart run bin/dynbox.dart --help
  ```

- **Check Version:**
  ```bash
  dart run bin/dynbox.dart --version
  ```

- **Run Environment & SDK Doctor:**
  ```bash
  dart run bin/dynbox.dart doctor
  ```

- **Validate Explicit Flutter SDK Root:**
  ```bash
  dart run bin/dynbox.dart doctor --flutter-root /path/to/flutter
  ```

---

## Creating Projects (`dynbox create`)

Create a new Flutter application using the explicitly configured Flutter SDK and an architecture preset:

```bash
dart run bin/dynbox.dart create my_app
```

### Options:

- `--path <dir>`: Parent directory where the project will be created (defaults to current directory).
- `--flutter-root <path>`: Explicit SDK directory override for this command.
- `--org <domain>`: Reverse-domain organization identifier (default: `com.example`).
- `--platforms <list>`: Comma-separated target platforms (default: `android,ios`).
- `--preset <name>`: Architecture preset (`minimal`, `layered`, `feature_first`) (default: `minimal`).

### Architecture Presets:

1. **`minimal`**: Standard official Flutter starter application.
2. **`layered`**: Generates `lib/app/`, `lib/core/`, `lib/features/`, and `lib/STRUCTURE.md`.
3. **`feature_first`**: Generates `lib/app/`, `lib/core/`, `lib/features/home/presentation/`, and `lib/STRUCTURE.md`.

---

## Backend Provider Integrations (`dynbox backend`)

DynBox provides provider-independent backend management to connect existing cloud projects without hardcoding secrets.

### 1. Inspect Backend Tools & Workspace Status
Inspect detected CLI tools, authentication state, and workspace configuration:

```bash
dart run bin/dynbox.dart backend status
```

### 2. Configure Firebase
Connect an existing Firebase project using the official FlutterFire CLI:

```bash
dart run bin/dynbox.dart backend configure firebase --project-id <your-firebase-project-id>
```

### 3. Configure Supabase
Connect an existing Supabase project with client public configuration:

```bash
dart run bin/dynbox.dart backend configure supabase \
  --project-url https://<your-project-ref>.supabase.co \
  --anon-key <your-public-anon-key> \
  --add-dependency
```

> **Security Reminder**: Never supply `service_role` or secret keys. Client applications must use public anonymous keys protected by database Row Level Security (RLS).

---

## Workspace Configuration (`.dynbox/config.yaml`)

Each DynBox workspace is configured via `.dynbox/config.yaml`. Relative paths resolve against the workspace root.

An example template is available at `.dynbox/config.yaml.example`:

```yaml
configVersion: 1

project:
  name: my_app
  kind: flutter_app # flutter_app, flutter_package, flutter_plugin

sdk:
  flutter:
    source: local
    path: /path/to/official/flutter_sdk
    versionConstraint: ">=3.24.0"

backend:
  provider: firebase # none, firebase, supabase
  firebase:
    projectId: my-project-id
```

---

## Persistent Global Configuration (`dynbox config`)

To avoid repeatedly passing `--flutter-root` when running commands or creating new projects, configure your default Flutter SDK root once globally:

```bash
# Set default Flutter SDK root
dynbox config set flutter-root /path/to/official/flutter

# Read configured SDK root
dynbox config get flutter-root

# List all persistent configuration settings
dynbox config list

# Remove persistent setting
dynbox config unset flutter-root
```

Global configuration is securely persisted in:
- macOS & Linux: `~/.dynbox/config.yaml`
- Windows: `%LOCALAPPDATA%\DynBox\config.yaml`

---

## SDK Selection Precedence

DynBox strictly requires an explicit SDK path and will **never** silently fall back to an ambient `flutter` executable found on system `$PATH`.

The resolution order is:
1. **Command Line Flag**: `--flutter-root <path>` (overrides current command without modifying configuration files)
2. **Workspace Configuration**: `.dynbox/config.yaml` (`sdk.flutter.path` or `flutter_sdk_path`)
3. **Persistent Global Configuration**: `~/.dynbox/config.yaml` (`dynbox config set flutter-root <path>`)
4. **Environment Variable**: `DYNBOX_FLUTTER_ROOT`

If none of these are present, DynBox aborts with an actionable error.

---

## Safe Subprocess Execution

DynBox executes toolchains (`flutter`, `dart`, `git`, `flutterfire`, `firebase`, `supabase`) using `SafeProcessExecutor`:
- Spawns processes directly via `Process.start` with `runInShell: false`.
- Never concatenates commands into a shell string.
- Preserves literal argument boundaries (spaces and metacharacters).
- Redacts known sensitive tokens from stdout/stderr logs.
- Enforces timeout limits and terminates hung child processes.

---

## Native Build & Release Orchestration

DynBox orchestrates official Flutter compilation commands for Android and iOS release artifacts using the pinned SDK:

```bash
# Build an Android APK
dynbox build <project-path> --platform android --target apk --mode release

# Build an Android App Bundle (AAB) with manifest generation
dynbox build <project-path> --platform android --target appbundle --mode release --manifest

# Build an iOS IPA
dynbox build <project-path> --platform ios --target ipa --mode release

# Validate configuration and inspect planned build without compilation
dynbox build <project-path> --platform android --target apk --dry-run

# Output structured JSON for automation or CI pipelines
dynbox build <project-path> --platform android --target apk --dry-run --json

# Run with verbose diagnostic tracing to stderr
dynbox build <project-path> --platform android --target apk --verbose
```

### Build CLI Flags:

- `-p, --platform` *(mandatory)*: `android` or `ios`.
- `-t, --target` *(mandatory)*: `apk`, `appbundle`, `ipa`, or `archive`.
- `-m, --mode`: `release` (default), `profile`, or `debug`.
- `--dry-run`: Validates project, toolchains, permissions, and command structure without running the build.
- `--manifest`: Generates an immutable, machine-readable build manifest (`build/dynbox_manifest.json`) upon verified build success.
- `--json`: Emits complete structured JSON to standard output.
- `-v, --verbose`: Outputs detailed diagnostic execution context to standard error without exposing sensitive credentials.
- `--flutter-root <path>`: Explicit SDK directory override for this build command.
- `--[no-]codesign`: Whether to codesign the output artifact (iOS builds, defaults to true).
- `--export-method`: iOS IPA export distribution method (`app-store`, `ad-hoc`, `development`, `enterprise`).

### Preflight Validation:
- Validates project structure, `pubspec.yaml`, and `.dynbox/config.yaml` (`kind: flutter_app`).
- Validates write permissions for `build/` directory before starting execution.
- Strict pinned SDK resolution (precedence order: CLI arg > workspace config > environment variable; never ambient `$PATH`).
- Checks host tools (Java JDK for Android; macOS and `xcodebuild` for iOS).
- Resolves external signing configurations safely (`DYNBOX_KEY_PROPERTIES_PATH` or `android/key.properties`).

### Build Plan & Dry-Run:
During a `--dry-run`, DynBox validates all prerequisites and outputs a comprehensive build plan including:
- Resolved SDK directory, version, and source.
- Target platform, artifact format, and compilation mode.
- Expected destination artifact path.
- Planned command arguments with sensitive values redacted.
- Verified toolchain prerequisites and available signature verification tools.
- Whether signing is configured.

### Artifact Verification & Manifest:
- Computes SHA-256 checksum and exact byte size.
- Performs actual cryptographic signature checks using host platform tooling (`apksigner verify` for APK, `jarsigner -verify` for AAB, `codesign -v` for iOS) with a 4-state `SignatureStatus` (`verifiedSigned`, `verifiedUnsigned`, `verificationFailed`, `unknown`).
- When `--manifest` is specified on a successful build, writes `build/dynbox_manifest.json`:
  ```json
  {
    "schemaVersion": "1.0",
    "dynboxVersion": "0.1.0",
    "platform": "android",
    "target": "apk",
    "mode": "release",
    "sdkVersion": "3.24.0",
    "artifact": {
      "path": "/path/to/project/build/app/outputs/flutter-apk/app-release.apk",
      "sizeBytes": 18452019,
      "sha256": "3a7b...",
      "signatureStatus": "verified_signed",
      "signatureDetails": "Verified by apksigner"
    },
    "timing": {
      "startedAt": "2026-10-16T12:00:00.000Z",
      "completedAt": "2026-10-16T12:00:45.000Z",
      "durationMs": 45000
    }
  }
  ```
- Failed builds never write or leave misleading success manifests.

---

---

## DynBox First-Party OTA Update System (No Shorebird)

DynBox includes its own first-party code update system implemented and controlled natively by DynBox. It does **not** use Shorebird, does not depend on `shorebird_code_push`, and does not modify the Flutter engine.

### How It Works:
1. **Schema-Driven Dynamic UI**: Updates declarative UI configuration, styling, themes, allowlisted animations, and allowlisted actions through `packages/dynbox_ui_runtime`.
2. **What It Can Update**: Text, colors, padding, layout structures (Column, Row, Container, Card), buttons, allowlisted icons, allowlisted animations (`fade_in`, `slide_up`, `scale`), and safe actions (`navigate`, `show_dialog`, `open_url`).
3. **What It Cannot Update**: Arbitrary downloaded Dart bytecode, native C/C++ libraries (`.so`, `.dylib`), native Android/iOS platform code, or Flutter SDK engine code.
4. **Security & Cryptographic Verification**:
   - Every update bundle is verified against a versioned release manifest (`schemas/ota_manifest.v1.json`).
   - SHA-256 digest validation ensures bytes have not been altered in transit.
   - HMAC-SHA256 signature verification ensures releases originate from an authorized publisher key.
   - Staged atomically in sandbox filesystem cache and backed up with Last-Known-Good (LKG) rollback support.
5. **Supabase Integration & Row Level Security (RLS)**:
   - Metadata and release tracking stored in Supabase table `public.ota_releases` via versioned migration (`backend/supabase/migrations/20261016000000_ota_releases.sql`).
   - Client applications connect via `SupabaseOtaServerProvider` using strictly public `anonKey` identifiers with read-only RLS policies.
   - Publishing releases is strictly protected and requires elevated `service_role` credentials (never bundled in client applications).
   - Storage bucket `ota-payloads` holds release bundles with public read and administrative upload permissions.
6. **Non-Blocking Startup**:
   - `main.dart` initializes bundled UI instantly and runs update checks asynchronously on a background microtask, never blocking first paint or startup.
7. **Offline-First & Deterministic**:
   - `dynbox create <project-name>` succeeds completely offline without requiring accounts, remote credentials, or network access.
   - Includes `MockOtaServerProvider` for instant offline testing and development.

### OTA CLI Commands:
```bash
# Inspect current project OTA status and configuration
dynbox ota status [project-path]

# Initialize or update OTA configuration in .dynbox/config.yaml
dynbox ota init [project-path] --channel production --server-url https://ota.example.com --public-key <key>

# Check for updates against local mock, remote server, or Supabase
dynbox ota check [project-path]

# Validate an OTA release manifest or Dynamic UI payload file
dynbox ota validate <manifest-or-payload-path>

# Generate an immutable, secret-free source release snapshot
dynbox ota sync-source [project-path]

# Explicit user-driven release publishing to Supabase or local staging (requires --confirm for production)
dynbox ota publish [project-path] --channel production --payload <path> --confirm --supabase-service-key <key>
```

---

## Current Status & Limitations

- **Phase 1 (Completed)**: Core CLI, argument parsing, doctor environment inspector, non-zero exit codes.
- **Phase 2 (Completed)**: Project specification schema (`schemas/project_spec.v1.json`), typed `.dynbox/config.yaml` parser, strict SDK resolution precedence, and `SafeProcessExecutor`.
- **Phase 3 (Completed)**: `dynbox create <project-name>` workflow, architecture presets (`minimal`, `layered`, `feature_first`), safe destination validation, and automatic workspace config generation.
- **Phase 4 (Completed)**: Provider-independent backend adapter architecture, `dynbox backend status`, and configuration workflows for existing Firebase and Supabase projects.
- **Phase 5 (Completed)**: Dynamic UI runtime foundation (`packages/dynbox_ui_runtime`), versioned schema (`schemas/dynamic_ui.v1.json`), allowlisted widget registry, safe actions, configuration source abstraction, and fallback/rollback lifecycle.
- **Phase 6 & 6.1 (Completed)**: Native build orchestration (`dynbox build`), host toolchain validation, structured CLI diagnostics (`--verbose`, `--json`), dry-run build plans, machine-readable build manifests (`--manifest`), artifact verification with SHA-256 digests and 4-state signature checks, and strict zero-secret signing policies.
- **Phase 6.2 (Completed)**: Cross-platform installer (`install.sh`, `install.ps1`), standalone native executables, `dynbox upgrade`, and `dynbox uninstall`.
- **DynBox OTA Update System (Completed)**: First-party OTA SDK (`packages/dynbox_ota`), release manifest schema (`schemas/ota_manifest.v1.json`), interactive demo screen in generated apps, cryptographic integrity checks, rollback to LKG, offline mock server, and CLI commands (`dynbox ota`).
- **Planned for Later Phases**: Automated store publishing and release distribution (Phase 7).
