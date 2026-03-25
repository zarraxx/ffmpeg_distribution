#include "media_sdk.h"

#include "internal.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <string.h>

#define OUTPUT_WIDTH 1280
#define OUTPUT_HEIGHT 720
#define OUTPUT_VIDEO_BIT_RATE 2500000
#define OUTPUT_AUDIO_BIT_RATE 128000
#define OUTPUT_AUDIO_SAMPLE_RATE 48000

typedef struct VideoConvertContext {
    AVFormatContext *input_fmt;
    int video_stream_index;
    int audio_stream_index;
    AVCodecContext *video_decoder_ctx;
    AVCodecContext *audio_decoder_ctx;

    AVFormatContext *output_fmt;
    AVStream *video_output_stream;
    AVStream *audio_output_stream;
    AVCodecContext *video_encoder_ctx;
    AVCodecContext *audio_encoder_ctx;

    struct SwsContext *video_scaler;
    SwrContext *audio_resampler;
    AVAudioFifo *audio_fifo;

    int64_t next_video_pts;
    int64_t next_audio_pts;
} VideoConvertContext;

static int video_find_first_stream_index(const AVFormatContext *fmt, enum AVMediaType media_type) {
    unsigned int i;

    for (i = 0; i < fmt->nb_streams; ++i) {
        if (fmt->streams[i]->codecpar->codec_type == media_type) {
            return (int)i;
        }
    }

    return -1;
}

static int video_open_decoder(
    AVCodecContext **decoder_ctx,
    const AVStream *stream,
    const char *label,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    const AVCodec *decoder = avcodec_find_decoder(stream->codecpar->codec_id);

    if (decoder == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to find decoder for %s stream.", label);
        return AVERROR_DECODER_NOT_FOUND;
    }

    *decoder_ctx = avcodec_alloc_context3(decoder);
    if (*decoder_ctx == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avcodec_alloc_context3 failed");
        return AVERROR(ENOMEM);
    }

    ret = avcodec_parameters_to_context(*decoder_ctx, stream->codecpar);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_parameters_to_context", ret);
        return ret;
    }

    if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
        ret = ffmpeg_example_ensure_channel_layout(&(*decoder_ctx)->ch_layout, stream->codecpar->ch_layout.nb_channels);
        if (ret < 0) {
            return ret;
        }
    }

    ret = avcodec_open2(*decoder_ctx, decoder, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_open2(decoder)", ret);
        return ret;
    }

    return 0;
}

static int video_init_input(
    VideoConvertContext *context,
    const char *input_path,
    char *error_message,
    size_t error_message_size
) {
    int ret;

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

    context->video_stream_index = video_find_first_stream_index(context->input_fmt, AVMEDIA_TYPE_VIDEO);
    if (context->video_stream_index < 0) {
        ffmpeg_example_set_error(error_message, error_message_size, "No video stream found in input.");
        return AVERROR_STREAM_NOT_FOUND;
    }

    context->audio_stream_index = video_find_first_stream_index(context->input_fmt, AVMEDIA_TYPE_AUDIO);

    ret = video_open_decoder(
        &context->video_decoder_ctx,
        context->input_fmt->streams[context->video_stream_index],
        "video",
        error_message,
        error_message_size
    );
    if (ret < 0) {
        return ret;
    }

    if (context->audio_stream_index >= 0) {
        ret = video_open_decoder(
            &context->audio_decoder_ctx,
            context->input_fmt->streams[context->audio_stream_index],
            "audio",
            error_message,
            error_message_size
        );
        if (ret < 0) {
            return ret;
        }
    }

    return 0;
}

