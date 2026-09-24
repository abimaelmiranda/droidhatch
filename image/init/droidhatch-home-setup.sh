#!/system/bin/sh

# DroidHatch runs one selected Android app per session. Launcher3 and its
# app/recents surface are deliberately not part of that product model.
/system/bin/pm disable-user --user 0 com.android.launcher3 >/dev/null 2>&1 || true

# Keep the host keyboard path deterministic in the minimal Home image.
/system/bin/settings put secure show_ime_with_hard_keyboard 0 >/dev/null 2>&1 || true
