package org.hermes.keystone;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;

/** Stock's keystone app has no launcher entry, so this opens it. */
public class LaunchActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Intent intent = new Intent(Intent.ACTION_MAIN);
        intent.setComponent(new ComponentName("com.telanda.keystone", "com.telanda.keystone.MainActivity"));
        startActivity(intent);
        finish();
    }
}
