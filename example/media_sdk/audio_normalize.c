#include "media_sdk.h"

#include "internal.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <string.h>

typedef struct AudioConvertContext {
    AVFormatContext *input_fmt;
    AVCodecContext *decoder_ctx;
    int audio_stream_index;

    AVFormatContext *output_fmt;
    AVCodecContext *encoder_ctx;
    AVStream *output_stream;

    SwrContext *resampler;
    AVAudioFifo *fifo;
    int64_t next_pts;
} AudioConvertContext;

static int audio_encode_and_write(
    AudioConvertContext *context,
    AVFrame *frame,
    char *error_message,
    size_t error_message_size
) {
    int ret = avcodec_send_frame(context->encoder_ctx, frame);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_frame", ret);
        return ret;
    }

    while (ret >= 0) {
        AVPacket *packet = av_packet_alloc();
        if (packet == NULL) {
            ffmpeg_example_set_error(error_message, error_message_size, "av_packet_alloc failed");
            return AVERROR(ENOMEM);
        }

        ret = avcodec_receive_packet(context->encoder_ctx, packet);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            av_packet_free(&packet);
            return 0;
        }
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_receive_packet", ret);
            av_packet_free(&packet);
            return ret;
        }

        av_packet_rescale_ts(packet, context->encoder_ctx->time_base, context->output_stream->time_base);
        packet->stream_index = context->output_stream->index;

        ret = av_interleaved_write_frame(context->output_fmt, packet);
        av_packet_free(&packet);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_interleaved_write_frame", ret);
            return ret;
        }
    }

    return 0;
}

static int audio_init_input(
    AudioConvertContext *context,
    const char *input_path,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    const AVCodec *decoder = NULL;
    AVStream *audio_stream = NULL;

    ret = avformat_open_input(&context->input_fmt, input_path, NULL, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_open_input", ret);
        return ret;
    }

    ret = avformat_find_stream_info(context->input_fmt, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_find_stream_info", ret);
        return ret;
    }

    ret = av_find_best_stream(context->input_fmt, AVMEDIA_TYPE_AUDIO, -1, -1, &decoder, 0);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_find_best_stream", ret);
        return ret;
    }
    context->audio_stream_index = ret;
    audio_stream = context->input_fmt->streams[context->audio_stream_index];

    context->decoder_ctx = avcodec_alloc_context3(decoder);
    if (context->decoder_ctx == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avcodec_alloc_context3 failed");
        return AVERROR(ENOMEM);
    }

    ret = avcodec_parameters_to_context(context->decoder_ctx, audio_stream->codecpar);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_parameters_to_context", ret);
        return ret;
    }

    ret = ffmpeg_example_ensure_channel_layout(
        &context->decoder_ctx->ch_layout,
        audio_stream->codecpar->ch_layout.nb_channels
    );
    if (ret < 0) {
        return ret;
    }

    ret = avcodec_open2(context->decoder_ctx, decoder, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_open2(decoder)", ret);
        return ret;
    }

    return 0;
}

static int audio_init_output(
    AudioConvertContext *context,
    const char *output_path,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    const AVCodec *encoder = avcodec_find_encoder_by_name("libmp3lame");
    if (encoder == NULL) {
        encoder = avcodec_find_encoder(AV_CODEC_ID_MP3);
    }
    if (encoder == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to find an MP3 encoder.");
        return AVERROR_ENCODER_NOT_FOUND;
    }

    ret = avformat_alloc_output_context2(&context->output_fmt, NULL, "mp3", output_path);
    if (ret < 0 || context->output_fmt == NULL) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_alloc_output_context2", ret);
        return ret < 0 ? ret : AVERROR_UNKNOWN;
    }

    context->output_stream = avformat_new_stream(context->output_fmt, NULL);
    if (context->output_stream == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avformat_new_stream failed");
        return AVERROR(ENOMEM);
    }

    context->encoder_ctx = avcodec_alloc_context3(encoder);
    if (context->encoder_ctx == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avcodec_alloc_context3 failed");
        return AVERROR(ENOMEM);
    }

    context->encoder_ctx->bit_rate = 128000;
    context->encoder_ctx->sample_rate = 48000;
    context->encoder_ctx->sample_fmt = ffmpeg_example_select_audio_encoder_sample_fmt(encoder);
    context->encoder_ctx->time_base = (AVRational){1, context->encoder_ctx->sample_rate};
    av_channel_layout_default(&context->encoder_ctx->ch_layout, 2);

    if (context->output_fmt->oformat->flags & AVFMT_GLOBALHEADER) {
        context->encoder_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    ret = avcodec_open2(context->encoder_ctx, encoder, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_open2(encoder)", ret);
        return ret;
    }

    ret = avcodec_parameters_from_context(context->output_stream->codecpar, context->encoder_ctx);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_parameters_from_context", ret);
        return ret;
    }
    context->output_stream->time_base = context->encoder_ctx->time_base;

    if (!(context->output_fmt->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&context->output_fmt->pb, output_path, AVIO_FLAG_WRITE);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "avio_open", ret);
            return ret;
        }
    }

    ret = avformat_write_header(context->output_fmt, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_write_header", ret);
        return ret;
    }

    return 0;
}

