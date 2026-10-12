# Shared by the flow-test scripts (sourced): repository paths, the game's user folder, the slot check.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/extract"
# Godot's user folder for the game (application/config/name), where save_NN.json live
case "$(uname)" in
	Darwin) USERDIR="$HOME/Library/Application Support/Godot/app_userdata/兴唐传·瓦岗山异闻录" ;;
	*) USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/兴唐传·瓦岗山异闻录" ;;
esac
# Lines of Godot's output the logs leave out
NOISE='Case mismatch\|open_internal\|^$\|^\s*\[[0-9]*\] \|GDScript backtrace'

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
