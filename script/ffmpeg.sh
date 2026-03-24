export FFMPEG_VERSION=8.1
export LAME_VERSION=3.100
export OGG_VERSION=1.3.6
export VORBIS_VERSION=1.3.7
export X264_VERSION=stable-165
export x265_VERSION=4.1
export AV1_VERSION=1.5.3
export OPUS_VERSION=1.6.1

download_file() {
    local filename=$1
    local archive_dir=$ARCHIVE_DIR
    local base_url="https://bsoft.oss-cn-hangzhou.aliyuncs.com/static/source"
    local file_path="${archive_dir}/${filename}"
    
    if [ -f "${file_path}" ]; then
        echo "文件已存在，跳过下载: ${filename}"
        return 0
    fi
    
    echo "正在下载: ${filename}"
    wget -P "${archive_dir}" "${base_url}/${filename}"
    
    if [ $? -eq 0 ]; then
        echo "下载完成: ${filename}"
    else
        echo "下载失败: ${filename}"
        return 1
    fi
}

build_lame(){
    download_file "lame-$LAME_VERSION.tar.gz"
    cd $BUILD_DIR
    rm -rf lame*
    tar xvf $ARCHIVE_DIR/lame-$LAME_VERSION.tar.gz
    cd lame-$LAME_VERSION

    ./configure --prefix=$DEST_DIR  --disable-shared --enable-static --disable-frontend

    make -j$(nproc)
    make install
}

build_ogg(){
    download_file "libogg-$OGG_VERSION.tar.xz"
    cd $BUILD_DIR
    rm -rf libogg*
    tar xvf $ARCHIVE_DIR/libogg-$OGG_VERSION.tar.xz
    cd libogg-$OGG_VERSION

    rm -rf _build && mkdir -p _build && cd _build

    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release  \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_DIR ..
    make -j$(nproc)
    make install
}

build_vorbis(){
    download_file "libvorbis-$VORBIS_VERSION.tar.xz"
    cd $BUILD_DIR
    rm -rf libvorbis*
    tar xvf $ARCHIVE_DIR/libvorbis-$VORBIS_VERSION.tar.xz
    cd libvorbis-$VORBIS_VERSION

    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_DIR \
    ${VORBIS_CMAKE_EXTRA} ..
    make -j$(nproc)
    make install
}

build_vorbis_autotolls(){
    download_file "libvorbis-$VORBIS_VERSION.tar.xz"
    cd $BUILD_DIR
    rm -rf libvorbis*
    tar xvf $ARCHIVE_DIR/libvorbis-$VORBIS_VERSION.tar.xz
    cd libvorbis-$VORBIS_VERSION

    ./autogen.sh
    ./configure --prefix=$DEST_DIR  --disable-shared --enable-static --disable-frontend
    make -j$(nproc)
    make install
}

build_opus(){
    download_file "opus-$OPUS_VERSION.tar.gz"
    cd $BUILD_DIR
    rm -rf opus*
    tar xvf $ARCHIVE_DIR/opus-$OPUS_VERSION.tar.gz
    cd opus-$OPUS_VERSION

    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_DIR ..
    make -j$(nproc)
    make install
}

build_x264(){
    download_file "x264-$X264_VERSION.tar.bz2"
    cd $BUILD_DIR
    rm -rf x264*
    tar xvf $ARCHIVE_DIR/x264-$X264_VERSION.tar.bz2
    cd x264-stable

    ./configure --prefix=$DEST_DIR --enable-pic --enable-static --disable-shared --disable-cli
    make -j$(nproc)
    make install
}

build_x265(){
    download_file "x265_$x265_VERSION.tar.gz"
    cd $BUILD_DIR
    rm -rf x265*
    tar xvf $ARCHIVE_DIR/x265_$x265_VERSION.tar.gz
    cd x265_$x265_VERSION

    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release  -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=$DEST_DIR -DENABLE_SHARED=0 -DENABLE_CLI=0 -DENABLE_PIC=1 ${X265_CMAKE_EXTRA} ../source
    make -j$(nproc)
    make install
}

