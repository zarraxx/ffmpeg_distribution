#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(realpath "$0")")"; pwd)"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <audio_convert_binary> [work_dir]"
    exit 1
fi

AUDIO_CONVERT_BIN="$(realpath "$1")"
WORK_DIR="${2:-$ROOT/test_work}"
INPUT_DIR="$WORK_DIR/inputs"
OUTPUT_DIR="$WORK_DIR/outputs"

if [ ! -x "$AUDIO_CONVERT_BIN" ]; then
    echo "audio_convert binary not found or not executable: $AUDIO_CONVERT_BIN"
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

run_host_tool() {
    env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH "$@"
}

run_example_binary() {
    if [ -n "${FFMPEG_EXAMPLE_LD_LIBRARY_PATH:-}" ]; then
        LD_LIBRARY_PATH="${FFMPEG_EXAMPLE_LD_LIBRARY_PATH}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$@"
        return
    fi

    if [ -n "${FFMPEG_EXAMPLE_DYLD_LIBRARY_PATH:-}" ]; then
        DYLD_LIBRARY_PATH="${FFMPEG_EXAMPLE_DYLD_LIBRARY_PATH}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$@"
        return
    fi

    "$@" || {
        rc=$?
        echo "$0 failed with exit code $rc"
        ls -la "$(dirname "$0")"
        exit $rc
    }
}

ENCODERS_OUTPUT="$(run_host_tool ffmpeg -hide_banner -encoders 2>/dev/null || true)"

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

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"

generate_tone() {
    local output_file=$1
    shift

    run_host_tool ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i "sine=frequency=1000:sample_rate=48000:duration=3" \
        -af "aformat=sample_rates=48000:sample_fmts=s16:channel_layouts=stereo" \
        "$@" \
        "$output_file"
}

generate_optional_tone() {
    local output_file=$1
    local description=$2
    shift 2

    if generate_tone "$output_file" "$@"; then
        return 0
    fi

    rm -f "$output_file"
    echo "Skipping ${description}: system ffmpeg could not encode it"
    return 1
}

echo "Generating sine-wave test inputs under $INPUT_DIR"
generate_tone "$INPUT_DIR/sine.wav"  -c:a pcm_s16le

MP3_ENCODER="$(select_encoder libmp3lame)"
generate_tone "$INPUT_DIR/sine.mp3"  -c:a "$MP3_ENCODER" -b:a 128k
generate_tone "$INPUT_DIR/sine.aac"  -c:a aac -b:a 128k
generate_tone "$INPUT_DIR/sine.flac" -c:a flac

if [ "$(uname -s)" = "Darwin" ]; then
    echo "Skipping OGG input generation on macOS: Homebrew ffmpeg Vorbis encoder is not reliable here"
elif OGG_ENCODER="$(select_encoder libvorbis vorbis)"; then
    generate_optional_tone "$INPUT_DIR/sine.ogg" "OGG input generation" -c:a "$OGG_ENCODER" -b:a 128k
else
    echo "Skipping OGG input generation: no Vorbis encoder in system ffmpeg"
fi

if OPUS_ENCODER="$(select_encoder libopus opus)"; then
    generate_optional_tone "$INPUT_DIR/sine.opus" "Opus input generation" -c:a "$OPUS_ENCODER" -b:a 128k
else
    echo "Skipping Opus input generation: no Opus encoder in system ffmpeg"
fi

echo "Running audio_convert tests"
for input_file in "$INPUT_DIR"/*; do
    base_name="$(basename "$input_file")"
    stem="${base_name%.*}"
    output_file="$OUTPUT_DIR/${stem}.mp3"

    echo "  converting $base_name"
    run_example_binary "$AUDIO_CONVERT_BIN" "$input_file" "$output_file"

    codec_name="$(run_host_tool ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$output_file")"
    sample_rate="$(run_host_tool ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$output_file")"
    channels="$(run_host_tool ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$output_file")"

    if [ "$codec_name" != "mp3" ]; then
        echo "Unexpected codec for $output_file: $codec_name"
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

echo "All audio_convert tests passed."
echo "Inputs : $INPUT_DIR"
echo "Outputs: $OUTPUT_DIR"
