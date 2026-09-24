#define _POSIX_C_SOURCE 200809L
#define LOG_TAG "audio_hw_droidhatch"

#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <hardware/audio.h>
#include <hardware/hardware.h>

#include "droidhatch_audio_tee.h"

#ifndef DROIDHATCH_AUDIO_BUFFER_BYTES
#define DROIDHATCH_AUDIO_BUFFER_BYTES 4096
#endif

enum {
    DROIDHATCH_AUDIO_SAMPLE_RATE = 44100,
    DROIDHATCH_AUDIO_OUTPUT_BUFFER_BYTES = DROIDHATCH_AUDIO_BUFFER_BYTES,
    DROIDHATCH_AUDIO_OUTPUT_LATENCY_MS = 10,
    DROIDHATCH_AUDIO_INPUT_SAMPLE_RATE = 8000,
    DROIDHATCH_AUDIO_INPUT_BUFFER_BYTES = 320,
};

static const char droidhatch_audio_source_socket[] = "@droidhatch-audio-source";

struct droidhatch_audio_device {
    struct audio_hw_device device;
};

struct droidhatch_stream_out {
    struct audio_stream_out stream;
    struct droidhatch_audio_tee tee;
    bool has_write_deadline;
    uint64_t write_deadline_nanoseconds;
};

struct droidhatch_stream_in {
    struct audio_stream_in stream;
};

static uint32_t out_get_sample_rate(const struct audio_stream *stream) {
    (void)stream;
    return DROIDHATCH_AUDIO_SAMPLE_RATE;
}

static int out_set_sample_rate(struct audio_stream *stream, uint32_t rate) {
    (void)stream;
    (void)rate;
    return 0;
}

static size_t out_get_buffer_size(const struct audio_stream *stream) {
    (void)stream;
    return DROIDHATCH_AUDIO_OUTPUT_BUFFER_BYTES;
}

static audio_channel_mask_t out_get_channels(const struct audio_stream *stream) {
    (void)stream;
    return AUDIO_CHANNEL_OUT_STEREO;
}

static audio_format_t out_get_format(const struct audio_stream *stream) {
    (void)stream;
    return AUDIO_FORMAT_PCM_16_BIT;
}

static int out_set_format(struct audio_stream *stream, audio_format_t format) {
    (void)stream;
    (void)format;
    return 0;
}

static int out_standby(struct audio_stream *stream) {
    struct droidhatch_stream_out *output =
            (struct droidhatch_stream_out *)stream;
    droidhatch_audio_tee_close(&output->tee);
    output->has_write_deadline = false;
    output->write_deadline_nanoseconds = 0;
    return 0;
}

static int out_dump(const struct audio_stream *stream, int fd) {
    (void)stream;
    (void)fd;
    return 0;
}

static int out_set_parameters(struct audio_stream *stream, const char *kvpairs) {
    (void)stream;
    (void)kvpairs;
    return 0;
}

static char *out_get_parameters(const struct audio_stream *stream, const char *keys) {
    (void)stream;
    (void)keys;
    return strdup("");
}

static uint32_t out_get_latency(const struct audio_stream_out *stream) {
    (void)stream;
    return DROIDHATCH_AUDIO_OUTPUT_LATENCY_MS;
}

static uint64_t monotonic_time_nanoseconds(void) {
    struct timespec timestamp;
    if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0) {
        return 0;
    }
    return (uint64_t)timestamp.tv_sec * 1000000000ULL
            + (uint64_t)timestamp.tv_nsec;
}

