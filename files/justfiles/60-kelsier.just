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
    ujust install-chezmoi
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

# ── SSDs ────────────────────────────────────────────────────────────────
[group('kelsier')]
setup-local-disks:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo mkdir -p /var/mnt/crucial-ssd /var/mnt/teams-ssd

    if grep -q "crucial-ssd" /etc/fstab; then
        echo "fstab entries already present -- skipping."
    else
        printf '%s\n' \
            "/dev/disk/by-uuid/2a3bcf0a-49bf-4e70-b31f-1a4031e6f8ca /var/mnt/crucial-ssd auto nosuid,nodev,nofail,x-gvfs-show 0 0" \
            "/dev/disk/by-uuid/2a395d9f-121a-42b4-944c-1a48ea619c62 /var/mnt/teams-ssd auto nosuid,nodev,nofail,x-gvfs-show 0 0" \
            | sudo tee -a /etc/fstab > /dev/null
        echo "fstab entries added."
    fi
    sudo systemctl daemon-reload
    echo "Done: local SSDs configured."

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
