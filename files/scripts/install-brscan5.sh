#!/usr/bin/env bash
set -oue pipefail

# Install brscan5 bypassing signature checks (no digest header in Brother's RPM)
curl -L -o /tmp/brscan5.rpm https://download.brother.com/welcome/dlf104036/brscan5-1.5.1-0.x86_64.rpm
rpm -i --nodigest --nosignature /tmp/brscan5.rpm
rm /tmp/brscan5.rpm

# Fix udev rules so the scanner is accessible to the scanner group.
# Brother ships these lines commented out by default.
UDEV_RULES=$(find /etc/udev/rules.d/ -name "60-brother-mfp-brscan5-*.rules" 2>/dev/null | head -1)
if [[ -n "${UDEV_RULES}" ]]; then
    sed -i 's/#MODE="0666"/MODE="0666"/' "${UDEV_RULES}"
    sed -i 's/#GROUP="scanner"/GROUP="scanner"/' "${UDEV_RULES}"
fi