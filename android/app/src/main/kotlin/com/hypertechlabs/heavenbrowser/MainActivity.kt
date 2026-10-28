package com.hypertechlabs.heavenbrowser

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var shieldPlugin: HeavenShieldPlugin? = null
    private var pendingStartupIntent: Intent? = null
    private var refreshRateConfigured: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighestRefreshRate()
        if (savedInstanceState == null && intent != null) {
            pendingStartupIntent = intent
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = HeavenShieldPlugin(this)
        shieldPlugin = plugin
        flutterEngine.plugins.add(plugin)
        pendingStartupIntent?.let { initial ->
            pendingStartupIntent = null
            plugin.handleIncomingIntent(initial, false)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val plugin = shieldPlugin
        if (plugin != null) {
            plugin.handleIncomingIntent(intent, true)
        } else {
            pendingStartupIntent = intent
        }
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
        shieldPlugin?.onActivityResumed()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        shieldPlugin?.onWindowFocusChanged(hasFocus)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        shieldPlugin?.onTrimMemory(level)
    }

    private fun enableHighestRefreshRate() {
        if (refreshRateConfigured || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        refreshRateConfigured = true
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