static int audio_init_processing(
    AudioConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret = ffmpeg_example_ensure_channel_layout(&context->decoder_ctx->ch_layout, 0);
    if (ret < 0) {
        return ret;
    }

    ret = swr_alloc_set_opts2(
        &context->resampler,
        &context->encoder_ctx->ch_layout,
        context->encoder_ctx->sample_fmt,
        context->encoder_ctx->sample_rate,
        &context->decoder_ctx->ch_layout,
        context->decoder_ctx->sample_fmt,
        context->decoder_ctx->sample_rate,
        0,
        NULL
    );
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "swr_alloc_set_opts2", ret);
        return ret;
    }

    ret = swr_init(context->resampler);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "swr_init", ret);
        return ret;
    }

    context->fifo = av_audio_fifo_alloc(
        context->encoder_ctx->sample_fmt,
        context->encoder_ctx->ch_layout.nb_channels,
        1
    );
    if (context->fifo == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_alloc failed");
        return AVERROR(ENOMEM);
    }

    return 0;
}

static int audio_add_converted_samples_to_fifo(
    AudioConvertContext *context,
    const AVFrame *input_frame,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    int output_samples;
    AVFrame *converted_frame = NULL;

    output_samples = av_rescale_rnd(
        swr_get_delay(context->resampler, context->decoder_ctx->sample_rate) + input_frame->nb_samples,
        context->encoder_ctx->sample_rate,
        context->decoder_ctx->sample_rate,
        AV_ROUND_UP
    );

    converted_frame = av_frame_alloc();
    if (converted_frame == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
        return AVERROR(ENOMEM);
    }

    converted_frame->nb_samples = output_samples;
    converted_frame->format = context->encoder_ctx->sample_fmt;
    converted_frame->sample_rate = context->encoder_ctx->sample_rate;
    ret = av_channel_layout_copy(&converted_frame->ch_layout, &context->encoder_ctx->ch_layout);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_channel_layout_copy", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    ret = av_frame_get_buffer(converted_frame, 0);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    ret = swr_convert(
        context->resampler,
        converted_frame->data,
        output_samples,
        (const uint8_t **)input_frame->data,
        input_frame->nb_samples
    );
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "swr_convert", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    converted_frame->nb_samples = ret;

    if (av_audio_fifo_realloc(context->fifo, av_audio_fifo_size(context->fifo) + converted_frame->nb_samples) < 0) {
        av_frame_free(&converted_frame);
        ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_realloc failed");
        return AVERROR(ENOMEM);
    }

    if (av_audio_fifo_write(context->fifo, (void **)converted_frame->data, converted_frame->nb_samples) < converted_frame->nb_samples) {
        av_frame_free(&converted_frame);
        ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_write failed");
        return AVERROR_UNKNOWN;
    }

    av_frame_free(&converted_frame);
    return 0;
}

