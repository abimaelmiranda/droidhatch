#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct audio_mmap_buffer_info;
struct audio_mmap_position;
struct audio_port_config;
struct audio_port;
struct audio_port_v7;

typedef int audio_io_handle_t;
typedef int audio_patch_handle_t;
typedef int audio_port_handle_t;
typedef uint32_t audio_channel_mask_t;
typedef uint32_t audio_devices_t;
typedef uint32_t audio_format_t;
typedef uint32_t audio_input_flags_t;
typedef uint32_t audio_output_flags_t;
typedef int audio_source_t;
typedef int audio_mode_t;
typedef int audio_latency_mode_t;
typedef int audio_dual_mono_mode_t;
typedef int audio_microphone_direction_t;

typedef struct audio_config {
    uint32_t sample_rate;
    audio_channel_mask_t channel_mask;
    audio_format_t format;
    uint32_t frame_count;
} audio_config_t;

typedef struct audio_playback_rate {
    float mSpeed;
    float mPitch;
    int32_t mFallbackMode;
    int32_t mStretchMode;
} audio_playback_rate_t;

typedef struct audio_microphone_characteristic_t {
    char device_id[32];
} audio_microphone_characteristic_t;

enum {
    AUDIO_MODE_NORMAL = 0,
    AUDIO_MODE_RINGTONE = 1,
    AUDIO_MODE_IN_CALL = 2,
};

enum {
    AUDIO_CHANNEL_OUT_STEREO = 0x3,
    AUDIO_CHANNEL_IN_STEREO = 0xC,
};

enum {
    AUDIO_FORMAT_PCM_16_BIT = 0x1,
};

static inline bool audio_has_proportional_frames(audio_format_t format) {
    return format == AUDIO_FORMAT_PCM_16_BIT;
}

static inline size_t audio_bytes_per_sample(audio_format_t format) {
    return format == AUDIO_FORMAT_PCM_16_BIT ? sizeof(int16_t) : 0;
}

static inline uint32_t audio_channel_count_from_in_mask(audio_channel_mask_t mask) {
    return mask == AUDIO_CHANNEL_IN_STEREO ? 2 : 1;
}

static inline uint32_t audio_channel_count_from_out_mask(audio_channel_mask_t mask) {
    return mask == AUDIO_CHANNEL_OUT_STEREO ? 2 : 1;
}
