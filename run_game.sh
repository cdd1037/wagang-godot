#!/bin/bash
# Run the game from source with Godot 4.7 (brew install --cask godot).
# First run: download the HD graphics pack (game/assets_hd; without it the original art is used), and build
# Godot's import cache (game/.godot), without which the scripts' class names are not registered.
cd "$(dirname "$0")" || exit 1
if [ ! -d game/assets_hd/gfx ]; then
  tools/get_hd_pack.sh || echo "Could not download the HD graphics pack; using the original art."
fi
cd game || exit 1
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "First run: importing the project (takes a minute)…"
  godot --headless --path . --import || exit 1
fi
exec godot --path . "$@"
