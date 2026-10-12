#!/bin/bash
# Coverage of the mod code (docs/mod_patches.md, "Coverage of the mod code"): Ghidra's reachability graph of .text2
# from the audit's entry points, then tools/modcov.py lists what neither it nor modcov.py's own descent reaches.
# usage: modcov.sh [OUTFILE]   (default extract/modcov.txt; Ghidra's summary goes to OUTFILE.ghidra)
export JAVA_HOME=${JAVA_HOME_21:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}
GH=${GHIDRA_INSTALL_DIR:-/opt/homebrew/Cellar/ghidra/12.1.4/libexec}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY=$ROOT/tools/venv/bin/python3
OUT=${1:-$ROOT/extract/modcov.txt}
[ -d "$ROOT/extract/ghidra_proj/wg.rep" ] || { echo "no Ghidra project: run tools/ghidra/gdec.sh once" >&2; exit 1; }
SEEDS=$("$PY" -I "$ROOT/tools/modcov.py" --seeds)
"$GH/support/analyzeHeadless" "$ROOT/extract/ghidra_proj" wg -process wagan.wa -noanalysis -readOnly \
   -scriptPath "$ROOT/tools/ghidra" -postScript ModCoverage.java "$OUT.ghidra" "$SEEDS" > "$OUT.log" 2>&1
grep -i -E "exception|error" "$OUT.log" | head -5
"$PY" -I "$ROOT/tools/modcov.py" "$OUT.ghidra.reached" > "$OUT"
head -1 "$OUT.ghidra"; head -1 "$OUT"; tail -1 "$OUT"
