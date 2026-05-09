# Hoid-specific just recipes
# Run with: ujust <recipe-name>
# Shared recipes (bw-unlock, install-chezmoi, setup-mounts, etc.) live in 50-common.just

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
    ujust install-backrest
    ujust backrest-import-config
    ujust install-chezmoi
    ujust install-vscode-extensions
    ujust setup-printer
    ujust setup-scanner
    ujust install-konsave
    ujust konsave-import
    ujust firefox-profile-import
    ujust thunderbird-profile-import
    ujust install-mqtt-explorer
    ujust setup-wallpaper
    ujust setup-avatar
    ujust setup-nextcloud
    ujust setup-autostart
    ujust toggle-user-motd
    ujust bw-lock
    echo ""
    echo "=== Done! Manual steps still needed: ==="
    echo "  Log out and back in to activate zsh and scanner group membership"
    echo ""

# ── SSH ───────────────────────────────────────────────────────────────────────

[group('hoid')]
enable-ssh:
    sudo systemctl enable --now sshd
    echo "Done: SSH enabled."

# ── Backrest ─────────────────────────────────────────────────────────────────

[group('hoid')]
install-backrest:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "-- Installing Backrest --"
    BACKREST_VER=$(curl -sf https://api.github.com/repos/garethgeorge/backrest/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//')
    curl -fsSL -o /tmp/backrest.tar.gz \
        "https://github.com/garethgeorge/backrest/releases/download/v${BACKREST_VER}/backrest_Linux_x86_64.tar.gz"
    mkdir -p /tmp/backrest-install
    tar -xzf /tmp/backrest.tar.gz -C /tmp/backrest-install
    cd /tmp/backrest-install && bash install.sh
    sudo restorecon -v /usr/local/bin/backrest
    rm -rf /tmp/backrest.tar.gz /tmp/backrest-install
    echo "Done: Backrest ${BACKREST_VER} installed and service started."
    echo ""
    echo "Open http://localhost:9898 to complete setup."

[group('hoid')]
backrest-import-config:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null         || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    echo "-- Importing Backrest config from Bitwarden --"
    CONFIG=$(bw get notes "Hoid Backrest Config" 2>/dev/null || true)
    if [[ -z "${CONFIG}" ]]; then
        echo "ERROR: 'Hoid Backrest Config' item not found in Bitwarden or notes field is empty"
        exit 1
    fi

    CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/backrest"
    mkdir -p "${CONFIG_DIR}"

    # Stop service before replacing config
    sudo systemctl stop backrest.service 2>/dev/null || true

    printf '%s' "${CONFIG}" > "${CONFIG_DIR}/config.json"
    chmod u=rw,g=,o= "${CONFIG_DIR}/config.json"
    echo "Config written to ${CONFIG_DIR}/config.json"

    sudo systemctl start backrest.service
    echo "Done: Backrest config imported and service restarted."

[group('hoid')]
backrest-open:
    xdg-open http://localhost:9898

[group('hoid')]
backrest-restart:
    sudo systemctl restart backrest.service
    echo "Done: Backrest restarted."

[group('hoid')]
backrest-logs:
    journalctl -u backrest.service -f

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
    # Brother DCP-L2640DW (network, IPP Everywhere)
    sudo /usr/sbin/lpadmin -p Brother-DCP-L2640DW -E \
        -v ipp://192.168.30.10/ipp/port1 \
        -m everywhere \
        -o media=na_letter_8.5x11in

    # Brother HL-2270DW (network, brlaser PPD)
    sudo /usr/sbin/lpadmin -p Brother-HL2270DW -E \
        -v ipp://192.168.30.9/ipp/port1 \
        -m drv:///brlaser.drv/br2270d.ppd \
        -o media=na_letter_8.5x11in

    /usr/bin/lpoptions -d Brother-DCP-L2640DW
    echo "Done: Brother-DCP-L2640DW and Brother-HL2270DW configured."

# ── Scanner ───────────────────────────────────────────────────────────────────

[group('hoid')]
setup-scanner:
    #!/usr/bin/env bash
    set -euo pipefail
    USERNAME=$(whoami)

    echo "-- Creating scanner group if needed --"
    if ! getent group scanner > /dev/null 2>&1; then
        sudo groupadd scanner
        echo "Created scanner group."
    fi

    echo "-- Adding ${USERNAME} to scanner group --"
    sudo usermod -aG scanner "${USERNAME}"
    sudo usermod -aG dialout "${USERNAME}"

    echo "-- Fixing brscan5 udev rules --"
    UDEV_RULES=$(ls /etc/udev/rules.d/60-brother-mfp-brscan5-*.rules 2>/dev/null | head -1)
    if [[ -z "${UDEV_RULES}" ]]; then
        echo "WARNING: brscan5 udev rules file not found -- was brscan5 installed at build time?"
    else
        sudo sed -i 's/#MODE="0666"/MODE="0666"/' "${UDEV_RULES}"
        sudo sed -i 's/#GROUP="scanner"/GROUP="scanner"/' "${UDEV_RULES}"
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        echo "Done: udev rules updated at ${UDEV_RULES}"
    fi

    echo "Done: scanner configured."
    echo "NOTE: Unplug and replug the DS-740D, then log out and back in for group membership to take effect."
    echo "      Test with: scanimage -L"

# ── Firefox ───────────────────────────────────────────────────────────────────

[group('hoid')]
firefox-profile-import:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    ITEM=$(bw get item "uBlue Hoid")
    FIREFOX_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="FIREFOX_PROFILE_URL") | .value')
    if [[ -z "${FIREFOX_URL}" ]]; then
        echo "ERROR: FIREFOX_PROFILE_URL field not found in 'uBlue Hoid' vault item"
        exit 1
    fi
    echo "Downloading Firefox profile from: ${FIREFOX_URL}"

    PROFILE_DIR="${HOME}/.var/app/org.mozilla.firefox/config/mozilla/firefox"
    if ! find "${PROFILE_DIR}" -maxdepth 1 -type d -name "*.default-release" 2>/dev/null | grep -q .; then
        echo "Profile directory not found — launching Firefox to initialize it..."
        flatpak run org.mozilla.firefox --headless &>/dev/null &
        FIREFOX_PID=$!
        for i in $(seq 1 60); do
            if find "${PROFILE_DIR}" -maxdepth 1 -type d -name "*.default-release" 2>/dev/null | grep -q .; then
                break
            fi
            sleep 1
        done
        kill "${FIREFOX_PID}" 2>/dev/null || true
        wait "${FIREFOX_PID}" 2>/dev/null || true
        sleep 1
    fi
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

    ITEM=$(bw get item "uBlue Hoid")
    THUNDERBIRD_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="THUNDERBIRD_PROFILE_URL") | .value')
    if [[ -z "${THUNDERBIRD_URL}" ]]; then
        echo "ERROR: THUNDERBIRD_PROFILE_URL field not found in 'uBlue Hoid' vault item"
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

