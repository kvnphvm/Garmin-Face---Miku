#!/bin/bash
# Grab the watch screen out of a running Connect IQ simulator.
#
# The simulator has no screenshot command and its window often sits on another
# Space, so this captures by CGWindowID (which works even when the window is
# occluded) and then crops the device screen out of the bezel artwork using the
# offsets the device profile declares.
#
# Writes build/sim_screen.png (1:1) and build/sim_screen_2x.png (magnified).
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-fenix8solar47mm}"
PROFILE="$HOME/Library/Application Support/Garmin/ConnectIQ/Devices/$DEVICE"
mkdir -p "$PROJECT/build"

LISTER="$(mktemp -t winlist).swift"
cat > "$LISTER" <<'SWIFT'
import CoreGraphics
import Foundation
let opts = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    // Once a device is loaded the title gains a suffix, e.g.
    // "CIQ Simulator - fenix 8 Solar 47mm (6.0.2)".
    for w in list where (w[kCGWindowName as String] as? String)?.hasPrefix("CIQ Simulator") == true {
        print(w[kCGWindowNumber as String] as? Int ?? -1)
    }
}
SWIFT

WINDOW_ID="$(swift "$LISTER" | head -1)"
rm -f "$LISTER"

if [ -z "$WINDOW_ID" ] || [ "$WINDOW_ID" = "-1" ]; then
    echo "No CIQ Simulator window found. Start the simulator first." >&2
    exit 1
fi

screencapture -x -o -l "$WINDOW_ID" "$PROJECT/build/sim_window.png"

PROFILE="$PROFILE" PROJECT="$PROJECT" python3 <<'PY'
import json
import os
from PIL import Image

project = os.environ["PROJECT"]
profile = os.environ["PROFILE"]

with open(os.path.join(profile, "simulator.json")) as handle:
    location = json.load(handle)["display"]["location"]

bezel = Image.open(os.path.join(profile, os.path.basename(profile) + ".png"))
window = Image.open(os.path.join(project, "build", "sim_window.png"))

# The bezel artwork is drawn at the window's full width, so the leftover height
# is window chrome: a title bar above and a status bar below, in equal measure.
# The extra pixel on each axis is the window's own border, measured by drawing
# a bitmap at a known coordinate and finding where it landed.
scale = window.width // bezel.width
chrome = (window.height // scale - bezel.height) // 2
border = 1

x = (location["x"] + border) * scale
y = (location["y"] + chrome + border) * scale
w = location["width"] * scale
h = location["height"] * scale

screen = window.crop((x, y, x + w, y + h))
screen.resize((location["width"], location["height"]), Image.LANCZOS).save(
    os.path.join(project, "build", "sim_screen.png")
)
screen.save(os.path.join(project, "build", "sim_screen_2x.png"))
print("captured %dx%d watch screen" % (location["width"], location["height"]))
PY
