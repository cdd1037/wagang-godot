#!/bin/bash
# Download the HD graphics pack (game/assets_hd, ~770 MB) from the repository's hd-pack release.
# run_game.sh calls this on first run. The pack can also be built locally with tools/upscale_assets.py.
cd "$(dirname "$0")/.." || exit 1
REPO="seedds/wagang-godot"
URL="https://github.com/$REPO/releases/download/hd-pack/assets_hd.zip"
if [ -d game/assets_hd/gfx ]; then
  echo "game/assets_hd already exists"
  exit 0
fi
if [ -e game/assets_hd ]; then
  # left over from an interrupted install: keep it out of the way
  rm -rf game/assets_hd.partial && mv game/assets_hd game/assets_hd.partial || exit 1
  echo "Moved an incomplete game/assets_hd to game/assets_hd.partial"
fi
# the checkout pins the pack's SHA-256 (tools/publish_hd_pack.sh writes it)
want=$(cut -d' ' -f1 tools/hd_pack.sha256 2>/dev/null | tr 'A-F' 'a-f')
if [ -z "$want" ]; then
  echo "tools/hd_pack.sha256 is missing or empty: this checkout names no HD pack." >&2
  exit 1
fi
# the release's own SHA-256 of the asset (GitHub's digest): a pack this checkout does not pin is refused before the
# 770 MB download, not after (when the API cannot be asked, the download's check below still decides)
pub=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/hd-pack" 2>/dev/null \
  | python3 -I -c 'import json, sys
print(next((a.get("digest") or "" for a in json.load(sys.stdin).get("assets", []) if a.get("name") == "assets_hd.zip"), ""))' \
  2>/dev/null || true)
pub=${pub#sha256:}
if [ -n "$pub" ] && [ "$pub" != "$want" ]; then
  echo "The hd-pack release holds another pack ($pub) than this checkout pins ($want): git pull for the newer" >&2
  echo "pin, or build the pack locally with tools/upscale_assets.py." >&2
  exit 1
fi
echo "Downloading the HD graphics pack (~770 MB)…"
mkdir -p build
tmp=$(mktemp -d "$PWD/build/hdpack.XXXXXX") || exit 1    # same volume as game/, so the final mv is a rename
trap 'rm -rf "$tmp"' EXIT
curl -L --fail --progress-bar -o "$tmp/assets_hd.zip" "$URL" || exit 1
have=$(shasum -a 256 "$tmp/assets_hd.zip" | cut -d' ' -f1)
if [ "$have" != "$want" ]; then
  echo "The download is not the pack tools/hd_pack.sha256 pins: it is damaged (try again), or the hd-pack" >&2
  echo "release has a newer pack than this checkout (git pull)." >&2
  exit 1
fi
mkdir -p "$tmp/out" && unzip -q "$tmp/assets_hd.zip" -d "$tmp/out" || exit 1
mv "$tmp/out" game/assets_hd || exit 1
echo "HD graphics pack installed: $(find game/assets_hd -name '*.webp' | wc -l | tr -d ' ') images"
