#!/bin/bash
# UI playthrough test (game/src/debug/ui_bot.gd): a new game from the title screen, played only through real input
# events (clicks on dialogue, menu rows, window buttons, story actors and battle cells), checking that every click
# is taken, that no stage starts with UI left over, and that each town's windows open and close and a save / load
# round trip works (saves go to user://uibot/, not the player's slots).
# usage: uitest.sh [STOP] [seconds]   STOP: the scenario to stop at (default 5: up to the end of R_02, the first
# town with the toolbar).
# Headless unless WINDOW=1 (then failures and each stage's start are also saved as pictures in extract/uibot/).
# WG_GOD and WG_NOVIDEO default to 1; set them empty to turn them off. Other WG_* variables pass through.
# Prints the bot's lines and "uitest: PASS" or "uitest: FAIL"; the full log is extract/uibot/uitest.log.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOP=${1:-5}
SECS=${2:-3600}
OUT=$ROOT/extract/uibot
mkdir -p "$OUT"
LOG=$OUT/uitest.log
HL=(--headless)
[ -n "$WINDOW" ] && HL=()
cd "$ROOT/game" || exit 1
# under a pseudo-terminal, as from a shell; BSD script (macOS) takes the command after the file, util-linux's with -c
if [ "$(uname)" = Darwin ]; then
	RUN=(script -q /dev/null godot "${HL[@]}" --path .)
else
	RUN=(script -qec "godot ${HL[*]} --path ." /dev/null)
fi
WG_UIBOT="$OUT" WG_STOP=$STOP WG_GOD=${WG_GOD-1} WG_NOVIDEO=${WG_NOVIDEO-1} WG_UIBOT_TIME=$SECS \
	perl -e "alarm $((SECS + 120)); exec @ARGV" "${RUN[@]}" < /dev/null > "$LOG" 2>&1
# leaks reported at exit (resources, RIDs) are shutdown noise of headless runs, not errors of the game
ERRS=$(grep -a "SCRIPT ERROR\|ERROR:" "$LOG" | grep -av "Case mismatch\|at exit")
grep -a "UIBOT" "$LOG"
[ -n "$ERRS" ] && echo "$ERRS"
if grep -aq "UIBOT: PASS" "$LOG" && [ -z "$ERRS" ]; then
	echo "uitest: PASS"
else
	echo "uitest: FAIL (log: $LOG)"
	exit 1
fi
