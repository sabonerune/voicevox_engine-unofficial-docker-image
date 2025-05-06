variable "TAG_PREFIX" {
  default = "voicevox/voicevox_engine"
}

variable "ENGINE_VERSION" {
}

variable "TAG_ENGINE_VERSION" {
  default = notequal("",ENGINE_VERSION) ? ENGINE_VERSION : "dev"
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
  name = "cpu-${os.name}-${arch.name}"
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
    ],
    os = [
      {
        name = "ubuntu20"
        base_image = "mirror.gcr.io/ubuntu:20.04"
        tag = "ubuntu20.04"
      },
      {
        name = "ubuntu22"
        base_image = "mirror.gcr.io/ubuntu:22.04"
        tag = "ubuntu22.04"
      }
    ]
  }
  args = {
    BASE_IMAGE = os.base_image
    CORE_URL = core_url(arch.name, "cpu")
    RUNTIME_URL= runtime_url(arch.runtime, "cpu")
  }
  platforms = [arch.platform]
  tags = ["${TAG_PREFIX}:cpu-${os.tag}-${TAG_ENGINE_VERSION}"]
}

target "nvidia" {
  name = "nvidia-${os.name}"
  matrix = {
    os = [
      {
        name = "ubuntu20"
        base_image = "mirror.gcr.io/ubuntu:20.04"
        runtime_image = "mirror.gcr.io/nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu20.04"
        tag = "ubuntu20.04"
      },
      {
        name = "ubuntu22"
        base_image = "mirror.gcr.io/ubuntu:22.04"
        runtime_image = "mirror.gcr.io/nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04"
        tag = "ubuntu22.04"
      }
    ]
  }
  args = {
    BASE_IMAGE = os.base_image
    BASE_RUNTIME_IMAGE = os.runtime_image
    CORE_URL = core_url("x64", "gpu")
    RUNTIME_URL= runtime_url("x64", "gpu")
  }
  target = "runtime-nvidia-env"
  tags = ["${TAG_PREFIX}:nvidia-${os.tag}-${TAG_ENGINE_VERSION}"]
}
