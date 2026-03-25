#!/bin/bash
set -e
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"

export ARCHIVE_DIR=~/archive
mkdir -p $ARCHIVE_DIR

source $ROOT/script/ffmpeg.sh


download_file "lame-$LAME_VERSION.tar.gz"
download_file "libogg-$OGG_VERSION.tar.xz"
download_file "libvorbis-$VORBIS_VERSION.tar.xz"
download_file "opus-$OPUS_VERSION.tar.gz"

download_file "x264-$X264_VERSION.tar.bz2"
download_file "x265_$x265_VERSION.tar.gz"
download_file "dav1d-$AV1_VERSION.tar.xz"    
download_file "ffmpeg-$FFMPEG_VERSION.tar.xz"

