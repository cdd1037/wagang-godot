#!/bin/bash
# usage: gtest.sh t_name [timeout]
# Runs game/src/debug/t_name.gd under the headless test runner. Exit status: 0 passed, 1 failed (or a script
# error), 2 timed out (the runner's own limit, TEST_TIMEOUT; perl's alarm 30 s later is the backstop).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/game" || exit 1
LIMIT=${2:-120}
TEST=res://src/debug/$1.gd TEST_TIMEOUT=$LIMIT perl -e "alarm $LIMIT + 30; exec @ARGV" \
	godot --headless --path . res://src/debug/test_runner.tscn 2>&1 \
	| awk '/Case mismatch/ {skip = 1; next} skip && /^[[:space:]]/ {next} {skip = 0} /^Godot Engine|^$/ {next} {print; fflush()}'
status=${PIPESTATUS[0]}
[ "$status" -gt 2 ] && status=2      # killed by the alarm
exit "$status"
