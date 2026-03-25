#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(realpath "$0")")"; pwd)"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <video_convert_binary> [work_dir]"
    exit 1
fi

VIDEO_CONVERT_BIN="$(realpath "$1")"
WORK_DIR="${2:-$ROOT/test_work}"
INPUT_DIR="$WORK_DIR/inputs"
OUTPUT_DIR="$WORK_DIR/outputs"

if [ ! -x "$VIDEO_CONVERT_BIN" ]; then
    echo "video_convert binary not found or not executable: $VIDEO_CONVERT_BIN"
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg not found in PATH"
    exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe not found in PATH"
    exit 1
fi

find_font_file() {
    local candidate

    for candidate in \
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/TTF/DejaVuSans.ttf"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

require_encoder() {
    local encoder_name=$1
    local encoders_output

    encoders_output="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"
    if ! grep -Eq "[[:space:]]${encoder_name}([[:space:]]|$)" <<<"$encoders_output"; then
        echo "Required encoder not found in system ffmpeg: ${encoder_name}"
        exit 1
    fi
}

generate_video() {
    local output_file=$1
    shift
    local font_file=$1
    shift

    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i "color=c=black:s=1280x720:r=30:d=3" \
        -f lavfi -i "sine=frequency=1000:sample_rate=48000:duration=3" \
        -shortest \
        -pix_fmt yuv420p \
        -vf "drawtext=fontfile='${font_file}':text='DemoVideo':fontcolor=white:fontsize=54:x=(w-text_w)/2:y=(h-text_h)/2,format=yuv420p" \
        -ac 2 \
        -ar 48000 \
        "$@" \
        "$output_file"
}

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"

require_encoder "libx264"
require_encoder "libx265"
require_encoder "libaom-av1"

FONT_FILE="$(find_font_file || true)"
if [ -z "$FONT_FILE" ]; then
    echo "No suitable font file found for drawtext"
    exit 1
fi

echo "Generating video test inputs under $INPUT_DIR"
generate_video "$INPUT_DIR/blank_x264_avi.avi" \
    "$FONT_FILE" \
    -c:v libx264 -preset medium -crf 23 \
    -c:a mp3 -b:a 128k
generate_video "$INPUT_DIR/blank_x265_mp4.mp4" \
    "$FONT_FILE" \
    -c:v libx265 -preset medium -crf 28 -tag:v hvc1 \
    -c:a aac -b:a 128k
generate_video "$INPUT_DIR/blank_av1_mkv.mkv" \
    "$FONT_FILE" \
    -c:v libaom-av1 -crf 34 -b:v 0 -cpu-used 8 -row-mt 1 \
    -c:a libopus -b:a 128k

echo "Running video_convert tests"
for input_file in "$INPUT_DIR"/*; do
    base_name="$(basename "$input_file")"
    stem="${base_name%.*}"
    output_file="$OUTPUT_DIR/${stem}.mp4"

    echo "  converting $base_name"
    "$VIDEO_CONVERT_BIN" "$input_file" "$output_file"

    video_codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output_file")"
    width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$output_file")"
    height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$output_file")"
    audio_codec="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$output_file")"
    sample_rate="$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$output_file")"
    channels="$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$output_file")"

    if [ "$video_codec" != "h264" ]; then
        echo "Unexpected video codec for $output_file: $video_codec"
        exit 1
    fi

    if [ "$width" != "1280" ] || [ "$height" != "720" ]; then
        echo "Unexpected video size for $output_file: ${width}x${height}"
        exit 1
    fi

    if [ "$audio_codec" != "mp3" ]; then
        echo "Unexpected audio codec for $output_file: $audio_codec"
        exit 1
    fi

    if [ "$sample_rate" != "48000" ]; then
        echo "Unexpected sample rate for $output_file: $sample_rate"
        exit 1
    fi

    if [ "$channels" != "2" ]; then
        echo "Unexpected channel count for $output_file: $channels"
        exit 1
    fi
done

echo "All video_convert tests passed."
echo "Inputs : $INPUT_DIR"
echo "Outputs: $OUTPUT_DIR"
