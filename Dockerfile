# syntax=docker/dockerfile:1

ARG BASE_IMAGE=mirror.gcr.io/ubuntu:22.04
ARG BASE_RUNTIME_IMAGE=$BASE_IMAGE

ARG CORE_VERSION=0.16.0
ARG RUNTIME_VERSION=1.17.3
ARG RUNTIME_ACCELERATION=cpu
ARG RESOURCE_VERSION=0.24.1
ARG VVM_VERSION=0.16.0
ARG CUDNN_VERSION=8.9.7.29

ARG ENGINE_VERSION
ARG ENGINE_VERSION_FOR_CODE=${ENGINE_VERSION:-latest}

FROM scratch AS checkout-engine
ARG ENGINE_VERSION=master
ADD https://github.com/VOICEVOX/voicevox_engine.git#${ENGINE_VERSION} /voicevox_engine


FROM scratch AS checkout-resource
ARG RESOURCE_VERSION
ADD https://github.com/VOICEVOX/voicevox_resource.git#${RESOURCE_VERSION} .


FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS download-vvm
ARG VVM_VERSION
WORKDIR /vvm

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y jq wget

RUN <<EOF
#!/bin/bash
set -euxo pipefail
wget --no-verbose --output-document=- https://api.github.com/repos/VOICEVOX/voicevox_vvm/releases/tags/${VVM_VERSION} | \
  jq --raw-output '.assets[].browser_download_url' | \
  wget --no-verbose --input-file=-
EOF
RUN mkdir ./vvms
RUN mv ./*.vvm ./vvms/


FROM scratch AS download-runtime-cpu-amd64
ARG RUNTIME_VERSION
ADD https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-x64-${RUNTIME_VERSION}.tgz \
  voicevox_onnxruntime.tgz


FROM scratch AS download-runtime-cpu-arm64
ARG RUNTIME_VERSION
ADD https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-arm64-${RUNTIME_VERSION}.tgz \
  voicevox_onnxruntime.tgz


FROM scratch AS download-runtime-cuda-amd64
ARG RUNTIME_VERSION
ADD https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-x64-cuda-${RUNTIME_VERSION}.tgz \
  voicevox_onnxruntime.tgz


FROM download-runtime-${RUNTIME_ACCELERATION}-${TARGETARCH} AS download-runtime


FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS extract-onnxruntime
WORKDIR /work

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y tar

RUN mkdir -p /opt/voicevox_onnxruntime
RUN --mount=target=/tmp/voicevox_onnxruntime.tgz,source=/voicevox_onnxruntime.tgz,from=download-runtime \
  tar -xf /tmp/voicevox_onnxruntime.tgz -C /opt/voicevox_onnxruntime --strip-components 1


FROM scratch AS download-core-amd64
ARG CORE_VERSION
ADD https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-linux-x64-${CORE_VERSION}.zip \
  voicevox_core.zip


FROM scratch AS download-core-arm64
ARG CORE_VERSION
ADD https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-linux-arm64-${CORE_VERSION}.zip \
  voicevox_core.zip


FROM download-core-${TARGETARCH} AS download-core


FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS extract-core
WORKDIR /work

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y unzip

RUN --mount=target=/tmp/voicevox_core.zip,source=/voicevox_core.zip,from=download-core \
  unzip /tmp/voicevox_core.zip
RUN mv voicevox_core-linux-* /opt/voicevox_core


FROM scratch AS download-cudnn-amd64
ARG CUDNN_VERSION
ADD https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-${CUDNN_VERSION}_cuda12-archive.tar.xz \
  cudnn.tar.xz


FROM download-cudnn-${TARGETARCH} AS download-cudnn


FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS extract-cudnn
WORKDIR /work

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y tar xz-utils

RUN mkdir -p /opt/cudnn
RUN --mount=target=/tmp/cudnn.tar.xz,source=/cudnn.tar.xz,from=download-cudnn \
  tar -xf /tmp/cudnn.tar.xz \
  -C /opt/cudnn \
  --strip-components 1 \
  --wildcards "*/libcudnn.so*" \
  --wildcards "*/libcudnn_*_infer.so*" \
  --wildcards "*/LICENSE"


FROM ${BASE_IMAGE} AS build-env
WORKDIR /opt/voicevox_engine

COPY --from=ghcr.io/astral-sh/uv /uv /uvx /opt/uv/bin/
ENV PATH=/opt/uv/bin:$PATH
ENV UV_PYTHON_INSTALL_DIR=/opt/python

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
  build-essential \
  git

COPY --from=checkout-engine /voicevox_engine /opt/voicevox_engine

