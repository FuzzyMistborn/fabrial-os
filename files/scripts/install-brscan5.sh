#!/usr/bin/env bash

set -oue pipefail

# Brother's brscan5 RPM has no GPG digest, so it must be installed with --nogpgcheck
dnf install -y --nogpgcheck https://download.brother.com/welcome/dlf104036/brscan5-1.5.1-0.x86_64.rpm
