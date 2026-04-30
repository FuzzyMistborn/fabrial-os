#!/usr/bin/env bash
set -oue pipefail

# Install brscan5 bypassing signature checks (no digest header in Brother's RPM)
curl -L -o /tmp/brscan5.rpm https://download.brother.com/welcome/dlf104036/brscan5-1.5.1-0.x86_64.rpm
rpm -i --nodigest --nosignature /tmp/brscan5.rpm
rm /tmp/brscan5.rpm

# Fix udev rules so the scanner is accessible to the scanner group
# (lines are commented out by default in Brother's package)
UDEV_RULES=$(ls /etc/udev/rules.d/60-brother-mfp-brscan5-*.rules 2>/dev/null | head -1)
if [[ -n "${UDEV_RULES}" ]]; then
    sed -i 's/#MODE="0666"/MODE="0666"/' "${UDEV_RULES}"
    sed -i 's/#GROUP="scanner"/GROUP="scanner"/' "${UDEV_RULES}"
fi