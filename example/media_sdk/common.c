#include "internal.h"

#include <libavutil/channel_layout.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

void ffmpeg_example_clear_error(char *error_message, size_t error_message_size) {
    if (error_message != NULL && error_message_size > 0) {
        error_message[0] = '\0';
    }
}

void ffmpeg_example_set_error(
    char *error_message,
    size_t error_message_size,
    const char *format,
    ...
) {
    va_list args;

    if (error_message == NULL || error_message_size == 0) {
        return;
    }

    va_start(args, format);
    vsnprintf(error_message, error_message_size, format, args);
    va_end(args);
}

void ffmpeg_example_set_av_error(
    char *error_message,
    size_t error_message_size,
    const char *step,
    int errnum
) {
    char buffer[AV_ERROR_MAX_STRING_SIZE] = {0};

    av_strerror(errnum, buffer, sizeof(buffer));
    ffmpeg_example_set_error(error_message, error_message_size, "%s failed: %s", step, buffer);
}

int ffmpeg_example_ensure_channel_layout(AVChannelLayout *layout, int fallback_channels) {
    if (layout->nb_channels > 0) {
        return 0;
    }

    if (fallback_channels <= 0) {
        fallback_channels = 1;
    }

    av_channel_layout_default(layout, fallback_channels);
    return 0;
}

enum AVSampleFormat ffmpeg_example_select_audio_encoder_sample_fmt(const AVCodec *encoder) {
    static const enum AVSampleFormat preferred_formats[] = {
        AV_SAMPLE_FMT_S32P,
        AV_SAMPLE_FMT_FLTP,
        AV_SAMPLE_FMT_S16P,
        AV_SAMPLE_FMT_S16,
    };
    size_t i;

    if (encoder->sample_fmts == NULL) {
        return AV_SAMPLE_FMT_FLTP;
    }

    for (i = 0; i < sizeof(preferred_formats) / sizeof(preferred_formats[0]); ++i) {
        const enum AVSampleFormat *sample_fmt = encoder->sample_fmts;
        while (*sample_fmt != AV_SAMPLE_FMT_NONE) {
            if (*sample_fmt == preferred_formats[i]) {
                return *sample_fmt;
            }
            ++sample_fmt;
        }
    }

    return encoder->sample_fmts[0];
}

enum AVPixelFormat ffmpeg_example_select_video_encoder_pixel_fmt(const AVCodec *encoder) {
    const enum AVPixelFormat *pixel_format = encoder->pix_fmts;

    if (pixel_format == NULL) {
        return AV_PIX_FMT_YUV420P;
    }

    while (*pixel_format != AV_PIX_FMT_NONE) {
        if (*pixel_format == AV_PIX_FMT_YUV420P) {
            return *pixel_format;
        }
        ++pixel_format;
    }

    return encoder->pix_fmts[0];
}
