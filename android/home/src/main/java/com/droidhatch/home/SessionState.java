package com.droidhatch.home;

import android.content.Context;
import android.content.SharedPreferences;

final class SessionState {
    private SessionState() {
    }

    static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(
            HomeConstants.PREFERENCES_NAME,
            Context.MODE_PRIVATE);
    }

    static String activePackage(Context context) {
        return preferences(context).getString(HomeConstants.ACTIVE_PACKAGE_KEY, null);
    }

    static void setActive(Context context, String packageName, String sessionId) {
        preferences(context).edit()
            .putString(HomeConstants.ACTIVE_PACKAGE_KEY, packageName)
            .putString(HomeConstants.SESSION_ID_KEY, sessionId == null ? "" : sessionId)
            .apply();
    }

    static void clear(Context context) {
        preferences(context).edit().clear().apply();
    }
}
