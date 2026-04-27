# Shared just recipes — included by all machine justfiles
# Run with: ujust <recipe-name>

# ── Sudoers ───────────────────────────────────────────────────────────────────

[group('common')]
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
#   SSH Key type items (private key from sshKey field):
#     "SSH: github"            → ~/.ssh/github
#     "SSH: chezmoi"            → ~/.ssh/chezmoi
#     "SSH: desktop_lxcs"      → ~/.ssh/desktop_lxcs
#     "SSH: desktop_ambition"  → ~/.ssh/desktop_ambition
#
#   Login "Samba":
#     username → SMB username
#     password → SMB password

[group('common')]
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

[group('common')]
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

[group('common')]
bw-lock:
    bw lock
    rm -f /tmp/.bw_session
    echo "Done: Bitwarden locked."

[group('common')]
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
    _bw_ssh_key "SSH: chezmoi"            "${HOME}/.ssh/chezmoi"
    _bw_ssh_key "SSH: desktop_lxcs"      "${HOME}/.ssh/desktop_lxcs"
    _bw_ssh_key "SSH: desktop_ambition"  "${HOME}/.ssh/desktop_ambition"
    echo "Done: SSH keys installed."

# ── SMB Mounts ────────────────────────────────────────────────────────────────

[group('common')]
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
        printf '\n# SMB mounts\n' | sudo tee -a /etc/fstab > /dev/null
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

# ── Local Disks ──────────────────────────────────────────────────────────────

[group('common')]
setup-local-disks:
    #!/usr/bin/env bash
    set -euo pipefail

    echo ""
    echo "=== Local Disk Setup ==="
    echo ""

    # List block devices that have a filesystem, are not swap, and are not currently mounted
    mapfile -t entries < <(
        lsblk -Jpo name,uuid,fstype,size,label,mountpoint \
        | jq -r '
            .. | objects
            | select(
                (.uuid  // "") != "" and
                (.fstype // "") != "" and .fstype != "swap" and
                (.mountpoint == null or .mountpoint == "")
              )
            | [.name, .uuid, .fstype, .size, (.label // "(no label)")]
            | @tsv
        '
    )

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "No unmounted disks with filesystems found."
        exit 0
    fi

    printf "  %-4s %-12s %-8s %-8s %-22s %s\n" "NUM" "DEVICE" "TYPE" "SIZE" "LABEL" "UUID"
    printf "  %-4s %-12s %-8s %-8s %-22s %s\n" "---" "------" "----" "----" "-----" "----"
    for i in "${!entries[@]}"; do
        IFS=$'\t' read -r name uuid fstype size label <<< "${entries[$i]}"
        printf "  %-4s %-12s %-8s %-8s %-22s %s\n" "$((i+1))" "$name" "$fstype" "$size" "$label" "$uuid"
    done
    echo ""

    read -rp "Disk numbers to configure (space-separated), or q to quit: " selection
    [[ "$selection" == "q" ]] && exit 0

    added=0
    for num in $selection; do
        if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#entries[@]} )); then
            echo "Invalid selection: $num -- skipping"
            continue
        fi

        IFS=$'\t' read -r name uuid fstype size label <<< "${entries[$((num-1))]}"
        echo ""
        echo "  Selected: $name  ($fstype, $size, label: $label)"
        echo "  UUID: $uuid"
        read -rp "  Mount point name under /var/mnt/ (e.g. crucial-ssd): " mountname
        [[ -z "$mountname" ]] && echo "  No name given -- skipping" && continue

        mountpt="/var/mnt/${mountname}"
        sudo mkdir -p "$mountpt"

        if grep -q "$uuid" /etc/fstab; then
            echo "  Already in fstab -- skipping"
        else
            echo "/dev/disk/by-uuid/${uuid} ${mountpt} auto nosuid,nodev,nofail,x-gvfs-show 0 0" \
                | sudo tee -a /etc/fstab > /dev/null
            echo "  Added: $mountpt"
            (( added++ )) || true
        fi
    done

    echo ""
    if (( added > 0 )); then
        sudo systemctl daemon-reload
        echo "Done: $added fstab $([ "$added" -eq 1 ] && echo entry || echo entries) added."
        echo "Run 'sudo mount -a' or reboot to mount now."
    else
        echo "No new fstab entries added."
    fi

# ── Konsave ──────────────────────────────────────────────────────────────────

[group('common')]
install-konsave:
    pipx install konsave
    echo "Done: konsave installed."

[group('common')]
konsave-import bw_item="uBlue Hoid":
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    BW_ITEM="{{bw_item}}"
    PROFILE=$(printf '%s' "${BW_ITEM}" | awk '{print tolower($NF)}')

    ITEM=$(bw get item "${BW_ITEM}")
    KONSAVE_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="KONSAVE_URL") | .value')
    if [[ -z "${KONSAVE_URL}" ]]; then
        echo "ERROR: KONSAVE_URL field not found in '${BW_ITEM}' vault item"
        exit 1
    fi
    konsave -s "${BW_ITEM} Default"
    echo "Saved current profile as '${BW_ITEM} Default'."
    curl -fsSL -o "/tmp/${PROFILE}.knsv" "${KONSAVE_URL}"
    konsave -i "/tmp/${PROFILE}.knsv"
    konsave -a "${PROFILE}"
    rm -f "/tmp/${PROFILE}.knsv"
    echo "Done: Konsave profile imported and applied."

[group('common')]
konsave-save name="hoid":
    konsave -s {{name}}
    echo "KDE profile saved as '{{name}}'."

[group('common')]
konsave-apply name="hoid":
    konsave -a {{name}}
    echo "Applied KDE profile '{{name}}'."

# ── Chezmoi ──────────────────────────────────────────────────────────────────
# Requires: ujust install-ssh-keys to have run first (uses ~/.ssh/chezmoi)

[group('common')]
install-chezmoi:
    #!/usr/bin/env bash
    set -euo pipefail
    CHEZMOI_REPO="git@git.fuzzymistborn.com:FuzzyMistborn/dotfiles.git"

    install -dm755 "${HOME}/.local/bin"

    echo "-- Initializing chezmoi from ${CHEZMOI_REPO} --"
    GIT_SSH_COMMAND="ssh -i ${HOME}/.ssh/chezmoi -o IdentitiesOnly=yes -o Hostname=remote.fuzzymistborn.com -p 222" \
        chezmoi init "${CHEZMOI_REPO}"

    echo "-- Pre-applying chezmoi_media_manager --"
    chezmoi apply "${HOME}/.local/bin/chezmoi_media_manager"

    echo "-- Applying chezmoi --"
    chezmoi apply

    sudo usermod -s /usr/bin/zsh "$(whoami)"
    echo "Done: chezmoi applied, zsh set as default shell. Log out and back in to activate."

# ── Wallpaper ────────────────────────────────────────────────────────────────

[group('common')]
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

[group('common')]
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

# ── Wake-on-LAN ───────────────────────────────────────────────────────────────

[group('common')]
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
