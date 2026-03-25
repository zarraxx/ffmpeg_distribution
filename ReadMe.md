# FFmpeg SDK

一个用于构建精简版、静态链接 FFmpeg SDK 的脚本仓库，面向 Linux、macOS 和 Windows 三类目标平台。

项目的目标不是产出 `ffmpeg`/`ffprobe` 命令行工具，而是产出可集成到业务程序中的头文件和静态库，并且默认关闭了网络、文档、自动探测等能力，尽量缩小体积和依赖面。

## 项目特点

- 默认构建静态库，不生成共享库。
- 默认不安装 `ffmpeg`/`ffprobe` 等程序，只安装库和头文件。
- 通过 `--disable-everything` 后按需开启模块，产物更可控。
- 关闭网络能力，仅保留本地文件和管道协议。
- 自动打包输出为 `tar.gz` 归档文件。
- 内置常用外部编解码依赖：`lame`、`libogg`、`libvorbis`、`opus`、`x264`、`x265`、`dav1d`。

## 当前版本

`./version.sh` 会输出当前 FFmpeg 版本。当前脚本中配置的版本如下：

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
| `prepare.sh` | 预下载源码压缩包 |
| `clean.sh` | 清理构建产物 |
| `version.sh` | 输出 FFmpeg 版本 |
| `example` | 基于静态 FFmpeg SDK 的示例工程入口 |
| `example/audio_convert` | 使用静态 FFmpeg SDK 的音频转码 demo，输出 `128 kbps / 48 kHz / 双声道 MP3` |
| `example/video_convert` | 使用静态 FFmpeg SDK 的视频转码 demo，输出 `720p MP4`，并把第一条音轨转成 `128 kbps / 48 kHz / 双声道 MP3` |
| `script/ffmpeg.sh` | 通用下载、依赖编译和 FFmpeg 配置逻辑 |
| `script/ffmpeg_centos_devtoolset.sh` | Linux 容器内构建逻辑 |
| `script/ffmpeg_darwin.sh` | macOS 构建逻辑 |
| `script/ffmpeg_win32.sh` | Windows 构建逻辑 |

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
- 默认使用 `podman`，如需切换到 Docker 可通过环境变量指定：

```bash
DOCKER=docker ./build_linux.sh
```

### macOS

- 需要可用的本地编译工具链
- 脚本会直接使用下面这个 CMake 路径：

```bash
$HOME/.local/cmake/cmake-3.27.9-macos-universal/CMake.app/Contents/bin
```

如果你的 CMake 不在这个位置，需要先自行调整 `build_macos.sh`。

### Windows

- 需要可用的 `bash`/`make`/`cmake`/`meson`/`ninja` 构建环境
- 脚本会直接使用下面这个 CMake 路径：

```bash
/opt/cmake/cmake-3.27.9-windows-x86_64/bin
```

如果本机环境不同，需要先自行调整 `build_windows.sh`。

## 快速开始

### 1. 查看版本

```bash
./version.sh
```

### 2. 可选：预下载源码包

```bash
./prepare.sh
```

说明：`prepare.sh` 当前会把源码包下载到 `~/archive`，而各平台构建脚本默认使用项目目录下的 `archive/`。如果你希望复用预下载文件，需要自行复制，或者统一修改脚本中的 `ARCHIVE_DIR`。

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

说明：三个 `build_*.sh` 在完成 FFmpeg 静态库构建后，会继续执行 `example/` 的 CMake 构建，并产出 `audio_convert` 和 `video_convert` 两个示例程序。

### 4. 清理产物

```bash
./clean.sh
```

## 输出目录

构建完成后会生成两个层面的产物：

- 解包目录：位于 `dist/`
- 压缩包：位于 `out/`

典型输出如下：

### Linux

- 目录：`dist/linux-<arch>/ffmpeg`
- 压缩包：`out/ffmpeg-linux-<arch>.tar.gz`

例如 `x86_64` 平台会生成：

```text
dist/linux-x86_64/ffmpeg
out/ffmpeg-linux-x86_64.tar.gz
```