static int video_init_video_output(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    AVRational input_frame_rate;
    const AVCodec *video_encoder = avcodec_find_encoder_by_name("libx264");

    if (video_encoder == NULL) {
        video_encoder = avcodec_find_encoder(AV_CODEC_ID_H264);
    }
    if (video_encoder == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to find an H.264 encoder.");
        return AVERROR_ENCODER_NOT_FOUND;
    }

    context->video_output_stream = avformat_new_stream(context->output_fmt, NULL);
    if (context->video_output_stream == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avformat_new_stream failed");
        return AVERROR(ENOMEM);
    }

    context->video_encoder_ctx = avcodec_alloc_context3(video_encoder);
    if (context->video_encoder_ctx == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avcodec_alloc_context3 failed");
        return AVERROR(ENOMEM);
    }

    input_frame_rate = av_guess_frame_rate(
        context->input_fmt,
        context->input_fmt->streams[context->video_stream_index],
        NULL
    );
    if (input_frame_rate.num <= 0 || input_frame_rate.den <= 0) {
        input_frame_rate = (AVRational){30, 1};
    }

    context->video_encoder_ctx->codec_type = AVMEDIA_TYPE_VIDEO;
    context->video_encoder_ctx->codec_id = video_encoder->id;
    context->video_encoder_ctx->bit_rate = OUTPUT_VIDEO_BIT_RATE;
    context->video_encoder_ctx->width = OUTPUT_WIDTH;
    context->video_encoder_ctx->height = OUTPUT_HEIGHT;
    context->video_encoder_ctx->pix_fmt = ffmpeg_example_select_video_encoder_pixel_fmt(video_encoder);
    context->video_encoder_ctx->sample_aspect_ratio = (AVRational){1, 1};
    context->video_encoder_ctx->time_base = av_inv_q(input_frame_rate);
    context->video_encoder_ctx->framerate = input_frame_rate;
    context->video_encoder_ctx->gop_size = 60;
    context->video_encoder_ctx->max_b_frames = 2;

    if (video_encoder->id == AV_CODEC_ID_H264 && context->video_encoder_ctx->priv_data != NULL) {
        av_opt_set(context->video_encoder_ctx->priv_data, "preset", "medium", 0);
    }

    if (context->output_fmt->oformat->flags & AVFMT_GLOBALHEADER) {
        context->video_encoder_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    ret = avcodec_open2(context->video_encoder_ctx, video_encoder, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_open2(video_encoder)", ret);
        return ret;
    }

    ret = avcodec_parameters_from_context(
        context->video_output_stream->codecpar,
        context->video_encoder_ctx
    );
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_parameters_from_context(video)", ret);
        return ret;
    }

    context->video_output_stream->time_base = context->video_encoder_ctx->time_base;
    return 0;
}

static int video_init_audio_output(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    const AVCodec *audio_encoder = avcodec_find_encoder_by_name("libmp3lame");

    if (audio_encoder == NULL) {
        audio_encoder = avcodec_find_encoder(AV_CODEC_ID_MP3);
    }
    if (audio_encoder == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to find an MP3 encoder.");
        return AVERROR_ENCODER_NOT_FOUND;
    }

    context->audio_output_stream = avformat_new_stream(context->output_fmt, NULL);
    if (context->audio_output_stream == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avformat_new_stream failed");
        return AVERROR(ENOMEM);
    }

    context->audio_encoder_ctx = avcodec_alloc_context3(audio_encoder);
    if (context->audio_encoder_ctx == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "avcodec_alloc_context3 failed");
        return AVERROR(ENOMEM);
    }

    context->audio_encoder_ctx->bit_rate = OUTPUT_AUDIO_BIT_RATE;
    context->audio_encoder_ctx->sample_rate = OUTPUT_AUDIO_SAMPLE_RATE;
    context->audio_encoder_ctx->sample_fmt = ffmpeg_example_select_audio_encoder_sample_fmt(audio_encoder);
    context->audio_encoder_ctx->time_base = (AVRational){1, context->audio_encoder_ctx->sample_rate};
    av_channel_layout_default(&context->audio_encoder_ctx->ch_layout, 2);

    if (context->output_fmt->oformat->flags & AVFMT_GLOBALHEADER) {
        context->audio_encoder_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    ret = avcodec_open2(context->audio_encoder_ctx, audio_encoder, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_open2(audio_encoder)", ret);
        return ret;
    }

    ret = avcodec_parameters_from_context(
        context->audio_output_stream->codecpar,
        context->audio_encoder_ctx
    );
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_parameters_from_context(audio)", ret);
        return ret;
    }

    context->audio_output_stream->time_base = context->audio_encoder_ctx->time_base;
    return 0;
}

static int video_init_output(
    VideoConvertContext *context,
    const char *output_path,
    char *error_message,
    size_t error_message_size
) {
    int ret;

    ret = avformat_alloc_output_context2(&context->output_fmt, NULL, "mp4", output_path);
    if (ret < 0 || context->output_fmt == NULL) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_alloc_output_context2", ret);
        return ret < 0 ? ret : AVERROR_UNKNOWN;
    }

    ret = video_init_video_output(context, error_message, error_message_size);
    if (ret < 0) {
        return ret;
    }

    if (context->audio_decoder_ctx != NULL) {
        ret = video_init_audio_output(context, error_message, error_message_size);
        if (ret < 0) {
            return ret;
        }
    }

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

