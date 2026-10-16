# DynBox — Security Policy & Guidelines

## 1. Core Security Principles
DynBox adheres strictly to secure-by-default software engineering practices. As a developer tooling and project orchestration platform, security boundaries must be rigorously maintained to protect developer workstations, source repositories, and downstream end-user applications.

## 2. Secrets Management & Zero-Leakage Policy
- **No Hardcoded Secrets**: Service account JSON files, Supabase service-role keys, private database connection strings, keystore passwords, signing certificates, and OAuth bearer tokens must NEVER be committed to Git repositories or hardcoded into source templates or configuration schemas (`schemas/project_spec.v1.json`, `.dynbox/config.yaml`).
- **Client Identifier vs. Privileged Credential Separation**:
  - *Public Identifiers*: Firebase Project IDs, Supabase Project URLs, and client anon/public keys (intended for client application bundle distribution) are treated as identifiers. They are protected exclusively via backend security rules (Firebase Security Rules, Supabase Row-Level Security).
  - *Privileged Credentials*: Service-role keys, secret master keys, and database passwords must NEVER enter client code (`lib/supabase_config.dart`, `lib/firebase_options.dart`) or DynBox configuration files.
  - *Rejection of Privileged Keys*: The Supabase adapter explicitly inspects configured keys and rejects tokens containing `service_role` or `secret`.
- **Environment Isolation**: Secret environment variables must be injected only at runtime or during isolated build steps via environment variables (e.g., CI secrets, `.env.local` which is explicitly ignored by `.gitignore`).

## 3. Safe Logging & Subprocess Execution
- **Zero Shell Evaluation (`runInShell: false`)**: The `SafeProcessExecutor` strictly spawns executables via `Process.start` without shell wrapper evaluation. Commands are never evaluated inside `sh -c` or `bash -c`, mitigating shell injection and argument-splitting exploits.
- **Discrete Argument Preservation**: Arguments containing spaces, quotes, or metacharacters (e.g., semicolons, pipes, ampersands) are handled as discrete literal arguments by the operating system kernel rather than shell commands.
- **Secret Redaction**: `SafeProcessExecutor` masks known secrets and sensitive tokens from stdout and stderr output before recording or displaying output.
- **No Wholesale Environment Logging**: Process executors never dump inherited environment variables into diagnostic logs.

## 4. Workstation Safeguards & Destructive Actions
- **No Destructive Workspace Alterations**: The DynBox CLI will not recursively delete user directories (`rm -rf`), wipe Git history, or overwrite uncommitted files without explicit user consent.
- **Strict Overwrite Protection**: `dynbox create` validates destination directories and aborts immediately if the target folder exists. It never passes `--overwrite` to Flutter and never deletes existing user directories.
- **Path Traversal Protection**: Project names and target paths are validated to ensure they cannot escape the intended parent directory via directory traversal sequences (`..`).
- **Partial Project Preservation**: In the event of a failure during project generation, DynBox preserves the partially generated directory at its explicit path for developer diagnosis, rather than attempting an unsafe, automatic recursive deletion rollback.
- **No Silent Startup Modifications**: DynBox will never write to or modify developer shell configuration profiles (`~/.zshrc`, `~/.bashrc`, `~/.profile`) or system directories.
- **Strict SDK Boundaries**: DynBox verifies paths and binaries before execution to prevent executing malicious or rogue binaries masquerading as SDK tooling. Ambient `$PATH` is never used as an implicit fallback.

## 5. Dynamic UI Runtime & OTA Safeguards
The Dynamic UI runtime (`packages/dynbox_ui_runtime`) is designed specifically to maintain strict platform sandbox constraints and comply with Apple App Store Review Guidelines (section 2.5.2) and Google Play Developer Policies:
- **No Arbitrary Executable Code**: The runtime does not download, compile, or execute arbitrary Dart code, JavaScript, bytecode, native dynamic libraries, or reflection instructions.
- **Strict Allowlisted Registry**: Only the closed set of 12 built-in widgets in `WidgetRegistry` can be rendered. Remotely supplied class names or dynamic reflection cannot be instantiated.
- **Bounded Resource Limits**: Documents are constrained by size (max 512 KB), component depth (max 20 levels), and child counts (max 50 children). Durations and dimensions have numeric bounds to prevent CPU/memory exhaustion.
- **Closed Actions & Navigation Boundaries**: Actions are restricted to declared pre-bundled routes (`registeredRoutes`). Network URL actions (`open_url`) strictly require HTTPS. Remote configurations cannot access authentication tokens, local device files, device permissions, or platform channels.
- **No Secrets in Bundles**: Configurations contain only public styling, text, and structure. Client tokens or secret keys are prohibited.
- **Safe Fallback & Rollback**: Any parsing error, schema validation failure, version incompatibility, or fetch failure preserves the active or bundled default UI without degrading to a blank screen.

