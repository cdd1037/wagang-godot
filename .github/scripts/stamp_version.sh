#!/bin/bash
# Version stamp: the title screen (application/config/version) and the macOS / iOS bundle versions.
# usage: stamp_version.sh VERSION BUILD   (Linux or macOS)
set -euo pipefail
version="$1"
build="$2"
perl -ni -e 'print unless /^config\/version=/' game/project.godot
V="$version" perl -pi -e 's/^(config\/name=.*)$/$1\nconfig\/version="$ENV{V}"/' game/project.godot
V="$version" B="$build" perl -pi -e 's/^application\/short_version=.*/application\/short_version="$ENV{V}"/;
  s/^application\/version=.*/application\/version="$ENV{B}"/' game/export_presets.cfg
test "$(grep -c "^config/version=\"${version}\"" game/project.godot)" -eq 1
test "$(grep -c "^application/short_version=\"${version}\"" game/export_presets.cfg)" -eq 2   # macOS and iOS
test "$(grep -c "^application/version=\"${build}\"" game/export_presets.cfg)" -eq 2
