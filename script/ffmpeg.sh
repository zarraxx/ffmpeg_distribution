export FFMPEG_VERSION=8.1
export LAME_VERSION=3.100
export OGG_VERSION=1.3.6
export VORBIS_VERSION=1.3.7
export X264_VERSION=stable-165
export x265_VERSION=4.1
export AV1_VERSION=1.5.3
export OPUS_VERSION=1.6.1

export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"

init_shared_runtime_flags() {
    SDK_RUNTIME_RPATH=""
    SDK_SHARED_LINK_FLAGS=""
    SDK_CMAKE_SHARED_ARGS=""

    case "$(uname -s)" in
        Linux)
            SDK_RUNTIME_RPATH='$ORIGIN'
            SDK_SHARED_LINK_FLAGS="-Wl,-rpath,$SDK_RUNTIME_RPATH -Wl,-rpath-link,$DEST_DYNAMIC_DIR/lib -Wl,-rpath-link,$DEST_DYNAMIC_DIR/lib64"
            SDK_CMAKE_SHARED_ARGS="-DCMAKE_BUILD_RPATH=$SDK_RUNTIME_RPATH -DCMAKE_INSTALL_RPATH=$SDK_RUNTIME_RPATH"
            ;;
        Darwin)
            SDK_RUNTIME_RPATH='@loader_path'
            SDK_SHARED_LINK_FLAGS="-Wl,-rpath,$SDK_RUNTIME_RPATH"
            SDK_CMAKE_SHARED_ARGS="-DCMAKE_BUILD_RPATH=$SDK_RUNTIME_RPATH -DCMAKE_INSTALL_RPATH=$SDK_RUNTIME_RPATH"
            ;;
    esac
}

init_shared_runtime_flags

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

get_cpu_count() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

