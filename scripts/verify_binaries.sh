#!/bin/bash
set -euo pipefail

# Verifies cryptographic checksums for all bundled native binaries and model assets.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -A EXPECTED_CHECKSUMS=(
  ["pipecat_smart_turn_platform_interface/assets/smart-turn-v3.2-cpu.onnx"]="2bb026316b14a660486a75b1733cd3fbab8c2fd0314dc9af7be49f8cca967e4f"
  ["pipecat_smart_turn_linux/linux/arm64/libonnxruntime.so.1.24.2"]="e18fe095919d8613ead3a31ff78212bde4fad929418a9b48f49d61c829ed5c82"
  ["pipecat_smart_turn_linux/linux/x64/libonnxruntime.so.1.24.2"]="ffc84d48e845cf0b562ba4ea5ca32aaafc0d4069019fef4f63095b307d0270ad"
  ["pipecat_smart_turn_windows/windows/arm64/onnxruntime.dll"]="d4c4d939c8bd1e93a86bc5a45b37a1fdd08dce34d8231db014a7e4a023923f5a"
  ["pipecat_smart_turn_windows/windows/x64/onnxruntime.dll"]="114947d633e6844ce3c4b51ef6678f776628571d08a5763859c61642c8dcca9c"
)

ERRORS=0

echo "Verifying third-party binary and model checksums against THIRD_PARTY.md..."

for REL_PATH in "${!EXPECTED_CHECKSUMS[@]}"; do
  FILE_PATH="${ROOT_DIR}/${REL_PATH}"
  EXPECTED="${EXPECTED_CHECKSUMS[$REL_PATH]}"
  
  if [ ! -f "${FILE_PATH}" ]; then
    echo "ERROR: Missing binary file: ${REL_PATH}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  ACTUAL=$(sha256sum "${FILE_PATH}" | awk '{print $1}')
  if [ "${ACTUAL}" != "${EXPECTED}" ]; then
    echo "ERROR: Checksum mismatch for ${REL_PATH}"
    echo "  Expected: ${EXPECTED}"
    echo "  Actual:   ${ACTUAL}"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK: ${REL_PATH}"
  fi
done

if [ ${ERRORS} -ne 0 ]; then
  echo "Verification failed with ${ERRORS} error(s)."
  exit 1
fi

echo "All third-party binaries and models verified successfully."
