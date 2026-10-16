#!/bin/sh
# DynBox Official Installation Script (macOS & Linux)
# Installs standalone DynBox CLI into ~/.dynbox/bin and updates shell PATH idempotently.
set -e

# Default configuration
DYNBOX_INSTALL_DIR="${DYNBOX_INSTALL_DIR:-$HOME/.dynbox/bin}"
DYNBOX_RELEASE_URL="${DYNBOX_RELEASE_URL:-}"
DYNBOX_VERSION="${DYNBOX_VERSION:-latest}"

echo "=========================================================="
echo "           DynBox CLI Cross-Platform Installer            "
echo "=========================================================="
echo ""

# 1. Detect Operating System and CPU Architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    TARGET_OS="macos"
    ;;
  Linux)
    TARGET_OS="linux"
    ;;
  *)
    echo "❌ Error: Unsupported operating system: $OS"
    echo "DynBox standalone installer supports macOS and Linux."
    echo "On Windows, please use the PowerShell installer: install.ps1"
    exit 1
    ;;
esac

case "$ARCH" in
  arm64|aarch64)
    TARGET_ARCH="arm64"
    ;;
  x86_64|amd64)
    TARGET_ARCH="x64"
    ;;
  *)
    echo "❌ Error: Unsupported CPU architecture: $ARCH"
    exit 1
    ;;
esac

PLATFORM_ID="${TARGET_OS}-${TARGET_ARCH}"
echo "Detected Platform: ${PLATFORM_ID}"
echo "Installation Directory: ${DYNBOX_INSTALL_DIR}"
echo ""

# 2. Check Prerequisites
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "❌ Error: curl or wget is required to download DynBox."
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "❌ Error: tar is required to extract DynBox release archives."
  exit 1
fi

# 3. Create Secure Temporary Directory
TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'dynbox_install')"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# 4. Resolve Base Release URL
if [ -z "$DYNBOX_RELEASE_URL" ]; then
  if [ "$DYNBOX_VERSION" = "latest" ]; then
    DYNBOX_RELEASE_URL="https://github.com/juwelzan/dynbox/releases/latest/download"
  else
    DYNBOX_RELEASE_URL="https://github.com/juwelzan/dynbox/releases/download/v${DYNBOX_VERSION}"
  fi
fi

MANIFEST_URL="${DYNBOX_RELEASE_URL}/release_manifest.json"
echo "Fetching release metadata from:"
echo "  $MANIFEST_URL"
echo ""

download_file() {
  url="$1"
  dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -qO "$dest" "$url"
  fi
}

MANIFEST_FILE="${TEMP_DIR}/release_manifest.json"
if ! download_file "$MANIFEST_URL" "$MANIFEST_FILE"; then
  echo "❌ Error: Failed to download release manifest from $MANIFEST_URL."
  echo "Please check your network connection or verify that the release exists."
  exit 1
fi

# Parse manifest (using grep / sed to avoid python/jq dependency)
RESOLVED_VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$MANIFEST_FILE" | head -n1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"//;s/"//')"
if [ -z "$RESOLVED_VERSION" ]; then
  echo "❌ Error: Malformed release manifest."
  exit 1
fi

echo "Resolved DynBox Version: v${RESOLVED_VERSION}"

# Locate artifact entry for platform
ARTIFACT_NAME="dynbox-v${RESOLVED_VERSION}-${PLATFORM_ID}.tar.gz"
EXPECTED_SHA256="$(grep -A 5 "\"$PLATFORM_ID\"" "$MANIFEST_FILE" | grep -o '"sha256"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"sha256"[[:space:]]*:[[:space:]]*"//;s/"//')"

if [ -z "$EXPECTED_SHA256" ]; then
  echo "❌ Error: No release artifact available for ${PLATFORM_ID} in version v${RESOLVED_VERSION}."
  exit 1
fi

ARTIFACT_URL="${DYNBOX_RELEASE_URL}/${ARTIFACT_NAME}"
ARCHIVE_FILE="${TEMP_DIR}/${ARTIFACT_NAME}"

echo "Downloading ${ARTIFACT_NAME}..."
if ! download_file "$ARTIFACT_URL" "$ARCHIVE_FILE"; then
  echo "❌ Error: Failed to download artifact from $ARTIFACT_URL."
  exit 1
fi

# 5. Cryptographic Integrity Verification (SHA-256)
echo "Verifying SHA-256 checksum..."
ACTUAL_SHA256=""
if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_FILE" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "$ARCHIVE_FILE" | awk '{print $1}')"
else
  echo "❌ Error: Neither shasum nor sha256sum found for integrity verification."
  exit 1
fi

if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "❌ Error: Cryptographic checksum mismatch!"
  echo "  Expected: $EXPECTED_SHA256"
  echo "  Actual:   $ACTUAL_SHA256"
  echo "Installation aborted to protect system integrity."
  exit 1
fi
echo "✅ Checksum verified."

# 6. Extract Archive
mkdir -p "$TEMP_DIR/extracted"
tar -xzf "$ARCHIVE_FILE" -C "$TEMP_DIR/extracted"

if [ ! -f "$TEMP_DIR/extracted/dynbox" ]; then
  echo "❌ Error: Archive did not contain 'dynbox' binary."
  exit 1
fi

chmod +x "$TEMP_DIR/extracted/dynbox"

# 7. Atomic Install to User Directory
mkdir -p "$DYNBOX_INSTALL_DIR"
cp "$TEMP_DIR/extracted/dynbox" "$DYNBOX_INSTALL_DIR/dynbox.tmp"
mv -f "$DYNBOX_INSTALL_DIR/dynbox.tmp" "$DYNBOX_INSTALL_DIR/dynbox"
chmod +x "$DYNBOX_INSTALL_DIR/dynbox"

echo "✅ DynBox binary installed at: $DYNBOX_INSTALL_DIR/dynbox"
echo ""

# 8. Configure Shell PATH Idempotently
add_to_profile() {
  profile_file="$1"
  line="export PATH=\"\$PATH:${DYNBOX_INSTALL_DIR}\""
  if [ -f "$profile_file" ]; then
    if grep -Fqs "$DYNBOX_INSTALL_DIR" "$profile_file"; then
      return 0
    fi
    cp "$profile_file" "${profile_file}.dynbox_backup_$(date +%s)"
    echo "" >> "$profile_file"
    echo "# DynBox CLI" >> "$profile_file"
    echo "$line" >> "$profile_file"
    echo "Updated $profile_file (backup created)"
  fi
}

PATH_UPDATED=0
case "$SHELL" in
  */zsh)
    add_to_profile "$HOME/.zshrc"
    PATH_UPDATED=1
    ;;
  */bash)
    if [ -f "$HOME/.bashrc" ]; then
      add_to_profile "$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      add_to_profile "$HOME/.bash_profile"
    fi
    PATH_UPDATED=1
    ;;
  *)
    if [ -f "$HOME/.profile" ]; then
      add_to_profile "$HOME/.profile"
      PATH_UPDATED=1
    fi
    ;;
esac

echo "=========================================================="
echo "🎉 DynBox was successfully installed!"
echo "=========================================================="
echo ""
echo "To verify installation in your current shell:"
echo "  export PATH=\"\$PATH:${DYNBOX_INSTALL_DIR}\""
echo "  dynbox --version"
echo ""
echo "Or simply open a new terminal window."
echo ""
