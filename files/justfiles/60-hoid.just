# Custom just recipes for the hoid image
# Run with: ujust <recipe-name>

# ── Full first-boot setup ─────────────────────────────────────────────────────

[group('hoid')]
setup-hoid:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "=== Hoid first-boot setup ==="
    echo ""
    ujust install-bw-cli
    ujust bw-unlock
    ujust setup-sudoers
    ujust enable-ssh
    ujust install-ssh-keys
    ujust setup-mounts
    ujust install-backup-tools
    ujust setup-restic-env
    ujust setup-autorestic
    ujust install-veracrypt
    ujust install-zsh
    ujust install-vscode-extensions
    ujust setup-printer
    ujust install-konsave
    ujust konsave-import
    ujust firefox-profile-import
    ujust thunderbird-profile-import
    ujust install-mqtt-explorer
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

[group('hoid')]
setup-sudoers:
    #!/usr/bin/env bash
    set -euo pipefail
    USERNAME=$(whoami)
    echo "${USERNAME} ALL= NOPASSWD: /bin/systemctl,/usr/sbin/grub-reboot" \
        | sudo tee /etc/sudoers.d/${USERNAME} > /dev/null
    sudo chmod u=r,g=r,o= /etc/sudoers.d/${USERNAME}
    echo "Done: sudoers configured for ${USERNAME}."

# ── SSH ───────────────────────────────────────────────────────────────────────

[group('hoid')]
enable-ssh:
    sudo systemctl enable --now sshd
    echo "Done: SSH enabled."

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

[group('hoid')]
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

[group('hoid')]
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

[group('hoid')]
bw-lock:
    bw lock
    rm -f /tmp/.bw_session
    echo "Done: Bitwarden locked."

[group('hoid')]
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

[group('hoid')]
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
        printf '\n# SMB mounts for hoid\n' | sudo tee -a /etc/fstab > /dev/null
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

# ── Restic / Autorestic ───────────────────────────────────────────────────────

