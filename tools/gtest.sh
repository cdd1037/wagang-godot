#!/bin/bash
# usage: gtest.sh t_name [timeout]
cd /Users/f2pgod/Downloads/rea/game
TEST=res://src/debug/$1.gd perl -e "alarm ${2:-120}; exec @ARGV" godot --headless --path . res://src/debug/test_runner.tscn 2>&1 | grep -v "^Godot Engine\|^$\|Case mismatch\|open_internal"
