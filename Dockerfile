# syntax=docker/dockerfile:1

ARG BUILD_IMAGE=ubuntu:22.04
ARG RUNTIME_IMAGE=gcr.io/distroless/base-nossl-debian13

ARG CORE_VERSION=0.16.2
ARG RUNTIME_VERSION=1.17.3
ARG RUNTIME_ACCELERATION=cpu
ARG RESOURCE_VERSION=0.25.0
ARG VVM_VERSION=0.16.1

ARG CUDART_VERSION=12.2.128
ARG CUBLAS_VERSION=12.2.4.5
ARG CUFFT_VERSION=11.0.8.91
ARG CUDNN_VERSION=8.9.7.29

ARG ENGINE_VERSION

FROM scratch AS checkout-resource
ARG RESOURCE_VERSION
ADD https://github.com/VOICEVOX/voicevox_resource.git#${RESOURCE_VERSION} .


FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS download-vvm
WORKDIR /vvm

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y ca-certificates jq wget

ARG VVM_VERSION
RUN <<EOF
#!/bin/bash
set -euxo pipefail
wget --no-verbose --tries=3 --output-document=- https://api.github.com/repos/VOICEVOX/voicevox_vvm/releases/tags/${VVM_VERSION} | \
  jq --raw-output '.assets[]|select(.name|test("^n.*\\.vvm$")|not).browser_download_url' | \
  wget --no-verbose --tries=3 --input-file=-
EOF
RUN mkdir ./vvms
RUN mv ./*.vvm ./vvms/


FROM scratch AS download-runtime-cpu-amd64
ARG RUNTIME_VERSION
ADD --unpack=true \
  --checksum=sha256:72b5287fdd48dc833a9929f6e9e3826e793b54ce1202181be93f63823a222f58 \
  https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-x64-${RUNTIME_VERSION}.tgz .


FROM scratch AS download-runtime-cpu-arm64
ARG RUNTIME_VERSION
ADD --unpack=true \
  --checksum=sha256:276eedc007b694324f59bc35c2cf9041724eb786608437a649f096edea3943a9 \
  https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-arm64-${RUNTIME_VERSION}.tgz .


FROM scratch AS download-runtime-cuda-amd64
ARG RUNTIME_VERSION
ADD --unpack=true \
  --checksum=sha256:c836e110d4eb68c9b45f7e05e2ef86931e6edaee71e27bbe1cf2c6da52b17ee2 \
  https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-x64-cuda-${RUNTIME_VERSION}.tgz .


FROM download-runtime-${RUNTIME_ACCELERATION}-${TARGETARCH} AS download-runtime


FROM scratch AS download-core-amd64
ARG CORE_VERSION
ADD --checksum=sha256:2eba5c17f6dda1628f9673e3fbed69fe5dc5c49dc709c9bcad0caa3542dfe249 \
  https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-linux-x64-${CORE_VERSION}.zip \
  voicevox_core.zip


FROM scratch AS download-core-arm64
ARG CORE_VERSION
ADD --checksum=sha256:03697bc2734017bdf0d6fbc8bae75d24601d567eb015f114d953539798a30e95 \
  https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-linux-arm64-${CORE_VERSION}.zip \
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
  unzip /tmp/voicevox_core.zip && \
  mv voicevox_core-linux-* /opt/voicevox_core


FROM scratch AS download-cuda-lib-amd64

ARG BASE_URL=developer.download.nvidia.com/compute
ARG CUDART_VERSION
ADD --link --unpack=true \
  --checksum=sha256:915a52fd0798d63ab49eda08232c02a394488b37e2c46633b755c9a49131ca71 \
  https://${BASE_URL}/cuda/redist/cuda_cudart/linux-x86_64/cuda_cudart-linux-x86_64-${CUDART_VERSION}-archive.tar.xz /cudart

ARG CUBLAS_VERSION
ADD --link --unpack=true \
  --checksum=sha256:739719b7b9a464b37f0587ccd5c4f39a83d53f642cdcaad48a7dd59e5e4c0930 \
  https://${BASE_URL}/cuda/redist/libcublas/linux-x86_64/libcublas-linux-x86_64-${CUBLAS_VERSION}-archive.tar.xz /cublas

ARG CUFFT_VERSION
ADD --link --unpack=true \
  --checksum=sha256:2ba28ab14eb42002cfa188be8191d4ba77b4ccefebc1c316e836845cd87e6a56 \
  https://${BASE_URL}/cuda/redist/libcufft/linux-x86_64/libcufft-linux-x86_64-${CUFFT_VERSION}-archive.tar.xz /cufft

ARG CUDNN_VERSION
ADD --link --unpack=true \
  --checksum=sha256:475333625c7e42a7af3ca0b2f7506a106e30c93b1aa0081cd9c13efb6e21e3bb \
  https://${BASE_URL}/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-${CUDNN_VERSION}_cuda12-archive.tar.xz /cudnn


FROM download-cuda-lib-${TARGETARCH} AS download-cuda-lib


FROM scratch AS checkout-engine

ARG ENGINE_VERSION=master
ADD --link \
  --exclude=.github \
  --exclude=docs \
  --exclude=test \
  --exclude=.gitattributes \
  --exclude=.gitignore \
  --exclude=.pre-commit-config.yaml \
  --exclude=CONTRIBUTING.md \
  --exclude=Dockerfile \
  --exclude=README.md \
  https://github.com/VOICEVOX/voicevox_engine.git#${ENGINE_VERSION} .


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

RUN --mount=target=/tmp/uv.lock,source=/uv.lock,from=checkout-engine <<EOF
# Download Python
set -eux
PYTHON_VERSION=$(sed -En 's/requires-python.*"==(.*)".*/\1/p' /tmp/uv.lock)
wget --no-verbose --tries=3 --output-document=- \
  https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz | \
  tar -x -J -f - --strip-components 1
