# Third-Party Assets & Binaries Provenance

This document records the provenance, upstream source URLs, versions, and cryptographic hashes (SHA-256) for all pre-built native binaries and machine learning models bundled with the `pipecat_smart_turn` package suite.

## ONNX Runtime Binaries (v1.24.2)

Upstream release: [microsoft/onnxruntime v1.24.2](https://github.com/microsoft/onnxruntime/releases/tag/v1.24.2)
License: MIT

| Platform | Architecture | File Path | Upstream Archive | SHA-256 Checksum |
|---|---|---|---|---|
| Linux | x86_64 | `pipecat_smart_turn_linux/linux/x64/libonnxruntime.so.1.24.2` | `onnxruntime-linux-x64-1.24.2.tgz` | `ffc84d48e845cf0b562ba4ea5ca32aaafc0d4069019fef4f63095b307d0270ad` |
| Linux | aarch64 (ARM64) | `pipecat_smart_turn_linux/linux/arm64/libonnxruntime.so.1.24.2` | `onnxruntime-linux-aarch64-1.24.2.tgz` | `e18fe095919d8613ead3a31ff78212bde4fad929418a9b48f49d61c829ed5c82` |
| Windows | x86_64 (x64) | `pipecat_smart_turn_windows/windows/x64/onnxruntime.dll` | `onnxruntime-win-x64-1.24.2.zip` | `114947d633e6844ce3c4b51ef6678f776628571d08a5763859c61642c8dcca9c` |
| Windows | arm64 (ARM64) | `pipecat_smart_turn_windows/windows/arm64/onnxruntime.dll` | `onnxruntime-win-arm64-1.24.2.zip` | `d4c4d939c8bd1e93a86bc5a45b37a1fdd08dce34d8231db014a7e4a023923f5a` |

## Model Assets

Upstream source: [Pipecat AI Smart Turn Model](https://github.com/pipecat-ai/pipecat)
Model version: `smart-turn-v3.2-cpu.onnx`
License: Apache-2.0 / BSD-2-Clause compatible

| Model File | File Path | Size | SHA-256 Checksum |
|---|---|---|---|
| `smart-turn-v3.2-cpu.onnx` | `pipecat_smart_turn_platform_interface/assets/smart-turn-v3.2-cpu.onnx` | 8,720,830 bytes | `2bb026316b14a660486a75b1733cd3fbab8c2fd0314dc9af7be49f8cca967e4f` |
