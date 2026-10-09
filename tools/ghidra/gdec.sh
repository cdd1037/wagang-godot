#!/bin/bash
# Decompile wagan.wa functions with Ghidra headless. usage: gdec.sh OUTFILE ADDR [ADDR...]
# First run imports + auto-analyses the exe into a project (slow, once).
export JAVA_HOME=${JAVA_HOME_21:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}
GH=${GHIDRA_INSTALL_DIR:-/opt/homebrew/Cellar/ghidra/12.1.4/libexec}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ=$ROOT/extract/ghidra_proj
EXE=$ROOT/wg2025/wagan.wa
SP=$ROOT/tools/ghidra
mkdir -p "$PROJ"
OUT=$1; shift
if [ ! -d "$PROJ/wg.rep" ]; then
  "$GH/support/analyzeHeadless" "$PROJ" wg -import "$EXE" -processor x86:LE:32:default -cspec windows \
     -scriptPath "$SP" -postScript Decompile.java "$OUT" "$@" > "$PROJ/import.log" 2>&1
else
  "$GH/support/analyzeHeadless" "$PROJ" wg -process wagan.wa -noanalysis -readOnly \
     -scriptPath "$SP" -postScript Decompile.java "$OUT" "$@" > "$PROJ/last.log" 2>&1
fi
tail -3 "$PROJ"/*.log | grep -i -E "error|exception" | head -5
