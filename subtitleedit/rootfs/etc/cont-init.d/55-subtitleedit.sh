#!/bin/sh
set -u
# Log GPU visibility so it's easy to confirm passthrough in the Unraid log.
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "[subtitleedit] NVIDIA GPU(s):"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true
else
    echo "[subtitleedit] nvidia-smi not found - GPU not passed through (add --runtime=nvidia)."
fi
mkdir -p /config/xdg/config /config/xdg/data /config/xdg/cache
