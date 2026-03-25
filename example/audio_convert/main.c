#include <inttypes.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <stdio.h>
#include <stdlib.h>
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

static void print_usage(const char *program) {
    fprintf(stderr, "Usage: %s <input_audio> <output_mp3>\n", program);
}

static void log_error(const char *step, int errnum) {
    char buffer[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(errnum, buffer, sizeof(buffer));
    fprintf(stderr, "%s failed: %s\n", step, buffer);
}

static int ensure_channel_layout(AVChannelLayout *layout, int fallback_channels) {
    if (layout->nb_channels > 0) {
        return 0;
    }

    if (fallback_channels <= 0) {
        fallback_channels = 1;
    }

    av_channel_layout_default(layout, fallback_channels);
    return 0;
}

static enum AVSampleFormat select_encoder_sample_fmt(const AVCodec *encoder) {
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

static int encode_and_write(AudioConvertContext *context, AVFrame *frame) {
    int ret = avcodec_send_frame(context->encoder_ctx, frame);
    if (ret < 0) {
        log_error("avcodec_send_frame", ret);
        return ret;
    }

    while (ret >= 0) {
        AVPacket *packet = av_packet_alloc();
        if (packet == NULL) {
            return AVERROR(ENOMEM);
        }

        ret = avcodec_receive_packet(context->encoder_ctx, packet);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            av_packet_free(&packet);
            return 0;
        }
        if (ret < 0) {
            log_error("avcodec_receive_packet", ret);
            av_packet_free(&packet);
            return ret;
        }

        av_packet_rescale_ts(packet, context->encoder_ctx->time_base, context->output_stream->time_base);
        packet->stream_index = context->output_stream->index;

        ret = av_interleaved_write_frame(context->output_fmt, packet);
        av_packet_free(&packet);
        if (ret < 0) {
            log_error("av_interleaved_write_frame", ret);
            return ret;
        }
    }

    return 0;
}

static int init_input(AudioConvertContext *context, const char *input_path) {
    int ret;
    const AVCodec *decoder = NULL;
    AVStream *audio_stream = NULL;

    ret = avformat_open_input(&context->input_fmt, input_path, NULL, NULL);
    if (ret < 0) {
        log_error("avformat_open_input", ret);
        return ret;
    }

    ret = avformat_find_stream_info(context->input_fmt, NULL);
    if (ret < 0) {
        log_error("avformat_find_stream_info", ret);
        return ret;
    }

    ret = av_find_best_stream(context->input_fmt, AVMEDIA_TYPE_AUDIO, -1, -1, &decoder, 0);
    if (ret < 0) {
        log_error("av_find_best_stream", ret);
        return ret;
    }
    context->audio_stream_index = ret;
    audio_stream = context->input_fmt->streams[context->audio_stream_index];

    context->decoder_ctx = avcodec_alloc_context3(decoder);
    if (context->decoder_ctx == NULL) {
        return AVERROR(ENOMEM);
    }

    ret = avcodec_parameters_to_context(context->decoder_ctx, audio_stream->codecpar);
    if (ret < 0) {
        log_error("avcodec_parameters_to_context", ret);
        return ret;
    }

    ret = ensure_channel_layout(&context->decoder_ctx->ch_layout, audio_stream->codecpar->ch_layout.nb_channels);
    if (ret < 0) {
        return ret;
    }

    ret = avcodec_open2(context->decoder_ctx, decoder, NULL);
    if (ret < 0) {
        log_error("avcodec_open2(decoder)", ret);
        return ret;
    }

    return 0;
}

static int init_output(AudioConvertContext *context, const char *output_path) {
    int ret;
    const AVCodec *encoder = avcodec_find_encoder_by_name("libmp3lame");
    if (encoder == NULL) {
        encoder = avcodec_find_encoder(AV_CODEC_ID_MP3);
    }
    if (encoder == NULL) {
        fprintf(stderr, "Unable to find an MP3 encoder.\n");
        return AVERROR_ENCODER_NOT_FOUND;
    }

    ret = avformat_alloc_output_context2(&context->output_fmt, NULL, "mp3", output_path);
    if (ret < 0 || context->output_fmt == NULL) {
        log_error("avformat_alloc_output_context2", ret);
        return ret < 0 ? ret : AVERROR_UNKNOWN;
    }

    context->output_stream = avformat_new_stream(context->output_fmt, NULL);
    if (context->output_stream == NULL) {
        return AVERROR(ENOMEM);
    }

    context->encoder_ctx = avcodec_alloc_context3(encoder);
    if (context->encoder_ctx == NULL) {
        return AVERROR(ENOMEM);
    }

    context->encoder_ctx->bit_rate = 128000;
    context->encoder_ctx->sample_rate = 48000;
    context->encoder_ctx->sample_fmt = select_encoder_sample_fmt(encoder);
    context->encoder_ctx->time_base = (AVRational){1, context->encoder_ctx->sample_rate};
    av_channel_layout_default(&context->encoder_ctx->ch_layout, 2);

    if (context->output_fmt->oformat->flags & AVFMT_GLOBALHEADER) {
        context->encoder_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    ret = avcodec_open2(context->encoder_ctx, encoder, NULL);
    if (ret < 0) {
        log_error("avcodec_open2(encoder)", ret);
        return ret;
    }

    ret = avcodec_parameters_from_context(context->output_stream->codecpar, context->encoder_ctx);
    if (ret < 0) {
        log_error("avcodec_parameters_from_context", ret);
        return ret;
    }
    context->output_stream->time_base = context->encoder_ctx->time_base;

    if (!(context->output_fmt->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&context->output_fmt->pb, output_path, AVIO_FLAG_WRITE);
        if (ret < 0) {
            log_error("avio_open", ret);
            return ret;
        }
    }

    ret = avformat_write_header(context->output_fmt, NULL);
    if (ret < 0) {
        log_error("avformat_write_header", ret);
        return ret;
    }

    return 0;
}

static int init_processing(AudioConvertContext *context) {
    int ret = ensure_channel_layout(&context->decoder_ctx->ch_layout, 0);
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
        log_error("swr_alloc_set_opts2", ret);
        return ret;
    }

    ret = swr_init(context->resampler);
    if (ret < 0) {
        log_error("swr_init", ret);
        return ret;
    }

    context->fifo = av_audio_fifo_alloc(
        context->encoder_ctx->sample_fmt,
        context->encoder_ctx->ch_layout.nb_channels,
        1
    );
    if (context->fifo == NULL) {
        return AVERROR(ENOMEM);
    }

    return 0;
}

static int add_converted_samples_to_fifo(AudioConvertContext *context, const AVFrame *input_frame) {
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
        return AVERROR(ENOMEM);
    }

    converted_frame->nb_samples = output_samples;
    converted_frame->format = context->encoder_ctx->sample_fmt;
    converted_frame->sample_rate = context->encoder_ctx->sample_rate;
    ret = av_channel_layout_copy(&converted_frame->ch_layout, &context->encoder_ctx->ch_layout);
    if (ret < 0) {
        log_error("av_channel_layout_copy", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    ret = av_frame_get_buffer(converted_frame, 0);
    if (ret < 0) {
        log_error("av_frame_get_buffer", ret);
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
        log_error("swr_convert", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    converted_frame->nb_samples = ret;

    if (av_audio_fifo_realloc(context->fifo, av_audio_fifo_size(context->fifo) + converted_frame->nb_samples) < 0) {
        av_frame_free(&converted_frame);
        return AVERROR(ENOMEM);
    }

    if (av_audio_fifo_write(context->fifo, (void **)converted_frame->data, converted_frame->nb_samples) < converted_frame->nb_samples) {
        av_frame_free(&converted_frame);
        return AVERROR_UNKNOWN;
    }

    av_frame_free(&converted_frame);
    return 0;
}

static int drain_fifo(AudioConvertContext *context, int flush) {
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
            return AVERROR(ENOMEM);
        }

        frame->nb_samples = encoder_frame_samples;
        frame->format = context->encoder_ctx->sample_fmt;
        frame->sample_rate = context->encoder_ctx->sample_rate;
        ret = av_channel_layout_copy(&frame->ch_layout, &context->encoder_ctx->ch_layout);
        if (ret < 0) {
            log_error("av_channel_layout_copy", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = av_frame_get_buffer(frame, 0);
        if (ret < 0) {
            log_error("av_frame_get_buffer", ret);
            av_frame_free(&frame);
            return ret;
        }

        samples_read = av_audio_fifo_read(context->fifo, (void **)frame->data, samples_to_read);
        if (samples_read < samples_to_read) {
            av_frame_free(&frame);
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

        ret = encode_and_write(context, frame);
        av_frame_free(&frame);
        if (ret < 0) {
            return ret;
        }
    }

    return 0;
}

static int flush_resampler(AudioConvertContext *context) {
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
            return AVERROR(ENOMEM);
        }

        frame->nb_samples = output_samples;
        frame->format = context->encoder_ctx->sample_fmt;
        frame->sample_rate = context->encoder_ctx->sample_rate;
        ret = av_channel_layout_copy(&frame->ch_layout, &context->encoder_ctx->ch_layout);
        if (ret < 0) {
            log_error("av_channel_layout_copy", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = av_frame_get_buffer(frame, 0);
        if (ret < 0) {
            log_error("av_frame_get_buffer", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = swr_convert(context->resampler, frame->data, output_samples, NULL, 0);
        if (ret < 0) {
            log_error("swr_convert(flush)", ret);
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
            return AVERROR(ENOMEM);
        }

        if (av_audio_fifo_write(context->fifo, (void **)frame->data, frame->nb_samples) < frame->nb_samples) {
            av_frame_free(&frame);
            return AVERROR_UNKNOWN;
        }

        av_frame_free(&frame);
    }
}

static int process_audio(AudioConvertContext *context) {
    int ret;
    AVPacket *packet = av_packet_alloc();
    AVFrame *decoded_frame = av_frame_alloc();

    if (packet == NULL || decoded_frame == NULL) {
        ret = AVERROR(ENOMEM);
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
            log_error("avcodec_send_packet", ret);
            goto end;
        }

        while ((ret = avcodec_receive_frame(context->decoder_ctx, decoded_frame)) >= 0) {
            ret = add_converted_samples_to_fifo(context, decoded_frame);
            if (ret < 0) {
                goto end;
            }

            ret = drain_fifo(context, 0);
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
            log_error("avcodec_receive_frame", ret);
            goto end;
        }
    }

    if (ret == AVERROR_EOF) {
        ret = 0;
    }
    if (ret < 0) {
        log_error("av_read_frame", ret);
        goto end;
    }

    ret = avcodec_send_packet(context->decoder_ctx, NULL);
    if (ret < 0) {
        log_error("avcodec_send_packet(flush)", ret);
        goto end;
    }

    while ((ret = avcodec_receive_frame(context->decoder_ctx, decoded_frame)) >= 0) {
        ret = add_converted_samples_to_fifo(context, decoded_frame);
        if (ret < 0) {
            goto end;
        }

        ret = drain_fifo(context, 0);
        if (ret < 0) {
            goto end;
        }

        av_frame_unref(decoded_frame);
    }

    if (ret != AVERROR_EOF && ret != AVERROR(EAGAIN)) {
        log_error("avcodec_receive_frame(flush)", ret);
        goto end;
    }

    ret = flush_resampler(context);
    if (ret < 0) {
        goto end;
    }

    ret = drain_fifo(context, 1);
    if (ret < 0) {
        goto end;
    }

    ret = encode_and_write(context, NULL);
    if (ret < 0) {
        goto end;
    }

    ret = av_write_trailer(context->output_fmt);
    if (ret < 0) {
        log_error("av_write_trailer", ret);
    }

end:
    av_packet_free(&packet);
    av_frame_free(&decoded_frame);
    return ret;
}

static void cleanup(AudioConvertContext *context) {
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

int main(int argc, char **argv) {
    AudioConvertContext context;
    int ret;

    memset(&context, 0, sizeof(context));
    context.audio_stream_index = -1;

    if (argc != 3) {
        print_usage(argv[0]);
        return 1;
    }

    ret = init_input(&context, argv[1]);
    if (ret < 0) {
        cleanup(&context);
        return 1;
    }

    ret = init_output(&context, argv[2]);
    if (ret < 0) {
        cleanup(&context);
        return 1;
    }

    ret = init_processing(&context);
    if (ret < 0) {
        cleanup(&context);
        return 1;
    }

    ret = process_audio(&context);
    cleanup(&context);
    if (ret < 0) {
        return 1;
    }

    fprintf(stdout, "Converted %s -> %s (128 kbps, 48 kHz, stereo MP3)\n", argv[1], argv[2]);
    return 0;
}