## 6. Native Build & Signing Security Guidelines
- **Zero Secrets in Arguments or Command Logs**: Keystore passwords, signing keys, and certificate credentials must NEVER be passed as plain CLI arguments or written into logs.
- **Android Signing Isolation**: DynBox respects standard Flutter Android signing conventions (`android/key.properties`). Developers must configure signing files locally and ensure `key.properties` and `.jks`/`.keystore` files remain ignored by Git. DynBox will never auto-generate production keystores without explicit developer interaction.
- **iOS Codesigning Boundaries**: DynBox supports `--codesign` and `--no-codesign` via official Flutter options. DynBox will never modify the macOS keychain, create developer certificates, or mutate App Store Connect provisioning profiles without developer consent.
- **Clear Distinction of Build Readiness**: DynBox explicitly marks release artifacts as unsigned when signing files are missing. It never misleads developers by declaring an unsigned artifact ready for Google Play or Apple App Store distribution.
- **No Destructive Cleanups**: A failed build process never attempts to delete the project tree. Intermediate build logs and error outputs are preserved for debugging.

## 7. Standalone Installer & Upgrade Security Guidelines
- **Mandatory Cryptographic Verification**: The installer scripts (`install.sh`, `install.ps1`) and CLI upgrader (`dynbox upgrade`) download artifacts into isolated temporary staging directories and strictly verify SHA-256 digests against `release_manifest.json` before unpacking or executing binaries. Any digest mismatch aborts immediately.
- **Atomic Replacement & Automatic Rollback**: Upgrades copy the running executable to a temporary backup file (`.dynbox_backup`) before staging new binaries. If extraction, staging, or permission setting fails, the backup is restored immediately.
- **Scoped User-Owned File Operations**: The installer and uninstaller operate exclusively in user-owned directories (`~/.dynbox/bin` or `%LOCALAPPDATA%\DynBox\bin`). They never request administrator/root privileges, never modify system directories, and never touch unrelated binaries.
- **Idempotent Shell Profile Management**: Installer scripts inspect existing profile configurations (`~/.zshrc`, `~/.bashrc`, `~/.profile`) before making changes. Prior to writing PATH additions, a timestamped backup of the profile is generated.
- **Zero Secrets in Installer Logs**: Neither the installer nor upgrader logs sensitive environment variables, credentials, or authentication tokens.
- **Flutter SDK Isolation**: The installation pipeline does not bundle, download, modify, or inject ambient Flutter binaries into system PATH. DynBox strictly acts as an orchestrator and interacts only with explicitly pinned Flutter SDKs.

## 8. DynBox First-Party OTA Update Security & Integrity
- **No Arbitrary Dart / Native Code Execution (No Shorebird)**:
  - DynBox does not use Shorebird or any engine fork. It does not load, patch, or execute downloaded native binaries (`.so`, `.dylib`, `.dll`) or arbitrary Dart bytecode.
  - Updates are strictly declarative schema-driven UI configurations delivered to `packages/dynbox_ui_runtime`.
- **Two-Tier Cryptographic Verification**:
  - Every downloaded release manifest and payload must satisfy two-tier verification:
    1. SHA-256 Digest Verification: The exact binary hash of the downloaded payload is verified against `payloadSha256` in the manifest before staging.
    2. Cryptographic Signature Verification: Payloads must match their HMAC-SHA256 signature signed with the publisher's key and validated against the client's configured verification key.
- **Strict Size and Complexity Bounds**:
  - Payloads are capped at a strict 512 KB maximum size to prevent memory exhaustion and denial-of-service vectors.
  - Component nesting depth is capped at 15-20 levels; lists of children are limited to 50 elements.
- **Sandboxed Atomic Staging & Rollback**:
  - Updates are downloaded into isolated temporary staging files (`stage_<releaseId>.tmp`) and renamed atomically only after digest and signature verification succeed.
  - The cache maintains the previous active version as Last-Known-Good (LKG). If an update fails or is rejected, the client falls back to LKG or bundled defaults.
- **Offline Safety & No Default Remote Calls**:
  - Project generation (`dynbox create <app>`) works 100% offline and never contacts remote servers or transmits telemetry.
  - Client applications start with an in-memory/offline mock provider by default unless an explicit remote server URL is configured in `.dynbox/config.yaml`.
- **Zero Leaks of Server Secrets**:
  - Client applications never store private publisher signing keys or administrative credentials.
  - The CLI `dynbox ota publish` command requires explicit local secret-key provisioning and never commits credentials to project source control.
  - Client apps connecting to Supabase use strictly public `anonKey` identifiers subject to Row Level Security (RLS). Privileged `service_role` keys are strictly prohibited in client code and will cause immediate constructor exceptions.
- **Supabase Backend Security & Row Level Security (RLS)**:
  - Database table `public.ota_releases` enables RLS by default.
  - Public anonymous clients (`anon`) have `SELECT` permission strictly filtered to active, non-rolled-back releases (`is_active = true AND is_rolled_back = false`).
  - Mutations (`INSERT`, `UPDATE`, `DELETE`) are strictly restricted to `service_role` administrators. Public clients can never create or modify releases.
  - Supabase Storage bucket `ota-payloads` is read-only for public clients and writable exclusively by `service_role`.
- **Source Snapshotting & Sync Security (`dynbox ota sync-source`)**:
  - Snapshot archiver automatically audits and excludes sensitive files: Android keystores (`.keystore`, `.jks`), signing properties (`key.properties`), local environment secrets (`.env*`), private SSH keys, and VCS metadata (`.git/`).
  - Guarantees that synchronized source trees are clean and safe for remote build infrastructure without leaking signing keys or developer secrets.

