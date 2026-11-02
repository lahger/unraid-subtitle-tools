#!/bin/bash
# Watch WATCH_DIR for finished .mkv rips and, for each one:
#   1. pick tracks: all video, the first audio track + any AUDIO_LANGS audio,
#      and per SUB_LANGS language the first full and first forced image subtitle
#   2. extract those subtitles (one read of the file) and OCR them to SRT with seconv
#   3. remux video + chosen audio + new SRTs (+ the original image subs if KEEP_PGS=1)
#      into OUTPUT_DIR, keeping the source's sub-folder
#   4. move the source to WATCH_DIR/done (or WATCH_DIR/failed with a log)
set -uo pipefail

WATCH="${WATCH_DIR:-/watch}"
OUT="${OUTPUT_DIR:-/output}"
DONE="${DONE_DIR:-$WATCH/done}"
FAILED="${FAILED_DIR:-$WATCH/failed}"
WORK="$OUT/.autosub-work"
DICT=/opt/dictionaries

SUB_LANGS="${SUB_LANGS:-eng,swe}"
AUDIO_LANGS="${AUDIO_LANGS:-swe}"
DEFAULT_SUB_LANG="${DEFAULT_SUB_LANG:-eng}"
KEEP_PGS="${KEEP_PGS:-1}"
OCR_ENGINE="${OCR_ENGINE:-ollama}"
OCR_FALLBACK="${OCR_FALLBACK-tesseract}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5vl:7b}"
STABLE_MINUTES="${STABLE_MINUTES:-5}"
# Added before .mkv in the output name: "Movie_t00.mkv" -> "Movie_t00-REMUX.mkv". Empty = same name.
OUTPUT_SUFFIX="${OUTPUT_SUFFIX--REMUX}"
SCAN_INTERVAL="${SCAN_INTERVAL:-60}"
# Fix-common-errors rules; the excluded ones would join the disc's two-line subtitles.
FCE_RULES="${FCE_RULES:-all,-FixShortLines,-FixShortLinesAll,-FixShortLinesPixelWidth}"

log() { echo "[$(date '+%F %T')] $*"; }

# Matroska uses ISO 639-2/B codes; map the common ones to a name (Ollama prompt,
# Fix-common-errors language) and to Tesseract's 639-2/T traineddata name.
lang_name() {
    case "$1" in
        eng) echo English ;;   swe) echo Swedish ;;   nor|nob|nno) echo Norwegian ;;
        dan) echo Danish ;;    fin) echo Finnish ;;   ger|deu) echo German ;;
        fre|fra) echo French ;; spa) echo Spanish ;;  ita) echo Italian ;;
        dut|nld) echo Dutch ;;  por) echo Portuguese ;; pol) echo Polish ;;
        *) echo "$1" ;;
    esac
}
tess_lang() {
    case "$1" in
        ger) echo deu ;; fre) echo fra ;; dut) echo nld ;; cze) echo ces ;;
        nor|nob) echo nor ;; *) echo "$1" ;;
    esac
}

# ocr <engine> <input.sup> <lang> <output.srt>
ocr() {
    local engine="$1" sup="$2" lang="$3" srt="$4" name
    name="$(lang_name "$lang")"
    local args=("$sup" subrip
        --output-folder:"$(dirname "$srt")" --output-filename:"$(basename "$srt")" --overwrite
        --fix-common-errors-rules:"$FCE_RULES" --fce-language:"$name" --dictionary-folder:"$DICT" --quiet)
    case "$engine" in
        ollama)    args+=(--ocr-engine:ollama --ollama-url:"${OLLAMA_URL%/}/api/chat"
                          --ollama-model:"$OLLAMA_MODEL" --ocr-language:"$name") ;;
        tesseract) args+=(--ocr-engine:tesseract --ocr-language:"$(tess_lang "$lang")") ;;
        *)         args+=(--ocr-engine:"$engine" --ocr-language:"$(tess_lang "$lang")") ;;
    esac
    rm -f "$srt"
    seconv "${args[@]}" </dev/null || return 1
    # Accept only a non-empty result with real text in it.
    [ -s "$srt" ] && grep -q -- '-->' "$srt" && [ "$(grep -cvE '^\s*$|-->|^[0-9]+\s*$' "$srt")" -gt 0 ]
}

