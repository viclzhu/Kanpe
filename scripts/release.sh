#!/usr/bin/env bash
# Builds a release zip of Kanpe.app for GitHub Releases / the Homebrew cask.
#   VERSION=0.2.0 scripts/release.sh   # → build/Kanpe-0.2.0.zip, prints its sha256
# Sign with the same identity every release (Kanpe Local Signing, or a Developer ID) so
# macOS keeps users' Accessibility permission across updates.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:?set VERSION, e.g. VERSION=0.2.0}"
VERSION="$VERSION" scripts/bundle.sh
ZIP="build/Kanpe-${VERSION}.zip"
rm -f "$ZIP"
# ditto keeps the code signature and extended attributes intact (zip can break them).
ditto -c -k --sequesterRsrc --keepParent build/Kanpe.app "$ZIP"
echo "Wrote $ZIP"
echo "sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
