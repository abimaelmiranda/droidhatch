#include "uinput_devices.h"

#include "input_key_mapping.h"
#include "input_protocol.h"

#include <cerrno>
#include <array>
#include <cstring>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <string>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>

namespace droidhatch::input {
namespace {

constexpr gid_t kAndroidInputGroupId = 1004;
constexpr mode_t kAndroidInputDeviceMode = 0660;
constexpr unsigned int kMaximumInputEventDevices = 32;
constexpr int kMaximumTrackingId = 65'535;
constexpr const char* kMusicStreamArgument = "3";

struct DeviceDescriptor {
    const char* name;
    std::uint16_t vendor;
    std::uint16_t product;
};

enum class DeviceKind {
    Keyboard,
    Touchscreen,
    Scroll,
};

bool WriteEvent(int fileDescriptor, unsigned short type, unsigned short code, int value) {
    input_event event = {};
    event.type = type;
    event.code = code;
    event.value = value;
    return write(fileDescriptor, &event, sizeof(event)) == sizeof(event);
}

bool SendKeyCode(int fileDescriptor, unsigned short keyCode, int value) {
    return WriteEvent(fileDescriptor, EV_KEY, keyCode, value)
        && WriteEvent(fileDescriptor, EV_SYN, SYN_REPORT, 0);
}

bool AdjustMusicVolume(const char* adjustment) {
    const pid_t child = fork();
    if (child < 0) {
        std::fprintf(stderr, "droidhatch-frame-agent: volume fork failed: %s\n", std::strerror(errno));
        return false;
    }
    if (child == 0) {
        execl(
            "/system/bin/cmd",
            "cmd",
            "media_session",
            "volume",
            "--stream",
            kMusicStreamArgument,
            "--show",
            "--adj",
            adjustment,
            static_cast<char*>(nullptr));
        _exit(127);
    }

    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            std::fprintf(stderr, "droidhatch-frame-agent: volume wait failed: %s\n", std::strerror(errno));
            return false;
        }
    }

    if (!WIFEXITED(status)) {
        std::fprintf(stderr, "droidhatch-frame-agent: volume command did not exit normally\n");
        return false;
    }

    const int exitCode = WEXITSTATUS(status);
    if (exitCode != 0) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: volume command exited with code %d\n",
            exitCode);
        return false;
    }

    return true;
}

bool SendAndroidKeyEvent(const char* keyCode) {
    const pid_t child = fork();
    if (child < 0) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: input keyevent fork failed: %s\n",
            std::strerror(errno));
        return false;
    }
    if (child == 0) {
        execl(
            "/system/bin/input",
            "input",
            "keyevent",
            keyCode,
            static_cast<char*>(nullptr));
        _exit(127);
    }

    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: input keyevent wait failed: %s\n",
                std::strerror(errno));
            return false;
        }
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

void ConfigureAbsoluteAxis(
    int fileDescriptor,
    unsigned int code,
    int minimum,
    int maximum) {
#if defined(UI_ABS_SETUP)
    uinput_abs_setup axis = {};
    axis.code = static_cast<unsigned short>(code);
    axis.absinfo.minimum = minimum;
    axis.absinfo.maximum = maximum;
    ioctl(fileDescriptor, UI_ABS_SETUP, &axis);
#else
    static_cast<void>(fileDescriptor);
    static_cast<void>(code);
    static_cast<void>(minimum);
    static_cast<void>(maximum);
#endif
}

bool CreateUInputDevice(
    int fileDescriptor,
    const DeviceDescriptor& descriptor,
    const uinput_user_dev& legacyDevice,
    bool touchscreen) {
#if defined(UI_DEV_SETUP)
    uinput_setup setup = {};
    std::strncpy(setup.name, descriptor.name, sizeof(setup.name) - 1);
    setup.id.bustype = BUS_USB;
    setup.id.vendor = descriptor.vendor;
    setup.id.product = descriptor.product;
    setup.id.version = 1;
    if (ioctl(fileDescriptor, UI_DEV_SETUP, &setup) == 0) {
        if (touchscreen) {
            ConfigureAbsoluteAxis(fileDescriptor, ABS_MT_SLOT, 0, 0);
            ConfigureAbsoluteAxis(
                fileDescriptor,
                ABS_MT_TRACKING_ID,
                0,
                kMaximumTrackingId);
            ConfigureAbsoluteAxis(
                fileDescriptor,
                ABS_MT_POSITION_X,
                0,
                kNormalizedCoordinateMaximum);
            ConfigureAbsoluteAxis(
                fileDescriptor,
                ABS_MT_POSITION_Y,
                0,
                kNormalizedCoordinateMaximum);
            ConfigureAbsoluteAxis(
                fileDescriptor,
                ABS_X,
                0,
                kNormalizedCoordinateMaximum);
            ConfigureAbsoluteAxis(
                fileDescriptor,
                ABS_Y,
                0,
                kNormalizedCoordinateMaximum);
        }
        return ioctl(fileDescriptor, UI_DEV_CREATE) == 0;
    }
#endif

    return write(
        fileDescriptor,
        &legacyDevice,
        sizeof(legacyDevice)) == sizeof(legacyDevice)
        && ioctl(fileDescriptor, UI_DEV_CREATE) == 0;
}

