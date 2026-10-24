#!/usr/bin/env bash
set -oue pipefail

VERSION="4.0.0"
APPIMAGE="OpenCloud_Desktop-v${VERSION}-linux-gcc-x86_64.AppImage"
BASE_URL="https://github.com/opencloud-eu/desktop/releases/download/v${VERSION}"
INSTALL_DIR="/usr/lib/opencloud-desktop"
WORK_DIR=$(mktemp -d)

trap 'rm -rf "${WORK_DIR}"' EXIT

echo "-- Installing OpenCloud Desktop ${VERSION} --"

cd "${WORK_DIR}"
curl -fsSL -O "${BASE_URL}/${APPIMAGE}"
curl -fsSL -O "${BASE_URL}/${APPIMAGE}.sha256"
# The .sha256 file may reference a different filename, so compare hashes only
[[ "$(awk '{print $1}' "${APPIMAGE}.sha256")" == "$(sha256sum "${APPIMAGE}" | awk '{print $1}')" ]]

# Extract rather than run the AppImage directly, so FUSE isn't required
chmod +x "${APPIMAGE}"
"./${APPIMAGE}" --appimage-extract > /dev/null

install -d "${INSTALL_DIR}"
cp -a squashfs-root/. "${INSTALL_DIR}/"
chmod -R a+rX "${INSTALL_DIR}"

ln -sf "${INSTALL_DIR}/AppRun" /usr/bin/opencloud-desktop

# Desktop entry and icons
DESKTOP=$(find squashfs-root -maxdepth 1 -name "*.desktop" | head -1)
if [[ -n "${DESKTOP}" ]]; then
    sed -E 's|^Exec=.*|Exec=/usr/bin/opencloud-desktop %u|' "${DESKTOP}" \
        > /usr/share/applications/opencloud-desktop.desktop
    ICON_NAME=$(sed -n 's/^Icon=//p' "${DESKTOP}" | head -1)
    if [[ -d squashfs-root/usr/share/icons ]]; then
        cp -a squashfs-root/usr/share/icons/. /usr/share/icons/
    fi
    if [[ -n "${ICON_NAME}" && -f "squashfs-root/${ICON_NAME}.png" ]]; then
        install -Dm644 "squashfs-root/${ICON_NAME}.png" "/usr/share/pixmaps/${ICON_NAME}.png"
    fi
else
    echo "WARNING: No desktop file found in AppImage"
fi

echo "Done: OpenCloud Desktop ${VERSION} installed"
