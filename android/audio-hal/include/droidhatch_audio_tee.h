#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct droidhatch_audio_tee {
    int socket_fd;
    uint64_t sequence;
    bool format_sent;
    const char *socket_name;
};

void droidhatch_audio_tee_init(
        struct droidhatch_audio_tee *tee,
        const char *socket_name);

void droidhatch_audio_tee_write(
        struct droidhatch_audio_tee *tee,
        const void *buffer,
        size_t bytes);

void droidhatch_audio_tee_close(struct droidhatch_audio_tee *tee);
