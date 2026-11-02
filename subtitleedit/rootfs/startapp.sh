#!/bin/sh
set -u
export HOME=/config
# The file-open dialog starts in the working directory.
cd "${INPUT_DIR:-/input}" 2>/dev/null || cd /config
exec /opt/subtitleedit/SubtitleEdit "$@"
