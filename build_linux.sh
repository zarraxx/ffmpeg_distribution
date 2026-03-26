#!/bin/bash
set -e
NAME=ffmpeg_build
IMAGE=registry.cn-hangzhou.aliyuncs.com/zarra/centos:x-tools-base
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"
#PARENT="$(cd $ROOT/..;pwd)"
ARCH=`uname -m`

ARCHIVE_DIR=$ROOT/archive
WORKSPACE=$ROOT/build
DEST_DIR=$ROOT/dist/linux-$ARCH
OUTPUT_DIR=$ROOT/out

mkdir -p $ARCHIVE_DIR
mkdir -p $DEST_DIR
mkdir -p $OUTPUT_DIR
rm -rf $WORKSPACE
rm -rf "$DEST_DIR/ffmpeg"
mkdir -p $WORKSPACE
DOCKER=${DOCKER:-podman}

# Check if container with same name exists, stop and remove it
if $DOCKER ps -a --format '{{.Names}}' | grep -q "^${NAME}$"; then
    echo "Container $NAME already exists, stopping and removing it..."
    $DOCKER stop $NAME 2>/dev/null || true
    $DOCKER rm $NAME 2>/dev/null || true
fi

$DOCKER run -it --rm --name=$NAME  \
        -e LINES=50 -e COLUMNS=160 \
        -v $WORKSPACE:/workspace/build:z,U \
        -v $ARCHIVE_DIR:/workspace/archive:z,U \
        -v $DEST_DIR:/opt/x-tools/dist:z,U \
        -v $ROOT/script:/script:z,U \
    	$IMAGE /bin/bash -c "/script/ffmpeg_centos_devtoolset.sh"

PACKAGE_SUFFIX_PART=""
if [ -n "$PACKAGE_SUFFIX" ]; then
    PACKAGE_SUFFIX_PART="-$PACKAGE_SUFFIX"
fi

tar -czvf $OUTPUT_DIR/ffmpeg-linux-${ARCH}${PACKAGE_SUFFIX_PART}.tar.gz -C "$(dirname "$DEST_DIR")" "$(basename "$DEST_DIR")"

SDK_ROOT="$DEST_DIR/ffmpeg-dynamic"
SDK_LIB_DIR="$SDK_ROOT/lib"
SDK_LIB64_DIR="$SDK_ROOT/lib64"

DEMO_BUILD_DIR=$ROOT/build/example-linux-$ARCH
echo "Building examples with CMake..."
cmake -S $ROOT/example -B $DEMO_BUILD_DIR -DFFMPEG_ROOT=$SDK_ROOT -DCMAKE_BUILD_TYPE=Release
cmake --build $DEMO_BUILD_DIR --parallel
echo "ffmpeg_example shared library built at: $DEMO_BUILD_DIR/bin/libffmpeg_example.so"
echo "audio_convert demo built at: $DEMO_BUILD_DIR/bin/audio_convert"
echo "video_convert demo built at: $DEMO_BUILD_DIR/bin/video_convert"
echo "media_info demo built at: $DEMO_BUILD_DIR/bin/media_info"

export FFMPEG_EXAMPLE_LD_LIBRARY_PATH="$SDK_LIB_DIR:$SDK_LIB64_DIR"
echo "Using FFMPEG_EXAMPLE_LD_LIBRARY_PATH=$FFMPEG_EXAMPLE_LD_LIBRARY_PATH"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "Installing system ffmpeg for example tests..."
$SUDO apt-get update
$SUDO apt-get install -y ffmpeg

chmod +x $ROOT/example/audio_convert/test_audio_convert.sh
chmod +x $ROOT/example/video_convert/test_video_convert.sh

echo "Running audio_convert tests..."
$ROOT/example/audio_convert/test_audio_convert.sh $DEMO_BUILD_DIR/bin/audio_convert $ROOT/build/audio_convert-test-linux-$ARCH

echo "Running video_convert tests..."
$ROOT/example/video_convert/test_video_convert.sh $DEMO_BUILD_DIR/bin/video_convert $ROOT/build/video_convert-test-linux-$ARCH
