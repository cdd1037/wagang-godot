#!/bin/bash
# Run the game from source with Godot 4.7 (brew install --cask godot).
# A fresh checkout has no Godot import cache (game/.godot); build it once first, otherwise the
# scripts' class names are not registered yet.
cd "$(dirname "$0")/game" || exit 1
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "First run: importing the project (takes a minute)…"
  godot --headless --path . --import || exit 1
fi
exec godot --path . "$@"