agent::UniqueFd OpenUInputDevice(
    const DeviceDescriptor& descriptor,
    DeviceKind kind,
    bool* highResolutionScrollEnabled) {
    if (highResolutionScrollEnabled != nullptr) {
        *highResolutionScrollEnabled = false;
    }

    const bool touchscreen = kind == DeviceKind::Touchscreen;
    const bool scroll = kind == DeviceKind::Scroll;
    agent::UniqueFd fileDescriptor(open("/dev/uinput", O_WRONLY | O_NONBLOCK));
    if (!fileDescriptor) {
        return {};
    }

    if (ioctl(fileDescriptor.get(), UI_SET_EVBIT, EV_SYN) < 0) {
        return {};
    }

    if (touchscreen) {
        if (ioctl(fileDescriptor.get(), UI_SET_EVBIT, EV_KEY) < 0
            || ioctl(fileDescriptor.get(), UI_SET_EVBIT, EV_ABS) < 0
            || ioctl(fileDescriptor.get(), UI_SET_PROPBIT, INPUT_PROP_DIRECT) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, BTN_TOUCH) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, BTN_TOOL_FINGER) < 0
            || ioctl(fileDescriptor.get(), UI_SET_ABSBIT, ABS_MT_SLOT) < 0
            || ioctl(fileDescriptor.get(), UI_SET_ABSBIT, ABS_MT_TRACKING_ID) < 0
            || ioctl(fileDescriptor.get(), UI_SET_ABSBIT, ABS_MT_POSITION_X) < 0
            || ioctl(fileDescriptor.get(), UI_SET_ABSBIT, ABS_MT_POSITION_Y) < 0
            || ioctl(fileDescriptor.get(), UI_SET_ABSBIT, ABS_X) < 0
            || ioctl(fileDescriptor.get(), UI_SET_ABSBIT, ABS_Y) < 0) {
            return {};
        }
    } else if (scroll) {
        if (ioctl(fileDescriptor.get(), UI_SET_EVBIT, EV_KEY) < 0
            || ioctl(fileDescriptor.get(), UI_SET_EVBIT, EV_REL) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, BTN_LEFT) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, BTN_RIGHT) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, BTN_MIDDLE) < 0
            || ioctl(fileDescriptor.get(), UI_SET_RELBIT, REL_X) < 0
            || ioctl(fileDescriptor.get(), UI_SET_RELBIT, REL_Y) < 0
            || ioctl(fileDescriptor.get(), UI_SET_RELBIT, REL_WHEEL) < 0
            || ioctl(fileDescriptor.get(), UI_SET_RELBIT, REL_HWHEEL) < 0) {
            return {};
        }

#if defined(REL_WHEEL_HI_RES) && defined(REL_HWHEEL_HI_RES)
        const bool highResolutionEnabled =
            ioctl(fileDescriptor.get(), UI_SET_RELBIT, REL_WHEEL_HI_RES) == 0
            && ioctl(fileDescriptor.get(), UI_SET_RELBIT, REL_HWHEEL_HI_RES) == 0;
        if (highResolutionScrollEnabled != nullptr) {
            *highResolutionScrollEnabled = highResolutionEnabled;
        }
