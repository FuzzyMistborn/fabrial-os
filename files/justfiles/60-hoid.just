# Hoid-specific just recipes
# Run with: ujust <recipe-name>
# Shared recipes (bw-unlock, install-zsh, setup-mounts, etc.) live in 50-common.just

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

# ── SSH ───────────────────────────────────────────────────────────────────────

[group('hoid')]
enable-ssh:
    sudo systemctl enable --now sshd
    echo "Done: SSH enabled."

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
