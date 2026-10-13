#!/bin/bash
# usage: gtest.sh t_name [timeout]
# Runs game/src/debug/t_name.gd under the headless test runner. Exit status: 0 passed, 1 failed (a script error,
# or godot crashed), 2 timed out (the runner's own limit, TEST_TIMEOUT; perl's alarm 30 s later is the backstop).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/game" || exit 1
LIMIT=${2:-120}
TEST=res://src/debug/$1.gd TEST_TIMEOUT=$LIMIT perl -e "alarm $LIMIT + 30; exec @ARGV" \
	godot --headless --path . res://src/debug/test_runner.tscn 2>&1 \
	| awk '/Case mismatch/ {skip = 1; next} skip && /^[[:space:]]/ {next} {skip = 0} /^Godot Engine|^$/ {next} {print; fflush()}'
status=${PIPESTATUS[0]}
case $status in
	0 | 1 | 2) ;;
	142) status=2 ;;                    # killed by perl's alarm (SIGALRM): still running at the limit
	*) echo "gtest: godot ended with status $status (crashed or missing)" >&2; status=1 ;;
esac
exit "$status"
