#!/usr/bin/env bash
set -euo pipefail

VERSION="0.4.0-beta1"
APPIMAGE_URL="https://github.com/thomasnordquist/MQTT-Explorer/releases/download/0.0.0-${VERSION}/MQTT-Explorer-${VERSION}.AppImage"
INSTALL_PATH="/usr/local/bin/MQTT_Explorer"
WORK_DIR=$(mktemp -d)

echo "-- Installing MQTT Explorer ${VERSION} --"

trap 'rm -rf "${WORK_DIR}"' EXIT

curl -fsSL -o "${WORK_DIR}/MQTT_Explorer.AppImage" "${APPIMAGE_URL}"
install -m755 "${WORK_DIR}/MQTT_Explorer.AppImage" "${INSTALL_PATH}"

# Extract icon from AppImage
mkdir -p "${WORK_DIR}/icon-extract"
cd "${WORK_DIR}/icon-extract"
"${INSTALL_PATH}" --appimage-extract 2>/dev/null || true
ICON=$(find "${WORK_DIR}/icon-extract/squashfs-root" -name "*.png" 2>/dev/null \
    | grep -i mqtt | head -1)
if [[ -n "${ICON}" ]]; then
    install -Dm644 "${ICON}" /usr/local/share/icons/hicolor/256x256/apps/MQTT_Explorer.png
    gtk-update-icon-cache /usr/local/share/icons/hicolor/ 2>/dev/null || true
    echo "Icon installed from: ${ICON}"
else
    echo "WARNING: No MQTT Explorer icon found in AppImage"
fi

echo "Done: MQTT Explorer ${VERSION} installed at ${INSTALL_PATH}"