static void pace_output(
        struct droidhatch_stream_out *output,
        size_t frame_count) {
    const uint64_t duration_nanoseconds =
            (uint64_t)frame_count * 1000000000ULL
            / DROIDHATCH_AUDIO_SAMPLE_RATE;
    uint64_t now = monotonic_time_nanoseconds();
    if (!output->has_write_deadline || now == 0) {
        output->write_deadline_nanoseconds = now;
        output->has_write_deadline = now != 0;
    }

    if (!output->has_write_deadline) {
        return;
    }

    output->write_deadline_nanoseconds += duration_nanoseconds;
    while (output->write_deadline_nanoseconds > now) {
        const uint64_t remaining_nanoseconds =
                output->write_deadline_nanoseconds - now;
        struct timespec remaining = {
            .tv_sec = (time_t)(remaining_nanoseconds / 1000000000ULL),
            .tv_nsec = (long)(remaining_nanoseconds % 1000000000ULL),
        };
        if (nanosleep(&remaining, NULL) != 0 && errno != EINTR) {
            break;
        }
        now = monotonic_time_nanoseconds();
    }

    if (now > output->write_deadline_nanoseconds + 1000000000ULL) {
        output->write_deadline_nanoseconds = now;
    }
}

static int out_set_volume(
        struct audio_stream_out *stream,
        float left,
        float right) {
    (void)stream;
    (void)left;
    (void)right;
    return 0;
}

static ssize_t out_write(
        struct audio_stream_out *stream,
        const void *buffer,
        size_t bytes) {
    struct droidhatch_stream_out *output =
            (struct droidhatch_stream_out *)stream;
    droidhatch_audio_tee_write(&output->tee, buffer, bytes);

    const size_t frame_size = audio_stream_out_frame_size(stream);
    if (frame_size == 0) {
        return -EINVAL;
    }
    pace_output(output, bytes / frame_size);
    return (ssize_t)bytes;
}

static int out_get_render_position(
        const struct audio_stream_out *stream,
        uint32_t *dsp_frames) {
    (void)stream;
    (void)dsp_frames;
    return -EINVAL;
}

static int out_add_audio_effect(
        const struct audio_stream *stream,
        effect_handle_t effect) {
    (void)stream;
    (void)effect;
    return 0;
}

static int out_remove_audio_effect(
        const struct audio_stream *stream,
        effect_handle_t effect) {
    (void)stream;
    (void)effect;
    return 0;
}

static int out_get_next_write_timestamp(
        const struct audio_stream_out *stream,
        int64_t *timestamp) {
    (void)stream;
    (void)timestamp;
    return -EINVAL;
}

static uint32_t in_get_sample_rate(const struct audio_stream *stream) {
    (void)stream;
    return DROIDHATCH_AUDIO_INPUT_SAMPLE_RATE;
}

static int in_set_sample_rate(struct audio_stream *stream, uint32_t rate) {
    (void)stream;
    (void)rate;
    return 0;
}

static size_t in_get_buffer_size(const struct audio_stream *stream) {
    (void)stream;
    return DROIDHATCH_AUDIO_INPUT_BUFFER_BYTES;
}

static audio_channel_mask_t in_get_channels(const struct audio_stream *stream) {
    (void)stream;
    return AUDIO_CHANNEL_IN_STEREO;
}

static audio_format_t in_get_format(const struct audio_stream *stream) {
    (void)stream;
    return AUDIO_FORMAT_PCM_16_BIT;
}

static int in_set_format(struct audio_stream *stream, audio_format_t format) {
    (void)stream;
    (void)format;
    return 0;
}

static int in_standby(struct audio_stream *stream) {
    (void)stream;
    return 0;
}

static int in_dump(const struct audio_stream *stream, int fd) {
    (void)stream;
    (void)fd;
    return 0;
}

static int in_set_parameters(struct audio_stream *stream, const char *kvpairs) {
    (void)stream;
    (void)kvpairs;
    return 0;
}

static char *in_get_parameters(
        const struct audio_stream *stream,
        const char *keys) {
    (void)stream;
    (void)keys;
    return strdup("");
}

static int in_set_gain(struct audio_stream_in *stream, float gain) {
    (void)stream;
    (void)gain;
    return 0;
}

static ssize_t in_read(
        struct audio_stream_in *stream,
        void *buffer,
        size_t bytes) {
    (void)stream;
    (void)buffer;
    usleep(bytes * 1000000U / sizeof(int16_t) / DROIDHATCH_AUDIO_INPUT_SAMPLE_RATE);
    return (ssize_t)bytes;
}

static uint32_t in_get_input_frames_lost(struct audio_stream_in *stream) {
    (void)stream;
    return 0;
}

