variable "TAG_PREFIX" {
  default = "voicevox/voicevox_engine"
}

variable "ENGINE_VERSION" {
}

variable "TAG_ENGINE_VERSION" {
  default = notequal("",ENGINE_VERSION) ? ENGINE_VERSION : "dev"
}

variable "CORE_VERSION" {
  default = "0.16.0"
}

variable "RUNTIME_VERSION" {
  default = "1.17.3"
}

function "core_url" {
  params = [arch]
  result = "https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-linux-${arch}-${CORE_VERSION}.zip"
}

function "runtime_url" {
  params = [arch, acceleration]
  result = "https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${RUNTIME_VERSION}/voicevox_onnxruntime-linux-${arch}-${notequal("cpu", acceleration)?"${acceleration}-":""}${RUNTIME_VERSION}.tgz"
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
        runtime = "arm64"
        platform = "linux/arm64"
      }
    ],
    os = [
      {
        name = "ubuntu22"
        base_image = "mirror.gcr.io/ubuntu:22.04"
        tag = "ubuntu22.04"
      }
    ]
  }
  args = {
    BASE_IMAGE = os.base_image
    CORE_URL = core_url(arch.name)
    RUNTIME_URL= runtime_url(arch.runtime, "cpu")
  }
  platforms = [arch.platform]
  target = "runtime-env"
  tags = ["${TAG_PREFIX}:cpu-${os.tag}-${TAG_ENGINE_VERSION}"]
}

target "nvidia" {
  name = "nvidia-${os.name}"
  matrix = {
    os = [
      {
        name = "ubuntu22"
        base_image = "mirror.gcr.io/ubuntu:22.04"
        runtime_image = "mirror.gcr.io/nvidia/cuda:12.4.1-runtime-ubuntu22.04"
        tag = "ubuntu22.04"
      }
    ]
  }
  args = {
    BASE_IMAGE = os.base_image
    BASE_RUNTIME_IMAGE = os.runtime_image
    CORE_URL = core_url("x64")
    RUNTIME_URL= runtime_url("x64", "cuda")
  }
  target = "runtime-nvidia-env"
  tags = ["${TAG_PREFIX}:nvidia-${os.tag}-${TAG_ENGINE_VERSION}"]
}

target "cpu-package-x64" {
  inherits = ["cpu-ubuntu22-x64"]
  target = "cpu-package"
  output = [
    {
      type = "local"
      dest = "dist/voicevox_engine-linux-cpu-x64-${TAG_ENGINE_VERSION}"
    }
  ]
}

target "cpu-package-arm64" {
  inherits = ["cpu-ubuntu22-arm64"]
  target = "cpu-package"
  output = [
    {
      type = "local"
      dest = "dist/voicevox_engine-linux-cpu-arm64-${TAG_ENGINE_VERSION}"
    }
  ]
}

target "nvidia-package" {
  inherits = ["nvidia-ubuntu22"]
  target = "nvidia-package"
  output = [
    {
      type = "local"
      dest = "dist/voicevox_engine-linux-cuda-x64-${TAG_ENGINE_VERSION}"
    }
  ]
}
