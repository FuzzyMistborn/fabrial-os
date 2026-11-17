#!/usr/bin/env bash
set -euo pipefail

VERSION="2.4.1"
BUNDLE="Snapmaker_Orca-Linux-flatpak_V${VERSION}_x86_64.flatpak"
URL="https://github.com/Snapmaker/OrcaSlicer/releases/download/v${VERSION}/${BUNDLE}"
WORK_DIR=$(mktemp -d)

trap 'rm -rf "${WORK_DIR}"' EXIT

echo "-- Installing Snapmaker Orca ${VERSION} --"

curl -fsSL -o "${WORK_DIR}/${BUNDLE}" "${URL}"

# Runtime dependencies are pulled from the configured remotes (Flathub)
flatpak install --system --noninteractive --bundle "${WORK_DIR}/${BUNDLE}"

echo "Done: Snapmaker Orca ${VERSION} installed"
