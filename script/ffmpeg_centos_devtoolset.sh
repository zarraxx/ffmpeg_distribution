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
build_x265
build_dav1d
build_ffmpeg