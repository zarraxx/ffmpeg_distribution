#!/bin/bash
set -e

ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"
ARCH=`uname -m`

if [ "$ARCH" = "arm64" ]; then
    ARCH="aarch64"
fi

WORKSPACE=$ROOT/build/workspace
ARCHIVE_DIR=$ROOT/archive
DEST_DIR=$ROOT/dist/darwin-$ARCH
OUTPUT_DIR=$ROOT/out

mkdir -p $DEST_DIR
mkdir -p $OUTPUT_DIR
rm -rf $WORKSPACE
mkdir -p $WORKSPACE
mkdir -p $ARCHIVE_DIR

export BUILD_DIR=$WORKSPACE
export DEST_DIR=$DEST_DIR
export ARCHIVE_DIR=$ARCHIVE_DIR

ls -la $ARCHIVE_DIR

echo "Building for macOS $ARCH"
export PATH="$HOME/.local/cmake/cmake-3.27.9-macos-universal/CMake.app/Contents/bin:$PATH"
cmake --version

chmod +x $ROOT/script/ffmpeg_darwin.sh
$ROOT/script/ffmpeg_darwin.sh
tar -czvf $OUTPUT_DIR/ffmpeg-darwin-$ARCH.tar.gz -C "$(dirname "$DEST_DIR")" "$(basename "$DEST_DIR")"