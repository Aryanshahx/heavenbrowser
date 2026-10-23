import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/omnibox_parser.dart';

class BrowserExtension {
  const BrowserExtension({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.matchPattern,
    required this.jsCode,
    this.cssCode = '',
    this.iconBadge = '🧩',
    this.enabled = false,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String matchPattern; // '*' or domain suffix e.g. 'youtube.com'
  final String jsCode;
  final String cssCode;
  final String iconBadge;
  final bool enabled;
  final bool isBuiltIn;

  BrowserExtension copyWith({bool? enabled}) {
    return BrowserExtension(
      id: id,
      name: name,
      description: description,
      version: version,
      matchPattern: matchPattern,
      jsCode: jsCode,
      cssCode: cssCode,
      iconBadge: iconBadge,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn,
    );
  }

  bool matchesHost(String host) {
    final String pattern = matchPattern.trim().toLowerCase();
    if (pattern.isEmpty || pattern == '*' || pattern == '<all_urls>') {
      return true;
    }
    final String cleanHost = OmniboxParser.cleanDomain(host);
    String cleanPat = pattern
        .replaceFirst(RegExp(r'^https?:\/\/'), '')
        .replaceFirst(RegExp(r'^\*\.'), '');
    final int slash = cleanPat.indexOf('/');
    if (slash >= 0) {
      cleanPat = cleanPat.substring(0, slash);
    }
    if (cleanPat.isEmpty || cleanPat == '*') {
      return true;
    }
    return cleanHost == cleanPat || cleanHost.endsWith('.$cleanPat');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'matchPattern': matchPattern,
    'jsCode': jsCode,
    'cssCode': cssCode,
    'iconBadge': iconBadge,
    'enabled': enabled,
  };

  factory BrowserExtension.fromJson(Map<String, Object?> map) {
    return BrowserExtension(
      id: (map['id']?.toString() ?? '').trim(),
      name: (map['name']?.toString() ?? 'Custom Extension').trim(),
      description: (map['description']?.toString() ?? 'Userscript extension')
          .trim(),
      version: (map['version']?.toString() ?? '1.0').trim(),
      matchPattern: (map['matchPattern']?.toString() ?? '*').trim(),
      jsCode: map['jsCode']?.toString() ?? '',
      cssCode: map['cssCode']?.toString() ?? '',
      iconBadge: (map['iconBadge']?.toString() ?? '🧩').trim(),
      enabled: map['enabled'] == true,
      isBuiltIn: false,
    );
  }
}

class ExtensionsController extends ChangeNotifier {
  ExtensionsController(this._prefs, {http.Client? client})
    : _client = client ?? http.Client() {
    _load();
  }

  static const String _keyEnabledBuiltIns = 'hb.ext.enabledBuiltIns.v8';
  static const String _keyCustomExtensions = 'hb.ext.customList.v8';

  final SharedPreferences _prefs;
  final http.Client _client;

  final Set<String> _enabledBuiltInIds = <String>{
    'ext_cookie_reject',
    'ext_copy_unlock',
  };
  List<BrowserExtension> _customExtensions = <BrowserExtension>[];

  static const List<BrowserExtension> _builtInCatalog = <BrowserExtension>[
    BrowserExtension(
      id: 'ext_dark_reader',
      name: 'Dark Reader Web',
      description:
          'Smart dark theme for bright websites while keeping images and videos natural.',
      version: '2.1',
      matchPattern: '*',
      iconBadge: '🌙',
      isBuiltIn: true,
      cssCode: '''
html {
  background-color: #0d1321 !important;
  filter: invert(0.91) hue-rotate(180deg) !important;
}
img, video, picture, canvas, svg, [style*="background-image"] {
  filter: invert(1) hue-rotate(180deg) !important;
}
''',
      jsCode: '',
    ),
    BrowserExtension(
      id: 'ext_cookie_reject',
      name: 'Cookie Banner Auto-Dismiss',
      description:
          'Automatically hides annoying GDPR cookie popups and unlocks page scrolling.',
      version: '1.8',
      matchPattern: '*',
      iconBadge: '🍪',
      isBuiltIn: true,
      cssCode: '''
#onetrust-consent-sdk, #CybotCookiebotDialog, .qc-cmp2-container,
[id*="cookie-banner"], [class*="cookie-banner"], [class*="cookie-consent"],
[aria-label*="cookie" i][role="dialog"] {
  display: none !important;
  visibility: hidden !important;
  pointer-events: none !important;
}
''',
      jsCode: '''
document.documentElement.style.setProperty('overflow', 'auto', 'important');
if (document.body) document.body.style.setProperty('overflow', 'auto', 'important');
''',
    ),
    BrowserExtension(
      id: 'ext_copy_unlock',
      name: 'Copy & Right-Click Unlocker',
      description:
          'Enables text selection, copy/paste, and context menus on websites that block copying.',
      version: '1.4',
      matchPattern: '*',
      iconBadge: '📋',
      isBuiltIn: true,
      cssCode: '''
*, *::before, *::after {
  -webkit-user-select: text !important;
  user-select: text !important;
}
''',
      jsCode: '''
['copy', 'cut', 'paste', 'contextmenu', 'selectstart'].forEach(function(ev) {
  window.addEventListener(ev, function(e) { e.stopPropagation(); }, true);
});
''',
    ),
    BrowserExtension(
      id: 'ext_yt_enhancer',
      name: 'Video & YouTube Enhancer',
      description:
          'Auto-skips video promos, hides Shorts clutter banners, and unlocks clean playback.',
      version: '1.9',
      matchPattern: 'youtube.com',
      iconBadge: '🎬',
      isBuiltIn: true,
      cssCode: '''
ytm-mealbar-promo-renderer, ytd-mealbar-promo-renderer,
ytm-statement-banner-renderer {
  display: none !important;
}
''',
      jsCode: '''
var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button');
if (skipBtn) skipBtn.click();
''',
    ),
    BrowserExtension(
      id: 'ext_amp_cleaner',
      name: 'AMP & Tracking Link Cleaner',
      description:
          'Strips ping click-trackers and rewrites AMP links directly to clean canonical URLs.',
      version: '1.3',
      matchPattern: '*',
      iconBadge: '🔗',
      isBuiltIn: true,
      jsCode: '''
document.querySelectorAll('a[ping]').forEach(function(a) {
  a.removeAttribute('ping');
});
''',
    ),
    BrowserExtension(
      id: 'ext_readability_boost',
      name: 'Crisp Font & Readability Boost',
      description:
          'Improves subpixel font rendering and paragraph readability across news and docs.',
      version: '1.2',
      matchPattern: '*',
      iconBadge: '✨',
      isBuiltIn: true,
      cssCode: '''
body {
  -webkit-font-smoothing: antialiased !important;
  text-rendering: optimizeLegibility !important;
}
''',
      jsCode: '',
    ),
  ];

  List<BrowserExtension> get builtInExtensions => _builtInCatalog
      .map(
        (BrowserExtension ext) =>
            ext.copyWith(enabled: _enabledBuiltInIds.contains(ext.id)),
      )
      .toList(growable: false);

  List<BrowserExtension> get customExtensions =>
      List<BrowserExtension>.unmodifiable(_customExtensions);

  List<BrowserExtension> get allExtensions => <BrowserExtension>[
    ...builtInExtensions,
    ..._customExtensions,
  ];

  int get enabledCount =>
      allExtensions.where((BrowserExtension e) => e.enabled).length;

  void _load() {
    final List<String>? savedBuiltIns = _prefs.getStringList(
      _keyEnabledBuiltIns,
    );
    if (savedBuiltIns != null) {
      _enabledBuiltInIds
        ..clear()
        ..addAll(savedBuiltIns);
    }
    final String? rawCustom = _prefs.getString(_keyCustomExtensions);
    if (rawCustom != null && rawCustom.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawCustom);
        if (decoded is List<Object?>) {
          _customExtensions = decoded
              .whereType<Map<String, Object?>>()
              .map(BrowserExtension.fromJson)
              .where((BrowserExtension e) => e.id.isNotEmpty)
              .toList();
        }
      } on FormatException {
        _customExtensions = <BrowserExtension>[];
      }
    }
  }

