#!/bin/bash
# Download the HD graphics pack (game/assets_hd, ~720 MB) from the repository's hd-pack release.
# run_game.sh calls this on first run. The pack can also be built locally with tools/upscale_assets.py.
cd "$(dirname "$0")/.." || exit 1
URL="https://github.com/seedds/wagang-godot/releases/download/hd-pack/assets_hd.zip"
if [ -d game/assets_hd/gfx ]; then
  echo "game/assets_hd already exists"
  exit 0
fi
echo "Downloading the HD graphics pack (~720 MB)…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -L --fail --progress-bar -o "$tmp/assets_hd.zip" "$URL" || exit 1
mkdir -p "$tmp/out" && unzip -q "$tmp/assets_hd.zip" -d "$tmp/out" || exit 1
mv "$tmp/out" game/assets_hd
echo "HD graphics pack installed: $(find game/assets_hd -name '*.webp' | wc -l | tr -d ' ') images"
