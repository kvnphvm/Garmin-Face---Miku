#!/bin/bash
# Rebuild Miku's idle animation resource from the source GIF.
#
# generate_miku.py writes build/miku-idle.gif already mapped into the display's
# palette; this hands that to Monkey Motion, which produces one .mm per target
# resolution plus a manifest keyed by device part number. Monkey Motion writes
# into a directory named after the output file, so the results are flattened
# back into resources/animations/ where the resource compiler expects them.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PROJECT/resources/animations"
RESOURCE_ID="MikuIdle"

SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
SDK="${SDK%/}"
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"

python3 "$PROJECT/tools/generate_miku.py"

SIZE="$(python3 -c "
from PIL import Image
im = Image.open('$PROJECT/build/miku-idle.gif')
print('%dx%d' % im.size)
")"

rm -rf "${OUT:?}"/*.mm "$OUT"/*.mmm "$OUT"/animations.xml
mkdir -p "$OUT"

# Color depth 2 matches the panel's ARGB2222 pixel format, and 10 fps is both
# the source's rate and Monkey Motion's ceiling.
java -cp "$SDK/bin/MonkeyMotion.app/Contents/Resources/monkeybrains.jar" \
    com.garmin.monkeybrains.monkeymotion.MonkeyMotion \
    --video "$PROJECT/build/miku-idle.gif" \
    --manifest "$PROJECT/manifest.xml" \
    --output "$OUT/miku-idle.mm" \
    --exportResource "$RESOURCE_ID" \
    --resolution "$SIZE" \
    --frameRate 10 \
    --colorDepth 2 \
    --warn

mv "$OUT/miku-idle.mm/miku-idle.xml" "$OUT/animations.xml"
mv "$OUT"/miku-idle.mm/* "$OUT/"
rmdir "$OUT/miku-idle.mm"

echo "animation resource $RESOURCE_ID at $SIZE:"
ls -1 "$OUT"
