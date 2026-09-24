package com.droidhatch.home;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

public final class SessionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (HomeConstants.CLEAR_ACTIVE_ACTION.equals(action)) {
            SessionState.clear(context);
            Log.i(HomeConstants.LOG_TAG, "active package cleared");
            return;
        }

        if (Intent.ACTION_BOOT_COMPLETED.equals(action)) {
            // Keep the last active package across a backend restart. The
            // backend is the Android session, so booting it again should
            // resume the selected app instead of showing an empty home.
            Log.i(HomeConstants.LOG_TAG, "boot completed; preserving active package");
            Intent home = new Intent(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            context.startActivity(home);
            return;
        }

        if (!HomeConstants.SET_ACTIVE_ACTION.equals(action)) {
            return;
        }

        String packageName = intent.getStringExtra(HomeConstants.PACKAGE_EXTRA);
        String sessionId = intent.getStringExtra(HomeConstants.SESSION_EXTRA);
        if (!isPackageName(packageName)) {
            SessionState.clear(context);
            Log.w(HomeConstants.LOG_TAG, "rejected invalid active package");
            return;
        }

        SessionState.setActive(context, packageName, sessionId);
        Log.i(HomeConstants.LOG_TAG, "active package set to " + packageName);

        Intent home = new Intent(context, MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        context.startActivity(home);
    }

    private static boolean isPackageName(String packageName) {
        return packageName != null
            && packageName.matches(HomeConstants.PACKAGE_NAME_PATTERN)
            && !HomeConstants.HOME_PACKAGE.equals(packageName);
    }
}