static int audio_drain_fifo(
    AudioConvertContext *context,
    int flush,
    char *error_message,
    size_t error_message_size
) {
    int ret;

    while (av_audio_fifo_size(context->fifo) >= context->encoder_ctx->frame_size ||
           (flush && av_audio_fifo_size(context->fifo) > 0)) {
        int encoder_frame_samples = context->encoder_ctx->frame_size;
        int available_samples = av_audio_fifo_size(context->fifo);
        int samples_to_read;
        int samples_read;
        AVFrame *frame;

        if (encoder_frame_samples <= 0) {
            encoder_frame_samples = available_samples;
        }
        samples_to_read = available_samples < encoder_frame_samples ? available_samples : encoder_frame_samples;

        frame = av_frame_alloc();
        if (frame == NULL) {
            ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
            return AVERROR(ENOMEM);
        }

        frame->nb_samples = encoder_frame_samples;
        frame->format = context->encoder_ctx->sample_fmt;
        frame->sample_rate = context->encoder_ctx->sample_rate;
        ret = av_channel_layout_copy(&frame->ch_layout, &context->encoder_ctx->ch_layout);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_channel_layout_copy", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = av_frame_get_buffer(frame, 0);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer", ret);
            av_frame_free(&frame);
            return ret;
        }

        samples_read = av_audio_fifo_read(context->fifo, (void **)frame->data, samples_to_read);
        if (samples_read < samples_to_read) {
            av_frame_free(&frame);
            ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_read failed");
            return AVERROR_UNKNOWN;
        }

        if (samples_to_read < encoder_frame_samples) {
            av_samples_set_silence(
                frame->data,
                samples_to_read,
                encoder_frame_samples - samples_to_read,
                context->encoder_ctx->ch_layout.nb_channels,
                context->encoder_ctx->sample_fmt
            );
        } else {
            frame->nb_samples = samples_to_read;
        }

        frame->pts = context->next_pts;
        context->next_pts += frame->nb_samples;

        ret = audio_encode_and_write(context, frame, error_message, error_message_size);
        av_frame_free(&frame);
        if (ret < 0) {
            return ret;
        }
    }

    return 0;
}

static int audio_flush_resampler(
    AudioConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    while (1) {
        int pending_input_samples = swr_get_delay(context->resampler, context->decoder_ctx->sample_rate);
        int output_samples;
        AVFrame *frame;
        int ret;

        if (pending_input_samples <= 0) {
            return 0;
        }

        output_samples = av_rescale_rnd(
            pending_input_samples,
            context->encoder_ctx->sample_rate,
            context->decoder_ctx->sample_rate,
            AV_ROUND_UP
        );

        frame = av_frame_alloc();
        if (frame == NULL) {
            ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
            return AVERROR(ENOMEM);
        }

        frame->nb_samples = output_samples;
        frame->format = context->encoder_ctx->sample_fmt;
        frame->sample_rate = context->encoder_ctx->sample_rate;
        ret = av_channel_layout_copy(&frame->ch_layout, &context->encoder_ctx->ch_layout);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_channel_layout_copy", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = av_frame_get_buffer(frame, 0);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = swr_convert(context->resampler, frame->data, output_samples, NULL, 0);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "swr_convert(flush)", ret);
            av_frame_free(&frame);
            return ret;
        }

        if (ret == 0) {
            av_frame_free(&frame);
            return 0;
        }

        frame->nb_samples = ret;

        if (av_audio_fifo_realloc(context->fifo, av_audio_fifo_size(context->fifo) + frame->nb_samples) < 0) {
            av_frame_free(&frame);
            ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_realloc failed");
            return AVERROR(ENOMEM);
        }

        if (av_audio_fifo_write(context->fifo, (void **)frame->data, frame->nb_samples) < frame->nb_samples) {
            av_frame_free(&frame);
            ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_write failed");
            return AVERROR_UNKNOWN;
        }

        av_frame_free(&frame);
    }
}

