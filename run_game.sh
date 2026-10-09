#!/bin/bash
# Run the game from source with Godot (brew install --cask godot)
cd "$(dirname "$0")/game" && exec godot --path . "$@"
