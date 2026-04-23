# Custom just recipes for the kelsier image
# Run with: ujust <recipe-name>

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
    ujust install-zsh
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

# ── Sudoers ───────────────────────────────────────────────────────────────────

[group('kelsier')]
setup-sudoers:
    #!/usr/bin/env bash
    set -euo pipefail
    USERNAME=$(whoami)
    echo "${USERNAME} ALL= NOPASSWD: /bin/systemctl,/usr/sbin/grub-reboot" \
        | sudo tee /etc/sudoers.d/${USERNAME} > /dev/null
    sudo chmod u=r,g=r,o= /etc/sudoers.d/${USERNAME}
    echo "Done: sudoers configured for ${USERNAME}."

# ── Bitwarden CLI ─────────────────────────────────────────────────────────────
# Expected vault items:
#   SSH Key type items (private key pulled from sshKey field, falls back to notes):
#     "SSH: github"            → ~/.ssh/github
#     "SSH: desktop_lxcs"      → ~/.ssh/desktop_lxcs
#     "SSH: desktop_ambition"  → ~/.ssh/desktop_ambition
#
#   Login "Samba":
#     username → SMB username
#     password → SMB password
#
#   Login "Hoid uBlue":
#     password      → RESTIC_PASSWORD (repo encryption password)
#     custom fields → REST_USERNAME, REST_PASSWORD,
#                     HC_BACKUP_UUID, HC_PRUNE_UUID, HC_CHECK_UUID,
#                     HC_PING_URL, REST_URL, KONSAVE_URL,
#                     FIREFOX_PROFILE_URL, THUNDERBIRD_PROFILE_URL

[group('kelsier')]
install-bw-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v bw &>/dev/null; then
        echo "bw already installed: $(bw --version)"
        exit 0
    fi
    echo "-- Installing Bitwarden CLI --"
    RELEASE_JSON=$(curl -sf https://api.github.com/repos/bitwarden/clients/releases \
        | jq '[.[] | select(.tag_name | startswith("cli-v"))] | first')
    VERSION=$(printf '%s' "${RELEASE_JSON}" | jq -r '.tag_name | ltrimstr("cli-v")')
    URL=$(printf '%s' "${RELEASE_JSON}" | jq -r '.assets[] | select(.name == "bw-linux-'"${VERSION}"'.zip") | .browser_download_url')
    curl -fsSL -o /tmp/bw.zip "${URL}"
    unzip -o /tmp/bw.zip bw -d /tmp/
    chmod +x /tmp/bw
    sudo mv /tmp/bw /usr/local/bin/bw
    sudo restorecon -v /usr/local/bin/bw
    rm -f /tmp/bw.zip
    echo "Done: bw ${VERSION} installed."

[group('kelsier')]
bw-unlock:
    #!/usr/bin/env bash
    set -euo pipefail
    SERVER=$(bw status 2>/dev/null | jq -r '.serverUrl // ""')
    if [[ -z "${SERVER}" || "${SERVER}" == *"vault.bitwarden.com"* ]]; then
        read -rp "Enter your self-hosted Bitwarden URL (e.g. https://bw.example.com): " BW_URL
        bw config server "${BW_URL}"
    fi
    if ! bw login --check &>/dev/null; then
        bw login
    fi
    BW_SESSION=$(bw unlock --raw)
    printf '%s' "${BW_SESSION}" > /tmp/.bw_session
    chmod 600 /tmp/.bw_session
    echo "Done: Bitwarden unlocked."

[group('kelsier')]
bw-lock:
    bw lock
    rm -f /tmp/.bw_session
    echo "Done: Bitwarden locked."

