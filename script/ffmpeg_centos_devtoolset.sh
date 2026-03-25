#!/bin/bash
set -e
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"

yum install -y \
    devtoolset-10-gcc \
    devtoolset-10-gcc-c++ \
    devtoolset-10-binutils \
    && yum clean all

source /opt/rh/rh-python38/enable
source /opt/rh/devtoolset-10/enable

export PATH=/opt/x-tools/utils/bin:$PATH

# Build a Linux SDK that can be linked outside the CentOS container.
# x264/x265 enable -ffast-math by default, which pulls in glibc __*_finite
# symbols and makes the static SDK fragile when used on the host toolchain.
# We also link these static FFmpeg libs into our own shared test library, so
# FFmpeg's asm objects need to be disabled for a consistently PIC-safe SDK.
export X264_CMAKE_EXTRA='--extra-cflags=-fno-fast-math -fno-finite-math-only -fno-unsafe-math-optimizations'
export FFMPEG_CONFIG_EXTRA="--disable-asm"


export BUILD_DIR=/workspace/build
export DEST_DIR=/opt/x-tools/dist/ffmpeg
export ARCHIVE_DIR=/workspace/archive

mkdir -p ${BUILD_DIR}
mkdir -p ${DEST_DIR}
mkdir -p ${ARCHIVE_DIR}

source $ROOT/ffmpeg.sh


build_lame
build_ogg
build_vorbis
build_opus
build_x264

export X265_CMAKE_EXTRA="-DENABLE_ASSEMBLY=OFF -DCC_HAS_FAST_MATH=FALSE"
if [ "$(uname -m)" = "aarch64" ]; then
 
  export FFMPEG_CONFIG_EXTRA="$FFMPEG_CONFIG_EXTRA --disable-neon"
fi

build_x265
build_dav1d
build_ffmpeg
