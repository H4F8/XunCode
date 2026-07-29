#!/bin/bash
set -e

# bundle-rootfs.sh — bundles a minimal Alpine rootfs for embedding into APK.
#
# Usage:
#   ./scripts/bundle-rootfs.sh [arch]
#
# arch defaults to aarch64. Supported: aarch64, armv7, x86_64, x86.
# The script downloads alpine-minirootfs, extracts it into assets/rootfs/
# and creates a manifest.json describing the build.

ARCH="${1:-aarch64}"
ASSET_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/rootfs"

# Map our arch names to Alpine release arch names.
case "$ARCH" in
  aarch64|arm64) ALPINE_ARCH="aarch64" ;;
  armv7|arm)     ALPINE_ARCH="armv7" ;;
  x86_64|amd64)  ALPINE_ARCH="x86_64" ;;
  x86|i686)      ALPINE_ARCH="x86" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

ALPINE_VERSION="3.20.3"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
TMP_DIR=$(mktemp -d)
TAR_GZ="$TMP_DIR/alpine-minirootfs.tar.gz"

echo "Downloading Alpine $ALPINE_VERSION rootfs for $ALPINE_ARCH..."
curl -L -o "$TAR_GZ" "$URL"

echo "Extracting to $ASSET_DIR..."
rm -rf "$ASSET_DIR"
mkdir -p "$ASSET_DIR"
tar -xzf "$TAR_GZ" -C "$ASSET_DIR"

# Ensure resolv.conf exists so DNS works immediately after extraction.
mkdir -p "$ASSET_DIR/etc"
cat > "$ASSET_DIR/etc/resolv.conf" <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Write manifest used by the app to verify version/arch.
cat > "$ASSET_DIR/manifest.json" <<EOF
{
  "arch": "$ALPINE_ARCH",
  "version": "$ALPINE_VERSION",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Marker file that the app looks for.
touch "$ASSET_DIR/.installed"

# Repack into a single tar.gz asset for efficient extraction.
rm -f "$ASSET_DIR/../rootfs.tar.gz"
tar -czf "$ASSET_DIR/rootfs.tar.gz" -C "$ASSET_DIR" .

rm -rf "$TMP_DIR"

echo "Rootfs ready at $ASSET_DIR"
echo "Asset archive: $ASSET_DIR/rootfs.tar.gz"