# ── Nextcloud ────────────────────────────────────────────────────────────────

[group('hoid')]
setup-nextcloud:
    #!/usr/bin/env bash
    set -euo pipefail
    BW_SESSION=$(cat /tmp/.bw_session 2>/dev/null \
        || { echo "ERROR: run ujust bw-unlock first"; exit 1; })
    export BW_SESSION

    ITEM=$(bw get item "uBlue Hoid")
    NEXTCLOUD_URL=$(printf '%s' "${ITEM}" \
        | jq -r '.fields[] | select(.name=="NEXTCLOUD_URL") | .value')
    if [[ -z "${NEXTCLOUD_URL}" ]]; then
        echo "ERROR: NEXTCLOUD_URL field not found in 'uBlue Hoid' vault item"
        exit 1
    fi
    echo "Setting Nextcloud server URL: ${NEXTCLOUD_URL}"
    nextcloud --overrideserverurl "${NEXTCLOUD_URL}"
    echo "Done: Nextcloud server URL configured."

# ── Autostart ────────────────────────────────────────────────────────────────

[group('hoid')]
setup-autostart:
    #!/usr/bin/env bash
    set -euo pipefail
    AUTOSTART_DIR="${HOME}/.config/autostart"
    mkdir -p "${AUTOSTART_DIR}"

    cp /usr/share/fabrial-os/autostart/*.desktop "${AUTOSTART_DIR}/"

    echo "Done: autostart entries created for Flameshot, Nextcloud, ULauncher."

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
