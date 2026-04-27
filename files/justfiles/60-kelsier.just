# Kelsier-specific just recipes
# Run with: ujust <recipe-name>
# Shared recipes (bw-unlock, install-chezmoi, setup-mounts, etc.) live in 50-common.just

# ── Full first-boot setup ─────────────────────────────────────────────────────

[group('kelsier')]
setup-kelsier:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "=== Kelsier first-boot setup ==="
    echo ""
    ujust install-bw-cli
    ujust bw-unlock
    ujust setup-sudoers
    ujust install-ssh-keys
    ujust setup-mounts
    ujust setup-local-disks
    ujust install-chezmoi
    ujust install-konsave
    ujust konsave-import "uBlue Bazzite"
    ujust setup-wallpaper
    ujust setup-avatar
    ujust setup-autostart
    ujust toggle-user-motd
    ujust bw-lock
    echo ""
    echo "=== Done! Manual steps still needed: ==="
    echo "  1. ujust enable-wol  (desktop/wired only)"
    echo "  2. Log out and back in to activate zsh"
    echo ""

# ── Autostart ────────────────────────────────────────────────────────────────

[group('kelsier')]
setup-autostart:
    #!/usr/bin/env bash
    set -euo pipefail
    AUTOSTART_DIR="${HOME}/.config/autostart"
    mkdir -p "${AUTOSTART_DIR}"
    printf '[Desktop Entry]\nName=Nextcloud\nExec=nextcloud --background\nIcon=Nextcloud\nType=Application\n' \
        > "${AUTOSTART_DIR}/nextcloud.desktop"
    echo "Done: autostart entries created for Nextcloud."