#endif
    } else {
        if (ioctl(fileDescriptor.get(), UI_SET_EVBIT, EV_KEY) < 0) {
            return {};
        }

        for (std::uint16_t usage = 0x04; usage <= 0xE7; ++usage) {
            const auto keyCode = LinuxKeyCodeForHidUsage(usage);
            if (keyCode.has_value()
                && ioctl(fileDescriptor.get(), UI_SET_KEYBIT, *keyCode) < 0) {
                return {};
            }
        }
        if (ioctl(fileDescriptor.get(), UI_SET_KEYBIT, KEY_HOME) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, KEY_BACK) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, KEY_APPSELECT) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, KEY_VOLUMEUP) < 0
            || ioctl(fileDescriptor.get(), UI_SET_KEYBIT, KEY_VOLUMEDOWN) < 0) {
            return {};
        }
    }

    uinput_user_dev device = {};
    std::strncpy(device.name, descriptor.name, sizeof(device.name) - 1);
    device.id.bustype = BUS_USB;
    device.id.vendor = descriptor.vendor;
    device.id.product = descriptor.product;
    device.id.version = 1;
    if (touchscreen) {
        device.absmin[ABS_MT_SLOT] = 0;
        device.absmax[ABS_MT_SLOT] = 0;
        device.absmin[ABS_MT_TRACKING_ID] = 0;
        device.absmax[ABS_MT_TRACKING_ID] = kMaximumTrackingId;
        device.absmin[ABS_MT_POSITION_X] = 0;
        device.absmax[ABS_MT_POSITION_X] = kNormalizedCoordinateMaximum;
        device.absmin[ABS_MT_POSITION_Y] = 0;
        device.absmax[ABS_MT_POSITION_Y] = kNormalizedCoordinateMaximum;
        device.absmin[ABS_X] = 0;
        device.absmax[ABS_X] = kNormalizedCoordinateMaximum;
        device.absmin[ABS_Y] = 0;
        device.absmax[ABS_Y] = kNormalizedCoordinateMaximum;

    }

    if (!CreateUInputDevice(fileDescriptor.get(), descriptor, device, touchscreen)) {
        return {};
    }

    return fileDescriptor;
}

bool ConfigureAndroidInputDevice(
    const char* expectedName,
    std::string* failureReason) {
    std::array<char, 256> actualName = {};
    for (unsigned int index = 0; index < kMaximumInputEventDevices; ++index) {
        const std::string path = "/dev/input/event" + std::to_string(index);
        agent::UniqueFd fileDescriptor(open(path.c_str(), O_RDONLY | O_NONBLOCK));
        if (!fileDescriptor) {
            continue;
        }

        const int nameLength = ioctl(
            fileDescriptor.get(),
            EVIOCGNAME(static_cast<int>(actualName.size())),
            actualName.data());
        if (nameLength <= 0 || std::strcmp(actualName.data(), expectedName) != 0) {
            actualName.fill('\0');
            continue;
        }

        if (chown(path.c_str(), 0, kAndroidInputGroupId) < 0
            || chmod(path.c_str(), kAndroidInputDeviceMode) < 0) {
            if (failureReason != nullptr) {
                *failureReason = path + ": " + std::strerror(errno);
            }
            return false;
        }
        return true;
    }

    if (failureReason != nullptr) {
        *failureReason = std::string("device not found: ") + expectedName;
    }
    return false;
}

} // namespace

UInputDevice::~UInputDevice() {
    Destroy();
}

void UInputDevice::Adopt(agent::UniqueFd descriptor) {
    Destroy();
    descriptor_ = std::move(descriptor);
}

void UInputDevice::Destroy() {
    if (descriptor_) {
        ioctl(descriptor_.get(), UI_DEV_DESTROY);
        descriptor_.reset();
    }
}

int UInputDevice::Get() const {
    return descriptor_.get();
}

bool UInputDevice::IsOpen() const {
    return static_cast<bool>(descriptor_);
}

bool UInputDevices::Initialize() {
    const DeviceDescriptor keyboard = {
        "DroidHatch Host Keyboard",
        0xD1D0,
        0x0001,
    };
    const DeviceDescriptor touchscreen = {
        "DroidHatch Virtual Touchscreen",
        0xD1D0,
        0x0002,
    };

    keyboardDevice_.Adopt(OpenUInputDevice(
        keyboard,
        DeviceKind::Keyboard,
        nullptr));
    if (!keyboardDevice_.IsOpen()) {
        failureReason_ = std::string("keyboard: ") + std::strerror(errno);
        return false;
    }

    touchscreenDevice_.Adopt(OpenUInputDevice(
        touchscreen,
        DeviceKind::Touchscreen,
        nullptr));
    if (!touchscreenDevice_.IsOpen()) {
        failureReason_ = std::string("touchscreen: ") + std::strerror(errno);
        return false;
    }

    const DeviceDescriptor scroll = {
        "DroidHatch Virtual Scroll Wheel",
        0xD1D0,
        0x0003,
    };
    scrollDevice_.Adopt(OpenUInputDevice(
        scroll,
        DeviceKind::Scroll,
        &highResolutionScrollEnabled_));
    if (!scrollDevice_.IsOpen()) {
        failureReason_ = std::string("scroll: ") + std::strerror(errno);
        return false;
    }

    if (!ConfigureAndroidInputDevice(keyboard.name, &failureReason_)
        || !ConfigureAndroidInputDevice(touchscreen.name, &failureReason_)
        || !ConfigureAndroidInputDevice(scroll.name, &failureReason_)) {
        return false;
    }

    return true;
}

