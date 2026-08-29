#!/bin/bash
set -euo pipefail

# Download script for ONNX Runtime v1.24.2 Linux & Windows x64 binaries

VERSION="1.24.2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LINUX_X64_DIR="${ROOT_DIR}/pipecat_smart_turn_linux/linux/x64"
WINDOWS_X64_DIR="${ROOT_DIR}/pipecat_smart_turn_windows/windows/x64"

mkdir -p "${LINUX_X64_DIR}"
mkdir -p "${WINDOWS_X64_DIR}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# --- Linux x64 ---
if [ ! -f "${LINUX_X64_DIR}/libonnxruntime.so.1.24.2" ]; then
    echo "Fetching Linux x64 ONNX Runtime v${VERSION}..."
    LINUX_TAR="onnxruntime-linux-x64-${VERSION}.tgz"
    curl -sSL "https://github.com/microsoft/onnxruntime/releases/download/v${VERSION}/${LINUX_TAR}" -o "${TMP_DIR}/${LINUX_TAR}"
    tar -xzf "${TMP_DIR}/${LINUX_TAR}" -C "${TMP_DIR}"
    cp "${TMP_DIR}/onnxruntime-linux-x64-${VERSION}/lib/libonnxruntime.so.${VERSION}" "${LINUX_X64_DIR}/libonnxruntime.so.1.24.2"
    echo "Linux x64 binary installed at ${LINUX_X64_DIR}/libonnxruntime.so.1.24.2"
else
    echo "Linux x64 ONNX Runtime library already exists."
fi

# --- Windows x64 ---
if [ ! -f "${WINDOWS_X64_DIR}/onnxruntime.dll" ]; then
    echo "Fetching Windows x64 ONNX Runtime v${VERSION}..."
    WIN_ZIP="onnxruntime-win-x64-${VERSION}.zip"
    curl -sSL "https://github.com/microsoft/onnxruntime/releases/download/v${VERSION}/${WIN_ZIP}" -o "${TMP_DIR}/${WIN_ZIP}"
    unzip -q "${TMP_DIR}/${WIN_ZIP}" -d "${TMP_DIR}"
    cp "${TMP_DIR}/onnxruntime-win-x64-${VERSION}/lib/onnxruntime.dll" "${WINDOWS_X64_DIR}/onnxruntime.dll"
    echo "Windows x64 binary installed at ${WINDOWS_X64_DIR}/onnxruntime.dll"
else
    echo "Windows x64 ONNX Runtime library already exists."
fi

echo "ONNX Runtime native binaries setup complete."