EOF

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
  LDFLAGS='-Wl,--strip-all,-rpath,\$$ORIGIN/../lib'
make -j "$(nproc)" --silent
make install --silent
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
COPY --from=build-python --link /opt/python /opt/python
ENV PATH=/opt/uv/bin:$PATH
ENV UV_CACHE_DIR=/tmp/uv-cache/
ENV UV_LINK_MODE=copy

ARG BUILD_IMAGE
ARG UV_CACHE_ID=uv-cache-${BUILD_IMAGE}
RUN --mount=type=cache,id=${UV_CACHE_ID},target=/tmp/uv-cache \
  --mount=target=pyproject.toml,source=/pyproject.toml,from=checkout-engine \
  --mount=target=uv.lock,source=/uv.lock,from=checkout-engine \
  uv sync --locked --no-progress --python=/opt/python/bin/python3
RUN uv run python -c "import pyopenjtalk; pyopenjtalk._lazy_init()"

# Copy Engine files
COPY --from=checkout-engine --link / /opt/voicevox_engine


FROM build-env AS generate-licenses
RUN --mount=type=cache,id=${UV_CACHE_ID},target=/tmp/uv-cache \
  OUTPUT_LICENSE_JSON_PATH=/opt/voicevox_engine/licenses.json \
  bash tools/create_venv_and_generate_licenses.bash


FROM build-env AS build-engine

# Fix version
ARG ENGINE_VERSION=latest
RUN sed -i "s/\"version\": \"999\\.999\\.999\"/\"version\": \"${ENGINE_VERSION}\"/" engine_manifest.json
RUN sed -i "s/__version__ = \"latest\"/__version__ = \"${ENGINE_VERSION}\"/" voicevox_engine/__init__.py

# Process resource
RUN --mount=target=/tmp/resource,source=/,from=checkout-resource \
  DOWNLOAD_RESOURCE_PATH="/tmp/resource" bash tools/process_voicevox_resource.bash
RUN unlink ./resources/engine_manifest_assets/downloadable_libraries.json

# Generate filemap
RUN uv run tools/generate_filemap.py --target_dir resources/character_info

COPY --from=generate-licenses --link /opt/voicevox_engine/licenses.json ./licenses.json
RUN cp ./licenses.json ./resources/engine_manifest_assets/dependency_licenses.json

# Run PyInstaller
RUN --mount=type=cache,id=${UV_CACHE_ID},target=/tmp/uv-cache \
  uv sync --group build --no-progress
RUN --mount=target=/tmp/vvms,source=/vvm/vvms,from=download-vvm \
  --mount=type=tmpfs,target=/opt/voicevox_engine/build \
  uv run -m PyInstaller --noconfirm run.spec -- --core_model_dir_path=/tmp/vvms

# WORKAROUND
RUN patchelf --add-rpath '$ORIGIN/engine_internal' ./dist/run/run


FROM scratch AS cpu-package
COPY --from=build-engine --link /opt/voicevox_engine/dist/run /
COPY --from=download-runtime --chown=0 --link /*/lib/libvoicevox_onnxruntime.so /libvoicevox_onnxruntime.so
COPY --from=extract-core --chown=0 --link /opt/voicevox_core/lib/libvoicevox_core.so /libvoicevox_core.so


FROM ${BUILD_IMAGE} AS gather-cuda-lib
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y patchelf

RUN --mount=target=/tmp,source=/,from=download-cuda-lib <<EOF
cp -P /tmp/cudart/*/lib/libcudart.so.* .
cp -P /tmp/cublas/*/lib/libcublas.so.* .
cp -P /tmp/cublas/*/lib/libcublasLt.so.* .
cp -P /tmp/cufft/*/lib/libcufft.so.* .
cp -P /tmp/cudnn/*/lib/libcudnn.so.* .
cp -P /tmp/cudnn/*/lib/libcudnn_*_infer.so.* .
EOF

COPY --from=download-runtime --chown=0 --link /*/lib/libvoicevox_onnxruntime_providers_*.so ./
RUN patchelf --set-rpath '$ORIGIN' /work/libvoicevox_onnxruntime_providers_*.so


FROM cpu-package AS cuda-package
COPY --from=gather-cuda-lib --link /work /


FROM ${RUNTIME_ACCELERATION}-package AS package


FROM ${BUILD_IMAGE} AS build-entrypoint
WORKDIR /work

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
  gcc \
  libc6-dev \
  make

COPY --link entrypoint .

RUN SOURCE_DATE_EPOCH=0 make --silent


FROM ${RUNTIME_IMAGE} AS runtime-env

ADD --link rootfs.tar /
COPY --from=build-entrypoint --link /work/entrypoint /opt/entrypoint

COPY --from=checkout-resource --link /engine/README.md /opt/README.md
COPY --from=package --link / /opt/voicevox_engine

ENV XDG_DATA_HOME=/opt/setting
ENV VV_HOST=0.0.0.0
EXPOSE 50021
USER 65532
VOLUME ["${XDG_DATA_HOME}"]
ENTRYPOINT ["/opt/entrypoint", "/opt/README.md", "/opt/voicevox_engine/run"]


FROM runtime-env AS runtime-cuda-env

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute
ENV VV_USE_GPU=1


FROM runtime-env AS runtime-cpu-env
