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

DEMO_BUILD_DIR=$ROOT/build/audio_convert-linux-$ARCH
echo "Building example/audio_convert with CMake..."
cmake -S $ROOT/example/audio_convert -B $DEMO_BUILD_DIR -DFFMPEG_ROOT=$DEST_DIR/ffmpeg -DCMAKE_BUILD_TYPE=Release
cmake --build $DEMO_BUILD_DIR --parallel
echo "audio_convert demo built at: $DEMO_BUILD_DIR/bin/audio_convert"
