#include "media_sdk.h"

#include <stdio.h>

static void print_usage(const char *program) {
    fprintf(stderr, "Usage: %s <input_video> <output_mp4>\n", program);
}

int main(int argc, char **argv) {
    char error_message[1024] = {0};
    int ret;

    if (argc != 3) {
        print_usage(argv[0]);
        return 1;
    }

    ret = ffmpeg_example_normalize_video(argv[1], argv[2], error_message, sizeof(error_message));
    if (ret < 0) {
        fprintf(stderr, "%s\n", error_message[0] != '\0' ? error_message : "Video normalization failed.");
        return 1;
    }

    fprintf(stdout, "Converted %s -> %s (720p MP4)\n", argv[1], argv[2]);
    return 0;
}
