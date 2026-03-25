#!/bin/bash
set -e

ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"
ARCH=`uname -m`
WORKSPACE=$ROOT/build/workspace
ARCHIVE_DIR=$ROOT/archive
DEST_DIR=$ROOT/dist/windowx-x86_64
OUTPUT_DIR=$ROOT/out

mkdir -p $DEST_DIR
mkdir -p $OUTPUT_DIR
rm -rf $WORKSPACE
rm -rf "$DEST_DIR/ffmpeg"
mkdir -p $WORKSPACE
mkdir -p $ARCHIVE_DIR

export BUILD_DIR=$WORKSPACE
export DEST_DIR=$DEST_DIR
export ARCHIVE_DIR=$ARCHIVE_DIR
export CC=${CC:-gcc}
export CXX=${CXX:-g++}

ls -la $ARCHIVE_DIR

export PATH="/opt/cmake/cmake-3.27.9-windows-x86_64/bin:$PATH"
cmake --version

chmod +x $ROOT/script/ffmpeg_win32.sh
$ROOT/script/ffmpeg_win32.sh

PACKAGE_SUFFIX_PART=""
if [ -n "$PACKAGE_SUFFIX" ]; then
    PACKAGE_SUFFIX_PART="-$PACKAGE_SUFFIX"
fi

tar -czvf $OUTPUT_DIR/ffmpeg-windows-x86_64${PACKAGE_SUFFIX_PART}.tar.gz -C "$(dirname "$DEST_DIR")" "$(basename "$DEST_DIR")"

DEMO_BUILD_DIR=$ROOT/build/example-windows-x86_64
echo "Building examples with CMake..."
cmake -S $ROOT/example -B $DEMO_BUILD_DIR \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=$CC \
    -DFFMPEG_ROOT=$DEST_DIR/ffmpeg
cmake --build $DEMO_BUILD_DIR --parallel
echo "ffmpeg_example shared library built at: $DEMO_BUILD_DIR/bin/ffmpeg_example.dll"
echo "audio_convert demo built at: $DEMO_BUILD_DIR/bin/audio_convert.exe"
echo "video_convert demo built at: $DEMO_BUILD_DIR/bin/video_convert.exe"
echo "media_info demo built at: $DEMO_BUILD_DIR/bin/media_info.exe"

echo "Installing system ffmpeg for example tests..."
pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-ffmpeg

chmod +x $ROOT/example/audio_convert/test_audio_convert.sh
chmod +x $ROOT/example/video_convert/test_video_convert.sh

echo "Running audio_convert tests..."
$ROOT/example/audio_convert/test_audio_convert.sh $DEMO_BUILD_DIR/bin/audio_convert.exe $ROOT/build/audio_convert-test-windows-x86_64

echo "Running video_convert tests..."
$ROOT/example/video_convert/test_video_convert.sh $DEMO_BUILD_DIR/bin/video_convert.exe $ROOT/build/video_convert-test-windows-x86_64