build_dav1d(){
    download_file "dav1d-$AV1_VERSION.tar.xz"
    cd $BUILD_DIR
    rm -rf dav1d*
    tar xvf $ARCHIVE_DIR/dav1d-$AV1_VERSION.tar.xz
    cd dav1d-$AV1_VERSION

    rm -rf _build && mkdir -p _build && cd _build
    meson setup .. \
        --buildtype=release \
        -Dprefix=$DEST_DIR \
        -Dlibdir=lib \
        -Denable_tools=false \
        -Denable_tests=false \
        -Ddefault_library=static \
        -Db_pie=false \
        -Db_staticpic=true
    ninja -j$(nproc)
    ninja install
}

build_ffmpeg(){
    download_file "ffmpeg-$FFMPEG_VERSION.tar.xz"
    cd $BUILD_DIR
    rm -rf ffmpeg*
    tar xvf $ARCHIVE_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz
    cd ffmpeg-$FFMPEG_VERSION
    export PKG_CONFIG_PATH="$DEST_DIR/lib/pkgconfig:$DEST_DIR/lib64/pkgconfig:$PKG_CONFIG_PATH"


 ./configure \
    --prefix=$DEST_DIR \
    --pkg-config-flags="--static" \
    --extra-cflags="-I$DEST_DIR/include" \
    --extra-ldflags="-L$DEST_DIR/lib -L$DEST_DIR/lib64" \
    --extra-libs="-lm -lpthread" \
    --disable-programs \
    --disable-doc \
    --disable-debug \
    --disable-shared \
    --enable-static \
    --enable-small \
    --disable-everything \
    --disable-network \
    --disable-autodetect \
    --disable-iconv \
    --disable-zlib \
    --disable-bzlib \
    --disable-lzma \
    --disable-sdl2 \
    --enable-gpl \
    \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    --enable-swresample \
    --enable-swscale \
    --enable-avfilter \
    --enable-avdevice \
    \
    --enable-protocol=file \
    --enable-protocol=pipe \
    \
    --enable-demuxer=wav \
    --enable-demuxer=mp3 \
    --enable-demuxer=aac \
    --enable-demuxer=flac \
    --enable-demuxer=ogg \
    --enable-demuxer=mov \
    --enable-demuxer=matroska \
    --enable-demuxer=avi \
    --enable-demuxer=hevc \
    \
    --enable-muxer=adts \
    --enable-muxer=mp3 \
    --enable-muxer=ogg \
    --enable-muxer=opus \
    --enable-muxer=ipod \
    --enable-muxer=mp4 \
    --enable-muxer=matroska \
    --enable-muxer=hevc \
    \
    --enable-parser=aac \
    --enable-parser=flac \
    --enable-parser=mpegaudio \
    --enable-parser=h264 \
    --enable-parser=hevc \
    --enable-parser=av1 \
    \
    --enable-decoder=pcm_s16le \
    --enable-decoder=pcm_s24le \
    --enable-decoder=pcm_s32le \
    --enable-decoder=pcm_f32le \
    --enable-decoder=pcm_f64le \
    --enable-decoder=mp3 \
    --enable-decoder=aac \
    --enable-decoder=flac \
    --enable-decoder=vorbis \
    --enable-decoder=opus \
    --enable-decoder=h264 \
    --enable-decoder=hevc \
    \
    --enable-encoder=aac \
    --enable-libmp3lame \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libx264 \
    --enable-libx265 \
    --enable-encoder=libmp3lame \
    --enable-encoder=libvorbis \
    --enable-encoder=libopus \
    --enable-encoder=libx264 \
    --enable-encoder=libx265 \
    \
    --enable-libdav1d \
    --enable-decoder=libdav1d \
    \
    --enable-bsf=aac_adtstoasc \
    --enable-bsf=hevc_mp4toannexb


    make -j$(nproc)
    make install-libs install-headers
}