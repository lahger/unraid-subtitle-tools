# unraid-subtitle-tools

Two Docker containers for Unraid (or any Docker host) built around
[Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit) by Nikolaj Olsson (Nikse):

| | Image | What it does |
|---|---|---|
| [**subtitleedit**](subtitleedit/) | `ghcr.io/lahger/subtitleedit-nvidia` | The Subtitle Edit app in your browser, with NVIDIA GPU support for Whisper speech-to-text, OCR and ffmpeg. |
| [**mkv-autosub**](mkv-autosub/) | `ghcr.io/lahger/mkv-autosub` | Headless pipeline for Blu-ray rips: keeps the tracks you want, OCRs the image subtitles to SRT (Ollama AI or Tesseract) and remuxes everything into one `.mkv`. |

They're made for a MakeMKV → Jellyfin/Plex workflow:

```
MakeMKV ──rip──▶ mkv-autosub (automatic) ──▶ Movie-REMUX.mkv ──▶ Jellyfin / Plex
                            ▲
                 subtitleedit (by hand, when a subtitle needs fixing)
```

## Install on Unraid

Each folder has its own README with the details. In short, from the Unraid terminal, download the template:

```bash
wget -O /boot/config/plugins/dockerMan/templates-user/my-SubtitleEdit.xml https://raw.githubusercontent.com/lahger/unraid-subtitle-tools/main/subtitleedit/subtitleedit-nvidia.xml
```

```bash
wget -O /boot/config/plugins/dockerMan/templates-user/my-mkv-autosub.xml https://raw.githubusercontent.com/lahger/unraid-subtitle-tools/main/mkv-autosub/mkv-autosub.xml
```

Then go to *Docker → Add Container*, pick the template, fill in your folders and click **Apply**. Unraid pulls
the image from ghcr.io and shows updates like any other app.

The images are built for `linux/amd64` by [GitHub Actions](.github/workflows/build.yml) on every change.

## Credits and licenses

- **[Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit)** by Nikolaj Olsson and contributors (MIT)
  does all the subtitle work, both the app and its `seconv` command-line converter.
- **[docker-baseimage-gui](https://github.com/jlesage/docker-baseimage-gui)** by Jocelyn Le Sage (MIT)
  provides the browser desktop for the `subtitleedit` image.
- **[MKVToolNix](https://mkvtoolnix.download/)** by Moritz Bunkus, **[Tesseract OCR](https://github.com/tesseract-ocr/tesseract)**,
  **[FFmpeg](https://ffmpeg.org/)**, **[mpv](https://mpv.io/)**, NVIDIA CUDA/cuDNN and the Ubuntu packages are
  included as listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This is an unofficial project and is not affiliated with or endorsed by Subtitle Edit, MakeMKV, NVIDIA
or Unraid. The scripts, Dockerfiles and templates here are MIT-licensed ([LICENSE](LICENSE)); the bundled
software keeps its own licenses.
