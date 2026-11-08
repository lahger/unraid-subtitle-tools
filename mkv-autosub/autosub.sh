#!/bin/bash
# Watch WATCH_DIR for finished .mkv rips and, for each one:
#   1. pick tracks: all video, the first audio track + any AUDIO_LANGS audio,
#      and per SUB_LANGS language the first full and first forced image subtitle
#   2. extract those subtitles (one read of the file) and OCR them to SRT with seconv
#   3. remux video + chosen audio + new SRTs (+ the original image subs if KEEP_PGS=1)
#      into OUTPUT_DIR, keeping the source's sub-folder
#   4. remember the rip in CONFIG_DIR/processed.list (the watch folder is never written to);
#      on failure write <name>-FAILED.log where the output would have gone
set -uo pipefail

WATCH="${WATCH_DIR:-/watch}"
OUT="${OUTPUT_DIR:-/output}"
CONFIG="${CONFIG_DIR:-/config}"
WORK="$CONFIG/work"
# OCR fix lists and spell-check dictionaries, editable in appdata. Seeded from the image.
DICT="$CONFIG/dictionaries"
LOG="$CONFIG/autosub.log"
# Rips already handled, one "relative path|size" per line.
PROCESSED="$CONFIG/processed.list"

SUB_LANGS="${SUB_LANGS:-eng,swe}"
AUDIO_LANGS="${AUDIO_LANGS:-swe}"
DEFAULT_SUB_LANG="${DEFAULT_SUB_LANG:-eng}"
KEEP_PGS="${KEEP_PGS:-1}"
OCR_ENGINE="${OCR_ENGINE:-ollama}"
OCR_FALLBACK="${OCR_FALLBACK-tesseract}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5vl:7b}"
STABLE_MINUTES="${STABLE_MINUTES:-5}"
# What to do with the rip after a successful run: keep | delete
SOURCE_AFTER="${SOURCE_AFTER:-keep}"
# Added before .mkv in the output name: "Movie_t00.mkv" -> "Movie_t00-REMUX.mkv". Empty = same name.
OUTPUT_SUFFIX="${OUTPUT_SUFFIX--REMUX}"
SCAN_INTERVAL="${SCAN_INTERVAL:-60}"
# Fix-common-errors rules; the excluded ones would join the disc's two-line subtitles.
FCE_RULES="${FCE_RULES:-all,-FixShortLines,-FixShortLinesAll,-FixShortLinesPixelWidth}"
# Subtitle tracks that aren't tagged with a SUB_LANGS language:
#   all      = also take untagged tracks, and every track if none is tagged right (default)
#   detected = same, but keep only those whose text turns out to be a SUB_LANGS language
#   none     = only tracks tagged with a SUB_LANGS language
SUB_UNMATCHED="${SUB_UNMATCHED:-all}"
# Languages the quick detection pass can read (Tesseract packs installed in the image).
DETECT_LANGS="${DETECT_LANGS:-eng,swe,dan,nor,fin}"

log() { echo "[$(date '+%F %T')] $*"; }

if mkdir -p "$CONFIG" 2>/dev/null && touch "$LOG" 2>/dev/null; then
    [ "$(stat -c %s "$LOG")" -gt 10485760 ] && mv -f "$LOG" "$LOG.1"
    exec > >(tee -a "$LOG") 2>&1
