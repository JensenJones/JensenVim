#!/bin/sh
set -eu
JVIM_SOURCE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$JVIM_SOURCE/install/macos.py" "$@"
