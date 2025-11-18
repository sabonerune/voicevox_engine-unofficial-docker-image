# syntax=docker/dockerfile:1

ARG BUILD_IMAGE=ubuntu:22.04
ARG CUDA_IMAGE=nvidia/cuda:12.4.1-runtime-ubuntu22.04
ARG RUNTIME_IMAGE=gcr.io/distroless/base-nossl-debian12

ARG CORE_VERSION=0.16.2
ARG RUNTIME_VERSION=1.17.3
ARG RUNTIME_ACCELERATION=cpu
ARG RESOURCE_VERSION=0.25.0
ARG VVM_VERSION=0.16.1
ARG CUDNN_VERSION=8.9.7.29

ARG ENGINE_VERSION
ARG ENGINE_VERSION_FOR_CODE=${ENGINE_VERSION:-latest}

FROM scratch AS checkout-resource
ARG RESOURCE_VERSION
ADD https://github.com/VOICEVOX/voicevox_resource.git#${RESOURCE_VERSION} .


FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS download-vvm
ARG VVM_VERSION
WORKDIR /vvm

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y ca-certificates jq wget

RUN <<EOF
#!/bin/bash
set -euxo pipefail
wget --no-verbose --output-document=- https://api.github.com/repos/VOICEVOX/voicevox_vvm/releases/tags/${VVM_VERSION} | \
  jq --raw-output '.assets[]|select(.name|test("^n.*\\.vvm$")|not).browser_download_url' | \
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


FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS extract-onnxruntime
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y tar zlib1g

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


FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS extract-core
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y unzip

RUN --mount=target=/tmp/voicevox_core.zip,source=/voicevox_core.zip,from=download-core \
  unzip /tmp/voicevox_core.zip
RUN mv voicevox_core-linux-* /opt/voicevox_core


FROM scratch AS download-cudnn-amd64
ARG CUDNN_VERSION
ADD https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-${CUDNN_VERSION}_cuda12-archive.tar.xz \
  cudnn.tar.xz


FROM download-cudnn-${TARGETARCH} AS download-cudnn


FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS extract-cudnn
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y tar xz-utils

RUN mkdir -p /opt/cudnn
RUN --mount=target=/tmp/cudnn.tar.xz,source=/cudnn.tar.xz,from=download-cudnn \
  tar -xf /tmp/cudnn.tar.xz \
  -C /opt/cudnn \
  --strip-components 1 \
  --wildcards "*/libcudnn.so*" \
  --wildcards "*/libcudnn_*_infer.so*" \
  --wildcards "*/LICENSE"


FROM scratch AS checkout-engine

ARG ENGINE_VERSION=master
ADD --link https://github.com/VOICEVOX/voicevox_engine.git#${ENGINE_VERSION} /opt/voicevox_engine


FROM ${BUILD_IMAGE} AS build-python
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
  build-essential \
  ca-certificates \
  libffi-dev \
  libssl-dev \
  pkg-config \
  tar \
  uuid-dev \
  wget \
  zlib1g-dev

RUN --mount=target=/tmp/pyproject.toml,source=/opt/voicevox_engine/pyproject.toml,from=checkout-engine <<EOF
# Download Python
set -eux
PYTHON_VERSION=$(sed -En 's/requires-python.*"==(.*)".*/\1/p' /tmp/pyproject.toml)
wget --no-verbose --output-document=./Python.tar.xz \
  https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz
EOF
RUN tar -xf ./Python.tar.xz --strip-components 1 && \
  unlink ./Python.tar.xz

RUN <<EOF
# Build Python
set -eux
./configure \
  --prefix=/opt/python \
  --disable-test-modules \
  --with-ensurepip=no \
  --enable-optimizations \
  --with-lto \
  --without-doc-strings \
  --enable-shared \
  --without-static-libpython \
  --without-readline \
  LDFLAGS='-Wl,-rpath,\$$ORIGIN/../lib,-s'
make -j "$(nproc)"
make install
EOF


FROM ${BUILD_IMAGE} AS build-env
WORKDIR /opt/voicevox_engine

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
  build-essential \
  ca-certificates \
  git \
  patchelf

COPY --from=ghcr.io/astral-sh/uv --link /uv /uvx /opt/uv/bin/
ENV PATH=/opt/uv/bin:$PATH
COPY --from=build-python --link /opt/python /opt/python

COPY --from=checkout-engine --link /opt/voicevox_engine /opt/voicevox_engine

RUN uv sync --python=/opt/python/bin/python3
RUN uv run python -c "import pyopenjtalk; pyopenjtalk._lazy_init()"