bool UInputDevices::SendKey(std::uint16_t hidUsage, KeyAction action) {
    const auto keyCode = LinuxKeyCodeForHidUsage(hidUsage);
    if (!keyCode.has_value()) {
        return false;
    }

    const int value = action == KeyAction::Down ? 1 : 0;
    return SendKeyCode(keyboardDevice_.Get(), *keyCode, value);
}

bool UInputDevices::SendTouch(
    std::uint32_t pointerId,
    TouchAction action,
    std::uint32_t normalizedX,
    std::uint32_t normalizedY) {
    if (pointerId != 0
        || normalizedX > kNormalizedCoordinateMaximum
        || normalizedY > kNormalizedCoordinateMaximum) {
        return false;
    }

    if (action == TouchAction::Down) {
        if (!WriteEvent(touchscreenDevice_.Get(), EV_ABS, ABS_MT_SLOT, 0)
            || !WriteEvent(touchscreenDevice_.Get(), EV_ABS, ABS_MT_TRACKING_ID, 1)
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_MT_POSITION_X,
                static_cast<int>(normalizedX))
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_MT_POSITION_Y,
                static_cast<int>(normalizedY))
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_X,
                static_cast<int>(normalizedX))
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_Y,
                static_cast<int>(normalizedY))
            || !WriteEvent(touchscreenDevice_.Get(), EV_KEY, BTN_TOUCH, 1)
            || !WriteEvent(touchscreenDevice_.Get(), EV_KEY, BTN_TOOL_FINGER, 1)
            || !WriteEvent(touchscreenDevice_.Get(), EV_SYN, SYN_REPORT, 0)) {
            return false;
        }
        touchActive_ = true;
        return true;
    }

    if (action == TouchAction::Move) {
        if (!touchActive_
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_MT_POSITION_X,
                static_cast<int>(normalizedX))
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_MT_POSITION_Y,
                static_cast<int>(normalizedY))
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_X,
                static_cast<int>(normalizedX))
            || !WriteEvent(
                touchscreenDevice_.Get(),
                EV_ABS,
                ABS_Y,
                static_cast<int>(normalizedY))
            || !WriteEvent(touchscreenDevice_.Get(), EV_SYN, SYN_REPORT, 0)) {
            return false;
        }
        return true;
    }

    if (!touchActive_
        || !WriteEvent(touchscreenDevice_.Get(), EV_ABS, ABS_MT_TRACKING_ID, -1)
        || !WriteEvent(touchscreenDevice_.Get(), EV_KEY, BTN_TOUCH, 0)
        || !WriteEvent(touchscreenDevice_.Get(), EV_KEY, BTN_TOOL_FINGER, 0)
        || !WriteEvent(touchscreenDevice_.Get(), EV_SYN, SYN_REPORT, 0)) {
        return false;
    }

    touchActive_ = false;
    return true;
}

