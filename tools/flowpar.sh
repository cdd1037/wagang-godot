#!/bin/bash
# Parallel flow test of a scenario range: flowpar.sh START STOP SLOT [ALARM] [PARTY]
# log → extract/flow_par_START.log
# SLOT is a save slot in the game's user folder: use 11 or higher (0-9 are the player's saves)
# A range that starts after R_09 (scenario 18) gets R_09's branch flag 755 (突围), which a jump start lacks and
# R_21's 出征 needs (through flag 19); set WG_SETFLAGS yourself to choose otherwise.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/game" || exit 1
LOG=$ROOT/extract/flow_par_$1.log
: > "$LOG"
FLAGS=${WG_SETFLAGS-}
if [ -z "${WG_SETFLAGS+x}" ] && [ "$1" -gt 18 ]; then FLAGS=755; fi
env WG_START=$1 WG_PARTY=${5:-} WG_SETFLAGS=$FLAGS WG_AUTOSLOT=$3 WG_TRACE_SEC=1 WG_TRACE_TEXT=1 WG_AUTOSAVE=1 WG_RANDOM=1 WG_GOD=1 WG_AUTO=1 WG_STOP=$2 WG_NOVIDEO=1 \
  perl -e "alarm ${4:-3000}; exec @ARGV" godot --headless --path . 2>&1 | grep --line-buffered -v "Case mismatch\|open_internal\|^$\|^\s*\[[0-9]*\] \|GDScript backtrace" >> "$LOG"
