variable "TAG_PREFIX" {
  default = "voicevox/voicevox_engine"
}

variable "ENGINE_VERSION" {
  default = "0.23.0"
}

variable "CORE_VERSION" {
  default = "0.15.7"
}

variable "RUNTIME_VERSION" {
  default = "1.13.1"
}

function "core_url" {
  params = [arch, acceleration]
  result = "https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-linux-${arch}-${acceleration}-${CORE_VERSION}.zip"
}

function "runtime_url" {
  params = [arch, acceleration]
  result = "https://github.com/microsoft/onnxruntime/releases/download/v${RUNTIME_VERSION}/onnxruntime-linux-${arch}-${notequal("cpu",acceleration) ? "${acceleration}-": ""}${RUNTIME_VERSION}.tgz"
}

group "default" {
  targets = ["cpu", "nvidia"]
}

target "_common" {
  args = {
    ENGINE_VERSION = ENGINE_VERSION
  }
}

target "cpu" {
  name = "cpu-${arch.name}"
  matrix = {
    arch = [
      {
        name="x64"
        runtime = "x64"
        platform = "linux/amd64"
      },
      {
        name="arm64"
        runtime = "aarch64"
        platform = "linux/arm64"
      }
    ]
  }
  args = {
    "CORE_URL" = core_url(arch.name, "cpu")
    "RUNTIME_URL"= runtime_url(arch.runtime, "cpu")
  }
  platforms = [arch.platform]
  tags = ["${TAG_PREFIX}:cpu-ubuntu20.04-${ENGINE_VERSION}"]
}

target "nvidia" {
  args = {
    BASE_RUNTIME_IMAGE = "mirror.gcr.io/nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu20.04"
    "CORE_URL" = core_url("x64", "gpu")
    "RUNTIME_URL"= runtime_url("x64", "gpu")
  }
  target = "runtime-nvidia-env"
  tags = ["${TAG_PREFIX}:nvidia-ubuntu20.04-${ENGINE_VERSION}"]
}