[group('kelsier')]
install-ssh-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    install -dm700 "${HOME}/.ssh"

    _bw_ssh_key() {
        local item="$1" dest="$2"
        local raw key
        raw=$(bw get item "${item}" 2>/dev/null)
        if [[ -z "${raw}" ]]; then
            echo "WARNING: '${item}' — bw returned nothing (session expired?)"
            return 1
        fi
        key=$(printf '%s' "${raw}" | jq -r '(.sshKey // {}).privateKey // ""' 2>/dev/null)
        if [[ -z "${key}" ]]; then
            echo "WARNING: '${item}' — found but privateKey field is empty"
            return 1
        fi
        printf '%s\n' "${key}" > "${dest}"
        chmod 600 "${dest}"
        echo "  Written: ${dest}"
    }

    echo "-- Syncing Bitwarden vault --"
    bw sync --session "${BW_SESSION}" > /dev/null

    echo "-- Installing SSH keys from Bitwarden --"
    _bw_ssh_key "SSH: github"            "${HOME}/.ssh/github"
    _bw_ssh_key "SSH: desktop_lxcs"      "${HOME}/.ssh/desktop_lxcs"
    _bw_ssh_key "SSH: desktop_ambition"  "${HOME}/.ssh/desktop_ambition"
    echo "Done: SSH keys installed."

# ── SMB Mounts ────────────────────────────────────────────────────────────────

[group('kelsier')]
setup-mounts:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    echo "-- SMB mount setup --"
    SMB_USER=$(bw get username "Samba")
    SMB_PASS=$(bw get password "Samba")

    CRED_FILE="${HOME}/.smbcredentials"
    printf '%s\n' "user=${SMB_USER}" "password=${SMB_PASS}" "domain=cosmere" \
        > "${CRED_FILE}"
    chmod u=rw,g=,o= "${CRED_FILE}"
    echo "Credentials written to ${CRED_FILE}"

    sudo mkdir -p /mnt/Backup /mnt/NVR /mnt/Media

    UID_VAL=$(id -u)
    GID_VAL=$(id -g)
    OPTS="_netdev,noauto,nofail,x-systemd.automount,uid=${UID_VAL},gid=${GID_VAL},credentials=${CRED_FILE}"

    if grep -q "/mnt/Backup" /etc/fstab; then
        echo "fstab entries already present -- skipping."
    else
        printf '\n# SMB mounts for kelsier\n' | sudo tee -a /etc/fstab > /dev/null
        printf '//192.168.1.5/Backup/config  /mnt/Backup  cifs  %s  0 0\n' "${OPTS}" \
            | sudo tee -a /etc/fstab > /dev/null
        printf '//192.168.1.5/Backup/NVR     /mnt/NVR     cifs  %s  0 0\n' "${OPTS}" \
            | sudo tee -a /etc/fstab > /dev/null
        printf '//192.168.1.10/Media         /mnt/Media   cifs  %s  0 0\n' "${OPTS}" \
            | sudo tee -a /etc/fstab > /dev/null
        echo "fstab entries added."
    fi
    sudo systemctl daemon-reload
    echo "Done: mounts configured."

# ── Zsh / Oh My Zsh ──────────────────────────────────────────────────────────

