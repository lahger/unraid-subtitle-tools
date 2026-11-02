# Third-party software

The scripts, Dockerfiles and Unraid templates in this repository are MIT-licensed (see [LICENSE](LICENSE)).
The Docker images built from them download and bundle the software below, which belongs to its
respective authors and stays under its own license. This project is not affiliated with or endorsed
by any of them.

## In both images

| Software | Author | License | Where it's used |
|---|---|---|---|
| [Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit) | Nikolaj Olsson (Nikse) and contributors | [MIT](https://github.com/SubtitleEdit/subtitleedit/blob/main/LICENSE) | `subtitleedit` (the app) and `mkv-autosub` (its `seconv` command-line converter). Downloaded unmodified from the official GitHub releases; its LICENSE file is kept next to the binaries in `/opt/subtitleedit` and `/opt/seconv`. |
| Subtitle Edit dictionaries (`*_OCRFixReplaceList.xml`, `*_names.xml`, `en_US.dic/.aff`, ...) | Subtitle Edit project | see the [Subtitle Edit repository](https://github.com/SubtitleEdit/subtitleedit/tree/main/Dictionaries) | OCR fix lists and spell checking in `mkv-autosub` (`/opt/dictionaries`) |
| Ubuntu 24.04 packages (FFmpeg, mpv/libmpv, MKVToolNix, Tesseract OCR, Hunspell dictionaries, fonts, ...) | their respective authors, packaged by Ubuntu | various free licenses (GPL, LGPL, Apache-2.0, ...) | Installed unmodified from the Ubuntu archive. Each package's license is in the image at `/usr/share/doc/<package>/copyright`; source code is available from [Ubuntu](https://launchpad.net/ubuntu) (`apt-get source <package>`). |

## `subtitleedit` image only

| Software | Author | License |
|---|---|---|
| [docker-baseimage-gui](https://github.com/jlesage/docker-baseimage-gui) (web/VNC desktop base image) | Jocelyn Le Sage | [MIT](https://github.com/jlesage/docker-baseimage-gui/blob/master/LICENSE) |
| NVIDIA CUDA runtime, cuBLAS, cuFFT | NVIDIA Corporation | [NVIDIA CUDA Toolkit EULA](https://docs.nvidia.com/cuda/eula/index.html) (redistributable components) |
| NVIDIA cuDNN | NVIDIA Corporation | [NVIDIA cuDNN Software License Agreement](https://docs.nvidia.com/deeplearning/cudnn/latest/reference/eula.html) |

The NVIDIA libraries are installed unmodified from NVIDIA's official Ubuntu repository. The NVIDIA
driver itself is not included; it is provided by the host (Unraid's Nvidia Driver plugin).

## Downloaded at runtime (not included in the images)

Subtitle Edit can download speech-to-text engines (Whisper, Faster-Whisper-XXL, ...), OCR engines
(PaddleOCR, ...) and AI models when you choose to use them. Those come from their own projects under
their own licenses and are stored in your `/config` folder.

`mkv-autosub` can use [Ollama](https://github.com/ollama/ollama) (MIT) running in its own container,
with whichever vision model you pull (e.g. Qwen2.5-VL, under its own license).
