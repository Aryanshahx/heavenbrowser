import 'package:flutter/material.dart';
import 'package:heavenbrowser/app.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final BrowserSettingsController settings = BrowserSettingsController(prefs);
  runApp(HeavenBrowserApp(settings: settings));
}
