#!/bin/bash
# Runs the headless unit checks (game/src/debug/t_*.gd) one after another and prints a summary.
# usage: test_all.sh [t_name ...]     (default: every check below that needs no window)
# Exit status 0 when all passed, else 1. A failed check's output is printed under its line.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# not run by default: t_hd, t_resize, t_storyclick and t_toolbar need a window (DEVELOPMENT.md); t_person only
# prints, t_flow is a stub
SKIP=" t_hd t_resize t_storyclick t_toolbar t_person t_flow "
if [ $# -gt 0 ]; then
	TESTS=("$@")
else
	TESTS=()
	for f in "$ROOT"/game/src/debug/t_*.gd; do
		t=$(basename "$f" .gd)
		[[ "$SKIP" == *" $t "* ]] || TESTS+=("$t")
	done
fi
failed=""
for t in "${TESTS[@]}"; do
	start=$(date +%s)
	out=$("$ROOT/tools/gtest.sh" "$t" 2>&1)
	status=$?
	case $status in
		0) result=PASS ;;
		2) result="FAIL (timeout)" ;;
		*) result=FAIL ;;
	esac
	printf '%-14s %s  %ds\n' "$t" "$result" $(($(date +%s) - start))
	if [ $status -ne 0 ]; then
		failed="$failed $t"
		echo "$out" | sed 's/^/    /'
	fi
done
if [ -z "$failed" ]; then
	echo "test_all: ${#TESTS[@]} checks passed"
else
	echo "test_all: FAILED:$failed"
	exit 1
fi