  Future<void> toggleExtension(String id, bool enabled) async {
    final bool isBuiltIn = _builtInCatalog.any(
      (BrowserExtension e) => e.id == id,
    );
    if (isBuiltIn) {
      if (enabled) {
        _enabledBuiltInIds.add(id);
      } else {
        _enabledBuiltInIds.remove(id);
      }
      await _prefs.setStringList(
        _keyEnabledBuiltIns,
        _enabledBuiltInIds.toList(),
      );
    } else {
      _customExtensions = _customExtensions
          .map(
            (BrowserExtension e) => e.id == id ? e.copyWith(enabled: enabled) : e,
          )
          .toList();
      await _persistCustom();
    }
    notifyListeners();
  }

  Future<String?> addCustomExtension({
    required String name,
    String description = 'Custom browser extension',
    String matchPattern = '*',
    String cssCode = '',
    String jsCode = '',
  }) async {
    final String cleanName = name.trim();
    if (cleanName.isEmpty) {
      return 'Enter an extension name.';
    }
    if (cssCode.trim().isEmpty && jsCode.trim().isEmpty) {
      return 'Provide JavaScript or CSS code for the extension.';
    }
    final BrowserExtension ext = BrowserExtension(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: cleanName,
      description: description.trim().isEmpty
          ? 'Custom JS/CSS extension'
          : description.trim(),
      version: '1.0',
      matchPattern: matchPattern.trim().isEmpty ? '*' : matchPattern.trim(),
      cssCode: cssCode.trim(),
      jsCode: jsCode.trim(),
      enabled: true,
    );
    _customExtensions = <BrowserExtension>[ext, ..._customExtensions];
    await _persistCustom();
    notifyListeners();
    return null;
  }

