#!/bin/bash
# Publish game/assets_hd as assets_hd.zip of the release tagged hd-pack, and pin its SHA-256 in tools/hd_pack.sha256:
# the release builds (.github/scripts/add_hd_pack.sh) and tools/get_hd_pack.sh accept only the pinned pack. Commit
# and push the pin file afterwards; release builds of a commit with the old pin fail until then.
# --dry-run: build the zip and print its SHA-256, upload nothing. Needs gh (logged in) for the upload.
set -euo pipefail
cd "$(dirname "$0")/.."
dry=0
[ "${1:-}" = "--dry-run" ] && dry=1
if [ ! -d game/assets_hd/gfx ]; then
  echo "No game/assets_hd (tools/upscale_assets.py builds it)" >&2
  exit 1
fi
mkdir -p build
rm -f build/assets_hd.zip            # zip adds to an existing archive
(cd game/assets_hd && zip -0 -qr ../../build/assets_hd.zip . -x '*.tmp' -x '*.DS_Store')
sum=$(shasum -a 256 build/assets_hd.zip | cut -d' ' -f1)
echo "build/assets_hd.zip: $(find game/assets_hd -name '*.webp' | wc -l | tr -d ' ') images, SHA-256 $sum"
if [ "$sum" = "$(cut -d' ' -f1 tools/hd_pack.sha256)" ]; then
  echo "That is the pinned pack: nothing to publish."
  exit 0
fi
if [ $dry = 1 ]; then
  echo "Dry run: not uploaded (the pinned pack is $(cut -d' ' -f1 tools/hd_pack.sha256))."
  exit 0
fi
# --clobber deletes the old file before the new one is up: a release build that starts meanwhile fails
gh release upload hd-pack build/assets_hd.zip --clobber
got=$(gh release view hd-pack --json assets --jq '.assets[] | select(.name=="assets_hd.zip") | .digest')
if [ "${got#sha256:}" != "$sum" ]; then
  echo "GitHub reports ${got:-no digest} for the upload, not sha256:$sum; tools/hd_pack.sha256 left as it was" >&2
  exit 1
fi
echo "$sum  assets_hd.zip" > tools/hd_pack.sha256
echo "Uploaded and pinned. Commit tools/hd_pack.sha256 and push: the release build of that commit uses the new pack."
