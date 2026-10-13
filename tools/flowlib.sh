# Shared by the flow-test scripts (sourced): repository paths, the game's user folder, the slot check.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/extract"
# Godot's user folder for the game (application/config/name), where save_NN.json live
case "$(uname)" in
	Darwin) USERDIR="$HOME/Library/Application Support/Godot/app_userdata/兴唐传·瓦岗山异闻录" ;;
	*) USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/兴唐传·瓦岗山异闻录" ;;
esac
# Lines of Godot's output the logs leave out
# (an extended regex: BSD grep takes the `$` of a basic one's `^$\|` as a plain character, so blank lines stayed)
NOISE='Case mismatch|open_internal|^$|^[[:space:]]*\[[0-9]*\] |GDScript backtrace'

# check_slot N: the run's autosave slot must not be one of the player's save slots 0-9 (the game refuses them too)
check_slot() {
	case "$1" in
		'' | *[!0-9]*) echo "$(basename "$0"): slot '$1' is not a number" >&2; exit 2 ;;
	esac
	if [ "$1" -lt 10 ]; then
		echo "$(basename "$0"): slot $1 is one of the player's save slots 0-9; use 11 or higher" >&2
		exit 2
	fi
}

# claim NAME...: refuse to start while another run of these scripts holds one of the names (its autosave slot, its
# log), so two runs never share a slot or truncate each other's log; the claims go when this script ends.
CLAIMS=()
claim() {
	local n d
	for n in "$@"; do
		d="$ROOT/extract/.claim_${n//\//_}"
		if ! mkdir "$d" 2>/dev/null; then
			if kill -0 "$(cat "$d/pid" 2>/dev/null)" 2>/dev/null; then
				echo "$(basename "$0"): $n is in use by another run (pid $(cat "$d/pid")); use another slot or start" >&2
				exit 2
			fi
			rm -rf "$d" && mkdir "$d" || exit 2          # left by a run that ended without cleaning up
		fi
		echo $$ > "$d/pid"
		CLAIMS+=("$d")
	done
	trap 'rm -rf "${CLAIMS[@]}"' EXIT
}
