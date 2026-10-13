#!/bin/bash
# Convert WMV cutscenes to Ogg Theora/Vorbis for Godot. Numbered/END files have byte 0 zeroed (0x30 -> 0x00).
# A video already converted is skipped; a conversion goes to a .part file first, so a failed one leaves nothing a
# later run would take for done.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FF=$(brew --prefix ffmpeg-full)/bin/ffmpeg
SRC=$ROOT/wg2025
DST=$ROOT/game/assets/video
mkdir -p "$DST"
for f in "$SRC"/*.wmv; do
  b=$(basename "$f" .wmv | tr 'A-Z' 'a-z')
  [ -f "$DST/$b.ogv" ] && continue
  (printf '\x30'; tail -c +2 "$f") | "$FF" -hide_banner -loglevel error -y -i pipe:0 \
     -vf "scale='min(1280,iw)':-2" -c:v libtheora -q:v 6 -c:a libvorbis -q:a 4 -f ogg "$DST/$b.ogv.part"
  mv "$DST/$b.ogv.part" "$DST/$b.ogv"
  echo "ok $b"
done
