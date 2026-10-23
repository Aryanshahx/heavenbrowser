package com.hypertechlabs.heavenbrowser

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
}
