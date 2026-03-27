
export CC=${CC:-gcc}
export CXX=${CXX:-g++}

build_example() {
     
    # $1 cmake src directory
    # $2 cmake build directory
    # $3 ffmpeg sdk root

    local CMAKE_SRC_DIR=$1
    local CMAKE_BUILD_DIR=$2
    local FFMPEG_SDK_ROOT=$3


    echo "Building examples with CMake..."
    cmake -S $CMAKE_SRC_DIR -B $CMAKE_BUILD_DIR -G Ninja -DFFMPEG_ROOT=$FFMPEG_SDK_ROOT -DCMAKE_C_COMPILER=$CC  -DCMAKE_BUILD_TYPE=Release
    cmake --build $CMAKE_BUILD_DIR --parallel

    echo "ffmpeg_example shared library built at: $CMAKE_BUILD_DIR/bin/libffmpeg_example.so"
    echo "audio_convert demo built at: $CMAKE_BUILD_DIR/bin/audio_convert"
    echo "video_convert demo built at: $CMAKE_BUILD_DIR/bin/video_convert"
    echo "media_info demo built at: $CMAKE_BUILD_DIR/bin/media_info"
}


run_example() {
    local CMAKE_SRC_DIR=$1
    local CMAKE_BUILD_DIR=$2

    chmod +x $CMAKE_SRC_DIR/audio_convert/test_audio_convert.sh
    chmod +x $CMAKE_SRC_DIR/video_convert/test_video_convert.sh

    echo "Running audio_convert tests..."
    $CMAKE_SRC_DIR/audio_convert/test_audio_convert.sh $CMAKE_BUILD_DIR/bin/audio_convert $CMAKE_BUILD_DIR/bin/audio_convert_test_work

    echo "Running video_convert tests..."
    $CMAKE_SRC_DIR/video_convert/test_video_convert.sh $CMAKE_BUILD_DIR/bin/video_convert $CMAKE_BUILD_DIR/bin/video_convert_test_work
}