normalize_pkgconfig_metadata() {
    local pkgconfig_dir
    local pc_file
    local content
    local reloc_prefix='${pcfiledir}/../..'
    local win_dest_dir
    local candidate
    local -a prefix_candidates
    local DEST_DIR="${1:-$DEST_STATIC_DIR}"

    prefix_candidates=("$DEST_DIR")
    if command -v cygpath >/dev/null 2>&1; then
        win_dest_dir="$(cygpath -m "$DEST_DIR" 2>/dev/null || true)"
        if [ -n "$win_dest_dir" ]; then
            prefix_candidates+=("$win_dest_dir")
        fi
    fi

    for pkgconfig_dir in "$DEST_DIR/lib/pkgconfig" "$DEST_DIR/lib64/pkgconfig"; do
        [ -d "$pkgconfig_dir" ] || continue

        find "$pkgconfig_dir" -maxdepth 1 -type f -name '*.pc' | while IFS= read -r pc_file; do
            content=$(cat "$pc_file")
            for candidate in "${prefix_candidates[@]}"; do
                [ -n "$candidate" ] || continue
                content=${content//"$candidate"/$reloc_prefix}
            done
            printf '%s\n' "$content" > "$pc_file"
        done
    done
}

patch_lame_exports() {
    local sym_file="include/libmp3lame.sym"
    local tmp_file

    [ -f "$sym_file" ] || return 0

    # LAME 3.100 keeps lame_init_old in the export list even though the
    # symbol is compiled as static when deprecated code is removed.
    tmp_file="${sym_file}.tmp"
    grep -vx 'lame_init_old' "$sym_file" > "$tmp_file" || true
    mv "$tmp_file" "$sym_file"
}

patch_vorbis_windows_defs() {
    local def_file
    local tmp_file

    for def_file in win32/vorbis.def win32/vorbisenc.def win32/vorbisfile.def; do
        [ -f "$def_file" ] || continue

        tmp_file="${def_file}.tmp"
        awk '
            $0 == "LIBRARY" { next }
            { print }
        ' "$def_file" > "$tmp_file"
        mv "$tmp_file" "$def_file"
    done
}

build_lame(){
    download_file "lame-$LAME_VERSION.tar.gz"
    cd $BUILD_DIR
    rm -rf lame*
    tar xvf $ARCHIVE_DIR/lame-$LAME_VERSION.tar.gz
    cd lame-$LAME_VERSION
    patch_lame_exports

    CFLAGS="${CFLAGS:+$CFLAGS }-fPIC" ./configure --prefix=$DEST_STATIC_DIR  --disable-shared --enable-static --disable-frontend

    make -j$(get_cpu_count)
    make install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf lame*
    tar xvf $ARCHIVE_DIR/lame-$LAME_VERSION.tar.gz
    cd lame-$LAME_VERSION
    patch_lame_exports

    LDFLAGS="${LDFLAGS:+$LDFLAGS }${SDK_SHARED_LINK_FLAGS}" \
    CFLAGS="${CFLAGS:+$CFLAGS }-fPIC" \
    ./configure --prefix=$DEST_DYNAMIC_DIR  --disable-static --enable-shared --disable-frontend

    make -j$(get_cpu_count)
    make install
}

build_ogg(){
    download_file "libogg-$OGG_VERSION.tar.xz"

    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf libogg*
    tar xvf $ARCHIVE_DIR/libogg-$OGG_VERSION.tar.xz
    cd libogg-$OGG_VERSION

    rm -rf _build && mkdir -p _build && cd _build


    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release  \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_STATIC_DIR ..
    make -j$(get_cpu_count)
    make install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf libogg*
    tar xvf $ARCHIVE_DIR/libogg-$OGG_VERSION.tar.xz
    cd libogg-$OGG_VERSION
    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release  \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_DYNAMIC_DIR \
    ${SDK_CMAKE_SHARED_ARGS} ..
    make -j$(get_cpu_count)
    make install
}

build_vorbis(){
    download_file "libvorbis-$VORBIS_VERSION.tar.xz"

    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf libvorbis*
    tar xvf $ARCHIVE_DIR/libvorbis-$VORBIS_VERSION.tar.xz
    cd libvorbis-$VORBIS_VERSION
    patch_vorbis_windows_defs

    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_STATIC_DIR \
    ${VORBIS_CMAKE_EXTRA} ..
    make -j$(get_cpu_count)
    make install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf libvorbis*
    tar xvf $ARCHIVE_DIR/libvorbis-$VORBIS_VERSION.tar.xz
    cd libvorbis-$VORBIS_VERSION
    patch_vorbis_windows_defs
    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_DYNAMIC_DIR \
    ${SDK_CMAKE_SHARED_ARGS} \
    ${VORBIS_CMAKE_EXTRA} ..
    make -j$(get_cpu_count)
    make install
}


build_opus(){
    download_file "opus-$OPUS_VERSION.tar.gz"

    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"
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
    -DCMAKE_INSTALL_PREFIX=$DEST_STATIC_DIR ..
    make -j$(get_cpu_count)
    make install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf opus*
    tar xvf $ARCHIVE_DIR/opus-$OPUS_VERSION.tar.gz
    cd opus-$OPUS_VERSION
    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib  \
    -DCMAKE_INSTALL_PREFIX=$DEST_DYNAMIC_DIR \
    ${SDK_CMAKE_SHARED_ARGS} ..
    make -j$(get_cpu_count)
    make install
}

build_x264(){
    download_file "x264-$X264_VERSION.tar.bz2"

    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf x264*
    tar xvf $ARCHIVE_DIR/x264-$X264_VERSION.tar.bz2
    cd x264-stable

    ./configure --prefix=$DEST_STATIC_DIR --enable-pic --enable-static --disable-shared --disable-cli ${X264_CONF_EXTRA}
    make -j$(get_cpu_count)
    make install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf x264*
    tar xvf $ARCHIVE_DIR/x264-$X264_VERSION.tar.bz2
    cd x264-stable
    ./configure --prefix=$DEST_DYNAMIC_DIR --enable-pic --disable-static --enable-shared --disable-cli \
    --extra-ldflags="$SDK_SHARED_LINK_FLAGS" ${X264_CONF_EXTRA}
    make -j$(get_cpu_count)
    make install
}

build_x265(){
    download_file "x265_$x265_VERSION.tar.gz"

    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf x265*
    tar xvf $ARCHIVE_DIR/x265_$x265_VERSION.tar.gz
    cd x265_$x265_VERSION

    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release  -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=$DEST_STATIC_DIR -DENABLE_SHARED=0 -DENABLE_CLI=0 -DENABLE_PIC=1 ${X265_CMAKE_EXTRA} ../source
    make -j$(get_cpu_count)
    make install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf x265*
    tar xvf $ARCHIVE_DIR/x265_$x265_VERSION.tar.gz
    cd x265_$x265_VERSION
    rm -rf _build && mkdir -p _build && cd _build
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release  -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=$DEST_DYNAMIC_DIR -DENABLE_SHARED=1 -DENABLE_CLI=0 -DENABLE_PIC=1 \
    ${SDK_CMAKE_SHARED_ARGS} ${X265_CMAKE_EXTRA} ../source
    make -j$(get_cpu_count)
    make install
}

build_dav1d(){
    download_file "dav1d-$AV1_VERSION.tar.xz"
    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf dav1d*
    tar xvf $ARCHIVE_DIR/dav1d-$AV1_VERSION.tar.xz
    cd dav1d-$AV1_VERSION

    rm -rf _build && mkdir -p _build && cd _build
    meson setup .. \
        --buildtype=release \
        -Dprefix=$DEST_STATIC_DIR \
        -Dlibdir=lib \
        -Denable_tools=false \
        -Denable_tests=false \
        -Ddefault_library=static \
        -Db_pie=false \
        -Db_staticpic=true
    ninja -v -j$(get_cpu_count) || {
        echo "===== meson-log.txt ====="
        cat meson-logs/meson-log.txt || true
        exit 1
    }
    ninja install

    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf dav1d*
    tar xvf $ARCHIVE_DIR/dav1d-$AV1_VERSION.tar.xz
    cd dav1d-$AV1_VERSION
    rm -rf _build && mkdir -p _build && cd _build
    LDFLAGS="${LDFLAGS:+$LDFLAGS }${SDK_SHARED_LINK_FLAGS}" meson setup .. \
        --buildtype=release \
        -Dprefix=$DEST_DYNAMIC_DIR \
        -Dlibdir=lib \
        -Denable_tools=false \
        -Denable_tests=false \
        -Ddefault_library=shared \
        -Db_pie=false \
        -Db_staticpic=true
    ninja -v -j$(get_cpu_count) || {
        echo "===== meson-log.txt ====="
        cat meson-logs/meson-log.txt || true
        exit 1
    }
    ninja install
}

build_ffmpeg(){
    download_file "ffmpeg-$FFMPEG_VERSION.tar.xz"

    export PKG_CONFIG_PATH="$DEST_STATIC_DIR/lib/pkgconfig:$DEST_STATIC_DIR/lib64/pkgconfig"

    cd $BUILD_DIR
    rm -rf ffmpeg*
    tar xvf $ARCHIVE_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz
    cd ffmpeg-$FFMPEG_VERSION

    export FFMPEG_FEATURES=" --disable-doc \
    --disable-debug \
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
    --enable-bsf=hevc_mp4toannexb "

    ./configure \
    --prefix=$DEST_STATIC_DIR \
    --enable-pic \
    --enable-static \
    --disable-shared \
    --pkg-config-flags="--static" \
    --extra-cflags="-I$DEST_STATIC_DIR/include" \
    --extra-ldflags="-L$DEST_STATIC_DIR/lib -L$DEST_STATIC_DIR/lib64" \
    --extra-libs="-lm -lpthread" \
    --disable-programs \
    ${FFMPEG_FEATURES} \
    ${FFMPEG_CONFIG_EXTRA}


    make -j$(get_cpu_count)
    make install-libs install-headers


    export PKG_CONFIG_PATH="$DEST_DYNAMIC_DIR/lib/pkgconfig:$DEST_DYNAMIC_DIR/lib64/pkgconfig"
    cd $BUILD_DIR
    rm -rf ffmpeg*
    tar xvf $ARCHIVE_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz
    cd ffmpeg-$FFMPEG_VERSION

    ./configure \
    --prefix=$DEST_DYNAMIC_DIR \
    --enable-shared \
    --disable-static \
    --extra-cflags="-I$DEST_DYNAMIC_DIR/include" \
    --extra-ldflags="-L$DEST_DYNAMIC_DIR/lib -L$DEST_DYNAMIC_DIR/lib64 ${SDK_SHARED_LINK_FLAGS}" \
    --extra-libs="-lm -lpthread " \
    --disable-programs \
    ${FFMPEG_FEATURES} 

    make -j$(get_cpu_count)
    make install-libs install-headers

   
    normalize_pkgconfig_metadata ${DEST_STATIC_DIR}
    normalize_pkgconfig_metadata ${DEST_DYNAMIC_DIR}
}
