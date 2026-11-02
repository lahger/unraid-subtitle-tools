#!/bin/sh
set -u
# Adjust Subtitle Edit's Settings.json for running in the container:
#  - let the window manager keep the main window maximized
#  - point save/output folders at OUTPUT_DIR (the open dialog starts in INPUT_DIR,
#    see /startapp.sh). Set DEFAULT_FOLDERS=0 to manage folders in the app instead.

INPUT_DIR="${INPUT_DIR:-/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
SETTINGS="/config/xdg/config/Subtitle Edit/Settings.json"

mkdir -p "$(dirname "$SETTINGS")"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"

FILTER='.General.RememberPositionAndSize = false | .General.WindowPositions = []'
if [ "${DEFAULT_FOLDERS:-1}" = "1" ]; then
    FILTER="$FILTER"'
  | .General.DefaultSaveLocation = "CustomFolder"
  | .General.DefaultSaveLocationCustomFolder = $out
  | .Tools.BatchConvert.OutputFolder = $out
  | .Tools.BatchConvert.SaveInSourceFolder = false
  | .Tools.SplitOutputFolder = $out
  | .Video.BurnIn.UseOutputFolder = true
  | .Video.BurnIn.OutputFolder = $out
  | .Video.Transparent.UseOutputFolder = true
  | .Video.Transparent.OutputFolder = $out
  | .Video.TextToSpeech.GenerationFolder = $out'
    echo "[subtitleedit] Open folder: ${INPUT_DIR}, output folder: ${OUTPUT_DIR}"
else
    echo "[subtitleedit] DEFAULT_FOLDERS=${DEFAULT_FOLDERS}, leaving folder settings alone."
fi

tmp="$(mktemp)"
if jq --arg out "$OUTPUT_DIR" "$FILTER" "$SETTINGS" > "$tmp"; then
    cat "$tmp" > "$SETTINGS"
else
    echo "[subtitleedit] Could not update $SETTINGS (invalid JSON?), skipping."
fi
rm -f "$tmp"
chown -R "${USER_ID:-1000}:${GROUP_ID:-1000}" "/config/xdg/config/Subtitle Edit"
