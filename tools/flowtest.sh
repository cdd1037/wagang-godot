#!/bin/bash
# Long autoplay flow test with autosave/retry. usage: flowtest.sh [seconds] [stop_scenario]
cd /Users/f2pgod/Downloads/rea/game
LOG=/Users/f2pgod/Downloads/rea/extract/flow.log
SAVE="$HOME/Library/Application Support/Godot/app_userdata/兴唐传·瓦岗山异闻录/save_09.json"
if [ -f "$SAVE" ] && [ "$FRESH" = "" ]; then START="WG_LOADSLOT=9"; else START="WG_START=0"; fi
env $START WG_AUTOSAVE=1 WG_RANDOM=1 WG_GOD=1 WG_AUTO=1 WG_STOP=${2:-200} WG_NOVIDEO=1 perl -e "alarm ${1:-3000}; exec @ARGV" godot --headless --path . 2>&1 \
  | grep --line-buffered -E "== |chapter|WARNING|ERROR|SCRIPT" >> $LOG
