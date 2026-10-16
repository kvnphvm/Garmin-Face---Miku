#!/bin/bash
# Compile the watch face.
#
#   tools/build.sh            build for the simulator and launch it
#   tools/build.sh --device   build a signed release for sideloading
#
# Use the SDK the Connect IQ SDK Manager installed rather than anything on
# PATH: a Homebrew-relocated copy loses the files the simulator looks for
# beside its own app bundle and refuses to start.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="fenix8solar47mm"
KEY="$PROJECT/../developer_key.der"
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
SDK="${SDK%/}"

export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"

if [ ! -f "$KEY" ]; then
    echo "Developer key not found at $KEY" >&2
    echo "Generate one with: openssl genrsa -out /tmp/k.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/k.pem -out '$KEY' -nocrypt" >&2
    exit 1
fi

RELEASE=0
[ "${1:-}" = "--device" ] && RELEASE=1

mkdir -p "$PROJECT/bin"
cd "$PROJECT"

if [ "$RELEASE" = "1" ]; then
    # -r strips debug symbols and enables the optimiser, which is what the
    # watch should run; the simulator wants the debug build so it can report
    # line numbers when something throws.
    "$SDK/bin/monkeyc" -o bin/MikuFace.prg -f monkey.jungle -y "$KEY" -d "$DEVICE" -r -w
    echo "Release build at bin/MikuFace.prg — copy it to GARMIN/APPS on the watch."
    exit 0
fi

"$SDK/bin/monkeyc" -o bin/MikuFace.prg -f monkey.jungle -y "$KEY" -d "$DEVICE" -w

if ! pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" > /dev/null; then
    "$SDK/bin/connectiq" &
    sleep 12
fi

"$SDK/bin/monkeydo" bin/MikuFace.prg "$DEVICE"
