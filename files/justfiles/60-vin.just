# Vin-specific just recipes (Bazzite Steam Deck)
# Run with: ujust <recipe-name>
# Shared recipes (bw-unlock, install-zsh, etc.) live in 50-common.just

# ── Full first-boot setup ─────────────────────────────────────────────────────

[group('vin')]
setup-vin:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "=== Vin first-boot setup ==="
    echo ""
    ujust install-bw-cli
    ujust bw-unlock
    ujust install-ssh-keys
    ujust bw-lock
    echo ""
    echo "=== Done! ==="
    echo ""
