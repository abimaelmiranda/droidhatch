package com.droidhatch.home;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;

public final class MainActivity extends Activity {
    private static final int IMMERSIVE_SYSTEM_UI_FLAGS =
        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_FULLSCREEN
            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int launchAttempts;
    private long firstAttemptAt;
    private boolean launchScheduled;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().getDecorView().setSystemUiVisibility(IMMERSIVE_SYSTEM_UI_FLAGS);
        setContentView(new View(this));
    }

    @Override
    protected void onResume() {
        super.onResume();
        scheduleLaunch();
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    private void scheduleLaunch() {
        if (launchScheduled) {
            return;
        }
        launchScheduled = true;
        handler.postDelayed(() -> {
            launchScheduled = false;
            launchActivePackage();
        }, HomeConstants.RELAUNCH_DELAY_MILLISECONDS);
    }

    private void launchActivePackage() {
        String packageName = SessionState.activePackage(this);
        if (packageName == null || packageName.isEmpty()) {
            return;
        }

        long now = System.currentTimeMillis();
        if (firstAttemptAt == 0L
            || now - firstAttemptAt > HomeConstants.RETRY_WINDOW_MILLISECONDS) {
            firstAttemptAt = now;
            launchAttempts = 0;
        }
        if (launchAttempts >= HomeConstants.MAX_RETRIES_IN_WINDOW) {
            Log.e(HomeConstants.LOG_TAG, "stopping relaunch loop for " + packageName);
            SessionState.clear(this);
            return;
        }
        launchAttempts++;

        PackageManager packageManager = getPackageManager();
        Intent launchIntent = resolveLaunchIntent(packageManager, packageName);
        if (launchIntent == null) {
            Log.e(HomeConstants.LOG_TAG, "no launch activity for " + packageName);
            SessionState.clear(this);
            return;
        }

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
            | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        try {
            startActivity(launchIntent);
        } catch (RuntimeException exception) {
            Log.e(HomeConstants.LOG_TAG, "could not relaunch " + packageName, exception);
            if (launchAttempts >= HomeConstants.MAX_RETRIES_IN_WINDOW) {
                SessionState.clear(this);
            }
        }
    }

    private Intent resolveLaunchIntent(PackageManager packageManager, String packageName) {
        Intent launcher = new Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setPackage(packageName);
        ResolveInfo resolved = firstResolve(packageManager, launcher);
        if (resolved == null) {
            launcher = new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                .setPackage(packageName);
            resolved = firstResolve(packageManager, launcher);
        }
        if (resolved == null || resolved.activityInfo == null) {
            return null;
        }

        return new Intent(Intent.ACTION_MAIN)
            .setClassName(
                resolved.activityInfo.packageName,
                resolved.activityInfo.name);
    }

    private ResolveInfo firstResolve(PackageManager packageManager, Intent intent) {
        java.util.List<ResolveInfo> activities = packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_ALL);
        return activities.isEmpty() ? null : activities.get(0);
    }
}
