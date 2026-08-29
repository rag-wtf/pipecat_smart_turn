cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "pipecat_smart_turn_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "pipecat_smart_turn_windows_plugin.cpp"
  "include/pipecat_smart_turn_windows/pipecat_smart_turn_windows.h"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(X64_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/x64/onnxruntime.dll")
set(ARM64_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/arm64/onnxruntime.dll")

set(BUNDLED_LIBS)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
  if(NOT EXISTS "${ARM64_LIB_PATH}")
    message(FATAL_ERROR "ONNX Runtime library not found at ${ARM64_LIB_PATH}. Run scripts/download_onnxruntime.sh to fetch missing native binaries.")
  endif()
  list(APPEND BUNDLED_LIBS "${ARM64_LIB_PATH}")
else()
  # Default to x64
  if(NOT EXISTS "${X64_LIB_PATH}")
    message(FATAL_ERROR "ONNX Runtime library not found at ${X64_LIB_PATH}. Run scripts/download_onnxruntime.sh to fetch missing native binaries.")
  endif()
  list(APPEND BUNDLED_LIBS "${X64_LIB_PATH}")
endif()

set(pipecat_smart_turn_windows_bundled_libraries
  ${BUNDLED_LIBS}
  PARENT_SCOPE
)