static int video_init_processing(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;

    context->video_scaler = sws_getContext(
        context->video_decoder_ctx->width,
        context->video_decoder_ctx->height,
        context->video_decoder_ctx->pix_fmt,
        context->video_encoder_ctx->width,
        context->video_encoder_ctx->height,
        context->video_encoder_ctx->pix_fmt,
        SWS_BICUBIC,
        NULL,
        NULL,
        NULL
    );
    if (context->video_scaler == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to create video scaler.");
        return AVERROR(EINVAL);
    }

    if (context->audio_decoder_ctx == NULL) {
        return 0;
    }

    ret = ffmpeg_example_ensure_channel_layout(&context->audio_decoder_ctx->ch_layout, 0);
    if (ret < 0) {
        return ret;
    }

    ret = swr_alloc_set_opts2(
        &context->audio_resampler,
        &context->audio_encoder_ctx->ch_layout,
        context->audio_encoder_ctx->sample_fmt,
        context->audio_encoder_ctx->sample_rate,
        &context->audio_decoder_ctx->ch_layout,
        context->audio_decoder_ctx->sample_fmt,
        context->audio_decoder_ctx->sample_rate,
        0,
        NULL
    );
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "swr_alloc_set_opts2", ret);
        return ret;
    }

    ret = swr_init(context->audio_resampler);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "swr_init", ret);
        return ret;
    }

    context->audio_fifo = av_audio_fifo_alloc(
        context->audio_encoder_ctx->sample_fmt,
        context->audio_encoder_ctx->ch_layout.nb_channels,
        1
    );
    if (context->audio_fifo == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_alloc failed");
        return AVERROR(ENOMEM);
    }

    return 0;
}

static int video_encode_and_write(
    VideoConvertContext *context,
    AVCodecContext *encoder_ctx,
    AVStream *output_stream,
    AVFrame *frame,
    const char *send_step,
    const char *receive_step,
    char *error_message,
    size_t error_message_size
) {
    int ret = avcodec_send_frame(encoder_ctx, frame);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, send_step, ret);
        return ret;
    }

    while (ret >= 0) {
        AVPacket *packet = av_packet_alloc();
        if (packet == NULL) {
            ffmpeg_example_set_error(error_message, error_message_size, "av_packet_alloc failed");
            return AVERROR(ENOMEM);
        }

        ret = avcodec_receive_packet(encoder_ctx, packet);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            av_packet_free(&packet);
            return 0;
        }
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, receive_step, ret);
            av_packet_free(&packet);
            return ret;
        }

        av_packet_rescale_ts(packet, encoder_ctx->time_base, output_stream->time_base);
        packet->stream_index = output_stream->index;

        ret = av_interleaved_write_frame(context->output_fmt, packet);
        av_packet_free(&packet);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_interleaved_write_frame", ret);
            return ret;
        }
    }

    return 0;
}

static int video_process_video_frame(
    VideoConvertContext *context,
    const AVFrame *decoded_frame,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    AVFrame *scaled_frame = av_frame_alloc();

    if (scaled_frame == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
        return AVERROR(ENOMEM);
    }

    scaled_frame->format = context->video_encoder_ctx->pix_fmt;
    scaled_frame->width = context->video_encoder_ctx->width;
    scaled_frame->height = context->video_encoder_ctx->height;

    ret = av_frame_get_buffer(scaled_frame, 0);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer(video)", ret);
        av_frame_free(&scaled_frame);
        return ret;
    }

    ret = sws_scale(
        context->video_scaler,
        (const uint8_t * const *)decoded_frame->data,
        decoded_frame->linesize,
        0,
        context->video_decoder_ctx->height,
        scaled_frame->data,
        scaled_frame->linesize
    );
    if (ret <= 0) {
        ffmpeg_example_set_error(error_message, error_message_size, "sws_scale failed for video frame.");
        av_frame_free(&scaled_frame);
        return AVERROR_UNKNOWN;
    }

    scaled_frame->pts = context->next_video_pts++;

    ret = video_encode_and_write(
        context,
        context->video_encoder_ctx,
        context->video_output_stream,
        scaled_frame,
        "avcodec_send_frame(video)",
        "avcodec_receive_packet(video)",
        error_message,
        error_message_size
    );
    av_frame_free(&scaled_frame);
    return ret;
}

