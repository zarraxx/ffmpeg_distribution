#!/bin/bash
set -e
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"


export BUILD_DIR=$BUILD_DIR
export DEST_DIR=$DEST_DIR/ffmpeg
export ARCHIVE_DIR=$ARCHIVE_DIR

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