fi

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
# Language detected from text (seconv info, ISO 639-1) -> Matroska code.
iso3() {
    case "$1" in
        en) echo eng ;; sv) echo swe ;; da) echo dan ;; no|nb|nn) echo nor ;; fi) echo fin ;;
        de) echo ger ;; fr) echo fre ;; es) echo spa ;; it) echo ita ;;  nl) echo dut ;;
        pt) echo por ;; pl) echo pol ;; is) echo ice ;; *) echo und ;;
    esac
}
in_list() { [[ ",$2," == *",$1,"* ]]; }   # in_list swe "eng,swe"
# "eng,swe" -> "eng+swe" (Tesseract) or "English or Swedish" (Ollama prompt)
tess_list() { local l out=(); for l in ${1//,/ }; do out+=("$(tess_lang "$l")"); done; (IFS=+; echo "${out[*]}"); }
name_list() { local l out=""; for l in ${1//,/ }; do out="${out:+$out or }$(lang_name "$l")"; done; echo "$out"; }

# detect_lang <input.sup> -> Matroska language code, or "und"
# Quick multi-language Tesseract pass; only used to read the language from the text.
detect_lang() {
    local sup="$1" dir code
    dir="$(dirname "$sup")"
    seconv "$sup" subrip --ocr-engine:tesseract --ocr-language:"$(tess_list "$DETECT_LANGS")" \
        --output-folder:"$dir" --output-filename:detect.srt --overwrite --quiet </dev/null >/dev/null 2>&1 \
        || { echo und; return; }
    code="$(seconv info "$dir/detect.srt" --json </dev/null 2>/dev/null | jq -r '.language // empty' 2>/dev/null)"
    rm -f "$dir/detect.srt"
    iso3 "$code"
}

# ocr <engine> <input.sup> <lang> <output.srt>   (lang "und" = unknown)
ocr() {
    local engine="$1" sup="$2" lang="$3" srt="$4" name tl fce=()
    if [ "$lang" = und ]; then
        name="$(name_list "$SUB_LANGS")"; tl="$(tess_list "$SUB_LANGS")"
    else
        name="$(lang_name "$lang")"; tl="$(tess_lang "$lang")"; fce=(--fce-language:"$name")
    fi
    local args=("$sup" subrip
        --output-folder:"$(dirname "$srt")" --output-filename:"$(basename "$srt")" --overwrite
        --fix-common-errors-rules:"$FCE_RULES" "${fce[@]}" --dictionary-folder:"$DICT" --quiet)
    case "$engine" in
        ollama)    args+=(--ocr-engine:ollama --ollama-url:"${OLLAMA_URL%/}/api/chat"
                          --ollama-model:"$OLLAMA_MODEL" --ocr-language:"$name") ;;
        *)         args+=(--ocr-engine:"$engine" --ocr-language:"$tl") ;;
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

    # Image subtitles to process, as lines: id<TAB>tagged language<TAB>forced(0/1)
    #   - per SUB_LANGS language: the first full and the first forced track
    #   - SUB_UNMATCHED=all|detected: also every untagged ("und") track, and every
    #     track at all if none matched (discs often mislabel or don't tag subtitles)
    local subs
    subs="$(jq -r --arg langs "$SUB_LANGS" --arg unmatched "$SUB_UNMATCHED" '
        ($langs | split(",")) as $want
        | [.tracks[] | select(.type=="subtitles"
                              and (.properties.codec_id == "S_HDMV/PGS" or .properties.codec_id == "S_VOBSUB"))] as $s
        | [$want[] as $lang
           | ([$s[] | select(.properties.language == $lang and (.properties.forced_track | not))][0],
              [$s[] | select(.properties.language == $lang and .properties.forced_track)][0])
           | select(. != null)] as $matched
        | [$s[] | select((.properties.language // "und") == "und")] as $und
        | (if $unmatched == "none" then $matched
           elif ($matched | length) == 0 then $s
           else $matched + $und end)
        | unique_by(.id)[]
        | "\(.id)\t\(.properties.language // "und")\t\(if .properties.forced_track then 1 else 0 end)"' <<<"$json")"

    if [ -z "$subs" ]; then
        log "no $SUB_LANGS image subtitles found; remuxing audio/video only"
    elif ! jq -e --arg langs "$SUB_LANGS" '($langs | split(",")) as $w
            | any(.tracks[]; .type=="subtitles" and ((.properties.language // "und") as $l | $w | index($l)))' \
            <<<"$json" >/dev/null; then
        log "no subtitle track is tagged $SUB_LANGS; taking all $(wc -l <<<"$subs" | tr -d ' ') image subtitle tracks"
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
    # Per processed track: source id, final language, forced flag, SRT file.
    local sub_ids=() sub_langs=() sub_forced=() srt_files=() tagged detected
    while IFS=$'\t' read -r id tagged forced; do
        [ -n "$id" ] || continue
        lang="$tagged"
        if ! in_list "$tagged" "$SUB_LANGS"; then
            # Untagged or other language: read the real language from the text first.
            detected="$(detect_lang "$job/$id.sup")"
            [ "$detected" != und ] && lang="$detected"
            log "track $id is tagged '$tagged', text looks $([ "$detected" = und ] && echo 'unrecognised' || lang_name "$detected")"
            if [ "$SUB_UNMATCHED" = detected ] && ! in_list "$lang" "$SUB_LANGS"; then
                log "skipping track $id ($(lang_name "$lang") is not in $SUB_LANGS)"
                continue
            fi
        fi
        local srt="$job/$id.$lang.srt"
        log "OCR track $id ($(lang_name "$lang")$([ "$forced" = 1 ] && echo ', forced')) with $engine"
        if ! ocr "$engine" "$job/$id.sup" "$lang" "$srt"; then
            if [ -n "$OCR_FALLBACK" ] && [ "$OCR_FALLBACK" != "$engine" ]; then
                log "$engine failed, retrying track $id with $OCR_FALLBACK"
                ocr "$OCR_FALLBACK" "$job/$id.sup" "$lang" "$srt" || { log "OCR failed for track $id"; return 1; }
            else
                log "OCR failed for track $id"; return 1
            fi
        fi
        log "track $id: $(grep -c -- '-->' "$srt") subtitles"
        sub_ids+=("$id"); sub_langs+=("$lang"); sub_forced+=("$forced"); srt_files+=("$srt")
    done <<<"$subs"

    # SRTs in SUB_LANGS order (then the rest), keeping disc order within a language.
    local i rank sorted=()
    for i in "${!sub_ids[@]}"; do
        rank=$(( $(tr ',' '\n' <<<"$SUB_LANGS" | grep -nx -- "${sub_langs[$i]}" | cut -d: -f1 | head -1) + 0 ))
        [ "$rank" -eq 0 ] && rank=99
        sorted+=("$rank $i")
    done
    mapfile -t sorted < <(printf '%s\n' "${sorted[@]}" | sort -n -s -k1,1 | cut -d' ' -f2)
    [ ${#sub_ids[@]} -gt 0 ] || sorted=()

    # Remux. Order: video, audio, new SRTs, then the original image subs.
    local dest partial
    dest="$(output_path "$rel")"
    partial="$(dirname "$dest")/.$(basename "$dest").partial"
    mkdir -p "$(dirname "$dest")" || return 1
    if [ -e "$dest" ]; then log "output already exists: $dest"; return 1; fi

    local args=(-o "$partial") order=() t label
    [ -n "$audio_ids" ] && args+=(-a "$audio_ids") || args+=(-A)
    if [ "$KEEP_PGS" = 1 ] && [ ${#sub_ids[@]} -gt 0 ]; then
        args+=(-s "$(IFS=,; echo "${sub_ids[*]}")")
        for i in "${!sub_ids[@]}"; do
            label="$([ "${sub_langs[$i]}" = und ] && echo Unknown || lang_name "${sub_langs[$i]}")"
            args+=(--language "${sub_ids[$i]}:${sub_langs[$i]}" --default-track-flag "${sub_ids[$i]}:0"
                   --track-name "${sub_ids[$i]}:$label$([ "${sub_forced[$i]}" = 1 ] && echo ' Forced') (PGS)")
        done
    else
        args+=(-S)
    fi
    args+=("$src")
    for t in ${video_ids//,/ }; do order+=("0:$t"); done
    for t in ${audio_ids//,/ }; do order+=("0:$t"); done

    local n=0 default default_done=0
    for i in "${sorted[@]}"; do
        lang="${sub_langs[$i]}"; forced="${sub_forced[$i]}"
        label="$([ "$lang" = und ] && echo Unknown || lang_name "$lang")"
        default=0
        if [ $default_done = 0 ] && [ "$lang" = "$DEFAULT_SUB_LANG" ] && [ "$forced" = 0 ]; then
            default=1; default_done=1
        fi
        args+=(--language "0:$lang" --default-track-flag "0:$default" --forced-display-flag "0:$forced"
               --track-name "0:$label$([ "$forced" = 1 ] && echo ' Forced')"
               "${srt_files[$i]}")
        n=$((n + 1)); order+=("$n:0")
    done
    if [ "$KEEP_PGS" = 1 ]; then
        for i in "${sorted[@]}"; do order+=("0:${sub_ids[$i]}"); done
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

output_path() { echo "$OUT/${1%.*}${OUTPUT_SUFFIX}.mkv"; }
failed_log()  { echo "$OUT/${1%.*}${OUTPUT_SUFFIX}-FAILED.log"; }

log "mkv-autosub watching $WATCH -> $OUT, appdata $CONFIG (subs: $SUB_LANGS, unmatched subs: $SUB_UNMATCHED, extra audio: $AUDIO_LANGS, OCR: $OCR_ENGINE, fallback: ${OCR_FALLBACK:-none}, source after: $SOURCE_AFTER)"
[ "$OCR_ENGINE" = ollama ] && log "Ollama: $OLLAMA_URL, model $OLLAMA_MODEL"
if ! mkdir -p "$WORK" "$DICT" || ! touch "$PROCESSED" || [ ! -w "$OUT" ]; then
    log "ERROR: can't write to $CONFIG or $OUT as $(id -u):$(id -g). Fix the folder owner on the host:"
    log "       chown $(id -u):$(id -g) <host folder>"
    exit 1
fi
# Add dictionaries that are new in this image without overwriting the user's edits.
cp -r --update=none /opt/dictionaries/. "$DICT/"

while true; do
    # done/ and failed/ are where older versions moved rips; leave those alone.
    find "$WATCH" \( -path "$WATCH/done" -o -path "$WATCH/failed" \) -prune -o \
         -type f -iname '*.mkv' -mmin +"$STABLE_MINUTES" -print 2>/dev/null \
        | sort | while IFS= read -r f; do
        rel="${f#"$WATCH"/}"
        key="$rel|$(stat -c %s "$f" 2>/dev/null)"
        grep -qxF -- "$key" "$PROCESSED" && continue
        [ -e "$(failed_log "$rel")" ] && continue   # failed before; delete the log to retry
        logfile="$WORK/current.log"
        log "=== $rel"
        if process "$f" </dev/null 2>&1 | tee "$logfile"; [ "${PIPESTATUS[0]}" -eq 0 ]; then
            echo "$key" >> "$PROCESSED"
            if [ "$SOURCE_AFTER" = delete ]; then
                rm -f -- "$f" && log "deleted the source rip"
                # Remove the rip's now-empty folder (never WATCH itself).
                [ "$(dirname "$f")" != "$WATCH" ] && rmdir "$(dirname "$f")" 2>/dev/null
            fi
            log "=== done: $rel -> $(output_path "$rel")"
        else
            mkdir -p "$(dirname "$(failed_log "$rel")")" && cp "$logfile" "$(failed_log "$rel")"
            log "=== FAILED: $rel (see $(failed_log "$rel"); delete that log to retry)"
        fi
    done
    sleep "$SCAN_INTERVAL"
done