[group('hoid')]
install-backup-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "-- Installing runitor --"
    RUNITOR_VER=$(curl -sf https://api.github.com/repos/bdd/runitor/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//')
    curl -fsSL -o /tmp/runitor \
        "https://github.com/bdd/runitor/releases/download/v${RUNITOR_VER}/runitor-v${RUNITOR_VER}-linux-amd64"
    chmod +x /tmp/runitor
    sudo mv /tmp/runitor /usr/local/bin/runitor
    sudo restorecon -v /usr/local/bin/runitor
    echo "runitor ${RUNITOR_VER} installed."

    echo "-- Installing autorestic --"
    AUTORESTIC_VER=$(curl -sf https://api.github.com/repos/cupcakearmy/autorestic/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//')
    curl -fsSL -o /tmp/autorestic.bz2 \
        "https://github.com/cupcakearmy/autorestic/releases/download/v${AUTORESTIC_VER}/autorestic_${AUTORESTIC_VER}_linux_amd64.bz2"
    bunzip2 -f /tmp/autorestic.bz2
    chmod +x /tmp/autorestic
    sudo mv /tmp/autorestic /usr/local/bin/autorestic
    sudo restorecon -v /usr/local/bin/autorestic
    echo "autorestic ${AUTORESTIC_VER} installed."

[group('hoid')]
setup-restic-env:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    echo "-- Restic environment setup (pulling from Bitwarden) --"
    RESTIC_ITEM=$(bw get item "Hoid uBlue")

    _field() { printf '%s' "${RESTIC_ITEM}" \
        | jq -r --arg n "$1" '.fields[] | select(.name==$n) | .value'; }

    RESTIC_PASS=$(printf '%s' "${RESTIC_ITEM}" | jq -r '.login.password')
    REST_USER=$(_field "REST_USERNAME")
    REST_PASS=$(_field "REST_PASSWORD")
    HC_BACKUP=$(_field "HC_BACKUP_UUID")
    HC_PRUNE=$(_field "HC_PRUNE_UUID")
    HC_CHECK=$(_field "HC_CHECK_UUID")
    HC_URL=$(_field "HC_PING_URL")
    REST_URL=$(_field "REST_URL")

    ENV_FILE=$(mktemp)
    printf '%s\n' \
        "HC_BACKUP_UUID=${HC_BACKUP}" \
        "HC_PRUNE_UUID=${HC_PRUNE}" \
        "HC_CHECK_UUID=${HC_CHECK}" \
        "HC_PING_URL=${HC_URL}" \
        "RESTIC_PASSWORD=${RESTIC_PASS}" \
        "RESTIC_REST_USERNAME=${REST_USER}" \
        "RESTIC_REST_PASSWORD=${REST_PASS}" \
        "REST_URL=${REST_URL}" \
        > "${ENV_FILE}"
    sudo cp "${ENV_FILE}" /etc/restic.env
    rm -f "${ENV_FILE}"
    sudo chown root:root /etc/restic.env
    sudo chmod u=rw,g=,o= /etc/restic.env
    echo "Done: /etc/restic.env written."
    echo "Next: create ~/.autorestic.yml with your backend/location config."

[group('hoid')]
setup-autorestic:
    #!/usr/bin/env bash
    set -euo pipefail
    source <(sudo cat /etc/restic.env)

    printf '%s\n' \
        "version: 2" \
        "" \
        "backends:" \
        "    local_files:" \
        "        type: rest" \
        "        path: ${REST_URL}" \
        "        key: ${RESTIC_PASSWORD}" \
        "        rest:" \
        "            user: ${RESTIC_REST_USERNAME}" \
        "            password: ${RESTIC_REST_PASSWORD}" \
        "" \
        "locations:" \
        "    files:" \
        "        from: ${HOME}" \
        "        to:" \
        "        - local_files" \
        "        options:" \
        "            backup:" \
        "                exclude:" \
        "                - .cache*" \
        "                - Nextcloud" \
        "                - Downloads" \
        "                - git" \
        "                - '*steam*'" \
        "            forget:" \
        "                keep-daily: 3" \
        "                keep-weekly: 4" \
        "                keep-monthly: 2" \
        > "${HOME}/.autorestic.yml"
    chmod u=rw,g=,o= "${HOME}/.autorestic.yml"
    echo "Done: ~/.autorestic.yml written."

[group('hoid')]
restic-backup-now:
    sudo /usr/local/bin/autorestic backup -a

[group('hoid')]
restic-prune-now:
    sudo /usr/local/bin/autorestic forget -a --prune

[group('hoid')]
restic-check:
    #!/usr/bin/env bash
    set -euo pipefail
    source <(sudo cat /etc/restic.env)
    /usr/local/bin/runitor -api-url "${HC_PING_URL}" -uuid "${HC_CHECK_UUID}" -- \
        /usr/local/bin/autorestic exec -a -- check

# ── Zsh / Oh My Zsh ──────────────────────────────────────────────────────────

[group('hoid')]
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

# ── VS Code Extensions ────────────────────────────────────────────────────────

[group('hoid')]
install-vscode-extensions:
    #!/usr/bin/env bash
    set -euo pipefail
    extensions=(
        ms-vscode-remote.remote-ssh
        ms-python.python
        ms-azuretools.vscode-docker
        matthewpi.caddyfile-support
        keesschollaart.vscode-home-assistant
        wholroyd.jinja
        anthropic.claude-code
    )
    for ext in "${extensions[@]}"; do
        echo "  Installing: ${ext}"
        code --install-extension "${ext}"
    done
    echo "Done: VS Code extensions installed."

# ── Printer ───────────────────────────────────────────────────────────────────

[group('hoid')]
setup-printer:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo /usr/sbin/lpadmin -p Brother-HL2270DW -E \
        -v ipp://192.168.10.15/ipp/port1 \
        -o media=na_letter_8.5x11in
    /usr/bin/lpoptions -d Brother-HL2270DW
    echo "Done: Brother-HL2270DW configured."

# ── konsave ───────────────────────────────────────────────────────────────────

[group('hoid')]
install-konsave:
    pipx install konsave
    echo "Done: konsave installed."

[group('hoid')]
konsave-import:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    ITEM=$(bw get item "Hoid uBlue")
    KONSAVE_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="KONSAVE_URL") | .value')
    if [[ -z "${KONSAVE_URL}" ]]; then
        echo "ERROR: KONSAVE_URL field not found in 'Hoid uBlue' vault item"
        exit 1
    fi
    konsave -s "Aurora Default"
    echo "Saved current profile as 'Aurora Default'."
    curl -fsSL -o /tmp/hoid.knsv "${KONSAVE_URL}"
    konsave -i /tmp/hoid.knsv
    konsave -a hoid
    rm -f /tmp/hoid.knsv
    echo "Done: Konsave profile imported and applied."

[group('hoid')]
konsave-save name="hoid":
    konsave -s {{name}}
    echo "KDE profile saved as '{{name}}'."

[group('hoid')]
konsave-apply name="hoid":
    konsave -a {{name}}
    echo "Applied KDE profile '{{name}}'."

# ── Firefox ───────────────────────────────────────────────────────────────────

[group('hoid')]
firefox-profile-import:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    ITEM=$(bw get item "Hoid uBlue")
    FIREFOX_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="FIREFOX_PROFILE_URL") | .value')
    if [[ -z "${FIREFOX_URL}" ]]; then
        echo "ERROR: FIREFOX_PROFILE_URL field not found in 'Hoid uBlue' vault item"
        exit 1
    fi
    echo "Downloading Firefox profile from: ${FIREFOX_URL}"

    PROFILE_DIR="${HOME}/.var/app/org.mozilla.firefox/config/mozilla/firefox"
    TARGET=$(find "${PROFILE_DIR}" -maxdepth 1 -type d -name "*.default-release" | head -1)
    if [[ -z "${TARGET}" ]]; then
        echo "ERROR: no *.default-release folder found in ${PROFILE_DIR}"
        exit 1
    fi
    echo "Found profile folder: ${TARGET}"

    rm -rf "${TARGET:?}/"*
    echo "Cleared existing profile contents."

    curl -fSL -o /tmp/firefox-profile.tar.gz "${FIREFOX_URL}"
    [[ -s /tmp/firefox-profile.tar.gz ]] || { echo "ERROR: downloaded file is empty"; exit 1; }
    echo "Extracting into ${TARGET}..."
    tar -xzvf /tmp/firefox-profile.tar.gz -C "${TARGET}" --strip-components=1 --warning=no-unknown-keyword
    rm -f /tmp/firefox-profile.tar.gz
    echo "Done: Firefox profile imported."