[group('kelsier')]
install-zsh:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d "${HOME}/.oh-my-zsh" ]; then
        echo "oh-my-zsh already installed -- skipping."
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" --unattended
    fi

    ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh-custom}"

    if [ -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
        git -C "${ZSH_CUSTOM}/themes/powerlevel10k" pull --ff-only
    else
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "${ZSH_CUSTOM}/themes/powerlevel10k"
    fi

    if [ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
        git -C "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" pull --ff-only
    else
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
    fi

    if [ -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
        git -C "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" pull --ff-only
    else
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
            "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
    fi

    # oh-my-zsh --unattended creates a default .zshrc, so always overwrite with
    # our skel versions to ensure the correct config and p10k theme are applied.
    for f in .zshrc .p10k.zsh; do
        if [ -f "/etc/skel/${f}" ]; then
            cp "/etc/skel/${f}" "${HOME}/${f}"
            echo "Copied /etc/skel/${f} to ${HOME}/${f}"
        else
            echo "WARNING: /etc/skel/${f} not found — skipping"
        fi
    done

    # Set up .ssh dir and copy config from skel if not already present
    mkdir -p "${HOME}/.ssh"
    chmod u=rwx,g=,o= "${HOME}/.ssh"
    if [ ! -f "${HOME}/.ssh/config" ] && [ -f "/etc/skel/.ssh/config" ]; then
        cp "/etc/skel/.ssh/config" "${HOME}/.ssh/config"
        echo "Copied ssh config from skel"
    fi
    if [ -f "${HOME}/.ssh/config" ]; then
        chmod u=rw,g=,o= "${HOME}/.ssh/config"
    fi

    sudo usermod -s /usr/bin/zsh "$(whoami)"
    echo "Done: zsh set as default shell. Log out and back in to activate."

# ── Wallpaper ────────────────────────────────────────────────────────────────

[group('kelsier')]
setup-wallpaper desktop="stormlight_arc1_wallpaper_uw.png" sddm="WayofKings.jpg":
    #!/usr/bin/env bash
    set -euo pipefail
    DESKTOP_IMG="/usr/backgrounds/{{desktop}}"
    SDDM_IMG="/usr/backgrounds/{{sddm}}"

    for img in "${DESKTOP_IMG}" "${SDDM_IMG}"; do
        if [[ ! -f "${img}" ]]; then
            echo "ERROR: ${img} not found. Available wallpapers:"
            ls /usr/backgrounds/
            exit 1
        fi
    done

    echo "-- Applying desktop wallpaper --"
    plasma-apply-wallpaperimage "${DESKTOP_IMG}"

    echo "-- Applying SDDM login wallpaper --"
    sudo mkdir -p /etc/sddm.conf.d
    printf '[Theme]\nBackground=%s\n' "${SDDM_IMG}" \
        | sudo tee /etc/sddm.conf.d/10-wallpaper.conf > /dev/null

    echo "Done: desktop → ${DESKTOP_IMG}, SDDM → ${SDDM_IMG}."

# ── Avatar ───────────────────────────────────────────────────────────────────

[group('kelsier')]
setup-avatar avatar="avatar.png":
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="/usr/share/pixmaps/faces/{{avatar}}"
    if [[ ! -f "${SRC}" ]]; then
        echo "ERROR: ${SRC} not found."
        exit 1
    fi
    USERNAME=$(whoami)

    cp "${SRC}" "${HOME}/.face"
    cp "${SRC}" "${HOME}/.face.icon"

    sudo mkdir -p /var/lib/AccountsService/icons
    sudo cp "${SRC}" "/var/lib/AccountsService/icons/${USERNAME}"
    sudo chmod 644 "/var/lib/AccountsService/icons/${USERNAME}"

    echo "Done: avatar set for ${USERNAME}."

# ── Autostart ────────────────────────────────────────────────────────────────

[group('kelsier')]
setup-autostart:
    #!/usr/bin/env bash
    set -euo pipefail
    AUTOSTART_DIR="${HOME}/.config/autostart"
    mkdir -p "${AUTOSTART_DIR}"
    printf '[Desktop Entry]\nName=Nextcloud\nExec=nextcloud --background\nIcon=Nextcloud\nType=Application\n' \
        > "${AUTOSTART_DIR}/nextcloud.desktop"

# ── Wake-on-LAN ───────────────────────────────────────────────────────────────

[group('kelsier')]
enable-wol:
    #!/usr/bin/env bash
    set -euo pipefail
    CONN=$(nmcli -t -f NAME,TYPE con show --active \
        | grep ':ethernet' | cut -d: -f1 | head -1)
    if [ -z "${CONN}" ]; then
        echo "No active wired connection found. Connect ethernet and retry."
        exit 1
    fi
    nmcli c modify "${CONN}" 802-3-ethernet.wake-on-lan magic
    echo "Done: WOL enabled for '${CONN}'."
