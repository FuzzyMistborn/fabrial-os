#!/usr/bin/env bash
set -euo pipefail

VERSION="v2.3.1"
ZIP_URL="https://github.com/Snapmaker/OrcaSlicer/releases/download/${VERSION}/Snapmaker_Orca_Linux_ubuntu_2404_${VERSION^}.zip"
INSTALL_DIR="/usr/local/lib/snapmaker-orca"
WORK_DIR="/tmp/snapmaker-orca-install"

echo "-- Installing Snapmaker OrcaSlicer ${VERSION} --"

mkdir -p "${INSTALL_DIR}" "${WORK_DIR}"
curl -fsSL -o "${WORK_DIR}/snapmaker-orca.zip" "${ZIP_URL}"
unzip -o "${WORK_DIR}/snapmaker-orca.zip" -d "${WORK_DIR}/extracted/"

APPIMAGE=$(find "${WORK_DIR}/extracted/" -name "*.AppImage" | head -1)
if [[ -z "${APPIMAGE}" ]]; then
    echo "ERROR: No AppImage found in zip"
    exit 1
fi

install -m755 "${APPIMAGE}" "${INSTALL_DIR}/OrcaSlicer.AppImage"
mkdir -p /usr/local/bin
ln -sf "${INSTALL_DIR}/OrcaSlicer.AppImage" /usr/local/bin/OrcaSlicer

# Extract icon from AppImage (no FUSE needed with --appimage-extract)
mkdir -p "${WORK_DIR}/appimage-extract"
cd "${WORK_DIR}/appimage-extract"
"${INSTALL_DIR}/OrcaSlicer.AppImage" --appimage-extract '*.png' 2>/dev/null || true
"${INSTALL_DIR}/OrcaSlicer.AppImage" --appimage-extract '*.svg' 2>/dev/null || true
ICON=$(find "${WORK_DIR}/appimage-extract/squashfs-root" \( -name "OrcaSlicer.png" -o -name "OrcaSlicer.svg" \) 2>/dev/null | sort -r | head -1)
if [[ -n "${ICON}" ]]; then
    EXT="${ICON##*.}"
    install -Dm644 "${ICON}" "/usr/share/icons/hicolor/256x256/apps/OrcaSlicer.${EXT}"
fi

rm -rf "${WORK_DIR}"
echo "Done: Snapmaker OrcaSlicer ${VERSION} installed at ${INSTALL_DIR}/OrcaSlicer.AppImage"
