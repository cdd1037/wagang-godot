#!/bin/bash
# Resume a parallel flow test from its autosave slot: flowres.sh SLOT STOP LOGNAME [ALARM]
source "$(dirname "$0")/flowlib.sh"
if [ $# -lt 3 ]; then echo "usage: $(basename "$0") SLOT STOP LOGNAME [ALARM]" >&2; exit 2; fi
check_slot "$1"
claim "slot_$1" "$3"
cd "$ROOT/game" || exit 1
LOG=$ROOT/extract/$3
echo "=== resume slot $1 $(date)" >> "$LOG"
env WG_LOADSLOT=$1 WG_AUTOSLOT=$1 WG_TRACE_SEC=1 WG_TRACE_TEXT=1 WG_AUTOSAVE=1 WG_RANDOM=1 WG_GOD=1 WG_AUTO=1 WG_STOP=$2 WG_NOVIDEO=1 \
  perl -e "alarm ${4:-3000}; exec @ARGV" godot --headless --path . 2>&1 | grep --line-buffered -E -v "$NOISE" >> "$LOG"
