#!/bin/bash

NAME=ffmpeg_build
IMAGE=registry.cn-hangzhou.aliyuncs.com/zarra/centos:x-tools-base
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"
#PARENT="$(cd $ROOT/..;pwd)"
ARCH=`uname -m`
WORKSPACE=$ROOT/build
DEST_DIR=$ROOT/dist/linux-$ARCH
OUTPUT_DIR=$ROOT/out

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
        -v $WORKSPACE:/workspace:z,U \
        -v $DEST_DIR:/opt/x-tools/dist:z,U \
        -v $ROOT/script:/script:z,U \
    	$IMAGE /bin/bash -c "/script/ffmpeg_centos_devtoolset.sh"


tar -czvf $OUTPUT_DIR/ffmpeg-linux-$ARCH.tar.gz -C $DEST_DIR .