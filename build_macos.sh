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
rm -rf "$DEST_DIR/ffmpeg-static" "$DEST_DIR/ffmpeg-shared"
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

source $ROOT/script/ffmpeg_test.sh
DEMO_BUILD_DIR=$ROOT/build/example-darwin-$ARCH
rm -rf ${DEMO_BUILD_DIR}
build_example $ROOT/example ${DEMO_BUILD_DIR}/static $DEST_DIR/ffmpeg-static
build_example $ROOT/example ${DEMO_BUILD_DIR}/shared $DEST_DIR/ffmpeg-shared

echo "Installing system ffmpeg for example tests..."
brew install ffmpeg

echo "Running example tests with static ffmpeg..."
run_example $ROOT/example ${DEMO_BUILD_DIR}/static

echo "Running example tests with shared ffmpeg..."
export FFMPEG_EXAMPLE_LD_LIBRARY_PATH="$DEST_DIR/ffmpeg-shared/lib:$DEST_DIR/ffmpeg-shared/lib64"
export FFMPEG_EXAMPLE_DYLD_LIBRARY_PATH="$FFMPEG_EXAMPLE_LD_LIBRARY_PATH"
run_example $ROOT/example ${DEMO_BUILD_DIR}/shared

echo "Example tests completed successfully!"

echo "Checking shared library dependencies with otool..."
dyld_info -dependents $DEST_DIR/ffmpeg-shared/bin/ffmpeg_custom

echo "Checking rpath with otool..."
otool -l $DEST_DIR/ffmpeg-shared/bin/ffmpeg_custom | grep -A2 LC_RPATH


echo "Running ffmpeg_custom with DYLD_PRINT_LIBRARIES=1 to verify shared libraries are loaded correctly..."
DYLD_PRINT_LIBRARIES=1 $DEST_DIR/ffmpeg-shared/bin/ffmpeg_custom -version

echo "All checks passed successfully!"
