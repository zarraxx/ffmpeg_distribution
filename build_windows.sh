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

PACKAGE_SUFFIX_PART=""
if [ -n "$PACKAGE_SUFFIX" ]; then
    PACKAGE_SUFFIX_PART="-$PACKAGE_SUFFIX"
fi

tar -czvf $OUTPUT_DIR/ffmpeg-windows-x86_64${PACKAGE_SUFFIX_PART}.tar.gz -C "$(dirname "$DEST_DIR")" "$(basename "$DEST_DIR")"



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

run_windows_test() {
    local test_name=$1
    shift

    echo "Running ${test_name}..."
    if "$@"; then
        return 0
    fi

    local rc=$?
    echo "${test_name} failed with exit code ${rc}"
    #print_windows_runtime_diagnostics "$DEMO_BUILD_DIR/bin"
    return "$rc"
}



SDK_ROOT="$DEST_DIR/ffmpeg-dynamic"
SDK_BIN_DIR="$SDK_ROOT/bin"
SDK_LIB_DIR="$SDK_ROOT/lib"
SDK_LIB64_DIR="$SDK_ROOT/lib64"

copy_windows_runtime_dlls "$SDK_BIN_DIR"


DEMO_BUILD_DIR=$ROOT/build/example-windows-x86_64
rm -rf "$DEMO_BUILD_DIR"
echo "Building examples with CMake..."
cmake -S $ROOT/example -B $DEMO_BUILD_DIR \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=$CC \
    -DFFMPEG_ROOT=$SDK_ROOT
cmake --build $DEMO_BUILD_DIR --parallel
echo "ffmpeg_example shared library built at: $DEMO_BUILD_DIR/bin/ffmpeg_example.dll"
echo "audio_convert demo built at: $DEMO_BUILD_DIR/bin/audio_convert.exe"
echo "video_convert demo built at: $DEMO_BUILD_DIR/bin/video_convert.exe"
echo "media_info demo built at: $DEMO_BUILD_DIR/bin/media_info.exe"

for runtime_dir in "$SDK_BIN_DIR" "$SDK_LIB_DIR" "$SDK_LIB64_DIR"; do
    if [ -d "$runtime_dir" ]; then
        find "$runtime_dir" -maxdepth 1 -type f -name '*.dll' -exec cp -f {} "$DEMO_BUILD_DIR/bin/" \;
    fi
done

mkdir -p "$SDK_BIN_DIR"
copy_windows_runtime_dlls "$SDK_BIN_DIR"
copy_windows_runtime_dlls "$DEMO_BUILD_DIR/bin"

echo "Installing system ffmpeg for example tests..."
pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-ffmpeg

chmod +x $ROOT/example/audio_convert/test_audio_convert.sh
chmod +x $ROOT/example/video_convert/test_video_convert.sh

echo "Using PATH=$PATH"

#print_windows_runtime_diagnostics "$DEMO_BUILD_DIR/bin"

if [ "${SKIP_EXAMPLE_TESTS:-0}" = "1" ]; then
    echo "Skipping example tests because SKIP_EXAMPLE_TESTS=1"
    exit 0
fi

run_windows_test "audio_convert tests" \
    $ROOT/example/audio_convert/test_audio_convert.sh \
    $DEMO_BUILD_DIR/bin/audio_convert.exe \
    $ROOT/build/audio_convert-test-windows-x86_64

run_windows_test "video_convert tests" \
    $ROOT/example/video_convert/test_video_convert.sh \
    $DEMO_BUILD_DIR/bin/video_convert.exe \
    $ROOT/build/video_convert-test-windows-x86_64
