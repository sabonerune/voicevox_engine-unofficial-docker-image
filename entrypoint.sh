#!/bin/bash
set -eu

# Display README for engine
cat /opt/voicevox_engine/README.md >&2

exec /opt/voicevox_engine/.venv/bin/python3 /opt/voicevox_engine/run.py "$@"
