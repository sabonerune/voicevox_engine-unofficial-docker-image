#!/bin/bash
set -eu

# Set setting directory
export XDG_DATA_HOME="${XDG_DATA_HOME:-/opt/setting}"

args=("$@")
set_voicevox_dir=
set_voicelib_dir=
set_runtime_dir=
for arg in "$@"; do
	if [[ "$arg" =~ ^--voicevox_dir(=.*)?$ ]]; then
		set_voicevox_dir=0
	elif [[ "$arg" =~ ^--voicelib_dir(=.*)?$ ]]; then
		set_voicelib_dir=0
	elif [[ "$arg" =~ --runtime_dir(=.*)?$ ]]; then
		set_runtime_dir=0
	fi
done

if [[ -z "$set_voicevox_dir" && -z "$set_voicelib_dir" ]]; then
	# Set default voicelib directory
	args+=("--voicelib_dir=/opt/voicevox_core/lib")
	export VV_MODELS_ROOT_DIR="${VV_MODELS_ROOT_DIR:-/opt/voicevox_vvm/vvms}"
fi

if [[ -z "$set_voicevox_dir" && -z "$set_runtime_dir" ]]; then
	# Set default runtime directory
	args+=("--runtime_dir=/opt/voicevox_onnxruntime/lib")
fi

# Display README for engine
cat /opt/voicevox_engine/README.md >&2

if [[ "$(id -u)" == 0 ]]; then
	exec gosu USER "${args[@]}"
else
	exec "${args[@]}"
fi
