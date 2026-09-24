package com.droidhatch.home;

final class HomeConstants {
    static final String LOG_TAG = "DroidHatchHome";

    static final long RELAUNCH_DELAY_MILLISECONDS = 100L;
    static final long RETRY_WINDOW_MILLISECONDS = 3_000L;
    static final int MAX_RETRIES_IN_WINDOW = 6;

    static final String PREFERENCES_NAME = "droidhatch_session";
    static final String ACTIVE_PACKAGE_KEY = "active_package";
    static final String SESSION_ID_KEY = "session_id";

    static final String SET_ACTIVE_ACTION = "com.droidhatch.home.SET_ACTIVE_PACKAGE";
    static final String CLEAR_ACTIVE_ACTION = "com.droidhatch.home.CLEAR_ACTIVE_PACKAGE";
    static final String PACKAGE_EXTRA = "package_name";
    static final String SESSION_EXTRA = "session_id";
    static final String HOME_PACKAGE = "com.droidhatch.home";
    static final String PACKAGE_NAME_PATTERN =
        "[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+";

    private HomeConstants() {
    }
}
