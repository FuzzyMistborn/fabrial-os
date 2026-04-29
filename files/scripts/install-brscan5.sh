#!/usr/bin/env bash

set -oue pipefail

# Brother's brscan5 RPM has no digest header at all; dnf5 --nogpgcheck still rejects it.
# rpm --nodigest --nosignature bypasses both checks.
curl -L -o /tmp/brscan5.rpm https://download.brother.com/welcome/dlf104036/brscan5-1.5.1-0.x86_64.rpm
rpm -i --nodigest --nosignature /tmp/brscan5.rpm
rm /tmp/brscan5.rpm