RUN uv sync --managed-python
RUN uv run python -c "import pyopenjtalk; pyopenjtalk._lazy_init()"

ARG ENGINE_VERSION_FOR_CODE
RUN sed -i "s/__version__ = \"latest\"/__version__ = \"${ENGINE_VERSION_FOR_CODE}\"/" voicevox_engine/__init__.py


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

ARG ENGINE_VERSION_FOR_CODE
RUN sed -i "s/\"version\": \"999\\.999\\.999\"/\"version\": \"${ENGINE_VERSION_FOR_CODE}\"/" engine_manifest.json


FROM build-env AS build-engine
WORKDIR /opt/voicevox_engine

COPY --from=gen-licenses-env /opt/voicevox_engine/licenses.json ./licenses.json

COPY --from=prepare-resource /opt/voicevox_engine/resources ./resources
COPY --from=prepare-resource /opt/voicevox_engine/engine_manifest.json ./engine_manifest.json

COPY --from=extract-onnxruntime /opt/voicevox_onnxruntime /opt/voicevox_onnxruntime
COPY --from=extract-core /opt/voicevox_core /opt/voicevox_core
COPY --from=download-vvm /vvm/vvms /opt/voicevox_vvm/vvms

RUN uv sync --group build
RUN uv run -m PyInstaller --noconfirm run.spec -- \
  --libcore_path=/opt/voicevox_core/lib/libvoicevox_core.so \
  --libonnxruntime_path=/opt/voicevox_onnxruntime/lib/libvoicevox_onnxruntime.so \
  --core_model_dir_path=/opt/voicevox_vvm/vvms


FROM scratch AS cpu-package
COPY --from=build-engine /opt/voicevox_engine/dist/run /run


FROM ${BASE_RUNTIME_IMAGE} AS gather-cuda-lib
WORKDIR /work

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y patchelf

COPY --from=extract-onnxruntime /opt/voicevox_onnxruntime /opt/voicevox_onnxruntime
RUN cp /opt/voicevox_onnxruntime/lib/libvoicevox_onnxruntime_*.so .
RUN patchelf --set-rpath '$ORIGIN' /work/libvoicevox_onnxruntime_providers_*.so

COPY --from=extract-cudnn /opt/cudnn/lib /opt/cudnn/lib
RUN cp -P /opt/cudnn/lib/libcudnn.so.* .
RUN cp -P /opt/cudnn/lib/libcudnn_*_infer.so.* .

RUN cp -P /usr/local/cuda/lib64/libcublas.so.* .
RUN cp -P /usr/local/cuda/lib64/libcublasLt.so.* .
RUN cp -P /usr/local/cuda/lib64/libcudart.so.* .
RUN cp -P /usr/local/cuda/lib64/libcufft.so.* .


FROM cpu-package AS nvidia-package
COPY --from=gather-cuda-lib /work /run


FROM ${BASE_RUNTIME_IMAGE} AS runtime-env
WORKDIR /opt/voicevox_engine

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y gosu && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

COPY --from=build-env /opt/voicevox_engine/LGPL_LICENSE /opt/voicevox_engine/LICENSE /opt/voicevox_engine/run.py ./
COPY --from=build-env /opt/voicevox_engine/.venv ./.venv
COPY --from=build-env /opt/voicevox_engine/voicevox_engine ./voicevox_engine
COPY --from=build-env /opt/python /opt/python

COPY --from=gen-licenses-env /opt/voicevox_engine/licenses.json ./licenses.json
COPY --from=checkout-resource /engine/README.md ./README.md
COPY --from=prepare-resource /opt/voicevox_engine/resources ./resources
COPY --from=prepare-resource /opt/voicevox_engine/engine_manifest.json ./engine_manifest.json

COPY --from=extract-onnxruntime /opt/voicevox_onnxruntime /opt/voicevox_onnxruntime
COPY --from=extract-core /opt/voicevox_core /opt/voicevox_core
COPY --from=download-vvm /vvm /opt/voicevox_vvm

RUN useradd USER
RUN mkdir -m 1777 /opt/setting

COPY --chmod=755 entrypoint.sh /

EXPOSE 50021
VOLUME ["/opt/setting"]
ENTRYPOINT ["/entrypoint.sh", "/opt/voicevox_engine/.venv/bin/python3", "/opt/voicevox_engine/run.py"]
CMD ["--host", "0.0.0.0"]


FROM runtime-env AS runtime-nvidia-env

COPY --from=extract-cudnn /opt/cudnn /opt/cudnn
RUN echo "/opt/cudnn/lib" > /etc/ld.so.conf.d/cudnn.conf && ldconfig

CMD ["--use_gpu", "--host", "0.0.0.0"]
