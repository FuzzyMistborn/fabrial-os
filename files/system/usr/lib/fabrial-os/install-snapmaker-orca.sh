#!/usr/bin/env bash
set -euo pipefail

VERSION="v2.3.1"
ZIP_URL="https://github.com/Snapmaker/OrcaSlicer/releases/download/${VERSION}/Snapmaker_Orca_Linux_ubuntu_2404_${VERSION^}.zip"
INSTALL_PATH="/usr/local/bin/OrcaSlicer"
WORK_DIR=$(mktemp -d)

echo "-- Installing Snapmaker OrcaSlicer ${VERSION} --"

trap 'rm -rf "${WORK_DIR}"' EXIT

curl -fsSL -o "${WORK_DIR}/snapmaker-orca.zip" "${ZIP_URL}"
unzip -o "${WORK_DIR}/snapmaker-orca.zip" -d "${WORK_DIR}/extracted/"

APPIMAGE=$(find "${WORK_DIR}/extracted/" -name "*.AppImage" | head -1)
if [[ -z "${APPIMAGE}" ]]; then
    echo "ERROR: No AppImage found in zip"
    exit 1
fi

install -m755 "${APPIMAGE}" "${INSTALL_PATH}"

# Extract icon from AppImage
mkdir -p "${WORK_DIR}/icon-extract"
cd "${WORK_DIR}/icon-extract"
"${INSTALL_PATH}" --appimage-extract 2>/dev/null || true
ICON=$(find "${WORK_DIR}/icon-extract/squashfs-root" -name "Snapmaker_Orca.png" 2>/dev/null \
    | head -1)
if [[ -n "${ICON}" ]]; then
    install -Dm644 "${ICON}" /usr/local/share/icons/hicolor/192x192/apps/Snapmaker_Orca.png
    gtk-update-icon-cache /usr/local/share/icons/hicolor/ 2>/dev/null || true
    echo "Icon installed from: ${ICON}"
else
    echo "WARNING: No Snapmaker_Orca.png found in AppImage"
fi

echo "Done: Snapmaker OrcaSlicer ${VERSION} installed at ${INSTALL_PATH}"
