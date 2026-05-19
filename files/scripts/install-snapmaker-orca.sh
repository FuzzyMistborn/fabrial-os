#!/usr/bin/env bash
set -euo pipefail

VERSION="v2.3.1"
ZIP_URL="https://github.com/Snapmaker/OrcaSlicer/releases/download/${VERSION}/Snapmaker_Orca_Linux_ubuntu_2404_${VERSION^}.zip"
INSTALL_DIR="/usr/lib/snapmaker-orca"
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
ln -sf "${INSTALL_DIR}/OrcaSlicer.AppImage" /usr/bin/OrcaSlicer

rm -rf "${WORK_DIR}"

echo "Done: Snapmaker OrcaSlicer ${VERSION} installed"
ls -la "${INSTALL_DIR}/"
