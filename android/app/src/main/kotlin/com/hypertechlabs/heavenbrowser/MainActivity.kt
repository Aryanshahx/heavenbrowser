package com.hypertechlabs.heavenbrowser

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var shieldPlugin: HeavenShieldPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = HeavenShieldPlugin(this)
        shieldPlugin = plugin
        flutterEngine.plugins.add(plugin)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        shieldPlugin?.onActivityUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        shieldPlugin?.onPictureInPictureChanged(isInPictureInPictureMode)
    }

    override fun onPause() {
        super.onPause()
        shieldPlugin?.onActivityPaused()
    }

    override fun onResume() {
        super.onResume()
        shieldPlugin?.onActivityResumed()
    }
}