# ── Thunderbird ───────────────────────────────────────────────────────────────

[group('hoid')]
thunderbird-profile-import:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    ITEM=$(bw get item "Hoid uBlue")
    THUNDERBIRD_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="THUNDERBIRD_PROFILE_URL") | .value')
    if [[ -z "${THUNDERBIRD_URL}" ]]; then
        echo "ERROR: THUNDERBIRD_PROFILE_URL field not found in 'Hoid uBlue' vault item"
        exit 1
    fi
    echo "Downloading Thunderbird profile from: ${THUNDERBIRD_URL}"

    PROFILE_DIR="${HOME}/.thunderbird"

    if [[ -d "${PROFILE_DIR}" ]]; then
        BACKUP="${PROFILE_DIR}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "${PROFILE_DIR}" "${BACKUP}"
        echo "Backed up existing profile directory to ${BACKUP}"
        rm -rf "${PROFILE_DIR}"
        echo "Deleted original profile directory."
    fi

    curl -fSL -o /tmp/thunderbird-profile.tar.gz "${THUNDERBIRD_URL}"
    [[ -s /tmp/thunderbird-profile.tar.gz ]] || { echo "ERROR: downloaded file is empty"; exit 1; }
    echo "Extracting to ${HOME}..."
    tar -xzvf /tmp/thunderbird-profile.tar.gz -C "${HOME}" --warning=no-unknown-keyword
    rm -f /tmp/thunderbird-profile.tar.gz
    echo "Done: Thunderbird profile imported."

# ── Wallpaper ────────────────────────────────────────────────────────────────

[group('hoid')]
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

[group('hoid')]
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

