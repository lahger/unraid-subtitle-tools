# Subtitle Edit (Nikse) for Unraid, with NVIDIA GPU

This runs [Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit) 5 by Nikolaj Olsson (Nikse), its native
Linux build, in a browser desktop based on [jlesage/baseimage-gui](https://github.com/jlesage/docker-baseimage-gui).
Unofficial container; not affiliated with the Subtitle Edit project.
CUDA 12 runtime, cuBLAS and cuDNN are included, so Subtitle Edit's **Linux CUDA engines** work:
whisper.cpp CUDA, Faster-Whisper-XXL, CrispASR and PaddleOCR GPU.

## Prerequisites on Unraid
1. Install the **Nvidia Driver** plugin (Apps tab) and reboot.
2. Copy your GPU UUID from *Settings → Nvidia Driver* (or use `all`).

## Install
1. Download the template (Unraid terminal, the `>_` icon top right in the web UI):
   ```bash
   wget -O /boot/config/plugins/dockerMan/templates-user/my-SubtitleEdit.xml https://raw.githubusercontent.com/lahger/unraid-subtitle-tools/main/subtitleedit/subtitleedit-nvidia.xml
   ```
2. *Docker* tab → **Add Container** → *Template* dropdown → **SubtitleEdit**.
3. Set **Input folder**, **Output folder** and **NVIDIA_VISIBLE_DEVICES**, then click **Apply**.
   Unraid pulls `ghcr.io/lahger/subtitleedit-nvidia:latest` (about 2 GB).
4. Open `http://<unraid-ip>:5800` (or the container icon → *WebUI*).

Updates show up on the Docker tab like for any other app.

### Building it yourself
```bash
docker build -t subtitleedit-nvidia:latest .
```
To pin another Subtitle Edit release: `--build-arg SE_VERSION=v5.4.0-rc1`. On an ARM Mac, add
`--platform linux/amd64`. Then set the template's *Repository* to `subtitleedit-nvidia:latest`.

## Input and output folders

| Container path | Template field  | Used for |
|----------------|-----------------|----------|
| `/input`       | Input folder    | The *Open subtitle* and *Open video* dialogs start here |
| `/output`      | Output folder   | Save As, Whisper results, batch convert, split, burn-in, text-to-speech |
| `/config`      | AppData         | Settings, dictionaries, downloaded Whisper engines and models |

On every start the container sets Subtitle Edit's "default save location" and the tool output folders to
`/output`. Set `DEFAULT_FOLDERS=0` (advanced view) if you'd rather pick folders inside the app and keep them.
You can override the paths with `INPUT_DIR` / `OUTPUT_DIR` if you mount somewhere else.

Plain *Save* on a file that already has a name still writes back to where it came from; use *Save As*
to put it in `/output`.

## Using the GPU
- *Video → Audio to text (Whisper)*: pick a **CUDA** engine (e.g. whisper.cpp CUDA or Faster-Whisper-XXL).
  Subtitle Edit downloads the engine and models into `/config`, so they survive container updates.
- Check passthrough: the container log prints `nvidia-smi` output at startup, or run
  `docker exec SubtitleEdit nvidia-smi`.
- Video preview uses libmpv inside a VNC session, so playback is software-rendered. That's
  expected; the GPU is used for transcription, OCR and ffmpeg (NVENC/NVDEC).