static int video_add_audio_samples_to_fifo(
    VideoConvertContext *context,
    const AVFrame *decoded_frame,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    int output_samples;
    AVFrame *converted_frame = NULL;

    output_samples = av_rescale_rnd(
        swr_get_delay(context->audio_resampler, context->audio_decoder_ctx->sample_rate) + decoded_frame->nb_samples,
        context->audio_encoder_ctx->sample_rate,
        context->audio_decoder_ctx->sample_rate,
        AV_ROUND_UP
    );

    converted_frame = av_frame_alloc();
    if (converted_frame == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
        return AVERROR(ENOMEM);
    }

    converted_frame->nb_samples = output_samples;
    converted_frame->format = context->audio_encoder_ctx->sample_fmt;
    converted_frame->sample_rate = context->audio_encoder_ctx->sample_rate;
    ret = av_channel_layout_copy(&converted_frame->ch_layout, &context->audio_encoder_ctx->ch_layout);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_channel_layout_copy(audio)", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    ret = av_frame_get_buffer(converted_frame, 0);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer(audio)", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    ret = swr_convert(
        context->audio_resampler,
        converted_frame->data,
        output_samples,
        (const uint8_t **)decoded_frame->data,
        decoded_frame->nb_samples
    );
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "swr_convert", ret);
        av_frame_free(&converted_frame);
        return ret;
    }

    converted_frame->nb_samples = ret;

    if (av_audio_fifo_realloc(
            context->audio_fifo,
            av_audio_fifo_size(context->audio_fifo) + converted_frame->nb_samples
        ) < 0) {
        av_frame_free(&converted_frame);
        ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_realloc failed");
        return AVERROR(ENOMEM);
    }

    if (av_audio_fifo_write(
            context->audio_fifo,
            (void **)converted_frame->data,
            converted_frame->nb_samples
        ) < converted_frame->nb_samples) {
        av_frame_free(&converted_frame);
        ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_write failed");
        return AVERROR_UNKNOWN;
    }

    av_frame_free(&converted_frame);
    return 0;
}

static int video_drain_audio_fifo(
    VideoConvertContext *context,
    int flush,
    char *error_message,
    size_t error_message_size
) {
    int ret;

    while (av_audio_fifo_size(context->audio_fifo) >= context->audio_encoder_ctx->frame_size ||
           (flush && av_audio_fifo_size(context->audio_fifo) > 0)) {
        int encoder_frame_samples = context->audio_encoder_ctx->frame_size;
        int available_samples = av_audio_fifo_size(context->audio_fifo);
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
        frame->format = context->audio_encoder_ctx->sample_fmt;
        frame->sample_rate = context->audio_encoder_ctx->sample_rate;
        ret = av_channel_layout_copy(&frame->ch_layout, &context->audio_encoder_ctx->ch_layout);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_channel_layout_copy(audio_frame)", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = av_frame_get_buffer(frame, 0);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer(audio_frame)", ret);
            av_frame_free(&frame);
            return ret;
        }

        samples_read = av_audio_fifo_read(context->audio_fifo, (void **)frame->data, samples_to_read);
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
                context->audio_encoder_ctx->ch_layout.nb_channels,
                context->audio_encoder_ctx->sample_fmt
            );
        } else {
            frame->nb_samples = samples_to_read;
        }

        frame->pts = context->next_audio_pts;
        context->next_audio_pts += frame->nb_samples;

        ret = video_encode_and_write(
            context,
            context->audio_encoder_ctx,
            context->audio_output_stream,
            frame,
            "avcodec_send_frame(audio)",
            "avcodec_receive_packet(audio)",
            error_message,
            error_message_size
        );
        av_frame_free(&frame);
        if (ret < 0) {
            return ret;
        }
    }

    return 0;
}