[group('hoid')]
setup-autostart:
    #!/usr/bin/env bash
    set -euo pipefail
    AUTOSTART_DIR="${HOME}/.config/autostart"
    mkdir -p "${AUTOSTART_DIR}"

    printf '[Desktop Entry]\nName=Flameshot\nExec=flameshot\nIcon=flameshot\nType=Application\n' \
        > "${AUTOSTART_DIR}/flameshot.desktop"
    printf '[Desktop Entry]\nName=Nextcloud\nExec=nextcloud --background\nIcon=Nextcloud\nType=Application\n' \
        > "${AUTOSTART_DIR}/nextcloud.desktop"
    printf '[Desktop Entry]\nName=ULauncher\nExec=/usr/bin/ulauncher --hide-window\nIcon=ulauncher\nType=Application\n' \
        > "${AUTOSTART_DIR}/ulauncher.desktop"

    echo "Done: autostart entries created for Flameshot, Nextcloud, ULauncher."

# ── VeraCrypt ────────────────────────────────────────────────────────────────

[group('hoid')]
install-veracrypt:
    #!/usr/bin/env bash
    set -euo pipefail
    if rpm -q veracrypt &>/dev/null; then
        echo "veracrypt already installed: $(rpm -q veracrypt)"
        exit 0
    fi
    echo "-- Fetching latest VeraCrypt release --"
    RELEASE_JSON=$(curl -sf https://api.github.com/repos/veracrypt/VeraCrypt/releases/latest)
    VERSION=$(printf '%s' "${RELEASE_JSON}" | jq -r '.tag_name | ltrimstr("VeraCrypt_")')
    RPM_URL=$(printf '%s' "${RELEASE_JSON}" | jq -r '[.assets[] | select(.name | test("x86_64\\.rpm") and (test("(?i)console") | not)) | .browser_download_url] | first')
    echo "Downloading VeraCrypt ${VERSION} from ${RPM_URL}"
    curl -fsSL -o /tmp/veracrypt.rpm "${RPM_URL}"
    sudo rpm-ostree install /tmp/veracrypt.rpm || {
        echo "VeraCrypt already layered (pending reboot), skipping."
    }
    rm -f /tmp/veracrypt.rpm
    echo "Done: VeraCrypt ${VERSION} installed. Reboot to apply."

# ── logiops ──────────────────────────────────────────────────────────────────

[group('hoid')]
logi-restart:
    sudo systemctl restart logid
    echo "Done: logid restarted."

# ── Fingerprint ───────────────────────────────────────────────────────────────

[group('hoid')]
fingerprint-enable:
    sudo authselect enable-feature with-fingerprint
    echo "Done: fingerprint enabled."

[group('hoid')]
fingerprint-disable:
    sudo authselect disable-feature with-fingerprint
    echo "Done: fingerprint disabled."

# ── AppImages ────────────────────────────────────────────────────────────────

[group('hoid')]
install-mqtt-explorer:
    #!/usr/bin/env bash
    set -euo pipefail
    BIN_DIR="${HOME}/.local/bin"
    APPIMAGE="${BIN_DIR}/MQTT_Explorer.AppImage"
    mkdir -p "${BIN_DIR}" "${HOME}/.local/share/applications"
    echo "-- Installing MQTT Explorer --"
    APPIMAGE_URL="https://github.com/thomasnordquist/MQTT-Explorer/releases/download/0.0.0-0.4.0-beta1/MQTT-Explorer-0.4.0-beta1.AppImage"
    wget -q --show-progress -O "${APPIMAGE}" "${APPIMAGE_URL}"
    chmod 744 "${APPIMAGE}"
    printf '[Desktop Entry]\nType=Application\nName=MQTT Explorer\nExec=%s\nIcon=/usr/share/pixmaps/MQTT_Explorer.png\nCategories=Development;\nTerminal=false\n' \
        "${APPIMAGE}" \
        > "${HOME}/.local/share/applications/MQTT_Explorer.desktop"
    echo "Done: MQTT Explorer 0.4.0-beta1 installed."

# ── Wake-on-LAN ───────────────────────────────────────────────────────────────

[group('hoid')]
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