static int in_add_audio_effect(
        const struct audio_stream *stream,
        effect_handle_t effect) {
    (void)stream;
    (void)effect;
    return 0;
}

static int in_remove_audio_effect(
        const struct audio_stream *stream,
        effect_handle_t effect) {
    (void)stream;
    (void)effect;
    return 0;
}

static int adev_open_output_stream(
        struct audio_hw_device *device,
        audio_io_handle_t handle,
        audio_devices_t devices,
        audio_output_flags_t flags,
        struct audio_config *config,
        struct audio_stream_out **stream_out,
        const char *address) {
    (void)device;
    (void)handle;
    (void)devices;
    (void)flags;
    (void)config;
    (void)address;

    struct droidhatch_stream_out *output =
            (struct droidhatch_stream_out *)calloc(1, sizeof(*output));
    if (output == NULL) {
        return -ENOMEM;
    }

    output->stream.common.get_sample_rate = out_get_sample_rate;
    output->stream.common.set_sample_rate = out_set_sample_rate;
    output->stream.common.get_buffer_size = out_get_buffer_size;
    output->stream.common.get_channels = out_get_channels;
    output->stream.common.get_format = out_get_format;
    output->stream.common.set_format = out_set_format;
    output->stream.common.standby = out_standby;
    output->stream.common.dump = out_dump;
    output->stream.common.set_parameters = out_set_parameters;
    output->stream.common.get_parameters = out_get_parameters;
    output->stream.common.add_audio_effect = out_add_audio_effect;
    output->stream.common.remove_audio_effect = out_remove_audio_effect;
    output->stream.get_latency = out_get_latency;
    output->stream.set_volume = out_set_volume;
    output->stream.write = out_write;
    output->stream.get_render_position = out_get_render_position;
    output->stream.get_next_write_timestamp = out_get_next_write_timestamp;
    droidhatch_audio_tee_init(&output->tee, droidhatch_audio_source_socket);
    *stream_out = &output->stream;
    return 0;
}

static void adev_close_output_stream(
        struct audio_hw_device *device,
        struct audio_stream_out *stream) {
    (void)device;
    struct droidhatch_stream_out *output =
            (struct droidhatch_stream_out *)stream;
    droidhatch_audio_tee_close(&output->tee);
    free(output);
}

static int adev_set_parameters(
        struct audio_hw_device *device,
        const char *kvpairs) {
    (void)device;
    (void)kvpairs;
    return -ENOSYS;
}

static char *adev_get_parameters(
        const struct audio_hw_device *device,
        const char *keys) {
    (void)device;
    (void)keys;
    return NULL;
}

static int adev_init_check(const struct audio_hw_device *device) {
    (void)device;
    return 0;
}

static int adev_set_voice_volume(struct audio_hw_device *device, float volume) {
    (void)device;
    (void)volume;
    return -ENOSYS;
}

static int adev_set_master_volume(struct audio_hw_device *device, float volume) {
    (void)device;
    (void)volume;
    return -ENOSYS;
}

static int adev_get_master_volume(struct audio_hw_device *device, float *volume) {
    (void)device;
    (void)volume;
    return -ENOSYS;
}

static int adev_set_master_mute(struct audio_hw_device *device, bool muted) {
    (void)device;
    (void)muted;
    return -ENOSYS;
}

static int adev_get_master_mute(struct audio_hw_device *device, bool *muted) {
    (void)device;
    (void)muted;
    return -ENOSYS;
}

static int adev_set_mode(struct audio_hw_device *device, audio_mode_t mode) {
    (void)device;
    (void)mode;
    return 0;
}

static int adev_set_mic_mute(struct audio_hw_device *device, bool state) {
    (void)device;
    (void)state;
    return -ENOSYS;
}

static int adev_get_mic_mute(const struct audio_hw_device *device, bool *state) {
    (void)device;
    (void)state;
    return -ENOSYS;
}

static size_t adev_get_input_buffer_size(
        const struct audio_hw_device *device,
        const struct audio_config *config) {
    (void)device;
    (void)config;
    return DROIDHATCH_AUDIO_INPUT_BUFFER_BYTES;
}

