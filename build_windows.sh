#!/bin/bash
set -e

ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"
ARCH=`uname -m`
WORKSPACE=$ROOT/build/workspace
ARCHIVE_DIR=$ROOT/build/archive
DEST_DIR=$ROOT/dist/windowx-x64
OUTPUT_DIR=$ROOT/out

mkdir -p $DEST_DIR
mkdir -p $OUTPUT_DIR
rm -rf $WORKSPACE
rm -rf $ARCHIVE_DIR
mkdir -p $WORKSPACE
mkdir -p $ARCHIVE_DIR

export BUILD_DIR=$WORKSPACE
export DEST_DIR=$DEST_DIR
export ARCHIVE_DIR=$ARCHIVE_DIR

source $ROOT/script/ffmpeg.sh

build_lame
build_ogg

export VORBIS_CMAKE_EXTRA="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
build_vorbis
build_opus
build_x264
build_x265
build_dav1d
build_ffmpeg


tar -czvf $OUTPUT_DIR/ffmpeg-windows-x64.tar.gz -C $DEST_DIR .