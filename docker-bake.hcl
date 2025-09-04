variable "TAG_PREFIX" {
  default = "voicevox_engine-unofficial-docker-image"
}

variable "ENGINE_VERSION" {
}

variable "TAG_ENGINE_VERSION" {
  default = notequal("", ENGINE_VERSION) ? ENGINE_VERSION : "dev"
}

group "default" {
  targets = ["cpu", "nvidia"]
}

group "package" {
  targets = ["cpu-package", "nvidia-package"]
}

target "_common" {
  args = {
    ENGINE_VERSION = ENGINE_VERSION
  }
}

target "cpu" {
  inherits=["_common"]
  name = "cpu-${os.name}"
  matrix = {
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
  }
  platforms = ["linux/amd64", "linux/arm64"]
  target = "runtime-env"
  tags = ["${TAG_PREFIX}:cpu-${os.tag}-${TAG_ENGINE_VERSION}"]
}

target "nvidia" {
  inherits=["_common"]
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
    RUNTIME_ACCELERATION="cuda"
  }
  target = "runtime-nvidia-env"
  tags = ["${TAG_PREFIX}:nvidia-${os.tag}-${TAG_ENGINE_VERSION}"]
}

target "cpu-package" {
  inherits = ["cpu-ubuntu22"]
  target = "cpu-package"
  output = [
    {
      type = "local"
      dest = "dist/voicevox_engine-linux-cpu-${TAG_ENGINE_VERSION}"
    }
  ]
}

target "nvidia-package" {
  inherits = ["nvidia-ubuntu22"]
  target = "nvidia-package"
  output = [
    {
      type = "local"
      dest = "dist/voicevox_engine-linux-cuda-${TAG_ENGINE_VERSION}"
    }
  ]
}
