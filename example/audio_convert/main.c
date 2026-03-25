#include "media_sdk.h"

#include <stdio.h>

static void print_usage(const char *program) {
    fprintf(stderr, "Usage: %s <input_audio> <output_mp3>\n", program);
}

int main(int argc, char **argv) {
    char error_message[1024] = {0};
    int ret;

    if (argc != 3) {
        print_usage(argv[0]);
        return 1;
    }

    ret = ffmpeg_example_normalize_audio(argv[1], argv[2], error_message, sizeof(error_message));
    if (ret < 0) {
        fprintf(stderr, "%s\n", error_message[0] != '\0' ? error_message : "Audio normalization failed.");
        return 1;
    }

    fprintf(stdout, "Converted %s -> %s (128 kbps, 48 kHz, stereo MP3)\n", argv[1], argv[2]);
    return 0;
}
