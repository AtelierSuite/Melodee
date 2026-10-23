#!/bin/zsh
# Composes the App Store screenshots from the captures in Raw/.
#
#   ./compose.sh          every device
#   ./compose.sh iPhone   only the iPhone
set -euo pipefail

assets_dir=${0:A:h}
binary=$(mktemp -t melodee-compose)
trap 'rm -f "$binary"' EXIT

swiftc -swift-version 6 -O "$assets_dir"/Compose/*.swift -o "$binary"
"$binary" "$@"
