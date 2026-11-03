#!/bin/sh
# Build the Debian/Ubuntu/Mint package into dist/.
set -eu
cd "$(dirname "$0")/.."

if ! command -v dh >/dev/null 2>&1; then
    echo "Missing packaging tools. Install them with:" >&2
    echo "  sudo apt install debhelper" >&2
    exit 1
fi

dpkg-checkbuilddeps
dpkg-buildpackage --build=binary --no-sign

version=$(dpkg-parsechangelog --show-field Version)
arch=$(dpkg --print-architecture)
mkdir -p dist
for f in ../emozi_"${version}"_"${arch}".deb \
         ../emozi-dbgsym_"${version}"_"${arch}".ddeb \
         ../emozi_"${version}"_"${arch}".buildinfo \
         ../emozi_"${version}"_"${arch}".changes; do
    [ -e "$f" ] && mv "$f" dist/
done

echo
echo "Built dist/emozi_${version}_${arch}.deb"
echo "Install it with: sudo apt install ./dist/emozi_${version}_${arch}.deb"
