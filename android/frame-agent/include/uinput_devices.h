#pragma once

#include <cstdint>
#include <string>

#include "agent_resources.h"
#include "input_protocol.h"

namespace droidhatch::input {

class UInputDevice {
public:
    UInputDevice() = default;
    UInputDevice(const UInputDevice&) = delete;
    UInputDevice& operator=(const UInputDevice&) = delete;
    ~UInputDevice();

    void Adopt(agent::UniqueFd descriptor);
    void Destroy();
    int Get() const;
    bool IsOpen() const;

private:
    agent::UniqueFd descriptor_;
};

class UInputDevices {
public:
    UInputDevices() = default;
    UInputDevices(const UInputDevices&) = delete;
    UInputDevices& operator=(const UInputDevices&) = delete;
    ~UInputDevices() = default;

    bool Initialize();

    bool SendKey(std::uint16_t hidUsage, KeyAction action);

    bool SendTouch(
        std::uint32_t pointerId,
        TouchAction action,
        std::uint32_t normalizedX,
        std::uint32_t normalizedY);

    bool SendScroll(
        std::int32_t fixedPointDeltaX,
        std::int32_t fixedPointDeltaY,
        ScrollFlags flags);

    bool SendSystemAction(SystemAction action);

    void ReleaseAll();

    const std::string& FailureReason() const;

private:
    UInputDevice keyboardDevice_;
    UInputDevice touchscreenDevice_;
    UInputDevice scrollDevice_;
    bool touchActive_ = false;
    bool highResolutionScrollEnabled_ = false;
    std::int64_t accumulatedScrollX_ = 0;
    std::int64_t accumulatedScrollY_ = 0;
    std::int64_t accumulatedDetentScrollX_ = 0;
    std::int64_t accumulatedDetentScrollY_ = 0;
    std::string failureReason_;
};

} // namespace droidhatch::input
