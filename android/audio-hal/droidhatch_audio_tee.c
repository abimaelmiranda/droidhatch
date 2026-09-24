#define _POSIX_C_SOURCE 200809L

#include "droidhatch_audio_tee.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

enum {
    DROIDHATCH_AUDIO_PROTOCOL_VERSION = 1,
    DROIDHATCH_AUDIO_HEADER_SIZE = 48,
    DROIDHATCH_AUDIO_MESSAGE_FORMAT = 2,
    DROIDHATCH_AUDIO_MESSAGE_AUDIO = 3,
    DROIDHATCH_AUDIO_SAMPLE_RATE = 44100,
    DROIDHATCH_AUDIO_CHANNEL_COUNT = 2,
    DROIDHATCH_AUDIO_SAMPLE_FORMAT_PCM16_LE = 1,
    DROIDHATCH_AUDIO_MAX_PAYLOAD = 1024 * 1024,
};

static void write_u16(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)value;
    destination[1] = (uint8_t)(value >> 8);
}

static void write_u32(uint8_t *destination, uint32_t value) {
    destination[0] = (uint8_t)value;
    destination[1] = (uint8_t)(value >> 8);
    destination[2] = (uint8_t)(value >> 16);
    destination[3] = (uint8_t)(value >> 24);
}

static void write_u64(uint8_t *destination, uint64_t value) {
    size_t index;
    for (index = 0; index < sizeof(value); ++index) {
        destination[index] = (uint8_t)(value >> (index * 8));
    }
}

static uint64_t monotonic_time_nanoseconds(void) {
    struct timespec timestamp;
    if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0) {
        return 0;
    }
    return (uint64_t)timestamp.tv_sec * 1000000000ULL
            + (uint64_t)timestamp.tv_nsec;
}

static void close_socket(struct droidhatch_audio_tee *tee) {
    if (tee->socket_fd >= 0) {
        close(tee->socket_fd);
        tee->socket_fd = -1;
    }
    tee->format_sent = false;
}

static bool connect_socket(struct droidhatch_audio_tee *tee) {
    struct sockaddr_un address;
    const size_t name_length = strlen(tee->socket_name);
    const int socket_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socket_fd < 0 || name_length < 2 || tee->socket_name[0] != '@'
            || name_length >= sizeof(address.sun_path)) {
        if (socket_fd >= 0) {
            close(socket_fd);
        }
        return false;
    }

    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path + 1, tee->socket_name + 1, name_length - 1);
    const socklen_t address_size = (socklen_t)(offsetof(struct sockaddr_un, sun_path)
            + name_length);
    if (connect(socket_fd, (struct sockaddr *)&address, address_size) != 0) {
        close(socket_fd);
        return false;
    }

    const int current_flags = fcntl(socket_fd, F_GETFL, 0);
    if (current_flags < 0 || fcntl(socket_fd, F_SETFL, current_flags | O_NONBLOCK) != 0) {
        close(socket_fd);
        return false;
    }

    tee->socket_fd = socket_fd;
    return true;
}

static bool send_packet(
        struct droidhatch_audio_tee *tee,
        uint16_t message_type,
        uint64_t sequence,
        uint32_t frame_count,
        const void *payload,
        size_t payload_size) {
    uint8_t header[DROIDHATCH_AUDIO_HEADER_SIZE] = {
        'D', 'H', 'A', 'D',
    };
    struct iovec vectors[2];
    struct msghdr message;
    const size_t total_size = sizeof(header) + payload_size;

    if (payload_size > DROIDHATCH_AUDIO_MAX_PAYLOAD) {
        return false;
    }

    write_u16(header + 4, DROIDHATCH_AUDIO_PROTOCOL_VERSION);
    write_u16(header + 6, message_type);
    write_u32(header + 8, DROIDHATCH_AUDIO_HEADER_SIZE);
    write_u32(header + 12, (uint32_t)payload_size);
    write_u64(header + 16, sequence);
    write_u64(header + 24, monotonic_time_nanoseconds());
    write_u32(header + 32, DROIDHATCH_AUDIO_SAMPLE_RATE);
    write_u16(header + 36, DROIDHATCH_AUDIO_CHANNEL_COUNT);
    write_u16(header + 38, DROIDHATCH_AUDIO_SAMPLE_FORMAT_PCM16_LE);
    write_u32(header + 40, frame_count);

    memset(vectors, 0, sizeof(vectors));
    vectors[0].iov_base = header;
    vectors[0].iov_len = sizeof(header);
    vectors[1].iov_base = (void *)payload;
    vectors[1].iov_len = payload_size;
    memset(&message, 0, sizeof(message));
    message.msg_iov = vectors;
    message.msg_iovlen = payload_size == 0 ? 1 : 2;

    const ssize_t sent = sendmsg(
            tee->socket_fd,
            &message,
            MSG_DONTWAIT | MSG_NOSIGNAL);
    return sent == (ssize_t)total_size;
}

static bool ensure_format(struct droidhatch_audio_tee *tee) {
    if (tee->format_sent) {
        return true;
    }
    if (!send_packet(tee, DROIDHATCH_AUDIO_MESSAGE_FORMAT, 0, 0, NULL, 0)) {
        return false;
    }
    tee->format_sent = true;
    return true;
}

void droidhatch_audio_tee_init(
        struct droidhatch_audio_tee *tee,
        const char *socket_name) {
    tee->socket_fd = -1;
    tee->sequence = 0;
    tee->format_sent = false;
    tee->socket_name = socket_name;
}

void droidhatch_audio_tee_write(
        struct droidhatch_audio_tee *tee,
        const void *buffer,
        size_t bytes) {
    const size_t bytes_per_frame = DROIDHATCH_AUDIO_CHANNEL_COUNT * sizeof(int16_t);
    if (buffer == NULL || bytes == 0 || bytes % bytes_per_frame != 0) {
        return;
    }
    if (tee->socket_fd < 0 && !connect_socket(tee)) {
        return;
    }
    if (!ensure_format(tee)) {
        close_socket(tee);
        return;
    }

    if (!send_packet(
            tee,
            DROIDHATCH_AUDIO_MESSAGE_AUDIO,
            ++tee->sequence,
            (uint32_t)(bytes / bytes_per_frame),
            buffer,
            bytes)) {
        close_socket(tee);
    }
}

void droidhatch_audio_tee_close(struct droidhatch_audio_tee *tee) {
    close_socket(tee);
}
