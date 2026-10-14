#!/usr/bin/env bash
#
# Generates the Android launcher icon set from a source illustration.
#
# The source art is a full illustration, not a mark, so the crop is tuned to the
# character's head: an adaptive icon only ever shows the central 66% of its
# 108dp canvas (the "safe zone"), so art that is not pre-cropped loses its
# subject to the launcher's mask.
#
# Outputs:
#   mipmap-*/ic_launcher.png             legacy square
#   mipmap-*/ic_launcher_round.png       legacy round
#   mipmap-*/ic_launcher_background.png  adaptive background layer (full bleed)
#   mipmap-*/ic_launcher_monochrome.png  Android 13+ themed layer
#   mipmap-anydpi-v26/ic_launcher*.xml   adaptive icon definitions
#   drawable/ic_launcher_foreground.xml  transparent foreground layer
#   assets/icon/icon.png                 in-app logo for the About screen
#
# Usage: generate_icons.sh <source.png> <repo-root>
#
set -euo pipefail

SRC="${1:?source image required}"
ROOT="${2:?repo root required}"

[[ -f "$SRC" ]] || { echo "no such file: $SRC" >&2; exit 1; }
command -v magick >/dev/null || { echo "imagemagick (magick) required" >&2; exit 1; }

RES="$ROOT/android/app/src/main/res"

# Crop window onto the subject, in source pixels, tuned by inspecting the
# rendered result at launcher size.
CROP="860x860+190+60"

DENSITIES=(mdpi hdpi xhdpi xxhdpi xxxhdpi)
LEGACY=(48 72 96 144 192)
ADAPTIVE=(108 162 216 324 432)

echo "==> cropping subject"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
magick "$SRC" -crop "$CROP" +repage -resize 1080x1080 "$TMP/art.png"

echo "==> raster layers"
for i in "${!DENSITIES[@]}"; do
  d="${DENSITIES[$i]}"; L="${LEGACY[$i]}"; A="${ADAPTIVE[$i]}"
  mkdir -p "$RES/mipmap-$d"

  magick "$TMP/art.png" -resize "${L}x${L}^" -gravity center -extent "${L}x${L}" \
    -strip "$RES/mipmap-$d/ic_launcher.png"

  magick "$TMP/art.png" -resize "${L}x${L}^" -gravity center -extent "${L}x${L}" \
    \( +clone -alpha extract -fill black -colorize 100 \
       -fill white -draw "circle $((L/2)),$((L/2)) $((L/2)),0" \) \
    -alpha off -compose CopyOpacity -composite -strip \
    "$RES/mipmap-$d/ic_launcher_round.png"

  magick "$TMP/art.png" -resize "${A}x${A}^" -gravity center -extent "${A}x${A}" \
    -strip "$RES/mipmap-$d/ic_launcher_background.png"

  # The themed layer must be an ALPHA MASK, not a coloured shape.
  #
  # Android tints this layer itself, using only its opacity. A coloured or
  # thresholded image therefore renders as a solid blob in the system's chosen
  # colour, which is what a naive `-colorspace gray -black-threshold` produced.
  # What the system wants is a recognisable silhouette drawn in white on
  # transparency, so it is built from the subject's own alpha after a circular
  # crop — the same shape the launcher's mask reveals.
  magick "$TMP/art.png" -resize "${A}x${A}^" -gravity center -extent "${A}x${A}" \
    \( +clone -alpha extract -fill black -colorize 100 \
       -fill white -draw "circle $((A/2)),$((A/2)) $((A/2)),0" \) \
    -alpha off -compose CopyOpacity -composite \
    -fill white -colorize 100 \
    -strip "$RES/mipmap-$d/ic_launcher_monochrome.png"
done

echo "==> adaptive icon definitions"
mkdir -p "$RES/mipmap-anydpi-v26" "$RES/drawable"

cat > "$RES/drawable/ic_launcher_foreground.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!--
  The launcher artwork is carried by the adaptive background layer, which is a
  full-bleed raster. This foreground layer exists because <adaptive-icon>
  requires one; it is deliberately empty so nothing is drawn over the art.
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108" />
XML

cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML

cp "$RES/mipmap-anydpi-v26/ic_launcher.xml" \
   "$RES/mipmap-anydpi-v26/ic_launcher_round.xml"

echo "==> in-app logo"
mkdir -p "$ROOT/assets/icon"
magick "$TMP/art.png" -resize 512x512 -strip "$ROOT/assets/icon/icon.png"

echo "ICONS_DONE"
