# FFmpeg SDK

[![night-build](https://github.com/zarraxx/ffmpeg_distribution/actions/workflows/night-build.yml/badge.svg)](https://github.com/zarraxx/ffmpeg_distribution/actions/workflows/night-build.yml)

English | [简体中文](./README.zh-CN.md)

Scripted FFmpeg SDK builds for Linux, macOS, and Windows. The project provides both static and shared SDK variants, and each variant ships the `ffmpeg_custom` and `ffprobe_custom` validation binaries alongside headers and libraries.

The build scripts also compile and test the example applications under `example/`, so both SDK variants are exercised by real integration builds.

## Highlights

- Produces both `ffmpeg-static` and `ffmpeg-shared`.
- Installs `bin/ffmpeg_custom` and `bin/ffprobe_custom` in both variants.
- Keeps FFmpeg small by starting from `--disable-everything` and selectively enabling features.
- Disables networking, autodetect, `iconv`, `zlib`, `bzlib`, `lzma`, and `sdl2` by default.
- Builds common external codec dependencies: `lame`, `libogg`, `libvorbis`, `opus`, `x264`, `x265`, and `dav1d`.
- Packages the results into `out/` and runs example regression tests after the SDK build.

## Versions

`./version.sh` prints the FFmpeg version. Dependency versions are defined in [`script/ffmpeg.sh`](/opt/projects/ffmpeg_sdk/script/ffmpeg.sh).

| Component | Version |
| --- | --- |
| FFmpeg | `8.1` |
| lame | `3.100` |
| libogg | `1.3.6` |
| libvorbis | `1.3.7` |
| opus | `1.6.1` |
| x264 | `stable-165` |
| x265 | `4.1` |
| dav1d | `1.5.3` |

## Repository Layout

| Path | Description |
| --- | --- |
| `build_linux.sh` | Linux entry point; builds inside `podman` or `docker` by default |
| `build_macos.sh` | macOS entry point |
| `build_windows.sh` | Windows entry point |
| `prepare.sh` | Pre-downloads source archives into `~/archive` |
| `clean.sh` | Removes `build/`, `dist/`, and `out/` |
| `version.sh` | Prints the FFmpeg version |
| `script/ffmpeg.sh` | Shared download, dependency, and FFmpeg configure logic |
| `script/ffmpeg_test.sh` | Shared example build and test helper |
| `example/audio_convert` | Audio transcoding sample that writes `128 kbps / 48 kHz / stereo MP3` |
| `example/video_convert` | Video transcoding sample that writes `720p MP4` |
| `example/media_info` | Media inspection sample that prints JSON |

## Requirements

### Common

- `bash`
- `make`
- `tar`
- `wget`
- `cmake`
- `meson`
- `ninja`
- A working C/C++ toolchain

### Linux

- `podman` or `docker`
- Default image: `registry.cn-hangzhou.aliyuncs.com/zarra/centos:x-tools-base`

Switch to Docker if needed:

```bash
DOCKER=docker ./build_linux.sh
```

### macOS

The script expects CMake at:

```bash
$HOME/.local/cmake/cmake-3.27.9-macos-universal/CMake.app/Contents/bin
```

Adjust [`build_macos.sh`](/opt/projects/ffmpeg_sdk/build_macos.sh) if your local setup differs.

### Windows

The script expects CMake at:

```bash
/opt/cmake/cmake-3.27.9-windows-x86_64/bin
```

Adjust [`build_windows.sh`](/opt/projects/ffmpeg_sdk/build_windows.sh) if your local setup differs.

## Quick Start

### 1. Check the FFmpeg version

```bash
./version.sh
```

### 2. Optional: pre-download source archives

```bash
./prepare.sh
```

Note: `prepare.sh` downloads into `~/archive`, while the platform build scripts read from the repository-local `archive/` directory. If you want to reuse pre-downloaded sources, sync those locations or update the scripts to use the same `ARCHIVE_DIR`.

### 3. Build

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

After packaging the SDK, each build script also:

- builds one example tree against `ffmpeg-static`
- builds one example tree against `ffmpeg-shared`
- installs a system `ffmpeg` package for test generation
- runs the `audio_convert` and `video_convert` test scripts
- performs extra shared-library runtime checks on `ffmpeg_custom`

### 4. Clean build outputs

```bash
./clean.sh
```

## Output Layout

Builds generate both unpacked directories under `dist/` and tarballs under `out/`.

### SDK roots

Each platform build creates:

- `dist/<platform>/ffmpeg-static`
- `dist/<platform>/ffmpeg-shared`

Each SDK root contains:

- `bin/ffmpeg_custom`
- `bin/ffprobe_custom`
- `include/`
- `lib/` and, depending on platform, `lib64/`
- `lib/pkgconfig` and, depending on platform, `lib64/pkgconfig`

Current Linux output already present in this repository:

```text
dist/linux-x86_64/ffmpeg-static
dist/linux-x86_64/ffmpeg-shared
out/ffmpeg-linux-x86_64.tar.gz
```

### Archive naming

Linux:

- directories: `dist/linux-<arch>/ffmpeg-static` and `dist/linux-<arch>/ffmpeg-shared`
- tarball: `out/ffmpeg-linux-<arch>.tar.gz`

macOS:

- directories: `dist/darwin-<arch>/ffmpeg-static` and `dist/darwin-<arch>/ffmpeg-shared`
- tarball: `out/ffmpeg-darwin-<arch>.tar.gz`

Note: the scripts normalize macOS `arm64` to `aarch64`.

Windows:

- directories: `dist/windows-x86_64/ffmpeg-static` and `dist/windows-x86_64/ffmpeg-shared`
- tarball: `out/ffmpeg-windows-x86_64.tar.gz`

## Using the SDK

`example/` is the shared integration sample project. When configuring examples manually, pass `-DFFMPEG_ROOT=...` explicitly so you can target either the static or shared SDK.

### Build examples against the static SDK

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

### Build examples against the shared SDK

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

## Example Applications

The example project currently builds:

- `audio_convert`
- `video_convert`
- `media_info`

Typical output locations:

- `build/example-linux-x86_64/static/bin/`
- `build/example-linux-x86_64/shared/bin/`

### `audio_convert`

```bash
./build/example-linux-x86_64/static/bin/audio_convert input.wav output.mp3
```

Converts input audio to `128 kbps / 48 kHz / stereo MP3`.

### `video_convert`

```bash
./build/example-linux-x86_64/static/bin/video_convert input.mkv output.mp4
```

Converts input video to:

- `1280x720`
- `MP4`
- `H.264` video
- first audio track only, re-encoded as `128 kbps / 48 kHz / stereo MP3` when audio is present

### `media_info`

```bash
./build/example-linux-x86_64/static/bin/media_info input.mp4
```

Prints JSON-formatted media metadata, including container information, duration, streams, and tags.

### Automated example tests

The build scripts run:

- [`example/audio_convert/test_audio_convert.sh`](/opt/projects/ffmpeg_sdk/example/audio_convert/test_audio_convert.sh)
- [`example/video_convert/test_video_convert.sh`](/opt/projects/ffmpeg_sdk/example/video_convert/test_video_convert.sh)

To run them manually on Linux:

```bash
./example/audio_convert/test_audio_convert.sh ./build/example-linux-x86_64/static/bin/audio_convert
./example/video_convert/test_video_convert.sh ./build/example-linux-x86_64/static/bin/video_convert
```

## Enabled FFmpeg Features

The following lists are taken directly from the current configure block in [`script/ffmpeg.sh`](/opt/projects/ffmpeg_sdk/script/ffmpeg.sh).

### Programs

- `ffmpeg`
- `ffprobe`

Installed as:

- `ffmpeg_custom`
- `ffprobe_custom`

### Libraries

- `avcodec`
- `avformat`
- `avutil`
- `swresample`
- `swscale`
- `avfilter`
- `avdevice`

### Protocols

- `file`
- `pipe`

### Demuxers

- `wav`
- `mp3`
- `aac`
- `flac`
- `ogg`
- `mov`
- `matroska`
- `avi`
- `hevc`

### Muxers

- `adts`
- `mp3`
- `ogg`
- `opus`
- `ipod`
- `mp4`
- `matroska`
- `hevc`

### Parsers

- `aac`
- `flac`
- `mpegaudio`
- `h264`
- `hevc`
- `av1`

### Decoders

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

### Encoders

- `aac`
- `libmp3lame`
- `libvorbis`
- `libopus`
- `libx264`
- `libx265`

### External Libraries

- `libmp3lame`
- `libvorbis`
- `libopus`
- `libx264`
- `libx265`
- `libdav1d`

### Bitstream Filters

- `aac_adtstoasc`
- `hevc_mp4toannexb`

## Notes

- `build_linux.sh` removes and recreates the entire `build/` directory.
- The Linux build script removes any existing container named `ffmpeg_build` before starting.
- The macOS and Windows scripts recreate `build/workspace/` and the platform-specific example build directories.
- `clean.sh` removes `build/`, `dist/`, and `out/`, but does not remove `archive/` or `~/archive`.
- `prepare.sh` and the platform build scripts currently use different archive locations.
- FFmpeg is built with `--enable-ffmpeg`, `--enable-ffprobe`, and `--progs-suffix=_custom`, which is why the installed binaries are named `ffmpeg_custom` and `ffprobe_custom`.
- FFmpeg itself is configured with `--disable-doc`, but third-party dependency installs may still populate `share/` with docs or manpages.

## Common Commands

```bash
./version.sh
./prepare.sh
./build_linux.sh
./build_macos.sh
./build_windows.sh
./clean.sh
```
