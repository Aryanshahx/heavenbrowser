package com.hypertechlabs.heavenbrowser

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var shieldPlugin: HeavenShieldPlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = HeavenShieldPlugin(this)
        shieldPlugin = plugin
        flutterEngine.plugins.add(plugin)
    }

    override fun onPause() {
        super.onPause()
        shieldPlugin?.onActivityPaused()
    }

    override fun onStop() {
        super.onStop()
        shieldPlugin?.onActivityStopped()
    }

    override fun onResume() {
        super.onResume()
        enableHighestRefreshRate()
        shieldPlugin?.onActivityResumed()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        shieldPlugin?.onTrimMemory(level)
    }

    private fun enableHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return
            val activeMode = currentDisplay.mode
            var bestMode = activeMode
            for (candidate in currentDisplay.supportedModes) {
                if (candidate.physicalWidth == activeMode.physicalWidth &&
                    candidate.physicalHeight == activeMode.physicalHeight &&
                    candidate.refreshRate > bestMode.refreshRate
                ) {
                    bestMode = candidate
                }
            }
            if (bestMode.modeId != window.attributes.preferredDisplayModeId) {
                val params = window.attributes
                params.preferredDisplayModeId = bestMode.modeId
                window.attributes = params
            }
        } catch (_: Throwable) {
        }
    }
}
