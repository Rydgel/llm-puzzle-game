#!/bin/sh
# Painted signs for the walls and floors, as white text on transparent PNGs in game/decals/. Godot projects
# them as decals and tints them. Set in Noto Sans (SIL Open Font License), installed with the system.
#
#     sh art/decals.sh
set -e
cd "$(dirname "$0")/../game/decals"
BLACK=/usr/share/fonts/noto/NotoSans-Black.ttf
BOLD=/usr/share/fonts/noto/NotoSans-Bold.ttf

sign() {  # name width height font size text
	magick -size "$2x$3" xc:none -font "$4" -pointsize "$5" -fill white -gravity center -annotate +0+0 "$6" "$1.png"
}

sign chamber 1024 768 "$BLACK" 640 "04"
sign sublevel 2048 192 "$BOLD" 120 "SUBLEVEL NINE  ·  TEST CHAMBER 04"
sign caution 2048 256 "$BLACK" 170 "CAUTION  ·  ACID"
sign core 2048 192 "$BOLD" 120 "VESPER CORE  ·  STAFF ONLY"
sign w7 1024 512 "$BLACK" 360 "W-7"
ls -la
