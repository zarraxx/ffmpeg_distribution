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

ENCODERS_OUTPUT="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"

find_font_file() {
    local candidate
    local windows_root

    if command -v fc-match >/dev/null 2>&1; then
        candidate="$(fc-match -f '%{file}\n' "DejaVu Sans" 2>/dev/null | head -n 1 || true)"
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi

        candidate="$(fc-match -f '%{file}\n' "Arial" 2>/dev/null | head -n 1 || true)"
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    fi

    for candidate in \
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/TTF/DejaVuSans.ttf" \
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf" \
        "/System/Library/Fonts/Supplemental/Arial.ttf" \
        "/Library/Fonts/Arial.ttf" \
        "/System/Library/Fonts/Supplemental/Tahoma.ttf" \
        "/c/Windows/Fonts/arial.ttf" \
        "/c/Windows/Fonts/ARIAL.TTF" \
        "/c/Windows/Fonts/segoeui.ttf" \
        "/c/Windows/Fonts/tahoma.ttf" \
        "/c/windows/Fonts/arial.ttf" \
        "/c/windows/Fonts/segoeui.ttf" \
        "/c/windows/Fonts/tahoma.ttf" \
        "/mnt/c/Windows/Fonts/arial.ttf" \
        "/mnt/c/Windows/Fonts/segoeui.ttf" \
        "/mnt/c/Windows/Fonts/tahoma.ttf"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    if [ -n "${WINDIR:-}" ] && command -v cygpath >/dev/null 2>&1; then
        windows_root="$(cygpath -u "$WINDIR" 2>/dev/null || true)"
        for candidate in \
            "$windows_root/Fonts/arial.ttf" \
            "$windows_root/Fonts/ARIAL.TTF" \
            "$windows_root/Fonts/segoeui.ttf" \
            "$windows_root/Fonts/tahoma.ttf"; do
            if [ -f "$candidate" ]; then
                echo "$candidate"
                return 0
            fi
        done
    fi

    return 1
}

normalize_font_file_for_ffmpeg() {
    local font_path=$1

    font_path="${font_path//\\//}"

    if [[ "$font_path" =~ ^[A-Za-z]:/ ]] && command -v cygpath >/dev/null 2>&1; then
        font_path="$(cygpath -u "$font_path" 2>/dev/null || printf '%s' "$font_path")"
    fi

    printf '%s\n' "$font_path"
}

encoder_available() {
    local encoder_name=$1

    grep -Eq "[[:space:]]${encoder_name}([[:space:]]|$)" <<<"$ENCODERS_OUTPUT"
}

select_encoder() {
    local encoder_name

    for encoder_name in "$@"; do
        if encoder_available "$encoder_name"; then
            echo "$encoder_name"
            return 0
        fi
    done

    return 1
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

FONT_FILE="$(find_font_file || true)"
if [ -z "$FONT_FILE" ]; then
    echo "No suitable font file found for drawtext"
    exit 1
fi
FONT_FILE="$(normalize_font_file_for_ffmpeg "$FONT_FILE")"

echo "Generating video test inputs under $INPUT_DIR"
INPUT_COUNT=0

if X264_ENCODER="$(select_encoder libx264)"; then
    generate_video "$INPUT_DIR/blank_x264_avi.avi" \
        "$FONT_FILE" \
        -c:v "$X264_ENCODER" -preset medium -crf 23 \
        -c:a mp3 -b:a 128k
    INPUT_COUNT=$((INPUT_COUNT + 1))
else
    echo "Skipping AVI+x264 input generation: no x264 encoder in system ffmpeg"
fi

if X265_ENCODER="$(select_encoder libx265)"; then
    generate_video "$INPUT_DIR/blank_x265_mp4.mp4" \
        "$FONT_FILE" \
        -c:v "$X265_ENCODER" -preset medium -crf 28 -tag:v hvc1 \
        -c:a aac -b:a 128k
    INPUT_COUNT=$((INPUT_COUNT + 1))
else
    echo "Skipping MP4+x265 input generation: no x265 encoder in system ffmpeg"
fi

if AV1_ENCODER="$(select_encoder libaom-av1 librav1e libsvtav1)"; then
    if [ "$AV1_ENCODER" = "libaom-av1" ]; then
        AV1_VIDEO_ARGS="-c:v $AV1_ENCODER -crf 34 -b:v 0 -cpu-used 8 -row-mt 1"
    elif [ "$AV1_ENCODER" = "librav1e" ]; then
        AV1_VIDEO_ARGS="-c:v $AV1_ENCODER -qp 90 -speed 10"
    else
        AV1_VIDEO_ARGS="-c:v $AV1_ENCODER -crf 40 -preset 12"
    fi

    if OPUS_ENCODER="$(select_encoder libopus opus)"; then
        # shellcheck disable=SC2086
        generate_video "$INPUT_DIR/blank_av1_mkv.mkv" \
            "$FONT_FILE" \
            $AV1_VIDEO_ARGS \
            -c:a "$OPUS_ENCODER" -b:a 128k
        INPUT_COUNT=$((INPUT_COUNT + 1))
    else
        echo "Skipping MKV+AV1 input generation: no Opus encoder in system ffmpeg"
    fi
else
    echo "Skipping MKV+AV1 input generation: no AV1 encoder in system ffmpeg"
fi

if [ "$INPUT_COUNT" -eq 0 ]; then
    echo "No video inputs were generated. System ffmpeg lacks the required encoders."
    exit 1
fi

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
