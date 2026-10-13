#!/bin/bash
# Release builds ship the HD art in place of the originals. The pack (the contents of game/assets_hd, built locally
# with tools/upscale_assets.py) is the asset assets_hd.zip of the release tagged hd-pack, and the commit pins its
# SHA-256 in tools/hd_pack.sha256 (tools/publish_hd_pack.sh uploads a pack and writes the pin). This puts it into
# game/assets_hd and leaves the original pictures that have an HD version out of every export preset. Needs
# GH_TOKEN and python3; Linux or macOS.
set -euo pipefail
tmp="$(mktemp -d)"
gh release download hd-pack -p "assets_hd.zip" -D "$tmp"
# only the pinned pack: a damaged download or a pack uploaded after this commit fails the build
want=$(cut -d' ' -f1 tools/hd_pack.sha256)
if ! echo "$want  $tmp/assets_hd.zip" | shasum -a 256 -c -; then
  echo "::error::assets_hd.zip of the hd-pack release is not the pack tools/hd_pack.sha256 pins ($want)." \
    "After uploading a new pack, commit its pin (tools/publish_hd_pack.sh writes it)."
  exit 1
fi
unzip -q "$tmp/assets_hd.zip" -d game/assets_hd
rm -r "$tmp"
n=$(find game/assets_hd -name '*.webp' | wc -l)
echo "HD pack: $n images"
test "$n" -ge 3900
# the originals to leave out are the iOS / Android presets' list; copy it into the macOS / Windows presets and
# check that each picture it leaves out has an HD version (tools/check_hd_exclude.py)
python3 -I tools/check_hd_exclude.py --apply
