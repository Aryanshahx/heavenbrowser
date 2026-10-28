# Keep WireGuard GoBackend, JNI native methods, Config models, and VpnService intact under R8
-keep class com.wireguard.** { *; }
-dontwarn com.wireguard.**

# Keep OpenVPN 2.7 / ics-openvpn & openvpn_flutter classes and serialized VpnProfile intact
-keep class de.blinkt.openvpn.** { *; }
-dontwarn de.blinkt.openvpn.**
-keep class id.laskarmedia.openvpn_flutter.** { *; }

# Keep Heaven Browser native bridges, WebView multi-window ChromeClient parent, and @JavascriptInterface methods intact
-keep class com.hypertechlabs.heavenbrowser.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.plugins.webviewflutter.**
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
