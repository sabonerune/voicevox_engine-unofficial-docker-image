variable "TAG_PREFIX" {
  default = "voicevox_engine-unofficial-docker-image"
}

variable "ENGINE_VERSION" {
}

variable "TAG_ENGINE_VERSION" {
  default = equal(ENGINE_VERSION, "") ? "dev" : ENGINE_VERSION
}

group "default" {
  targets = ["cpu", "cuda"]
}

target "_common" {
  args = {
    ENGINE_VERSION = equal(ENGINE_VERSION, "") ? null : ENGINE_VERSION
  }
}

target "cpu" {
  inherits = ["_common"]
  platforms = ["linux/amd64", "linux/arm64"]
  target = "runtime-cpu-env"
  tags = ["${TAG_PREFIX}:cpu-${TAG_ENGINE_VERSION}"]
}

target "cuda" {
  inherits = ["_common"]
  args = {
    RUNTIME_ACCELERATION="cuda"
  }
  target = "runtime-cuda-env"
  tags = ["${TAG_PREFIX}:cuda-${TAG_ENGINE_VERSION}"]
}

target "package" {
  name = "${acceleration}-package"
  matrix = {
    "acceleration" = ["cpu", "cuda"]
  }
  inherits = ["${acceleration}"]
  target = "package"
  output = [
    {
      type = "local"
      dest = "dist/voicevox_engine-linux-${acceleration}-${TAG_ENGINE_VERSION}"
    }
  ]
}
