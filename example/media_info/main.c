#include "media_sdk.h"

#include <stdio.h>

static void print_usage(const char *program) {
    fprintf(stderr, "Usage: %s <input_media>\n", program);
}

int main(int argc, char **argv) {
    char error_message[1024] = {0};
    char *info_string;

    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }

    info_string = ffmpeg_example_media_info(argv[1], error_message, sizeof(error_message));
    if (info_string == NULL) {
        fprintf(stderr, "%s\n", error_message[0] != '\0' ? error_message : "Unable to inspect media.");
        return 1;
    }

    fputs(info_string, stdout);
    fputc('\n', stdout);
    ffmpeg_example_free_string(info_string);
    return 0;
}
