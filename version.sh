#!/bin/bash
set -e
ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"

source $ROOT/script/ffmpeg.sh

echo "$FFMPEG_VERSION"