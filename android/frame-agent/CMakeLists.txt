cmake_minimum_required(VERSION 3.22)

project(DroidHatch.FrameAgent LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(droidhatch-frame-agent
    src/agent_io.cpp
    src/agent_runtime.cpp
    src/audio_protocol.cpp
    src/audio_server.cpp
    src/agent_options.cpp
    src/agent_socket.cpp
    src/android_runtime_status.cpp
    src/frame_protocol.cpp
    src/hwcomposer_capture.cpp
    src/hwcomposer_diagnostics.cpp
    src/input_protocol.cpp
    src/input_key_mapping.cpp
    src/input_server.cpp
    src/main.cpp
    src/redroid_buffer.cpp
    src/synthetic_frame.cpp
    src/uinput_devices.cpp)

target_include_directories(droidhatch-frame-agent PRIVATE include)

target_compile_options(droidhatch-frame-agent PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Werror)

if(ANDROID)
    target_link_libraries(droidhatch-frame-agent PRIVATE log)
endif()