ollama_ready() {
    local tags
    if ! tags="$(curl -fsS -m 10 "${OLLAMA_URL%/}/api/tags" 2>&1)"; then
        log "Ollama not reachable at $OLLAMA_URL ($tags)"
        return 1
    fi
    # "qwen2.5vl:7b" or "name" (= name:latest)
    if ! jq -e --arg m "$OLLAMA_MODEL" \
         '.models[].name | select(. == $m or . == ($m + ":latest"))' <<<"$tags" >/dev/null; then
        log "Ollama model '$OLLAMA_MODEL' is not pulled (run: ollama pull $OLLAMA_MODEL)"
        return 1
    fi
}

process() {
    local src="$1" rel job json
    rel="${src#"$WATCH"/}"
    job="$WORK/job"
    rm -rf "$job" && mkdir -p "$job" || return 1

    json="$(mkvmerge -J "$src")" || { log "mkvmerge could not read the file"; return 1; }

    local video_ids audio_ids
    video_ids="$(jq -r '[.tracks[] | select(.type=="video") | .id] | join(",")' <<<"$json")"
    audio_ids="$(jq -r --arg langs "$AUDIO_LANGS" '
        ($langs | split(",")) as $want
        | [.tracks[] | select(.type=="audio")] as $a
        | ([$a[0].id] + [$a[] | select(.properties.language as $l | $want | index($l)) | .id])
        | map(select(. != null)) | unique | join(",")' <<<"$json")"
    log "video tracks: ${video_ids:-none}, audio tracks kept: ${audio_ids:-none}"

    # Selected image subtitles as lines: id<TAB>lang<TAB>forced(0/1)
    local subs
    subs="$(jq -r --arg langs "$SUB_LANGS" '
        ($langs | split(",")) as $want
        | [.tracks[] | select(.type=="subtitles"
                              and (.properties.codec_id == "S_HDMV/PGS" or .properties.codec_id == "S_VOBSUB"))] as $s
        | $want[] as $lang
        | ([$s[] | select(.properties.language == $lang and (.properties.forced_track | not))][0],
           [$s[] | select(.properties.language == $lang and .properties.forced_track)][0])
        | select(. != null)
        | "\(.id)\t\($lang)\t\(if .properties.forced_track then 1 else 0 end)"' <<<"$json")"

    if [ -z "$subs" ]; then
        log "no $SUB_LANGS image subtitles found; remuxing audio/video only"
    fi

    # Extract all chosen subtitle tracks in one pass over the file.
    local extract=() id lang forced
    while IFS=$'\t' read -r id lang forced; do
        [ -n "$id" ] && extract+=("$id:$job/$id.sup")
    done <<<"$subs"
    if [ ${#extract[@]} -gt 0 ]; then
        log "extracting subtitle tracks: ${extract[*]##*/}"
        mkvextract "$src" tracks "${extract[@]}" >/dev/null || { log "mkvextract failed"; return 1; }
    fi

    # OCR each one. Check Ollama once up front instead of timing out on every track.
    local engine="$OCR_ENGINE"
    if [ "$engine" = ollama ] && [ ${#extract[@]} -gt 0 ] && ! ollama_ready; then
        [ -n "$OCR_FALLBACK" ] || return 1
        engine="$OCR_FALLBACK"
        log "using $engine for this file instead"
    fi
    local srt_files=() srt_langs=() srt_forced=()
    while IFS=$'\t' read -r id lang forced; do
        [ -n "$id" ] || continue
        local srt="$job/$id.$lang.srt"
        log "OCR track $id ($lang$([ "$forced" = 1 ] && echo ', forced')) with $engine"
        if ! ocr "$engine" "$job/$id.sup" "$lang" "$srt"; then
            if [ -n "$OCR_FALLBACK" ] && [ "$OCR_FALLBACK" != "$engine" ]; then
                log "$engine failed, retrying track $id with $OCR_FALLBACK"
                ocr "$OCR_FALLBACK" "$job/$id.sup" "$lang" "$srt" || { log "OCR failed for track $id"; return 1; }
            else
                log "OCR failed for track $id"; return 1
            fi
        fi
        log "track $id: $(grep -c -- '-->' "$srt") subtitles"
        srt_files+=("$srt"); srt_langs+=("$lang"); srt_forced+=("$forced")
    done <<<"$subs"

    # Remux. Order: video, audio, new SRTs, then the original image subs.
    local dest="$OUT/${rel%.*}${OUTPUT_SUFFIX}.mkv" partial
    partial="${dest%.mkv}.partial.mkv"
    mkdir -p "$(dirname "$dest")" || return 1
    if [ -e "$dest" ]; then log "output already exists: $dest"; return 1; fi

    local args=(-o "$partial") order=() t
    [ -n "$audio_ids" ] && args+=(-a "$audio_ids") || args+=(-A)
    if [ "$KEEP_PGS" = 1 ] && [ ${#extract[@]} -gt 0 ]; then
        local pgs_ids
        pgs_ids="$(cut -f1 <<<"$subs" | paste -sd, -)"
        args+=(-s "$pgs_ids")
        while IFS=$'\t' read -r id lang forced; do
            args+=(--default-track-flag "$id:0"
                   --track-name "$id:$(lang_name "$lang")$([ "$forced" = 1 ] && echo ' Forced') (PGS)")
        done <<<"$subs"
    else
        args+=(-S)
    fi
    args+=("$src")
    for t in ${video_ids//,/ }; do order+=("0:$t"); done
    for t in ${audio_ids//,/ }; do order+=("0:$t"); done

    local i default
    for i in "${!srt_files[@]}"; do
        lang="${srt_langs[$i]}"; forced="${srt_forced[$i]}"
        default=0
        [ "$lang" = "$DEFAULT_SUB_LANG" ] && [ "$forced" = 0 ] && default=1
        args+=(--language "0:$lang" --default-track-flag "0:$default" --forced-display-flag "0:$forced"
               --track-name "0:$(lang_name "$lang")$([ "$forced" = 1 ] && echo ' Forced')"
               "${srt_files[$i]}")
        order+=("$((i + 1)):0")
    done
    if [ "$KEEP_PGS" = 1 ]; then
        while IFS=$'\t' read -r id lang forced; do [ -n "$id" ] && order+=("0:$id"); done <<<"$subs"
    fi
    args+=(--track-order "$(IFS=,; echo "${order[*]}")")

    log "muxing to $dest"
    mkvmerge "${args[@]}" >/dev/null
    local rc=$?
    # mkvmerge: 0 = ok, 1 = ok with warnings, 2 = error
    if [ $rc -ge 2 ]; then rm -f "$partial"; log "mkvmerge failed"; return 1; fi
    mv "$partial" "$dest" || return 1
    rm -rf "$job"
}

move_to() {
    local src="$1" base="$2" rel="${1#"$WATCH"/}"
    mkdir -p "$base/$(dirname "$rel")" && mv "$src" "$base/$rel"
    # Remove the rip's now-empty folder (never WATCH itself).
    local dir; dir="$(dirname "$src")"
    [ "$dir" != "$WATCH" ] && rmdir "$dir" 2>/dev/null
    return 0
}

log "mkv-autosub watching $WATCH -> $OUT (subs: $SUB_LANGS, extra audio: $AUDIO_LANGS, OCR: $OCR_ENGINE, fallback: ${OCR_FALLBACK:-none})"
[ "$OCR_ENGINE" = ollama ] && log "Ollama: $OLLAMA_URL, model $OLLAMA_MODEL"
if ! mkdir -p "$DONE" "$FAILED" "$WORK"; then
    log "ERROR: can't write to $WATCH or $OUT as $(id -u):$(id -g). Fix the folder owner on the host:"
    log "       chown $(id -u):$(id -g) <host folder>"
    exit 1
fi

while true; do
    find "$WATCH" \( -path "$DONE" -o -path "$FAILED" \) -prune -o \
         -type f -iname '*.mkv' ! -iname '*.partial.mkv' -mmin +"$STABLE_MINUTES" -print 2>/dev/null \
        | sort | while IFS= read -r f; do
        rel="${f#"$WATCH"/}"
        logfile="$WORK/current.log"
        log "=== $rel"
        if process "$f" </dev/null 2>&1 | tee "$logfile"; [ "${PIPESTATUS[0]}" -eq 0 ]; then
            move_to "$f" "$DONE"
            log "=== done: $rel"
        else
            move_to "$f" "$FAILED"
            cp "$logfile" "$FAILED/${rel%.mkv}.log" 2>/dev/null
            log "=== FAILED: $rel (moved to failed/, see the .log next to it)"
        fi
    done
    sleep "$SCAN_INTERVAL"
done
