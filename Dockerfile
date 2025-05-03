# syntax=docker/dockerfile:1

ARG BASE_IMAGE=mirror.gcr.io/ubuntu:20.04
ARG BASE_RUNTIME_IMAGE=$BASE_IMAGE

ARG PYTHON_VERSION=3.11.9
ARG ENGINE_VERSION=0.23.0
ARG RESOURCE_VERSION=0.23.0

ARG CORE_URL
ARG RUNTIME_URL

FROM scratch AS checkout-engine
ARG ENGINE_VERSION
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
RUN tar xf "./onnxruntime.tgz" -C "/opt/onnxruntime" --strip-components 1


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
      libssl-dev \
      zlib1g-dev \
      libbz2-dev \
      libreadline-dev \
      libsqlite3-dev \
      libncursesw5-dev \
      xz-utils \
      tk-dev \
      libxml2-dev \
      libxmlsec1-dev \
      libffi-dev \
      liblzma-dev

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

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    build-essential \
    git

COPY --from=build-python /opt/python /opt/python
COPY --from=checkout-engine /voicevox_engine /opt/voicevox_engine

# WORKAROUND
RUN sed -i "s/@0fcb731c94555e8d160d18e7f1a4d005b2e8e852/@5b70b94f3460ece07ea183227db088ce8d5212a6/" requirements.txt
RUN /opt/python/bin/python3 -m pip install -r requirements.txt

RUN /opt/python/bin/python3 -c "import pyopenjtalk; pyopenjtalk._lazy_init()"


FROM build-env AS gen-licenses-env
RUN <<EOF
  # Generate licenses.json
  set -eux
  requirements="$(grep pip-licenses requirements-dev.txt | cut -f 1 -d ';')"
  /opt/python/bin/python3 -m pip install $requirements
  export PATH="/opt/python/bin:${PATH:-}"
  /opt/python/bin/python3 tools/generate_licenses.py > licenses.json
EOF


FROM build-env AS prepare-resource
WORKDIR /opt/voicevox_engine

COPY --from=checkout-resource /character_info /tmp/resource/character_info
COPY --from=checkout-resource /scripts/clean_character_info.py /tmp/resource/scripts/
COPY --from=checkout-resource /engine /tmp/resource/engine

RUN ln -s python3.11 /opt/python/bin/python
RUN PATH="/opt/python/bin:${PATH:-}" DOWNLOAD_RESOURCE_PATH="/tmp/resource" bash tools/process_voicevox_resource.bash

RUN /opt/python/bin/python3 tools/generate_filemap.py --target_dir resources/character_info

COPY --from=gen-licenses-env /opt/voicevox_engine/licenses.json ./resources/engine_manifest_assets/dependency_licenses.json


FROM ${BASE_RUNTIME_IMAGE} AS runtime-nvidia-env
WORKDIR /opt/voicevox_engine

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    gosu \
    libssl1.1 &&\
  apt-get clean &&\
  rm -rf /var/lib/apt/lists/*
RUN useradd --create-home USER

COPY --from=checkout-engine /voicevox_engine/LICENSE /voicevox_engine/run.py ./
COPY --from=checkout-engine /voicevox_engine/voicevox_engine ./voicevox_engine

COPY --from=checkout-resource /engine/README.md .

COPY --from=build-env /opt/python /opt/python

COPY --from=gen-licenses-env /opt/voicevox_engine/licenses.json ./licenses.json

COPY --from=prepare-resource /opt/voicevox_engine/resources ./resources
COPY --from=prepare-resource /opt/voicevox_engine/engine_manifest.json ./engine_manifest.json

ARG VOICEVOX_ENGINE_VERSION=latest
RUN sed -i "s/__version__ = \"latest\"/__version__ = \"${VOICEVOX_ENGINE_VERSION}\"/" voicevox_engine/__init__.py
RUN sed -i "s/\"version\": \"999\\.999\\.999\"/\"version\": \"${VOICEVOX_ENGINE_VERSION}\"/" engine_manifest.json

COPY --from=extract-onnxruntime /opt/onnxruntime /opt/onnxruntime
COPY --from=extract-core /opt/voicevox_core /opt/voicevox_core

COPY --chmod=775 <<EOF /entrypoint.sh
#!/bin/bash
set -eu

# Display README for engine
cat /opt/voicevox_engine/README.md > /dev/stderr

if [ "$(id -u)" -eq 0 ]; then
  exec gosu USER "\$@"
else
  exec "\$@"
fi
EOF

EXPOSE 50021
ENTRYPOINT [ "/entrypoint.sh", "/opt/python/bin/python3", "/opt/voicevox_engine/run.py" ]
CMD [ "--use_gpu", "--voicelib_dir", "/opt/voicevox_core", "--runtime_dir", "/opt/onnxruntime/lib", "--host", "0.0.0.0" ]


FROM runtime-nvidia-env AS runtime-env
CMD [ "--voicelib_dir", "/opt/voicevox_core", "--runtime_dir", "/opt/onnxruntime/lib", "--host", "0.0.0.0" ]
