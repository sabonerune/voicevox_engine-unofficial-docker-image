# syntax=docker/dockerfile:1

ARG BASE_IMAGE=mirror.gcr.io/ubuntu:20.04
ARG BASE_RUNTIME_IMAGE=$BASE_IMAGE

ARG PYTHON_VERSION=3.11.9
ARG RESOURCE_VERSION=0.23.0

FROM scratch AS checkout-engine
ARG ENGINE_VERSION=master
ADD https://github.com/VOICEVOX/voicevox_engine.git#${ENGINE_VERSION} /voicevox_engine


FROM scratch AS checkout-resource
ARG RESOURCE_VERSION
ADD https://github.com/VOICEVOX/voicevox_resource.git#${RESOURCE_VERSION} .


FROM scratch AS download-runtime
ARG RUNTIME_URL
ADD ${RUNTIME_URL} onnxruntime.tgz


FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS extract-onnxruntime
WORKDIR /work

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y tar

COPY --from=download-runtime /onnxruntime.tgz ./
RUN mkdir -p /opt/onnxruntime
RUN tar xf onnxruntime.tgz -C /opt/onnxruntime --strip-components 1


FROM scratch AS download-core
ARG CORE_URL
ADD ${CORE_URL} voicevox_core.zip


FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS extract-core
WORKDIR /work

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y unzip

COPY --from=download-core /voicevox_core.zip ./
RUN unzip voicevox_core.zip
RUN mv voicevox_core-linux-* /opt/voicevox_core


FROM scratch AS download-python
ARG PYTHON_VERSION
ADD https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz ./Python.tar.xz


FROM ${BASE_IMAGE} AS build-python
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
      build-essential \
      pkg-config \
      libbz2-dev \
      libffi-dev \
      liblzma-dev \
      libncurses5-dev \
      libreadline-dev \
      libsqlite3-dev \
      libssl-dev \
      zlib1g-dev

RUN --mount=target=/tmp/Python.tar.xz,source=/Python.tar.xz,from=download-python \
  tar -xf /tmp/Python.tar.xz --strip-components 1

RUN <<EOF
  # Build Python
  set -eux
  ./configure \
    --prefix=/opt/python \
    --enable-shared \
    --enable-optimizations \
    LDFLAGS='-Wl,-rpath,\$$ORIGIN/../lib'
  make install
EOF


FROM ${BASE_IMAGE} AS build-env
WORKDIR /opt/voicevox_engine

COPY --from=ghcr.io/astral-sh/uv /uv /uvx /opt/uv/bin/
COPY --from=build-python /opt/python /opt/python
ENV PATH=/opt/uv/bin:$PATH

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    build-essential \
    git

COPY --from=checkout-engine /voicevox_engine /opt/voicevox_engine

RUN uv sync --python=/opt/python/bin/python3
RUN uv run python -c "import pyopenjtalk; pyopenjtalk._lazy_init()"


FROM build-env AS gen-licenses-env
RUN OUTPUT_LICENSE_JSON_PATH=/opt/voicevox_engine/licenses.json \
  bash tools/create_venv_and_generate_licenses.bash


FROM build-env AS prepare-resource
WORKDIR /opt/voicevox_engine

COPY --from=checkout-resource /character_info /tmp/resource/character_info
COPY --from=checkout-resource /scripts/clean_character_info.py /tmp/resource/scripts/
COPY --from=checkout-resource /engine /tmp/resource/engine

RUN DOWNLOAD_RESOURCE_PATH="/tmp/resource" bash tools/process_voicevox_resource.bash

RUN uv run tools/generate_filemap.py --target_dir resources/character_info

COPY --from=gen-licenses-env /opt/voicevox_engine/licenses.json ./resources/engine_manifest_assets/dependency_licenses.json


FROM ${BASE_RUNTIME_IMAGE} AS runtime-env
WORKDIR /opt/voicevox_engine

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    gosu \
    openssl &&\
  apt-get clean &&\
  rm -rf /var/lib/apt/lists/*

COPY --from=checkout-engine /voicevox_engine/LICENSE /voicevox_engine/run.py ./
COPY --from=checkout-engine /voicevox_engine/voicevox_engine ./voicevox_engine

COPY --from=checkout-resource /engine/README.md .

COPY --from=build-env /opt/python /opt/python
COPY --from=build-env /opt/voicevox_engine/.venv ./.venv

COPY --from=gen-licenses-env /opt/voicevox_engine/licenses.json ./licenses.json

COPY --from=prepare-resource /opt/voicevox_engine/resources ./resources
COPY --from=prepare-resource /opt/voicevox_engine/engine_manifest.json ./engine_manifest.json

ARG ENGINE_VERSION=latest
RUN sed -i "s/__version__ = \"latest\"/__version__ = \"${ENGINE_VERSION}\"/" voicevox_engine/__init__.py
RUN sed -i "s/\"version\": \"999\\.999\\.999\"/\"version\": \"${ENGINE_VERSION}\"/" engine_manifest.json

COPY --from=extract-onnxruntime /opt/onnxruntime /opt/onnxruntime
COPY --from=extract-core /opt/voicevox_core /opt/voicevox_core

RUN useradd USER
RUN mkdir -m 1777 /tmp/user_data

COPY --chmod=775 <<EOF /entrypoint.sh
#!/bin/bash
set -eu

# Set user_data directory
export XDG_DATA_HOME=/tmp/user_data

# Display README for engine
cat /opt/voicevox_engine/README.md >&2

if [ "$(id -u)" -eq 0 ]; then
  exec gosu USER "\$@"
else
  exec "\$@"
fi
EOF

EXPOSE 50021
ENTRYPOINT [ "/entrypoint.sh", "/opt/voicevox_engine/.venv/bin/python3", "/opt/voicevox_engine/run.py" ]
CMD [ "--voicelib_dir", "/opt/voicevox_core", "--runtime_dir", "/opt/onnxruntime/lib", "--host", "0.0.0.0" ]


FROM runtime-env AS runtime-nvidia-env
CMD [ "--use_gpu", "--voicelib_dir", "/opt/voicevox_core", "--runtime_dir", "/opt/onnxruntime/lib", "--host", "0.0.0.0" ]