static int adev_open_input_stream(
        struct audio_hw_device *device,
        audio_io_handle_t handle,
        audio_devices_t devices,
        struct audio_config *config,
        struct audio_stream_in **stream_in,
        audio_input_flags_t flags,
        const char *address,
        audio_source_t source) {
    (void)device;
    (void)handle;
    (void)devices;
    (void)config;
    (void)flags;
    (void)address;
    (void)source;

    struct droidhatch_stream_in *input =
            (struct droidhatch_stream_in *)calloc(1, sizeof(*input));
    if (input == NULL) {
        return -ENOMEM;
    }

    input->stream.common.get_sample_rate = in_get_sample_rate;
    input->stream.common.set_sample_rate = in_set_sample_rate;
    input->stream.common.get_buffer_size = in_get_buffer_size;
    input->stream.common.get_channels = in_get_channels;
    input->stream.common.get_format = in_get_format;
    input->stream.common.set_format = in_set_format;
    input->stream.common.standby = in_standby;
    input->stream.common.dump = in_dump;
    input->stream.common.set_parameters = in_set_parameters;
    input->stream.common.get_parameters = in_get_parameters;
    input->stream.common.add_audio_effect = in_add_audio_effect;
    input->stream.common.remove_audio_effect = in_remove_audio_effect;
    input->stream.set_gain = in_set_gain;
    input->stream.read = in_read;
    input->stream.get_input_frames_lost = in_get_input_frames_lost;
    *stream_in = &input->stream;
    return 0;
}

static void adev_close_input_stream(
        struct audio_hw_device *device,
        struct audio_stream_in *stream) {
    (void)device;
    free(stream);
}

static int adev_dump(const struct audio_hw_device *device, int fd) {
    (void)device;
    (void)fd;
    return 0;
}

static int adev_close(hw_device_t *device) {
    free(device);
    return 0;
}

static int adev_open(
        const hw_module_t *module,
        const char *name,
        hw_device_t **device) {
    if (strcmp(name, AUDIO_HARDWARE_INTERFACE) != 0) {
        return -EINVAL;
    }

    struct droidhatch_audio_device *audio_device =
            (struct droidhatch_audio_device *)calloc(1, sizeof(*audio_device));
    if (audio_device == NULL) {
        return -ENOMEM;
    }

    audio_device->device.common.tag = HARDWARE_DEVICE_TAG;
    audio_device->device.common.version = AUDIO_DEVICE_API_VERSION_2_0;
    audio_device->device.common.module = (struct hw_module_t *)module;
    audio_device->device.common.close = adev_close;
    audio_device->device.init_check = adev_init_check;
    audio_device->device.set_voice_volume = adev_set_voice_volume;
    audio_device->device.set_master_volume = adev_set_master_volume;
    audio_device->device.get_master_volume = adev_get_master_volume;
    audio_device->device.set_mode = adev_set_mode;
    audio_device->device.set_mic_mute = adev_set_mic_mute;
    audio_device->device.get_mic_mute = adev_get_mic_mute;
    audio_device->device.set_parameters = adev_set_parameters;
    audio_device->device.get_parameters = adev_get_parameters;
    audio_device->device.get_input_buffer_size = adev_get_input_buffer_size;
    audio_device->device.open_output_stream = adev_open_output_stream;
    audio_device->device.close_output_stream = adev_close_output_stream;
    audio_device->device.open_input_stream = adev_open_input_stream;
    audio_device->device.close_input_stream = adev_close_input_stream;
    audio_device->device.dump = adev_dump;
    audio_device->device.set_master_mute = adev_set_master_mute;
    audio_device->device.get_master_mute = adev_get_master_mute;
    *device = &audio_device->device.common;
    return 0;
}

static struct hw_module_methods_t droidhatch_audio_module_methods = {
    .open = adev_open,
};

struct audio_module HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = AUDIO_MODULE_API_VERSION_0_1,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = AUDIO_HARDWARE_MODULE_ID,
        .name = "DroidHatch tee audio HAL",
        .author = "DroidHatch",
        .methods = &droidhatch_audio_module_methods,
    },
};