  Future<String?> installUserscriptFromUrl(String rawUrl) async {
    final Uri? uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return 'Enter a valid http:// or https:// userscript URL.';
    }
    try {
      final http.Response res = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.body.trim().isEmpty) {
        return 'Unable to download script (HTTP ${res.statusCode}).';
      }
      return await installFromUserscriptSource(res.body);
    } catch (e) {
      return 'Failed to download userscript: $e';
    }
  }

  Future<String?> installFromUserscriptSource(String source) async {
    final String code = source.trim();
    if (code.isEmpty) {
      return 'Userscript source is empty.';
    }
    String name = 'Imported Userscript';
    String desc = 'Installed from .user.js';
    String match = '*';

    for (final String line in code.split('\n').take(40)) {
      final String trimmed = line.trim();
      final RegExpMatch? m = RegExp(
        r'^\/\/\s*@(\w+)\s+(.+)$',
      ).firstMatch(trimmed);
      if (m != null) {
        final String key = m.group(1)!.toLowerCase();
        final String val = m.group(2)!.trim();
        if (key == 'name' && val.isNotEmpty) name = val;
        if (key == 'description' && val.isNotEmpty) desc = val;
        if ((key == 'match' || key == 'include') && val.isNotEmpty) {
          match = val;
        }
      }
    }
    return addCustomExtension(
      name: name,
      description: desc,
      matchPattern: match,
      jsCode: code,
    );
  }

  Future<void> removeCustomExtension(String id) async {
    _customExtensions = _customExtensions
        .where((BrowserExtension e) => e.id != id)
        .toList();
    await _persistCustom();
    notifyListeners();
  }

  Future<void> _persistCustom() async {
    await _prefs.setString(
      _keyCustomExtensions,
      jsonEncode(_customExtensions.map((BrowserExtension e) => e.toJson()).toList()),
    );
  }

  String buildInjectionScriptForUrl(String url) {
    final Uri? parsed = Uri.tryParse(url);
    final String host = parsed?.host ?? '';
    if (host.isEmpty) {
      return '';
    }
    final List<BrowserExtension> active = allExtensions
        .where((BrowserExtension e) => e.enabled && e.matchesHost(host))
        .toList(growable: false);
    if (active.isEmpty) {
      return '';
    }

    final StringBuffer sb = StringBuffer('(function(){\n');
    for (final BrowserExtension ext in active) {
      final String safeStyleId = 'hb-ext-css-${ext.id}';
      if (ext.cssCode.isNotEmpty) {
        final String encodedCss = jsonEncode(ext.cssCode);
        sb.writeln('''
try {
  var st = document.getElementById('$safeStyleId');
  if (!st) {
    st = document.createElement('style');
    st.id = '$safeStyleId';
    st.textContent = $encodedCss;
    (document.head || document.documentElement).appendChild(st);
  }
} catch (_) {}
''');
      }
      if (ext.jsCode.isNotEmpty) {
        sb.writeln('try {\n${ext.jsCode}\n} catch (_) {}');
      }
    }
    sb.writeln('})();');
    return sb.toString();
  }
}
