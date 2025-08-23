# Nimble package file for denarocudaminer
version       = "0.1.0"
author        = "connor33341"
license       = "MIT"
description   = "Denaro CUDA miner manager and helper"
requires "nim >= 1.6.0"
# Runtime dependencies
deps = @[
  "nimcrypto",
  #"nbaser" # they say, why do you hate? I answer, base58 on nim
]

# No build action required here; compile.sh handles building


*** End of File
