# Subtitle Edit (Nikse) in a browser-accessible desktop, with NVIDIA CUDA support.
# Web UI on :5800, VNC on :5900. Settings persist in /config.
FROM jlesage/baseimage-gui:ubuntu-24.04-v4

ARG SE_VERSION=v5.3.0
ARG CUDA_MAJOR=12
ARG CUDA_MINOR=9

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=0 \
    LD_LIBRARY_PATH=/usr/local/cuda/targets/x86_64-linux/lib

# Runtime deps: X11/GL for Avalonia, libmpv for the video player, ffmpeg for
# waveforms/encoding, tesseract for OCR, openblas/vulkan for whisper engines.
RUN add-pkg \
        ca-certificates curl gnupg p7zip-full unzip xz-utils \
        libicu74 libfontconfig1 fonts-dejavu fonts-noto-core fonts-noto-cjk \
        libx11-6 libxext6 libxrandr2 libxi6 libxcursor1 libsm6 libice6 \
        libgl1 libegl1 libgles2 libvulkan1 mesa-vulkan-drivers \
        libmpv2 ffmpeg tesseract-ocr tesseract-ocr-eng libopenblas0 \
        hunspell-en-us xdg-utils

# CUDA 12 runtime + cuBLAS + cuDNN (needed by SE's Linux CUDA engines:
# whisper.cpp CUDA, Faster-Whisper-XXL, CrispASR, PaddleOCR GPU).
# The driver itself (libcuda.so) is injected by the NVIDIA container runtime.
RUN curl -fsSL -o /tmp/cuda-keyring.deb \
        https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb && \
    add-pkg \
        cuda-cudart-${CUDA_MAJOR}-${CUDA_MINOR} \
        libcublas-${CUDA_MAJOR}-${CUDA_MINOR} \
        libcufft-${CUDA_MAJOR}-${CUDA_MINOR} \
        libcudnn9-cuda-${CUDA_MAJOR} && \
    ln -sfn /usr/local/cuda-${CUDA_MAJOR}.${CUDA_MINOR} /usr/local/cuda && \
    echo /usr/local/cuda/targets/x86_64-linux/lib > /etc/ld.so.conf.d/cuda.conf && ldconfig

# Subtitle Edit (self-contained .NET build)
RUN mkdir -p /opt/subtitleedit && \
    curl -fsSL "https://github.com/SubtitleEdit/subtitleedit/releases/download/${SE_VERSION}/SubtitleEdit-Linux-x64.tar.gz" \
        | tar xz -C /opt/subtitleedit && \
    chmod +x /opt/subtitleedit/SubtitleEdit && \
    chmod -R a+rX /opt/subtitleedit

# jq edits Settings.json at startup (default input/output folders);
# wmctrl keeps the main window maximized.
RUN add-pkg jq wmctrl

COPY rootfs/ /

RUN set-cont-env APP_NAME "Subtitle Edit" && \
    set-cont-env APP_VERSION "${SE_VERSION#v}" && \
    chmod +x /startapp.sh /etc/cont-init.d/*.sh /etc/services.d/keepmax/run

# WEB_AUDIO: stream sound to the browser. The video player also needs an audio
# device to play back at all, so this is on by default.
ENV INPUT_DIR=/input \
    OUTPUT_DIR=/output \
    DEFAULT_FOLDERS=1 \
    WEB_AUDIO=1

VOLUME ["/config", "/input", "/output"]
