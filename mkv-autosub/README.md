# mkv-autosub

Automatic subtitle OCR and remux for MakeMKV rips, using the `seconv` command-line tool from
[Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit) (Nikolaj Olsson) and [MKVToolNix](https://mkvtoolnix.download/) (Moritz Bunkus).

Replaces a manual "extract subs → OCR in Subtitle Edit → remux" routine. MakeMKV still does the ripping;
everything after that happens on its own:

```
binhex-makemkv ──rip──▶ /watch/<Disc>/<title>.mkv
                              │  (unchanged for 5 min = rip finished)
                              ▼
   mkv-autosub:  keep video + first audio + Swedish audio
                 OCR English & Swedish PGS subs ──▶ SRT   (Ollama AI, Tesseract fallback)
                 remux: video, audio, SRTs, original PGS
                              │
                              ├──▶ /output/<Disc>/<title>-REMUX.mkv     finished file
                              └──▶ /config/processed.list              rip remembered
```

The watch folder is only read, never written to: the rip stays where MakeMKV put it (or is deleted
after a successful run with `SOURCE_AFTER=delete`).

## Requirements

- An **Ollama** container (e.g. *ollama* from Community Apps, with the GPU passed through) with a vision
  model pulled. Without Ollama, set `OCR_ENGINE=tesseract`; nothing else is needed then.

## What ends up in the file

| Track | Default | Notes |
|---|---|---|
| Video | | all video tracks |
| Audio: first track | ✔ | usually the original language |
| Audio: Swedish | | if the disc has it |
| **English (SRT)** | ✔ | OCR of the first full English subtitle track |
| English Forced (SRT) | | only if the disc has a separate forced track |
| **Swedish (SRT)** | | |
| English / Swedish (PGS) | | the original image subtitles, as a fallback |

Other subtitle tracks (other languages, commentary) and other audio are dropped.

## Install on Unraid

1. Pull a vision model in your **ollama** container (its console, or):
   ```bash
   docker exec ollama ollama pull qwen2.5vl:3b
   ```
   `qwen2.5vl:3b` needs about half the GPU memory of `qwen2.5vl:7b`; use it on 8 GB cards
   (set `OLLAMA_MODEL` to match).
2. Download the template:
   ```bash
   wget -O /boot/config/plugins/dockerMan/templates-user/my-mkv-autosub.xml https://raw.githubusercontent.com/lahger/unraid-subtitle-tools/main/mkv-autosub/mkv-autosub.xml
   ```
3. *Docker → Add Container → Template: mkv-autosub*:
   - **AppData**: e.g. `/mnt/user/appdata/mkv-autosub`
   - **Watch folder**: the same host folder MakeMKV writes its rips to
   - **Output folder**: where finished files go
   - **OLLAMA_URL**: `http://<unraid-ip>:11434`
4. Apply, and watch the container's log. Rip a disc and it is picked up 5 minutes after MakeMKV finishes.

No GPU settings are needed for this container; Ollama uses the GPU in its own container. Without
Ollama, set `OCR_ENGINE=tesseract`.

To build the image yourself: `docker build -t mkv-autosub:latest .` in this folder.

## Settings (Advanced View)

| Variable | Default | |
|---|---|---|
| `OCR_ENGINE` | `ollama` | `ollama`, `tesseract` or `nocr` |
| `OCR_FALLBACK` | `tesseract` | used if Ollama is down, the model isn't pulled, or OCR fails; empty = mark the file failed instead |
| `OLLAMA_MODEL` | `qwen2.5vl:7b` | any Ollama vision model |
| `SUB_LANGS` | `eng,swe` | subtitle languages to OCR (3-letter codes as in the MKV) |
| `SUB_UNMATCHED` | `all` | subtitle tracks that aren't tagged with a `SUB_LANGS` language, see below |
| `AUDIO_LANGS` | `swe` | audio kept in addition to the first track |
| `DEFAULT_SUB_LANG` | `eng` | SRT shown by default; empty = none |
| `KEEP_PGS` | `1` | `0` = SRT only |
| `OUTPUT_SUFFIX` | `-REMUX` | added before `.mkv` in the output name; empty = original name |
| `SOURCE_AFTER` | `keep` | `keep` = leave the rip in the watch folder, `delete` = delete it after a successful run |
| `STABLE_MINUTES` | `5` | how long a rip must be unchanged before it's processed |

## AppData (`/config`)

| | |
|---|---|
| `autosub.log` | log of every run (also shown in the container log); rotated at 10 MB |
| `processed.list` | rips already handled, as `path|size`. Remove a line to process that rip again. |
| `dictionaries/` | OCR fix lists (`eng_OCRFixReplaceList.xml`, `swe_OCRFixReplaceList.xml`) and spell-check dictionaries used by "Fix common errors". Edit them to add your own corrections; updates add new files but never overwrite yours. |
| `work/` | temporary subtitle files while a rip is processed |

## Untagged or mislabeled subtitles

Many discs (Scandinavian ones especially) don't tag their subtitle tracks, or tag them wrong. With
`SUB_UNMATCHED=all` (the default):

- tracks tagged `und` (undefined) are always taken as well, and
- if **no** track is tagged with a `SUB_LANGS` language, **every** image subtitle track is taken.

For those tracks a quick Tesseract pass first reads the language from the text (English, Swedish,
Danish, Norwegian, Finnish; `DETECT_LANGS`), then the track is OCR'd in that language and labelled with
it in the output, so "Swedish" ends up on the right track and English still gets the default flag.

`SUB_UNMATCHED=detected` does the same but keeps only tracks whose text turns out to be a `SUB_LANGS`
language (skips e.g. Danish and Finnish). `none` only uses tracks that are tagged correctly.

Only subtitles are detected this way. Audio still uses the tags: the first audio track is always kept,
plus tracks tagged with an `AUDIO_LANGS` language.

## Good to know

- **Speed.** The extra time is mostly OCR: a film has about 1,000–1,500 subtitle images per language. Tesseract
  does that in a minute or two; Ollama on a GPU such as an RTX 3070 takes longer per image, so expect tens of minutes per
  film (an estimate; it was only tested on a CPU here). Movies are processed one at a time.
- **The GPU is shared.** With `qwen2.5vl:7b`, Ollama uses about 6 GB of GPU memory while it runs. Avoid running Whisper in
  Subtitle Edit at the same time.
- **Failures** write `<title>-REMUX-FAILED.log` where the finished file would have gone. The rip is left
  alone and not retried; fix the cause and delete that log to retry.
- **Output already exists**: the rip is marked failed rather than overwriting anything.
- While a file is being written it has a hidden temporary name (`.<title>-REMUX.mkv.partial`), so media
  servers never pick up a half-written movie.
- Line breaks are kept. The "Fix common errors" rules that would join two-line subtitles are
  turned off (`FCE_RULES`).
- Disc subtitles where each line is individually flagged as forced (instead of a separate forced track)
  get no separate forced SRT.
