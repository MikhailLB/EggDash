package com.eggdash.eggdashgame

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow the window to draw under the display cutout (camera
        // notch / punch hole / curved corners) on both short edges
        // of the device. Without this, Android clips the layout so
        // a landscape rotation leaves black bars next to the cutout.
        //
        // Each screen still respects safe insets where needed:
        //   • BootStage  — full-bleed splash (intentional).
        //   • ShellStage — applies viewPadding.left/right manually so
        //                  WebView content never falls under the cutout.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }
}
