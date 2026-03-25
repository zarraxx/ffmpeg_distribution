cmake_minimum_required(VERSION 3.20)

project(audio_convert C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

if(NOT DEFINED FFMPEG_ROOT)
    if(WIN32)
        set(_ffmpeg_platform_dir "windowx-x86_64")
    elseif(APPLE)
        if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
            set(_ffmpeg_arch "aarch64")
        else()
            set(_ffmpeg_arch "${CMAKE_SYSTEM_PROCESSOR}")
        endif()
        set(_ffmpeg_platform_dir "darwin-${_ffmpeg_arch}")
    else()
        set(_ffmpeg_platform_dir "linux-${CMAKE_SYSTEM_PROCESSOR}")
    endif()

    set(FFMPEG_ROOT "${REPO_ROOT}/dist/${_ffmpeg_platform_dir}/ffmpeg" CACHE PATH "Path to the built FFmpeg SDK root")
endif()

if(NOT EXISTS "${FFMPEG_ROOT}/include")
    message(FATAL_ERROR "FFMPEG_ROOT does not contain include/: ${FFMPEG_ROOT}")
endif()

set(_pkgconfig_dirs)
if(EXISTS "${FFMPEG_ROOT}/lib/pkgconfig")
    list(APPEND _pkgconfig_dirs "${FFMPEG_ROOT}/lib/pkgconfig")
endif()
if(EXISTS "${FFMPEG_ROOT}/lib64/pkgconfig")
    list(APPEND _pkgconfig_dirs "${FFMPEG_ROOT}/lib64/pkgconfig")
endif()

if(NOT _pkgconfig_dirs)
    message(FATAL_ERROR "No pkgconfig directory found under ${FFMPEG_ROOT}")
endif()

if(WIN32)
    set(_path_sep ";")
else()
    set(_path_sep ":")
endif()

list(JOIN _pkgconfig_dirs "${_path_sep}" _pkgconfig_path)
if(DEFINED ENV{PKG_CONFIG_PATH} AND NOT "$ENV{PKG_CONFIG_PATH}" STREQUAL "")
    set(ENV{PKG_CONFIG_PATH} "${_pkgconfig_path}${_path_sep}$ENV{PKG_CONFIG_PATH}")
else()
    set(ENV{PKG_CONFIG_PATH} "${_pkgconfig_path}")
endif()

find_package(PkgConfig REQUIRED)
set(PKG_CONFIG_USE_CMAKE_PREFIX_PATH ON)
set(PKG_CONFIG_ARGN --static)
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
    libavformat
    libavcodec
    libswresample
    libavutil
)

add_executable(audio_convert main.c)
target_include_directories(audio_convert PRIVATE "${FFMPEG_ROOT}/include")
target_link_libraries(audio_convert PRIVATE PkgConfig::FFMPEG)

if(MSVC)
    target_compile_options(audio_convert PRIVATE /W4)
else()
    target_compile_options(audio_convert PRIVATE -Wall -Wextra -Wpedantic)
endif()
