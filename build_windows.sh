#!/bin/bash
set -ex

ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"
ARCH=`uname -m`
WORKSPACE=$ROOT/build/workspace
ARCHIVE_DIR=$ROOT/archive
DEST_DIR=$ROOT/dist/windowx-x86_64
OUTPUT_DIR=$ROOT/out

mkdir -p $DEST_DIR
mkdir -p $OUTPUT_DIR
rm -rf $WORKSPACE
rm -rf "$DEST_DIR/ffmpeg*"
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


copy_windows_runtime_dlls() {
    local target_dir=$1
    local runtime_dll
    local runtime_path

    for runtime_dll in libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll; do
        runtime_path="/ucrt64/bin/${runtime_dll}"
        if [ -n "$runtime_path" ] && [ -f "$runtime_path" ]; then
            cp -f "$runtime_path" "$target_dir/"
        fi
    done
}
copy_windows_runtime_dlls "$DEST_DIR/ffmpeg-dynamic/bin"

PACKAGE_SUFFIX_PART=""
if [ -n "$PACKAGE_SUFFIX" ]; then
    PACKAGE_SUFFIX_PART="-$PACKAGE_SUFFIX"
fi


tar -czvf $OUTPUT_DIR/ffmpeg-windows-x86_64${PACKAGE_SUFFIX_PART}.tar.gz -C "$(dirname "$DEST_DIR")" "$(basename "$DEST_DIR")"


source $ROOT/script/ffmpeg_test.sh
DEMO_BUILD_DIR=$ROOT/build/example-windows-x86_64
rm -rf $DEMO_BUILD_DIR
build_example $ROOT/example ${DEMO_BUILD_DIR}/static $DEST_DIR/ffmpeg-static
build_example $ROOT/example ${DEMO_BUILD_DIR}/dynamic $DEST_DIR/ffmpeg-dynamic

copy_windows_runtime_dlls "$DEST_DIR/ffmpeg-dynamic/bin"

echo "Installing system ffmpeg for example tests..."
pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-ffmpeg

echo "Running example tests with static ffmpeg..."
run_example $ROOT/example ${DEMO_BUILD_DIR}/static

echo "Running example tests with dynamic ffmpeg..."

for runtime_dir in "$DEST_DIR/ffmpeg-dynamic/bin" "$$DEST_DIR/ffmpeg-dynamic/lib" ; do
    if [ -d "$runtime_dir" ]; then
        find "$runtime_dir" -maxdepth 1 -type f -name '*.dll' -exec cp -f {} "${DEMO_BUILD_DIR}/dynamic/bin/" \;
    fi
done

run_example $ROOT/example ${DEMO_BUILD_DIR}/dynamic

echo "Example tests completed successfully!"