FROM build-env AS gen-licenses-env
RUN OUTPUT_LICENSE_JSON_PATH=/opt/voicevox_engine/licenses.json \
  bash tools/create_venv_and_generate_licenses.bash


FROM build-env AS build-engine

RUN --mount=target=/tmp/resource/,source=/,from=checkout-resource \
  DOWNLOAD_RESOURCE_PATH="/tmp/resource" bash tools/process_voicevox_resource.bash
RUN unlink ./resources/engine_manifest_assets/downloadable_libraries.json

RUN uv run tools/generate_filemap.py --target_dir resources/character_info

COPY --from=gen-licenses-env --link /opt/voicevox_engine/licenses.json ./licenses.json
RUN cp ./licenses.json ./resources/engine_manifest_assets/dependency_licenses.json

ARG ENGINE_VERSION_FOR_CODE
RUN sed -i "s/\"version\": \"999\\.999\\.999\"/\"version\": \"${ENGINE_VERSION_FOR_CODE}\"/" engine_manifest.json
RUN sed -i "s/__version__ = \"latest\"/__version__ = \"${ENGINE_VERSION_FOR_CODE}\"/" voicevox_engine/__init__.py

RUN uv sync --group build
RUN --mount=target=/tmp/voicevox_onnxruntime/,source=/opt/voicevox_onnxruntime,from=extract-onnxruntime \
  --mount=target=/tmp/voicevox_core/,source=/opt/voicevox_core,from=extract-core \
  --mount=target=/tmp/vvms/,source=/vvm/vvms,from=download-vvm \
  uv run -m PyInstaller --noconfirm run.spec -- \
  --libcore_path=/tmp/voicevox_core/lib/libvoicevox_core.so \
  --libonnxruntime_path=/tmp/voicevox_onnxruntime/lib/libvoicevox_onnxruntime.so \
  --core_model_dir_path=/tmp/vvms

# WORKAROUND
RUN patchelf --add-rpath '$ORIGIN/engine_internal' ./dist/run/run


FROM scratch AS cpu-package
COPY --from=build-engine --link /opt/voicevox_engine/dist/run /


FROM ${CUDA_IMAGE} AS cuda-image


FROM ${BUILD_IMAGE} AS gather-cuda-lib
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y patchelf

RUN --mount=target=/tmp/cuda,source=/usr/local/cuda/lib64,from=cuda-image <<EOF
# Copy cuda
cp -P /tmp/cuda/libcublas.so.* .
cp -P /tmp/cuda/libcublasLt.so.* .
cp -P /tmp/cuda/libcudart.so.* .
cp -P /tmp/cuda/libcufft.so.* .
EOF

RUN --mount=target=/tmp/cudnn,source=/opt/cudnn/lib,from=extract-cudnn <<EOF
# Copy cudnn
cp -P /tmp/cudnn/libcudnn.so.* .
cp -P /tmp/cudnn/libcudnn_*_infer.so.* .
EOF

COPY --from=extract-onnxruntime --link /opt/voicevox_onnxruntime/lib/libvoicevox_onnxruntime_*.so .
RUN patchelf --set-rpath '$ORIGIN' /work/libvoicevox_onnxruntime_providers_*.so


FROM cpu-package AS cuda-package
COPY --from=gather-cuda-lib --link /work /


FROM ${RUNTIME_ACCELERATION}-package AS package


FROM ${RUNTIME_IMAGE} AS runtime-env

COPY --from=busybox:stable-uclibc --link /bin/busybox /busybox/busybox
RUN ["/busybox/busybox", "mkdir", "-m", "1777", "-p", "/opt/setting"]
RUN ["/busybox/busybox", "adduser", "-D", "-H", "user"]

COPY --chmod=755 --link <<EOF /opt/entrypoint.sh
#!/busybox/busybox sh
/busybox/busybox set -eu

# Display README for engine
/busybox/busybox cat /opt/README.md >&2

exec /opt/voicevox_engine/run "\$@"
EOF
COPY --from=checkout-resource --link /engine/README.md /opt/README.md
COPY --from=package --link / /opt/voicevox_engine

ENV XDG_DATA_HOME=/opt/setting
ENV VV_HOST=0.0.0.0
EXPOSE 50021
USER user
VOLUME ["${XDG_DATA_HOME}"]
ENTRYPOINT ["/opt/entrypoint.sh"]


FROM runtime-env AS runtime-cuda-env

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute
ENV NVIDIA_REQUIRE_CUDA=cuda>=12.4
ENV VV_USE_GPU=1


FROM runtime-env AS runtime-cpu-env