### macOS

- 目录：`dist/darwin-<arch>/ffmpeg`
- 压缩包：`out/ffmpeg-darwin-<arch>.tar.gz`

注意：脚本会把 macOS 的 `arm64` 统一写成 `aarch64`。

### Windows

- 目录：`dist/windowx-x86_64/ffmpeg`
- 压缩包：`out/ffmpeg-windows-x86_64.tar.gz`

说明：目录名当前脚本中写的是 `windowx-x86_64`，README 保持与脚本实际行为一致。

## Example

`example/` 是统一的示例工程入口，会同时构建：

- `audio_convert`
- `video_convert`

直接使用构建好的静态 SDK 进行编译：

Linux:

```bash
cmake -S example -B build/example-linux -DFFMPEG_ROOT=$PWD/dist/linux-$(uname -m)/ffmpeg -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-linux --parallel
```

macOS:

```bash
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then ARCH=aarch64; fi
cmake -S example -B build/example-darwin -DFFMPEG_ROOT=$PWD/dist/darwin-$ARCH/ffmpeg -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-darwin --parallel
```

Windows:

```bash
cmake -S example -B build/example-windows -DFFMPEG_ROOT=$PWD/dist/windowx-x86_64/ffmpeg -DCMAKE_BUILD_TYPE=Release
cmake --build build/example-windows --parallel
```

### audio_convert

`example/audio_convert` 是一个基于 FFmpeg C API 的最小转码示例，用于把输入音频转换成：

- `128 kbps`
- `48 kHz`
- `双声道`
- `MP3`

Linux:

```bash
./build/example-linux/bin/audio_convert input.wav output.mp3
```

macOS:

```bash
./build/example-darwin/bin/audio_convert input.wav output.mp3
```

Windows:

```bash
./build/example-windows/bin/audio_convert.exe input.wav output.mp3
```

使用系统 `ffmpeg`/`ffprobe` 生成标准正弦波输入并批量验证 `audio_convert`：

```bash
chmod +x example/audio_convert/test_audio_convert.sh
./example/audio_convert/test_audio_convert.sh ./build/example-linux/bin/audio_convert
```

### video_convert

`example/video_convert` 会把输入视频转换成：

- `1280x720`
- `MP4`
- 视频编码：`H.264`
- 如果存在音轨：仅保留第一条音轨，并转成 `128 kbps / 48 kHz / 双声道 MP3`

Linux:

```bash
./build/example-linux/bin/video_convert input.mkv output.mp4
```

macOS:

```bash
./build/example-darwin/bin/video_convert input.mkv output.mp4
```

Windows:

```bash
./build/example-windows/bin/video_convert.exe input.mkv output.mp4
```

使用系统 `ffmpeg`/`ffprobe` 生成空画面加标准正弦波的测试视频，并批量验证 `video_convert`。
默认会覆盖：

- `AVI + x264`
- `MP4 + x265`
- `MKV + AV1`

```bash
chmod +x example/video_convert/test_video_convert.sh
./example/video_convert/test_video_convert.sh ./build/example-linux/bin/video_convert
```

## SDK 内容

当前 FFmpeg 配置会安装：

- 头文件
- 静态库

不会安装：

- `ffmpeg`
- `ffplay`
- `ffprobe`
- 文档

## 已启用的 FFmpeg 能力

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

- Linux 构建脚本会在启动前删除同名容器 `ffmpeg_build`。
- Linux 脚本会清空并重建项目下的 `build/` 工作目录。
- `clean.sh` 会删除项目下的 `build/`、`dist/`、`out/`、`archive/`。
- 当前配置显式关闭了 `network`、`zlib`、`bzlib`、`lzma`、`iconv`、`sdl2` 和自动探测能力，如需扩展功能，需要修改 [`script/ffmpeg.sh`](/opt/projects/ffmpeg_sdk/script/ffmpeg.sh)。

## 常用命令

```bash
./version.sh
./prepare.sh
./build_linux.sh
./build_macos.sh
./build_windows.sh
./clean.sh
```
