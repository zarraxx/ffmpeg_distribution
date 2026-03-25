#include "media_sdk.h"

#include "internal.h"

#include <libavcodec/codec_desc.h>
#include <libavformat/avformat.h>
#include <libavutil/bprint.h>
#include <libavutil/mem.h>
#include <libavutil/pixdesc.h>
#include <libavutil/samplefmt.h>

static void media_info_append_json_string(AVBPrint *output, const char *value) {
    const unsigned char *cursor = (const unsigned char *)(value != NULL ? value : "");

    av_bprint_chars(output, '"', 1);
    while (*cursor != '\0') {
        switch (*cursor) {
            case '\\':
                av_bprintf(output, "\\\\");
                break;
            case '"':
                av_bprintf(output, "\\\"");
                break;
            case '\n':
                av_bprintf(output, "\\n");
                break;
            case '\r':
                av_bprintf(output, "\\r");
                break;
            case '\t':
                av_bprintf(output, "\\t");
                break;
            default:
                if (*cursor < 0x20) {
                    av_bprintf(output, "\\u%04x", (unsigned int)*cursor);
                } else {
                    av_bprint_chars(output, (char)*cursor, 1);
                }
                break;
        }
        ++cursor;
    }
    av_bprint_chars(output, '"', 1);
}

static void media_info_append_tags(AVBPrint *output, const AVDictionary *metadata) {
    const AVDictionaryEntry *entry = NULL;
    int first = 1;

    av_bprintf(output, "{");
    while ((entry = av_dict_iterate(metadata, entry)) != NULL) {
        if (!first) {
            av_bprintf(output, ",");
        }
        media_info_append_json_string(output, entry->key);
        av_bprintf(output, ":");
        media_info_append_json_string(output, entry->value);
        first = 0;
    }
    av_bprintf(output, "}");
}

static void media_info_append_stream(AVBPrint *output, const AVStream *stream) {
    const AVCodecParameters *codecpar = stream->codecpar;
    const AVCodecDescriptor *codec_desc = avcodec_descriptor_get(codecpar->codec_id);
    const char *media_type = av_get_media_type_string(codecpar->codec_type);

    av_bprintf(output, "{");
    av_bprintf(output, "\"index\":%d,", stream->index);
    av_bprintf(output, "\"codec_type\":");
    media_info_append_json_string(output, media_type != NULL ? media_type : "unknown");
    av_bprintf(output, ",\"codec_name\":");
    media_info_append_json_string(output, avcodec_get_name(codecpar->codec_id));
    av_bprintf(output, ",\"codec_long_name\":");
    media_info_append_json_string(output, codec_desc != NULL ? codec_desc->long_name : "");
    av_bprintf(output, ",\"bit_rate\":%" PRId64, codecpar->bit_rate);

    if (stream->duration != AV_NOPTS_VALUE) {
        double duration_seconds = stream->duration * av_q2d(stream->time_base);
        av_bprintf(output, ",\"duration_seconds\":%.6f", duration_seconds);
    }

    if (codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
        av_bprintf(output, ",\"width\":%d,\"height\":%d", codecpar->width, codecpar->height);
        av_bprintf(output, ",\"format\":");
        media_info_append_json_string(output, av_get_pix_fmt_name(codecpar->format));
        if (stream->avg_frame_rate.num > 0 && stream->avg_frame_rate.den > 0) {
            av_bprintf(output, ",\"frame_rate\":%.6f", av_q2d(stream->avg_frame_rate));
        }
    } else if (codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
        char channel_layout[128] = {0};

        av_bprintf(output, ",\"sample_rate\":%d,\"channels\":%d", codecpar->sample_rate, codecpar->ch_layout.nb_channels);
        av_bprintf(output, ",\"format\":");
        media_info_append_json_string(output, av_get_sample_fmt_name(codecpar->format));

        if (codecpar->ch_layout.nb_channels > 0) {
            av_channel_layout_describe(&codecpar->ch_layout, channel_layout, sizeof(channel_layout));
        }
        av_bprintf(output, ",\"channel_layout\":");
        media_info_append_json_string(output, channel_layout);
    }

    av_bprintf(output, ",\"metadata\":");
    media_info_append_tags(output, stream->metadata);
    av_bprintf(output, "}");
}

char *ffmpeg_example_media_info(
    const char *input_path,
    char *error_message,
    size_t error_message_size
) {
    AVFormatContext *input_fmt = NULL;
    AVBPrint output;
    char *result = NULL;
    int ret;
    unsigned int i;

    ffmpeg_example_clear_error(error_message, error_message_size);

    ret = avformat_open_input(&input_fmt, input_path, NULL, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_open_input", ret);
        return NULL;
    }

    ret = avformat_find_stream_info(input_fmt, NULL);
    if (ret < 0) {
        ffmpeg_example_set_av_error(error_message, error_message_size, "avformat_find_stream_info", ret);
        avformat_close_input(&input_fmt);
        return NULL;
    }

    av_bprint_init(&output, 0, AV_BPRINT_SIZE_UNLIMITED);
    av_bprintf(&output, "{");
    av_bprintf(&output, "\"file\":");
    media_info_append_json_string(&output, input_path);
    av_bprintf(&output, ",\"format_name\":");
    media_info_append_json_string(&output, input_fmt->iformat != NULL ? input_fmt->iformat->name : "");
    av_bprintf(&output, ",\"format_long_name\":");
    media_info_append_json_string(&output, input_fmt->iformat != NULL ? input_fmt->iformat->long_name : "");

    if (input_fmt->duration != AV_NOPTS_VALUE) {
        av_bprintf(&output, ",\"duration_seconds\":%.6f", input_fmt->duration / (double)AV_TIME_BASE);
    }
    av_bprintf(&output, ",\"bit_rate\":%" PRId64, input_fmt->bit_rate);
    av_bprintf(&output, ",\"probe_score\":%d", input_fmt->probe_score);
    av_bprintf(&output, ",\"metadata\":");
    media_info_append_tags(&output, input_fmt->metadata);

    av_bprintf(&output, ",\"streams\":[");
    for (i = 0; i < input_fmt->nb_streams; ++i) {
        if (i > 0) {
            av_bprintf(&output, ",");
        }
        media_info_append_stream(&output, input_fmt->streams[i]);
    }
    av_bprintf(&output, "]}");

    if (!av_bprint_is_complete(&output)) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to allocate media info string");
        avformat_close_input(&input_fmt);
        av_bprint_finalize(&output, NULL);
        return NULL;
    }

    av_bprint_finalize(&output, &result);
    if (result == NULL) {
        ffmpeg_example_set_error(error_message, error_message_size, "Unable to allocate media info string");
    }

    avformat_close_input(&input_fmt);
    return result;
}

void ffmpeg_example_free_string(char *value) {
    av_free(value);
}
