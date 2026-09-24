#include "input_key_mapping.h"

#include <linux/input.h>

namespace droidhatch::input {
namespace {

constexpr std::uint16_t kHidModifierStart = 0xE0;
constexpr std::uint16_t kHidModifierEnd = 0xE7;

} // namespace

std::optional<unsigned short> LinuxKeyCodeForHidUsage(std::uint16_t usage) {
    static constexpr unsigned short letters[] = {
        KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J,
        KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T,
        KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
    };
    static constexpr unsigned short digits[] = {
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5,
        KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
    };
    static constexpr unsigned short modifiers[] = {
        KEY_LEFTCTRL, KEY_LEFTSHIFT, KEY_LEFTALT, KEY_LEFTMETA,
        KEY_RIGHTCTRL, KEY_RIGHTSHIFT, KEY_RIGHTALT, KEY_RIGHTMETA,
    };

    if (usage >= 0x04 && usage <= 0x1D) {
        return letters[usage - 0x04];
    }
    if (usage >= 0x1E && usage <= 0x27) {
        return digits[usage - 0x1E];
    }
    if (usage >= kHidModifierStart && usage <= kHidModifierEnd) {
        return modifiers[usage - kHidModifierStart];
    }

    switch (usage) {
    case 0x28: return KEY_ENTER;
    case 0x29: return KEY_ESC;
    case 0x2A: return KEY_BACKSPACE;
    case 0x2B: return KEY_TAB;
    case 0x2C: return KEY_SPACE;
    case 0x2D: return KEY_MINUS;
    case 0x2F: return KEY_LEFTBRACE;
    case 0x30: return KEY_RIGHTBRACE;
    case 0x31: return KEY_BACKSLASH;
    case 0x33: return KEY_SEMICOLON;
    case 0x34: return KEY_APOSTROPHE;
    case 0x35: return KEY_GRAVE;
    case 0x36: return KEY_COMMA;
    case 0x37: return KEY_DOT;
    case 0x38: return KEY_SLASH;
    case 0x39: return KEY_CAPSLOCK;
    case 0x4F: return KEY_RIGHT;
    case 0x50: return KEY_LEFT;
    case 0x51: return KEY_DOWN;
    case 0x52: return KEY_UP;
    case 0x4A: return KEY_HOME;
    case 0x4D: return KEY_END;
    case 0x4B: return KEY_PAGEUP;
    case 0x4E: return KEY_PAGEDOWN;
    case 0x49: return KEY_INSERT;
    case 0x4C: return KEY_DELETE;
    case 0x2E: return KEY_EQUAL;
    case 0x3A: return KEY_F1;
    case 0x3B: return KEY_F2;
    case 0x3C: return KEY_F3;
    case 0x3D: return KEY_F4;
    case 0x3E: return KEY_F5;
    case 0x3F: return KEY_F6;
    case 0x40: return KEY_F7;
    case 0x41: return KEY_F8;
    case 0x42: return KEY_F9;
    case 0x43: return KEY_F10;
    case 0x44: return KEY_F11;
    case 0x45: return KEY_F12;
    default: return std::nullopt;
    }
}

} // namespace droidhatch::input
