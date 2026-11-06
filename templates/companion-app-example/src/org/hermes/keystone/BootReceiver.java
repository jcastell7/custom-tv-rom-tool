package org.hermes.keystone;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.SystemProperties;
import android.util.Log;

/** At boot, does what stock's WindowManagerService.initTCorrection and PhoneWindowManager.GlsStartGsensor did. */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "HermesKeystone";
    private static final String PACKAGE = "com.telanda.keystone";
    private static final String PREFIX = "persist.display.keystone_";

    private static int corner(String name) {
        return SystemProperties.getInt(PREFIX + name, 0);
    }

    private static float zoom(String name) {
        return Float.parseFloat(SystemProperties.get(PREFIX + name, "100.0"));
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        final PendingResult result = goAsync();
        new Thread(() -> {
            try {
                restoreCorners(context);
                startAutoCorrection(context);
            } catch (Exception e) {
                Log.e(TAG, "Couldn't restore keystone", e);
            } finally {
                result.finish();
            }
        }).start();
    }

    private void restoreCorners(Context context) throws Exception {
        // The HAL client lives in the stock app, which this app shares a user ID with.
        Context stock = context.createPackageContext(PACKAGE,
                Context.CONTEXT_INCLUDE_CODE | Context.CONTEXT_IGNORE_SECURITY);
        Class<?> manager = stock.getClassLoader().loadClass("com.softwinner.tv.AwTvDisplayManager");
        Object instance = manager.getMethod("getInstance").invoke(null);
        manager.getMethod("setKeystoreValue", float.class, float.class, int.class, int.class, int.class, int.class,
                int.class, int.class, int.class, int.class)
                .invoke(instance, zoom("zoom_h"), zoom("zoom_v"), corner("lbx"), corner("ltx"), corner("rbx"),
                        corner("rtx"), corner("lby"), corner("lty"), corner("rby"), corner("rty"));
        Log.i(TAG, "Restored keystone corners");
    }

    /** The tilt service stays running while enabled, so it only starts if the user turned auto correction on. */
    private void startAutoCorrection(Context context) {
        if (SystemProperties.getBoolean("persist.sys.Auto.Correction", false)) {
            context.startService(new Intent().setComponent(
                    new ComponentName(PACKAGE, PACKAGE + ".GensorService")));
        }
    }
}