static int audio_process(
    AudioConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    AVPacket *packet = av_packet_alloc();
    AVFrame *decoded_frame = av_frame_alloc();

    if (packet == NULL || decoded_frame == NULL) {
        ret = AVERROR(ENOMEM);
        ffmpeg_example_set_error(error_message, error_message_size, "Failed to allocate decode buffers");
        goto end;
    }

    while ((ret = av_read_frame(context->input_fmt, packet)) >= 0) {
        if (packet->stream_index != context->audio_stream_index) {
            av_packet_unref(packet);
            continue;
        }

        ret = avcodec_send_packet(context->decoder_ctx, packet);
        av_packet_unref(packet);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_packet", ret);
            goto end;
        }

        while ((ret = avcodec_receive_frame(context->decoder_ctx, decoded_frame)) >= 0) {
            ret = audio_add_converted_samples_to_fifo(context, decoded_frame, error_message, error_message_size);
            if (ret < 0) {
                goto end;
            }

            ret = audio_drain_fifo(context, 0, error_message, error_message_size);
            if (ret < 0) {
                goto end;
            }

            av_frame_unref(decoded_frame);
        }

        if (ret == AVERROR(EAGAIN)) {
            ret = 0;
            continue;
        }
        if (ret == AVERROR_EOF) {
            ret = 0;
            break;
        }
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_receive_frame", ret);
            goto end;
        }
    }

    if (ret == AVERROR_EOF) {
        ret = 0;
    }
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_read_frame", ret);
        goto end;
    }

    ret = avcodec_send_packet(context->decoder_ctx, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_packet(flush)", ret);
        goto end;
    }

    while ((ret = avcodec_receive_frame(context->decoder_ctx, decoded_frame)) >= 0) {
        ret = audio_add_converted_samples_to_fifo(context, decoded_frame, error_message, error_message_size);
        if (ret < 0) {
            goto end;
        }

        ret = audio_drain_fifo(context, 0, error_message, error_message_size);
        if (ret < 0) {
            goto end;
        }

        av_frame_unref(decoded_frame);
    }

    if (ret != AVERROR_EOF && ret != AVERROR(EAGAIN)) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_receive_frame(flush)", ret);
        goto end;
    }

    ret = audio_flush_resampler(context, error_message, error_message_size);
    if (ret < 0) {
        goto end;
    }

    ret = audio_drain_fifo(context, 1, error_message, error_message_size);
    if (ret < 0) {
        goto end;
    }

    ret = audio_encode_and_write(context, NULL, error_message, error_message_size);
    if (ret < 0) {
        goto end;
    }

    ret = av_write_trailer(context->output_fmt);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_write_trailer", ret);
    }

end:
    av_packet_free(&packet);
    av_frame_free(&decoded_frame);
    return ret;
}

static void audio_cleanup(AudioConvertContext *context) {
    if (context->fifo != NULL) {
        av_audio_fifo_free(context->fifo);
    }

    if (context->resampler != NULL) {
        swr_free(&context->resampler);
    }

    if (context->decoder_ctx != NULL) {
        avcodec_free_context(&context->decoder_ctx);
    }

    if (context->encoder_ctx != NULL) {
        avcodec_free_context(&context->encoder_ctx);
    }

    if (context->input_fmt != NULL) {
        avformat_close_input(&context->input_fmt);
    }

    if (context->output_fmt != NULL) {
        if (!(context->output_fmt->oformat->flags & AVFMT_NOFILE) && context->output_fmt->pb != NULL) {
            avio_closep(&context->output_fmt->pb);
        }
        avformat_free_context(context->output_fmt);
    }
}

int ffmpeg_example_normalize_audio(
    const char *input_path,
    const char *output_path,
    char *error_message,
    size_t error_message_size
) {
    AudioConvertContext context;
    int ret;

    memset(&context, 0, sizeof(context));
    context.audio_stream_index = -1;
    ffmpeg_example_clear_error(error_message, error_message_size);

    ret = audio_init_input(&context, input_path, error_message, error_message_size);
    if (ret < 0) {
        audio_cleanup(&context);
        return ret;
    }

    ret = audio_init_output(&context, output_path, error_message, error_message_size);
    if (ret < 0) {
        audio_cleanup(&context);
        return ret;
    }

    ret = audio_init_processing(&context, error_message, error_message_size);
    if (ret < 0) {
        audio_cleanup(&context);
        return ret;
    }

    ret = audio_process(&context, error_message, error_message_size);
    audio_cleanup(&context);
    return ret;
}