static int video_flush_audio_resampler(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    while (1) {
        int pending_input_samples = swr_get_delay(context->audio_resampler, context->audio_decoder_ctx->sample_rate);
        int output_samples;
        AVFrame *frame;
        int ret;

        if (pending_input_samples <= 0) {
            return 0;
        }

        output_samples = av_rescale_rnd(
            pending_input_samples,
            context->audio_encoder_ctx->sample_rate,
            context->audio_decoder_ctx->sample_rate,
            AV_ROUND_UP
        );

        frame = av_frame_alloc();
        if (frame == NULL) {
            ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
            return AVERROR(ENOMEM);
        }

        frame->nb_samples = output_samples;
        frame->format = context->audio_encoder_ctx->sample_fmt;
        frame->sample_rate = context->audio_encoder_ctx->sample_rate;
        ret = av_channel_layout_copy(&frame->ch_layout, &context->audio_encoder_ctx->ch_layout);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_channel_layout_copy(audio_flush)", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = av_frame_get_buffer(frame, 0);
        if (ret < 0) {
            ffmpeg_example_set_av_error(error_message, error_message_size, "av_frame_get_buffer(audio_flush)", ret);
            av_frame_free(&frame);
            return ret;
        }

        ret = swr_convert(context->audio_resampler, frame->data, output_samples, NULL, 0);
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

        if (av_audio_fifo_realloc(context->audio_fifo, av_audio_fifo_size(context->audio_fifo) + frame->nb_samples) < 0) {
            av_frame_free(&frame);
            ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_realloc failed");
            return AVERROR(ENOMEM);
        }

        if (av_audio_fifo_write(context->audio_fifo, (void **)frame->data, frame->nb_samples) < frame->nb_samples) {
            av_frame_free(&frame);
            ffmpeg_example_set_error(error_message, error_message_size, "av_audio_fifo_write failed");
            return AVERROR_UNKNOWN;
        }

        av_frame_free(&frame);
    }
}

static int video_receive_video_frames(
    VideoConvertContext *context,
    AVFrame *frame,
    char *error_message,
    size_t error_message_size
) {
    int ret;

    while ((ret = avcodec_receive_frame(context->video_decoder_ctx, frame)) >= 0) {
        ret = video_process_video_frame(context, frame, error_message, error_message_size);
        if (ret < 0) {
            return ret;
        }
        av_frame_unref(frame);
    }

    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
        return 0;
    }

    ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_receive_frame(video)", ret);
    return ret;
}

static int video_receive_audio_frames(
    VideoConvertContext *context,
    AVFrame *frame,
    char *error_message,
    size_t error_message_size
) {
    int ret;

    while ((ret = avcodec_receive_frame(context->audio_decoder_ctx, frame)) >= 0) {
        ret = video_add_audio_samples_to_fifo(context, frame, error_message, error_message_size);
        if (ret < 0) {
            return ret;
        }

        ret = video_drain_audio_fifo(context, 0, error_message, error_message_size);
        if (ret < 0) {
            return ret;
        }

        av_frame_unref(frame);
    }

    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
        return 0;
    }

    ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_receive_frame(audio)", ret);
    return ret;
}

static int video_flush_video_pipeline(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    AVFrame *frame = av_frame_alloc();

    if (frame == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
        return AVERROR(ENOMEM);
    }

    ret = avcodec_send_packet(context->video_decoder_ctx, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_packet(video_flush)", ret);
        av_frame_free(&frame);
        return ret;
    }

    ret = video_receive_video_frames(context, frame, error_message, error_message_size);
    av_frame_free(&frame);
    if (ret < 0) {
        return ret;
    }

    return video_encode_and_write(
        context,
        context->video_encoder_ctx,
        context->video_output_stream,
        NULL,
        "avcodec_send_frame(video_flush)",
        "avcodec_receive_packet(video_flush)",
        error_message,
        error_message_size
    );
}

static int video_flush_audio_pipeline(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    AVFrame *frame;

    if (context->audio_decoder_ctx == NULL) {
        return 0;
    }

    frame = av_frame_alloc();
    if (frame == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "av_frame_alloc failed");
        return AVERROR(ENOMEM);
    }

    ret = avcodec_send_packet(context->audio_decoder_ctx, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_packet(audio_flush)", ret);
        av_frame_free(&frame);
        return ret;
    }

    ret = video_receive_audio_frames(context, frame, error_message, error_message_size);
    av_frame_free(&frame);
    if (ret < 0) {
        return ret;
    }

    ret = video_flush_audio_resampler(context, error_message, error_message_size);
    if (ret < 0) {
        return ret;
    }

    ret = video_drain_audio_fifo(context, 1, error_message, error_message_size);
    if (ret < 0) {
        return ret;
    }

    return video_encode_and_write(
        context,
        context->audio_encoder_ctx,
        context->audio_output_stream,
        NULL,
        "avcodec_send_frame(audio_flush)",
        "avcodec_receive_packet(audio_flush)",
        error_message,
        error_message_size
    );
}

