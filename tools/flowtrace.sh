#!/bin/bash
# Like flowtest.sh but with section/text tracing into extract/flow_trace.log. usage: flowtrace.sh [seconds] [stop_scenario]
source "$(dirname "$0")/flowlib.sh"
cd "$ROOT/game" || exit 1
LOG=$ROOT/extract/flow_trace.log
SLOT=${WG_AUTOSLOT:-19}     # not one of the player's save slots 0-9
check_slot "$SLOT"
claim "slot_$SLOT" flow_trace.log
if [ -f "$USERDIR/save_$SLOT.json" ] && [ "$FRESH" = "" ]; then START="WG_LOADSLOT=$SLOT"; else START="WG_START=0"; fi
env $START WG_AUTOSLOT=$SLOT WG_TRACE_SEC=1 WG_TRACE_TEXT=1 WG_AUTOSAVE=1 WG_RANDOM=1 WG_GOD=1 WG_AUTO=1 WG_STOP=${2:-200} WG_NOVIDEO=1 \
  perl -e "alarm ${1:-3000}; exec @ARGV" godot --headless --path . 2>&1 | grep --line-buffered -E -v "$NOISE" >> "$LOG"
