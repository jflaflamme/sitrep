#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build SITREP in release mode and copy it onto the USB-connected watch.
#
#   ./build.sh                 build, install if the watch is connected
#   ./build.sh --no-install    build only
#   DEVICE=fenix7x ./build.sh  another Connect IQ device id (default: fenix7x)
#
# Needs the Connect IQ SDK (its current-sdk.cfg) and a developer key, by default
# ~/.config/garmin-ciq/developer_key.der (override with KEY=...). The watch installs the
# face when it is unplugged: run tools/garmin-eject, unplug, then choose SITREP.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${DEVICE:-fenix7x}"   # tactix 7 Pro, part number 006-B4135-00, per the SDK device list
KEY="${KEY:-$HOME/.config/garmin-ciq/developer_key.der}"
SDK="$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")"
OUT=bin/SITREP.prg

# the version shown on the watch (strings.xml) must match the app version (manifest.xml)
app_version=$(sed -n 's/.* version="\([0-9.]*\)".*/\1/p' manifest.xml | tail -1)
shown_version=$(sed -n 's/.*id="AppVersion">\([^<]*\)<.*/\1/p' resources/strings/strings.xml)
if [ "$app_version" != "$shown_version" ]; then
    echo "version mismatch: manifest.xml $app_version, strings.xml AppVersion $shown_version" >&2
    exit 1
fi
echo "SITREP $app_version for $DEVICE"

mkdir -p bin
# -r: no debug info; -O 2z: fast code, then smallest size (faces run on tight memory)
"$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -y "$KEY" -o "$OUT" -r -O 2z -w
[ "${1:-}" = "--no-install" ] && exit 0

apps=$(ls -d /run/user/"$(id -u)"/gvfs/mtp:host=091e_*/*/GARMIN/Apps 2>/dev/null | head -1 || true)
if [ -z "$apps" ]; then
    uri=$(gio mount -li 2>/dev/null | grep -o 'activation_root=mtp://091e_[^ ]*' | head -1 | cut -d= -f2 || true)
    [ -n "$uri" ] && { gio mount "$uri" >/dev/null 2>&1 || true; }
    apps=$(ls -d /run/user/"$(id -u)"/gvfs/mtp:host=091e_*/*/GARMIN/Apps 2>/dev/null | head -1 || true)
fi
if [ -z "$apps" ]; then
    echo "watch not connected: built only ($OUT)"
    exit 0
fi
gio copy --backup=none "$OUT" "$(gio info "$apps" | sed -n 's/^uri: //p')/SITREP.prg"
[ "$(stat -c %s "$apps/SITREP.prg")" = "$(stat -c %s "$OUT")" ] || { echo "copy not verified; retry" >&2; exit 1; }
echo "installed SITREP.prg. Run tools/garmin-eject, unplug, then pick SITREP on the watch."
