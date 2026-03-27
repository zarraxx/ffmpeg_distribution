# FFmpeg SDK

[![night-build](https://github.com/zarraxx/ffmpeg_distribution/actions/workflows/night-build.yml/badge.svg)](https://github.com/zarraxx/ffmpeg_distribution/actions/workflows/night-build.yml)

[English](./README.md) | 简体中文

用于构建精简版 FFmpeg SDK 的脚本仓库，面向 Linux、macOS 和 Windows。项目提供静态链接和动态链接两套 SDK；每套 SDK 都包含头文件、库文件，以及用于验证构建结果的 `ffmpeg_custom` 和 `ffprobe_custom`。

构建脚本还会额外编译并测试 `example/` 下的示例程序，用于验证静态和动态 SDK 都可以被上层业务代码正常集成。

## 项目特点

- 同时产出 `ffmpeg-static` 和 `ffmpeg-shared` 两套 SDK。
- 两套 SDK 都会安装 `bin/ffmpeg_custom` 和 `bin/ffprobe_custom`。
- FFmpeg 仍然基于 `--disable-everything` 按需启用模块，产物可控。
- 默认关闭网络、自动探测、`iconv`、`zlib`、`bzlib`、`lzma`、`sdl2` 等能力。
- 内置常用外部编解码依赖：`lame`、`libogg`、`libvorbis`、`opus`、`x264`、`x265`、`dav1d`。
- 构建完成后会自动打包到 `out/`，并对示例程序执行回归测试。

## 当前版本

`./version.sh` 输出当前 FFmpeg 版本；外部依赖版本定义在 [`script/ffmpeg.sh`](/opt/projects/ffmpeg_sdk/script/ffmpeg.sh)。

| 组件 | 版本 |
| --- | --- |
| FFmpeg | `8.1` |
| lame | `3.100` |
| libogg | `1.3.6` |
| libvorbis | `1.3.7` |
| opus | `1.6.1` |
| x264 | `stable-165` |
| x265 | `4.1` |
| dav1d | `1.5.3` |

## 目录说明

| 路径 | 说明 |
| --- | --- |
| `build_linux.sh` | Linux 构建入口，默认通过 `podman` 或 `docker` 在容器内构建 |
| `build_macos.sh` | macOS 构建入口 |
| `build_windows.sh` | Windows 构建入口 |
| `prepare.sh` | 预下载源码包到 `~/archive` |
| `clean.sh` | 清理 `build/`、`dist/`、`out/` |
| `version.sh` | 输出 FFmpeg 版本 |
| `script/ffmpeg.sh` | 通用下载、依赖编译和 FFmpeg 配置逻辑 |
| `script/ffmpeg_test.sh` | 统一的示例构建与测试入口 |
| `example/audio_convert` | 音频转码示例，输出 `128 kbps / 48 kHz / 双声道 MP3` |
| `example/video_convert` | 视频转码示例，输出 `720p MP4` |
| `example/media_info` | 媒体探测示例，输出 JSON 格式的媒体信息 |

## 环境要求

### 通用

请确保构建环境具备以下基础工具：

- `bash`
- `make`
- `tar`
- `wget`
- `cmake`
- `meson`
- `ninja`
- C/C++ 编译工具链

### Linux

- 需要 `podman` 或 `docker`
- 默认镜像：`registry.cn-hangzhou.aliyuncs.com/zarra/centos:x-tools-base`
- 可通过环境变量切换容器命令：

```bash
DOCKER=docker ./build_linux.sh
```

### macOS

- 需要本地可用的编译工具链
- 脚本会直接使用下面这个 CMake 路径：

```bash
$HOME/.local/cmake/cmake-3.27.9-macos-universal/CMake.app/Contents/bin
```

如果本机环境不同，需要先调整 [`build_macos.sh`](/opt/projects/ffmpeg_sdk/build_macos.sh)。

### Windows

- 需要可用的 `bash`/`make`/`cmake`/`meson`/`ninja` 构建环境
- 脚本会直接使用下面这个 CMake 路径：

```bash
/opt/cmake/cmake-3.27.9-windows-x86_64/bin
```

如果本机环境不同，需要先调整 [`build_windows.sh`](/opt/projects/ffmpeg_sdk/build_windows.sh)。

## 快速开始

### 1. 查看 FFmpeg 版本

```bash
./version.sh
```

### 2. 可选：预下载源码包

```bash
./prepare.sh
```

说明：`prepare.sh` 当前下载到 `~/archive`，而各平台构建脚本默认读取项目内的 `archive/`。如果你想复用预下载文件，需要自行同步目录，或者统一修改脚本里的 `ARCHIVE_DIR`。

### 3. 开始构建

Linux:

```bash
./build_linux.sh
```

macOS:

```bash
./build_macos.sh
```

Windows:

```bash
./build_windows.sh
```

构建脚本在完成 SDK 打包后，还会：

- 为静态版 SDK 构建一套示例程序
- 为动态版 SDK 构建一套示例程序
- 自动安装系统 `ffmpeg`
- 运行 `audio_convert` 和 `video_convert` 的测试脚本
- 在动态版上额外检查运行时依赖与 `ffmpeg_custom -version`

### 4. 清理产物

```bash
./clean.sh
```

## 输出目录

构建完成后会同时生成：

- 解包目录：`dist/`
- 压缩包：`out/`

### SDK 目录结构

各平台构建脚本都会产出两个 SDK 根目录：

- `dist/<platform>/ffmpeg-static`
- `dist/<platform>/ffmpeg-shared`

每个根目录下都包含：

- `bin/ffmpeg_custom`
- `bin/ffprobe_custom`
- `include/`
- `lib/` 和按平台可能存在的 `lib64/`
- `lib/pkgconfig` 和按平台可能存在的 `lib64/pkgconfig`

当前仓库中已经存在的 Linux 产物示例：

```text
dist/linux-x86_64/ffmpeg-static
dist/linux-x86_64/ffmpeg-shared
out/ffmpeg-linux-x86_64.tar.gz
```

### 各平台打包命名

Linux:

- 目录：`dist/linux-<arch>/ffmpeg-static`
- 目录：`dist/linux-<arch>/ffmpeg-shared`
- 压缩包：`out/ffmpeg-linux-<arch>.tar.gz`

macOS:

- 目录：`dist/darwin-<arch>/ffmpeg-static`
- 目录：`dist/darwin-<arch>/ffmpeg-shared`
- 压缩包：`out/ffmpeg-darwin-<arch>.tar.gz`

注意：脚本会把 macOS 的 `arm64` 统一写成 `aarch64`。

Windows:

- 目录：`dist/windows-x86_64/ffmpeg-static`
- 目录：`dist/windows-x86_64/ffmpeg-shared`
- 压缩包：`out/ffmpeg-windows-x86_64.tar.gz`

## 使用 SDK

`example/` 是统一的示例工程入口。手工构建示例时建议显式传入 `FFMPEG_ROOT`，明确指定使用静态版或动态版 SDK。

### 静态版示例

Linux:

```bash
cmake -S example -B build/example-linux-$(uname -m)/static \
  -G Ninja \
  -DFFMPEG_ROOT=$PWD/dist/linux-$(uname -m)/ffmpeg-static \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-linux-$(uname -m)/static --parallel
```

macOS:

```bash
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then ARCH=aarch64; fi

cmake -S example -B build/example-darwin-$ARCH/static \
  -G Ninja \
  -DFFMPEG_ROOT=$PWD/dist/darwin-$ARCH/ffmpeg-static \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-darwin-$ARCH/static --parallel
```

Windows:

```bash
cmake -S example -B build/example-windows-x86_64/static \
  -G Ninja \
  -DFFMPEG_ROOT=$PWD/dist/windows-x86_64/ffmpeg-static \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-windows-x86_64/static --parallel
```

### 动态版示例

Linux:

```bash
cmake -S example -B build/example-linux-$(uname -m)/shared \
  -G Ninja \
  -DFFMPEG_ROOT=$PWD/dist/linux-$(uname -m)/ffmpeg-shared \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-linux-$(uname -m)/shared --parallel
```

macOS:

```bash
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then ARCH=aarch64; fi

cmake -S example -B build/example-darwin-$ARCH/shared \
  -G Ninja \
  -DFFMPEG_ROOT=$PWD/dist/darwin-$ARCH/ffmpeg-shared \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-darwin-$ARCH/shared --parallel
```

Windows:

```bash
cmake -S example -B build/example-windows-x86_64/shared \
  -G Ninja \
  -DFFMPEG_ROOT=$PWD/dist/windows-x86_64/ffmpeg-shared \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-windows-x86_64/shared --parallel
```

## 示例程序

当前 `example/` 会构建以下程序：

- `audio_convert`
- `video_convert`
- `media_info`

默认输出目录形如：

- `build/example-linux-x86_64/static/bin/`
- `build/example-linux-x86_64/shared/bin/`

### `audio_convert`

用法：

```bash
./build/example-linux-x86_64/static/bin/audio_convert input.wav output.mp3
```

功能：把输入音频转换成 `128 kbps / 48 kHz / 双声道 MP3`。

### `video_convert`

用法：

```bash
./build/example-linux-x86_64/static/bin/video_convert input.mkv output.mp4
```

功能：

- 输出 `1280x720`
- 容器格式为 `MP4`
- 视频编码为 `H.264`
- 如果存在音轨，则仅保留第一条音轨，并转成 `128 kbps / 48 kHz / 双声道 MP3`

### `media_info`

用法：

```bash
./build/example-linux-x86_64/static/bin/media_info input.mp4
```

功能：输出 JSON 格式的媒体信息，包括封装格式、时长、流列表和元数据。

### 自动化测试

构建脚本会自动运行：

- [`example/audio_convert/test_audio_convert.sh`](/opt/projects/ffmpeg_sdk/example/audio_convert/test_audio_convert.sh)
- [`example/video_convert/test_video_convert.sh`](/opt/projects/ffmpeg_sdk/example/video_convert/test_video_convert.sh)

如果你想单独执行测试，Linux 下可以这样运行：

```bash
./example/audio_convert/test_audio_convert.sh ./build/example-linux-x86_64/static/bin/audio_convert
./example/video_convert/test_video_convert.sh ./build/example-linux-x86_64/static/bin/video_convert
```

## 已启用的 FFmpeg 能力

以下列表直接对应 [`script/ffmpeg.sh`](/opt/projects/ffmpeg_sdk/script/ffmpeg.sh) 中当前启用的 `configure` 选项。

### 程序

- `ffmpeg`
- `ffprobe`

安装后的二进制文件名为：

- `ffmpeg_custom`
- `ffprobe_custom`

### 库

- `avcodec`
- `avformat`
- `avutil`
- `swresample`
- `swscale`
- `avfilter`
- `avdevice`

### 协议

- `file`
- `pipe`

### Demuxer

- `wav`
- `mp3`
- `aac`
- `flac`
- `ogg`
- `mov`
- `matroska`
- `avi`
- `hevc`

### Muxer

- `adts`
- `mp3`
- `ogg`
- `opus`
- `ipod`
- `mp4`
- `matroska`
- `hevc`

### Parser

- `aac`
- `flac`
- `mpegaudio`
- `h264`
- `hevc`
- `av1`

### Decoder

- `pcm_s16le`
- `pcm_s24le`
- `pcm_s32le`
- `pcm_f32le`
- `pcm_f64le`
- `mp3`
- `aac`
- `flac`
- `vorbis`
- `opus`
- `h264`
- `hevc`
- `libdav1d`

### Encoder

- `aac`
- `libmp3lame`
- `libvorbis`
- `libopus`
- `libx264`
- `libx265`

### 外部库

- `libmp3lame`
- `libvorbis`
- `libopus`
- `libx264`
- `libx265`
- `libdav1d`

### Bitstream Filter

- `aac_adtstoasc`
- `hevc_mp4toannexb`

## 注意事项

- Linux 构建脚本会删除并重建整个 `build/` 目录。
- Linux 脚本会在启动前清理同名容器 `ffmpeg_build`。
- macOS 和 Windows 构建脚本会重建 `build/workspace/`，并清理对应平台的 example 构建目录。
- `clean.sh` 只会删除 `build/`、`dist/`、`out/`，不会删除 `archive/` 或 `~/archive`。
- `prepare.sh` 和各平台构建脚本当前使用的归档目录并不一致。
- FFmpeg 配置显式开启了 `--enable-ffmpeg` 和 `--enable-ffprobe`，并通过 `--progs-suffix=_custom` 把程序名安装成 `ffmpeg_custom` / `ffprobe_custom`。
- FFmpeg 本身使用 `--disable-doc`，但第三方依赖安装时仍可能带出 `share/` 下的文档或 manpage 目录。

## 常用命令

```bash
./version.sh
./prepare.sh
./build_linux.sh
./build_macos.sh
./build_windows.sh
./clean.sh
```
