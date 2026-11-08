#!/bin/sh
set -eu
# Run the watcher as PUID:PGID (Unraid: nobody:users) so new files get normal share ownership.
umask "${UMASK:-000}"
export HOME="${CONFIG_DIR:-/config}"
mkdir -p "$HOME"
chown "${PUID}:${PGID}" /opt/seconv

# A host folder that didn't exist yet is created by Docker as root:root, which the
# watcher can't write to. Hand just that top-level folder over (not its contents).
for d in "${CONFIG_DIR:-/config}" "${WATCH_DIR:-/watch}" "${OUTPUT_DIR:-/output}"; do
    if ! setpriv --reuid="${PUID}" --regid="${PGID}" --clear-groups test -w "$d"; then
        echo "[entrypoint] $d is not writable for ${PUID}:${PGID}, taking ownership of the folder"
        chown "${PUID}:${PGID}" "$d" && chmod u+rwx "$d" || \
            echo "[entrypoint] could not fix $d - set its owner to ${PUID}:${PGID} on the host"
    fi
done

exec setpriv --reuid="${PUID}" --regid="${PGID}" --clear-groups /usr/local/bin/autosub.sh "$@"
