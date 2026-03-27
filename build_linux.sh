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
rm -rf "$DEST_DIR/ffmpeg-static" "$DEST_DIR/ffmpeg-shared"
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

source $ROOT/script/ffmpeg_test.sh
DEMO_BUILD_DIR=$ROOT/build/example-linux-$ARCH
rm -rf $DEMO_BUILD_DIR
build_example $ROOT/example ${DEMO_BUILD_DIR}/static $DEST_DIR/ffmpeg-static
build_example $ROOT/example ${DEMO_BUILD_DIR}/shared $DEST_DIR/ffmpeg-shared

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "Installing system ffmpeg for example tests..."
$SUDO apt-get update
$SUDO apt-get install -y ffmpeg

echo "Running example tests with static ffmpeg..."
run_example $ROOT/example ${DEMO_BUILD_DIR}/static

echo "Running example tests with shared ffmpeg..."
export FFMPEG_EXAMPLE_LD_LIBRARY_PATH="$DEST_DIR/ffmpeg-shared/lib:$DEST_DIR/ffmpeg-shared/lib64"
export FFMPEG_EXAMPLE_DYLD_LIBRARY_PATH="$FFMPEG_EXAMPLE_LD_LIBRARY_PATH"
run_example $ROOT/example ${DEMO_BUILD_DIR}/shared


echo "Example tests completed successfully!"

echo "Checking shared ffmpeg dependencies with ldd..."
ldd  $DEST_DIR/ffmpeg-shared/bin/ffmpeg_custom

echo "Checking ffmpeg version..."
$DEST_DIR/ffmpeg-shared/bin/ffmpeg_custom -version

echo "All checks passed successfully!"
