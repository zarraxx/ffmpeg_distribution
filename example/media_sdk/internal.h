#ifndef FFMPEG_EXAMPLE_INTERNAL_H
#define FFMPEG_EXAMPLE_INTERNAL_H

#include <libavcodec/avcodec.h>
#include <libavutil/error.h>
#include <libavutil/pixfmt.h>
#include <libavutil/samplefmt.h>
#include <stddef.h>

void ffmpeg_example_clear_error(char *error_message, size_t error_message_size);
void ffmpeg_example_set_error(
    char *error_message,
    size_t error_message_size,
    const char *format,
    ...
);
void ffmpeg_example_set_av_error(
    char *error_message,
    size_t error_message_size,
    const char *step,
    int errnum
);

int ffmpeg_example_ensure_channel_layout(AVChannelLayout *layout, int fallback_channels);
enum AVSampleFormat ffmpeg_example_select_audio_encoder_sample_fmt(const AVCodec *encoder);
enum AVPixelFormat ffmpeg_example_select_video_encoder_pixel_fmt(const AVCodec *encoder);

#endif
