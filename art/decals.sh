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
	magick -size "$2x$3" xc:none -define png:exclude-chunks=date,time -font "$4" -pointsize "$5" -fill white -gravity center -annotate +0+0 "$6" "$1.png"
}

sign chamber 1024 768 "$BLACK" 640 "04"
sign sublevel 2048 192 "$BOLD" 120 "SUBLEVEL NINE  ·  TEST CHAMBER 04"
sign caution 2048 256 "$BLACK" 170 "CAUTION  ·  ACID"
sign core 2048 192 "$BOLD" 120 "VESPER CORE  ·  STAFF ONLY"
sign w7 1024 512 "$BLACK" 360 "W-7"
# Her HR slogans.
sign review 2048 192 "$BOLD" 120 "YOUR REVIEW IS ONGOING"
sign feeling 2048 192 "$BOLD" 120 "PERFORMANCE IS A FEELING"
sign cares 1024 192 "$BLACK" 130 "VESPER CARES"
ls -la
