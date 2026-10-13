#!/bin/bash
# Publish game/assets_hd as assets_hd.zip of the release tagged hd-pack, and pin its SHA-256 in tools/hd_pack.sha256:
# the release builds (.github/scripts/add_hd_pack.sh) and tools/get_hd_pack.sh accept only the pinned pack. Commit
# and push the pin file afterwards; release builds of a commit with the old pin fail from the swap on.
# usage: publish_hd_pack.sh [--dry-run]
#   --dry-run: build the zip and print its SHA-256, upload nothing. Needs gh (logged in) for the upload.
# The zip is built by tools/zip_pack.py (name order, fixed dates and modes), so the same pictures give the same pack
# on any machine. The new pack goes up as assets_hd.next.zip and replaces assets_hd.zip only once GitHub reports the
# SHA-256 it was built with: a failed or damaged upload leaves the published pack and the pin as they were.
set -euo pipefail
cd "$(dirname "$0")/.."
dry=0
case "${1:-}" in
  "") ;;
  --dry-run) dry=1 ;;
  *) echo "usage: $(basename "$0") [--dry-run]" >&2; exit 2 ;;
esac
if [ $# -gt 1 ]; then
  echo "usage: $(basename "$0") [--dry-run]" >&2
  exit 2
fi
if [ ! -d game/assets_hd/gfx ]; then
  echo "No game/assets_hd (tools/upscale_assets.py builds it)" >&2
  exit 1
fi
mkdir -p build
python3 -I tools/zip_pack.py game/assets_hd build/assets_hd.zip
sum=$(shasum -a 256 build/assets_hd.zip | cut -d' ' -f1)
pinned=$(cut -d' ' -f1 tools/hd_pack.sha256 2>/dev/null | tr 'A-F' 'a-f' || true)
echo "build/assets_hd.zip: $(find game/assets_hd -name '*.webp' | wc -l | tr -d ' ') images, SHA-256 $sum"
if [ "$sum" = "$pinned" ]; then
  echo "That is the pinned pack: nothing to publish."
  exit 0
fi
if [ $dry = 1 ]; then
  echo "Dry run: not uploaded (the pinned pack is ${pinned:-none})."
  exit 0
fi
digest() {      # GitHub's SHA-256 of release asset $1, without the "sha256:" prefix
  gh release view hd-pack --json assets --jq ".assets[] | select(.name==\"$1\") | .digest" | sed 's/^sha256://'
}
cp build/assets_hd.zip build/assets_hd.next.zip
gh release delete-asset hd-pack assets_hd.next.zip -y >/dev/null 2>&1 || true     # left by a failed run
gh release upload hd-pack build/assets_hd.next.zip
rm -f build/assets_hd.next.zip
got=$(digest assets_hd.next.zip)
if [ "$got" != "$sum" ]; then
  gh release delete-asset hd-pack assets_hd.next.zip -y || true
  echo "GitHub reports ${got:-no digest} for the upload, not $sum: the published pack and tools/hd_pack.sha256" \
    "are left as they were" >&2
  exit 1
fi
# the swap: the old pack goes and the new one takes its name (a release build that downloads in between fails; re-run it)
api=$(gh release view hd-pack --json assets --jq '.assets[] | select(.name=="assets_hd.next.zip") | .apiUrl')
gh release delete-asset hd-pack assets_hd.zip -y || true
gh api -X PATCH "$api" -f name=assets_hd.zip >/dev/null
if [ "$(digest assets_hd.zip)" != "$sum" ]; then
  echo "The rename to assets_hd.zip did not take: the release holds assets_hd.next.zip ($sum); rename it on GitHub" \
    "and run this again to write the pin" >&2
  exit 1
fi
echo "$sum  assets_hd.zip" > tools/hd_pack.sha256
echo "Uploaded and pinned. Commit tools/hd_pack.sha256 and push: the release build of that commit uses the new pack."
