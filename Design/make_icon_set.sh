#!/bin/bash
# Regenerate the macOS app icon set from the master image, using macOS's built-in `sips`
# (nothing to install).
#
# Master: Design/AppIcon-1024.png, 1024x1024 with transparent corners. The rounded tile is
# 824x824, centred, leaving a 100 px margin (the macOS icon grid).
#
# Usage:  ./Design/make_icon_set.sh
set -euo pipefail
cd "$(dirname "$0")"

MASTER="AppIcon-1024.png"
SET="../Sources/Detour/Assets.xcassets/AppIcon.appiconset"

[ -f "$MASTER" ] || { echo "Missing Design/$MASTER"; exit 1; }
dims=$(sips -g pixelWidth -g pixelHeight "$MASTER" | awk '/pixel/{print $2}' | sort -u)
[ "$dims" = "1024" ] || { echo "$MASTER must be exactly 1024 x 1024 px"; exit 1; }
sips -g hasAlpha "$MASTER" | grep -q "yes" || echo "Warning: $MASTER has no transparency; the corners will be opaque."

mkdir -p "$SET"
# file name : pixel size   (Contents.json in the icon set already maps these names)
for entry in \
  icon_16x16.png:16      icon_16x16@2x.png:32 \
  icon_32x32.png:32      icon_32x32@2x.png:64 \
  icon_128x128.png:128   icon_128x128@2x.png:256 \
  icon_256x256.png:256   icon_256x256@2x.png:512 \
  icon_512x512.png:512
do
  name="${entry%%:*}"; px="${entry##*:}"
  sips -z "$px" "$px" "$MASTER" --out "$SET/$name" >/dev/null
done
cp "$MASTER" "$SET/icon_512x512@2x.png"

echo "Wrote 10 icons to Sources/Detour/Assets.xcassets/AppIcon.appiconset"
