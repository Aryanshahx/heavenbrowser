# Keep WireGuard GoBackend, JNI native methods, Config models, and VpnService intact under R8
-keep class com.wireguard.** { *; }
-dontwarn com.wireguard.**

# Keep OpenVPN 2.7 / ics-openvpn & openvpn_flutter classes and serialized VpnProfile intact
-keep class de.blinkt.openvpn.** { *; }
-dontwarn de.blinkt.openvpn.**
-keep class id.laskarmedia.openvpn_flutter.** { *; }

# Keep Google ML Kit On-Device GenAI (Gemini Nano / AICore) classes intact under R8
-keep class com.google.mlkit.genai.** { *; }
-dontwarn com.google.mlkit.genai.**

# Keep Heaven Browser native bridges and @JavascriptInterface methods intact
-keep class com.hypertechlabs.heavenbrowser.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
