#!/bin/sh
# The App Store screenshots, as recipes. shots-appstore builds the app for the
# simulator, boots each simulator ship.toml names, installs the app (the
# embedded watch app on a watch), and calls this with the simulator, the
# language and where the frames go; this file is the half that is Blick's:
# which screens, in which state, from the demo data the Debug build carries.
#
#     ./packaging/ios/shots.sh --app <Blick.app> --device <udid> --lang en-us --outdir <dir>
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

set -eu

app= device= lang= outdir=
while [ $# -gt 0 ]; do
    case "$1" in
        --app) app=$2; shift 2 ;;
        --device) device=$2; shift 2 ;;
        --lang) lang=$2; shift 2 ;;
        --outdir) outdir=$2; shift 2 ;;
        *) echo "shots.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done
[ -n "$app" ] && [ -n "$device" ] && [ -n "$lang" ] && [ -n "$outdir" ] || { echo "shots.sh: --app, --device, --lang and --outdir are all required" >&2; exit 2; }

case "$lang" in
    en|en-us|en-US) languages='(en)'; locale=en_US ;;
    *) echo "shots.sh: no set is written for $lang" >&2; exit 2 ;;
esac

# A watch simulator runs the embedded watch app, with its own bundle id.
case "$(xcrun simctl list devices | grep -F "($device)" | head -1)" in
    *Watch*) bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app"/Watch/*.app/Info.plist); watch=1 ;;
    *) bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist"); watch=0 ;;
esac
mkdir -p "$outdir"

settle=10

shot() {
    name=$1
    shift
    xcrun simctl launch --terminate-running-process "$device" "$bundle" \
        -AppleLanguages "$languages" -AppleLocale "$locale" --demo "$@" >/dev/null
    sleep "$settle"
    xcrun simctl io "$device" screenshot --type=png "$outdir/$name.png" >/dev/null
    echo "$name"
}

if [ "$watch" = 1 ]; then
    shot 01-glance
else
    shot 01-today
    shot 02-email --demo-email-list
fi

xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true
