#!/bin/bash
set -e
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"


export BUILD_DIR=$BUILD_DIR

export DEST_DYNAMIC_DIR=$DEST_DIR/ffmpeg-dynamic
export DEST_STATIC_DIR=$DEST_DIR//ffmpeg-static

export ARCHIVE_DIR=$ARCHIVE_DIR

mkdir -p ${BUILD_DIR}
mkdir -p ${DEST_DYNAMIC_DIR}
mkdir -p ${DEST_STATIC_DIR}

mkdir -p ${ARCHIVE_DIR}

source $ROOT/ffmpeg.sh

normalize_darwin_dependency_ids() {
    local lib_dir="$DEST_DYNAMIC_DIR/lib"
    local dylib
    local real_dylib
    local dylib_name

    [ -d "$lib_dir" ] || return 0

    find "$lib_dir" -type f -name '*.dylib' | while IFS= read -r dylib; do
        dylib_name="$(basename "$dylib")"

        case "$dylib_name" in
            libav*.dylib|libsw*.dylib)
                continue
                ;;
        esac

        install_name_tool -id "@rpath/$dylib_name" "$dylib"
    done
}


build_lame
build_ogg
build_vorbis
build_opus
build_x264
build_x265
build_dav1d

normalize_darwin_dependency_ids
export FFMPEG_DYNAMIC_CONFIG_EXTRA="--install-name-dir='@rpath' "
build_ffmpeg