static int video_process_streams(
    VideoConvertContext *context,
    char *error_message,
    size_t error_message_size
) {
    int ret;
    AVPacket *packet = av_packet_alloc();
    AVFrame *video_frame = av_frame_alloc();
    AVFrame *audio_frame = av_frame_alloc();

    if (packet == NULL || video_frame == NULL || (context->audio_decoder_ctx != NULL && audio_frame == NULL)) {
        ret = AVERROR(ENOMEM);
        ffmpeg_example_set_error(error_message, error_message_size, "Failed to allocate stream processing buffers");
        goto end;
    }

    while ((ret = av_read_frame(context->input_fmt, packet)) >= 0) {
        if (packet->stream_index == context->video_stream_index) {
            ret = avcodec_send_packet(context->video_decoder_ctx, packet);
            av_packet_unref(packet);
            if (ret < 0) {
                ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_packet(video)", ret);
                goto end;
            }

            ret = video_receive_video_frames(context, video_frame, error_message, error_message_size);
            if (ret < 0) {
                goto end;
            }
            continue;
        }

        if (context->audio_decoder_ctx != NULL && packet->stream_index == context->audio_stream_index) {
            ret = avcodec_send_packet(context->audio_decoder_ctx, packet);
            av_packet_unref(packet);
            if (ret < 0) {
                ffmpeg_example_set_av_error(error_message, error_message_size, "avcodec_send_packet(audio)", ret);
                goto end;
            }

            ret = video_receive_audio_frames(context, audio_frame, error_message, error_message_size);
            if (ret < 0) {
                goto end;
            }
            continue;
        }

        av_packet_unref(packet);
    }

    if (ret == AVERROR_EOF) {
        ret = 0;
    }
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_read_frame", ret);
        goto end;
    }

    ret = video_flush_video_pipeline(context, error_message, error_message_size);
    if (ret < 0) {
        goto end;
    }

    ret = video_flush_audio_pipeline(context, error_message, error_message_size);
    if (ret < 0) {
        goto end;
    }

    ret = av_write_trailer(context->output_fmt);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "av_write_trailer", ret);
    }

end:
    av_packet_free(&packet);
    av_frame_free(&video_frame);
    av_frame_free(&audio_frame);
    return ret;
}

static void video_cleanup(VideoConvertContext *context) {
    if (context->audio_fifo != NULL) {
        av_audio_fifo_free(context->audio_fifo);
    }

    if (context->audio_resampler != NULL) {
        swr_free(&context->audio_resampler);
    }

    if (context->video_scaler != NULL) {
        sws_freeContext(context->video_scaler);
    }

    if (context->video_decoder_ctx != NULL) {
        avcodec_free_context(&context->video_decoder_ctx);
    }

    if (context->audio_decoder_ctx != NULL) {
        avcodec_free_context(&context->audio_decoder_ctx);
    }

    if (context->video_encoder_ctx != NULL) {
        avcodec_free_context(&context->video_encoder_ctx);
    }

    if (context->audio_encoder_ctx != NULL) {
        avcodec_free_context(&context->audio_encoder_ctx);
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

int ffmpeg_example_normalize_video(
    const char *input_path,
    const char *output_path,
    char *error_message,
    size_t error_message_size
) {
    VideoConvertContext context;
    int ret;

    memset(&context, 0, sizeof(context));
    context.video_stream_index = -1;
    context.audio_stream_index = -1;
    ffmpeg_example_clear_error(error_message, error_message_size);

    ret = video_init_input(&context, input_path, error_message, error_message_size);
    if (ret < 0) {
        video_cleanup(&context);
        return ret;
    }

    ret = video_init_output(&context, output_path, error_message, error_message_size);
    if (ret < 0) {
        video_cleanup(&context);
        return ret;
    }

    ret = video_init_processing(&context, error_message, error_message_size);
    if (ret < 0) {
        video_cleanup(&context);
        return ret;
    }

    ret = video_process_streams(&context, error_message, error_message_size);
    video_cleanup(&context);
    return ret;
}
