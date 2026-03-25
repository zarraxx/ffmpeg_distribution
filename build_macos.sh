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

PACKAGE_SUFFIX_PART=""
if [ -n "$PACKAGE_SUFFIX" ]; then
    PACKAGE_SUFFIX_PART="-$PACKAGE_SUFFIX"
fi

tar -czvf $OUTPUT_DIR/ffmpeg-darwin-${ARCH}${PACKAGE_SUFFIX_PART}.tar.gz -C "$(dirname "$DEST_DIR")" "$(basename "$DEST_DIR")"

DEMO_BUILD_DIR=$ROOT/build/example-darwin-$ARCH
echo "Building examples with CMake..."
cmake -S $ROOT/example -B $DEMO_BUILD_DIR -DFFMPEG_ROOT=$DEST_DIR/ffmpeg -DCMAKE_BUILD_TYPE=Release
cmake --build $DEMO_BUILD_DIR --parallel
echo "audio_convert demo built at: $DEMO_BUILD_DIR/bin/audio_convert"
echo "video_convert demo built at: $DEMO_BUILD_DIR/bin/video_convert"

echo "Installing system ffmpeg for example tests..."
brew install ffmpeg

chmod +x $ROOT/example/audio_convert/test_audio_convert.sh
chmod +x $ROOT/example/video_convert/test_video_convert.sh

echo "Running audio_convert tests..."
$ROOT/example/audio_convert/test_audio_convert.sh $DEMO_BUILD_DIR/bin/audio_convert $ROOT/build/audio_convert-test-darwin-$ARCH

echo "Running video_convert tests..."
$ROOT/example/video_convert/test_video_convert.sh $DEMO_BUILD_DIR/bin/video_convert $ROOT/build/video_convert-test-darwin-$ARCH
