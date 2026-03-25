#ifndef FFMPEG_EXAMPLE_MEDIA_SDK_H
#define FFMPEG_EXAMPLE_MEDIA_SDK_H

#include <stddef.h>

#if defined(_WIN32)
#    if defined(FFMPEG_EXAMPLE_BUILD_SHARED)
#        define FFMPEG_EXAMPLE_API __declspec(dllexport)
#    elif defined(FFMPEG_EXAMPLE_USE_SHARED)
#        define FFMPEG_EXAMPLE_API __declspec(dllimport)
#    else
#        define FFMPEG_EXAMPLE_API
#    endif
#else
#    define FFMPEG_EXAMPLE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFMPEG_EXAMPLE_API int ffmpeg_example_normalize_audio(
    const char *input_path,
    const char *output_path,
    char *error_message,
    size_t error_message_size
);

FFMPEG_EXAMPLE_API int ffmpeg_example_normalize_video(
    const char *input_path,
    const char *output_path,
    char *error_message,
    size_t error_message_size
);

FFMPEG_EXAMPLE_API char *ffmpeg_example_media_info(
    const char *input_path,
    char *error_message,
    size_t error_message_size
);

FFMPEG_EXAMPLE_API void ffmpeg_example_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