bool UInputDevices::SendScroll(
    std::int32_t fixedPointDeltaX,
    std::int32_t fixedPointDeltaY,
    ScrollFlags flags) {
    accumulatedScrollX_ += fixedPointDeltaX;
    accumulatedScrollY_ += fixedPointDeltaY;

    const bool precise = (static_cast<std::uint8_t>(flags)
        & static_cast<std::uint8_t>(ScrollFlags::Precise)) != 0;

    std::int64_t detentDeltaX = 0;
    std::int64_t detentDeltaY = 0;

    if (precise) {
#if defined(REL_WHEEL_HI_RES) && defined(REL_HWHEEL_HI_RES)
        const auto highResolutionScale =
            static_cast<std::int64_t>(kPreciseScrollPointsPerDetent)
            * kScrollFixedPointScale;
        const auto highResolutionNumeratorX =
            accumulatedScrollX_ * kHighResolutionScrollUnitsPerDetent;
        const auto highResolutionNumeratorY =
            accumulatedScrollY_ * kHighResolutionScrollUnitsPerDetent;
        const auto highResolutionDeltaX =
            highResolutionNumeratorX / highResolutionScale;
        const auto highResolutionDeltaY =
            highResolutionNumeratorY / highResolutionScale;
        accumulatedScrollX_ -= highResolutionDeltaX * highResolutionScale
            / kHighResolutionScrollUnitsPerDetent;
        accumulatedScrollY_ -= highResolutionDeltaY * highResolutionScale
            / kHighResolutionScrollUnitsPerDetent;

        if (highResolutionScrollEnabled_
            && (!WriteEvent(
                    scrollDevice_.Get(),
                    EV_REL,
                    REL_HWHEEL_HI_RES,
                    static_cast<int>(highResolutionDeltaX))
                || !WriteEvent(
                    scrollDevice_.Get(),
                    EV_REL,
                    REL_WHEEL_HI_RES,
                    static_cast<int>(highResolutionDeltaY)))) {
            return false;
        }

        accumulatedDetentScrollX_ += highResolutionDeltaX;
        accumulatedDetentScrollY_ += highResolutionDeltaY;
        detentDeltaX = accumulatedDetentScrollX_
            / kHighResolutionScrollUnitsPerDetent;
        detentDeltaY = accumulatedDetentScrollY_
            / kHighResolutionScrollUnitsPerDetent;
        accumulatedDetentScrollX_ %= kHighResolutionScrollUnitsPerDetent;
        accumulatedDetentScrollY_ %= kHighResolutionScrollUnitsPerDetent;
#endif
    } else {
        detentDeltaX = accumulatedScrollX_ / kScrollFixedPointScale;
        detentDeltaY = accumulatedScrollY_ / kScrollFixedPointScale;
        accumulatedScrollX_ %= kScrollFixedPointScale;
        accumulatedScrollY_ %= kScrollFixedPointScale;
    }

    if (detentDeltaX != 0
        && !WriteEvent(
            scrollDevice_.Get(),
            EV_REL,
            REL_HWHEEL,
            static_cast<int>(detentDeltaX))) {
        return false;
    }
    if (detentDeltaY != 0
        && !WriteEvent(
            scrollDevice_.Get(),
            EV_REL,
            REL_WHEEL,
            static_cast<int>(detentDeltaY))) {
        return false;
    }

    return WriteEvent(scrollDevice_.Get(), EV_SYN, SYN_REPORT, 0);
}

bool UInputDevices::SendSystemAction(SystemAction action) {
    if (action == SystemAction::VolumeUp) {
        return AdjustMusicVolume("raise");
    }
    if (action == SystemAction::VolumeDown) {
        return AdjustMusicVolume("lower");
    }

    if (action == SystemAction::PlayPause) {
        return SendAndroidKeyEvent("23");
    }

    unsigned short keyCode = KEY_HOME;
    if (action == SystemAction::Back) {
        keyCode = KEY_BACK;
    }

    return SendKeyCode(keyboardDevice_.Get(), keyCode, 1)
        && SendKeyCode(keyboardDevice_.Get(), keyCode, 0);
}

void UInputDevices::ReleaseAll() {
    if (keyboardDevice_.IsOpen()) {
        for (std::uint16_t usage = 0x04; usage <= 0xE7; ++usage) {
            const auto keyCode = LinuxKeyCodeForHidUsage(usage);
            if (keyCode.has_value()) {
                WriteEvent(keyboardDevice_.Get(), EV_KEY, *keyCode, 0);
            }
        }
        WriteEvent(keyboardDevice_.Get(), EV_KEY, KEY_HOME, 0);
        WriteEvent(keyboardDevice_.Get(), EV_KEY, KEY_BACK, 0);
        WriteEvent(keyboardDevice_.Get(), EV_SYN, SYN_REPORT, 0);
    }

    if (touchscreenDevice_.IsOpen() && touchActive_) {
        WriteEvent(
            touchscreenDevice_.Get(),
            EV_ABS,
            ABS_MT_TRACKING_ID,
            -1);
        WriteEvent(touchscreenDevice_.Get(), EV_KEY, BTN_TOUCH, 0);
        WriteEvent(touchscreenDevice_.Get(), EV_KEY, BTN_TOOL_FINGER, 0);
        WriteEvent(touchscreenDevice_.Get(), EV_SYN, SYN_REPORT, 0);
        touchActive_ = false;
    }

    accumulatedScrollX_ = 0;
    accumulatedScrollY_ = 0;
    accumulatedDetentScrollX_ = 0;
    accumulatedDetentScrollY_ = 0;
}

const std::string& UInputDevices::FailureReason() const {
    return failureReason_;
}

} // namespace droidhatch::input
