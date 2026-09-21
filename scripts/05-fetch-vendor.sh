#!/usr/bin/env bash
# Clones the large third-party tool/vendor trees that .gitignore excludes
# from this repo (too big, or already their own upstream git repos).
# tools/das and tools/ftdi are NOT handled here: they're Infineon/FTDI
# proprietary downloads (DAS 8.3.0, D2XX driver SDK) with their own license
# terms — get those from Infineon's / FTDI's own sites.
set -euo pipefail
cd "$(dirname "$0")/.."

clone_if_missing() {
    local url=$1 dest=$2
    if [ -d "$dest/.git" ]; then
        echo "skip (exists): $dest"
    else
        git clone "$url" "$dest"
    fi
}

clone_if_missing https://github.com/Infineon/illd_release_tc4x.git vendor/illd-tc4x
clone_if_missing https://github.com/tricore-oss/openocd.git tools/openocd
clone_if_missing https://github.com/volumit/aurix_flasher_linux.git tools/aurix-flasher
clone_if_missing https://github.com/tricore-oss/tricore-toolchain.git tools/tricore-toolchain

cat << 'EOF'

Not fetched here (proprietary, manual download required):
  - tools/das   <- Infineon DAS (Debug Access Server), from Infineon's site
  - tools/ftdi  <- FTDI D2XX Linux driver SDK, from ftdichip.com

tools/openocd needs building afterwards:
  cd tools/openocd && ./bootstrap && ./configure --enable-tas_client && make
EOF
