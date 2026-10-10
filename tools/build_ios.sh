#!/bin/bash
# Build the iPhone app from game/ (Godot iOS export → Xcode project → xcodebuild) and optionally install it.
#
#   tools/build_ios.sh                  signed app (development) in build/ios_sym/Release-iphoneos/WaGang.app
#   tools/build_ios.sh --device [UDID]  ... then install and launch it on a connected iPhone (default: the first
#                                       reachable one with Developer Mode on); Xcode registers the device if needed
#   tools/build_ios.sh --unsigned       unsigned build/WaGang-iOS.ipa for sideloading (what the release workflow ships)
#
# Needs Xcode, Godot 4.7.2 (GODOT=path overrides `godot`) with its iOS export template (ios.zip, see
# docs/BUILDING.md) and the HD pack in game/assets_hd (the iOS preset leaves the original pictures out).
# Signing is automatic with the team in the iOS preset (TEAM=… overrides). IOS_ENV='{"WG_…":"…"}' passes
# environment variables to the launched app (debug switches, see docs/DEVELOPMENT.md).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-godot}"
mode="signed"
udid=""
case "${1:-}" in
  --device) mode="device"; udid="${2:-}" ;;
  --unsigned) mode="unsigned" ;;
  "") ;;
  *) sed -n '2,14p' "$0"; exit 2 ;;
esac

preset_value() {   # option of the iOS preset in export_presets.cfg
  awk -v key="$1" '/^\[preset\./ { ios = 0 } /^name="iOS"/ { ios = 1 } /^\[preset\.[0-9]+\.options\]/ { opts = ios }
    opts && index($0, key "=") == 1 { sub(/^[^=]*="?/, ""); sub(/"$/, ""); print; exit }' "$root/game/export_presets.cfg"
}
bundle_id="$(preset_value application/bundle_identifier)"
team="${TEAM:-$(preset_value application/app_store_team_id)}"

if [ ! -d "$root/game/assets_hd/gfx" ]; then
  echo "game/assets_hd is missing: the iOS build ships the HD pack only (see docs/HD_GRAPHICS.md)" >&2
  exit 1
fi
ver="$("$godot" --version | cut -d. -f1-3)"
tpl="$HOME/Library/Application Support/Godot/export_templates/${ver}.stable/ios.zip"
if [ ! -f "$tpl" ]; then
  echo "no iOS export template at $tpl (see docs/BUILDING.md)" >&2
  exit 1
fi

if [ "$mode" = "device" ] && [ -z "$udid" ]; then
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" > /dev/null
  udid="$(python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, cp, dp = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if (hw.get("reality") == "physical" and hw.get("deviceType") == "iPhone" and cp.get("pairingState") == "paired"
            and cp.get("tunnelState") != "unavailable" and dp.get("developerModeStatus") == "enabled"):
        print(hw["udid"]); break' "$json")"
  rm -f "$json"
  if [ -z "$udid" ]; then
    echo "no reachable iPhone: connect and unlock it (Developer Mode on), or pass its UDID" >&2
    xcrun devicectl list devices >&2
    exit 1
  fi
fi

echo "== exporting the Xcode project"
rm -rf "$root/build/ios"
mkdir -p "$root/build/ios"
(cd "$root/game" && "$godot" --headless --path . --export-release "iOS" ../build/ios/WaGang.ipa) > "$root/build/ios_export.log" 2>&1 \
  || { tail -30 "$root/build/ios_export.log"; exit 1; }
test -s "$root/build/ios/WaGang.pck" && test -d "$root/build/ios/WaGang.xcodeproj"

echo "== building ($mode)"
sym="$root/build/ios_sym"
common=(-project "$root/build/ios/WaGang.xcodeproj" -scheme WaGang -configuration Release -sdk iphoneos
  -derivedDataPath "$root/build/ios_dd" SYMROOT="$sym")
if [ "$mode" = "unsigned" ]; then
  xcodebuild "${common[@]}" -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build > "$root/build/ios_build.log" 2>&1 \
    || { grep -E "error:" "$root/build/ios_build.log" | head -20; exit 1; }
else
  dest="generic/platform=iOS"
  [ -n "$udid" ] && dest="id=$udid"
  xcodebuild "${common[@]}" -destination "$dest" -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" \
    CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" build > "$root/build/ios_build.log" 2>&1 \
    || { grep -E "error:" "$root/build/ios_build.log" | head -20; exit 1; }
fi
app="$sym/Release-iphoneos/WaGang.app"
test -f "$app/WaGang.pck"

if [ "$mode" = "unsigned" ]; then
  stage="$(mktemp -d)"
  mkdir "$stage/Payload"
  cp -R "$app" "$stage/Payload/"
  rm -f "$root/build/WaGang-iOS.ipa"
  (cd "$stage" && zip -q -r -y "$root/build/WaGang-iOS.ipa" Payload)
  rm -rf "$stage"
  echo "== $root/build/WaGang-iOS.ipa"
elif [ "$mode" = "device" ]; then
  echo "== installing on $udid"
  xcrun devicectl device install app --device "$udid" "$app"
  launch=(xcrun devicectl device process launch --device "$udid" --terminate-existing)
  [ -n "${IOS_ENV:-}" ] && launch+=(--environment-variables "$IOS_ENV")
  "${launch[@]}" "$bundle_id"
else
  echo "== $app"
fi
