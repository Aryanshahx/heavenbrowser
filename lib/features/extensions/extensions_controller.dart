import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/omnibox_parser.dart';
import '../shield/native_shield_bridge.dart';

class ChromeWebStoreSearchItem {
  const ChromeWebStoreSearchItem({
    required this.extensionId,
    required this.name,
    required this.description,
    required this.storeUrl,
  });

  final String extensionId;
  final String name;
  final String description;
  final String storeUrl;
}

class InstalledChromeExtension {
  const InstalledChromeExtension({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.manifestVersion,
    required this.enabled,
    required this.source,
    required this.popupUrl,
    this.optionsUrl = '',
    this.hasBackground = false,
    required this.iconBase64,
    this.iconBytes,
    this.permissions = const <String>[],
    this.matches = const <String>[],
    this.contentScriptCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final int manifestVersion;
  final bool enabled;
  final String source;
  final String popupUrl;
  final String optionsUrl;
  final bool hasBackground;
  final String iconBase64;
  final Uint8List? iconBytes;
  final List<String> permissions;
  final List<String> matches;
  final int contentScriptCount;

  bool get hasPopup => popupUrl.isNotEmpty;
  bool get hasOptions => optionsUrl.isNotEmpty;

  InstalledChromeExtension copyWith({bool? enabled}) {
    return InstalledChromeExtension(
      id: id,
      name: name,
      description: description,
      version: version,
      manifestVersion: manifestVersion,
      enabled: enabled ?? this.enabled,
      source: source,
      popupUrl: popupUrl,
      optionsUrl: optionsUrl,
      hasBackground: hasBackground,
      iconBase64: iconBase64,
      iconBytes: iconBytes,
      permissions: permissions,
      matches: matches,
      contentScriptCount: contentScriptCount,
    );
  }

  factory InstalledChromeExtension.fromNativeMap(Map<String, Object?> map) {
    final String rawIcon = map['iconBase64']?.toString().trim() ?? '';
    Uint8List? decodedIcon;
    if (rawIcon.isNotEmpty) {
      try {
        decodedIcon = base64Decode(rawIcon);
      } catch (_) {
        decodedIcon = null;
      }
    }
    final List<String> perms = (map['permissions'] is List<Object?>)
        ? (map['permissions']! as List<Object?>)
              .map((Object? e) => e?.toString() ?? '')
              .where((String s) => s.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final List<String> matchList = (map['matches'] is List<Object?>)
        ? (map['matches']! as List<Object?>)
              .map((Object? e) => e?.toString() ?? '')
              .where((String s) => s.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return InstalledChromeExtension(
      id: map['id']?.toString().trim() ?? '',
      name: map['name']?.toString().trim() ?? 'Chrome Extension',
      description: map['description']?.toString().trim() ?? '',
      version: map['version']?.toString().trim() ?? '1.0',
      manifestVersion: (map['manifestVersion'] as num?)?.toInt() ?? 3,
      enabled: map['enabled'] != false,
      source: map['source']?.toString() ?? 'webstore',
      popupUrl: map['popupUrl']?.toString().trim() ?? '',
      optionsUrl: map['optionsUrl']?.toString().trim() ?? '',
      hasBackground: map['hasBackground'] == true,
      iconBase64: rawIcon,
      iconBytes: decodedIcon,
      permissions: perms,
      matches: matchList,
      contentScriptCount: (map['contentScriptCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomUserscriptExtension {
  const CustomUserscriptExtension({
    required this.id,
    required this.name,
    required this.description,
    required this.matchPattern,
    required this.jsCode,
    this.cssCode = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final String matchPattern;
  final String jsCode;
  final String cssCode;
  final bool enabled;

  CustomUserscriptExtension copyWith({bool? enabled}) {
    return CustomUserscriptExtension(
      id: id,
      name: name,
      description: description,
      matchPattern: matchPattern,
      jsCode: jsCode,
      cssCode: cssCode,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'matchPattern': matchPattern,
    'jsCode': jsCode,
    'cssCode': cssCode,
    'enabled': enabled,
  };

  factory CustomUserscriptExtension.fromJson(Map<String, Object?> map) {
    return CustomUserscriptExtension(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Custom Script',
      description: map['description']?.toString() ?? '',
      matchPattern: map['matchPattern']?.toString() ?? '*',
      jsCode: map['jsCode']?.toString() ?? '',
      cssCode: map['cssCode']?.toString() ?? '',
      enabled: map['enabled'] != false,
    );
  }

  bool matchesUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return false;
    if (matchPattern == '*' || matchPattern == '<all_urls>') {
      return rawUrl.startsWith('http://') || rawUrl.startsWith('https://');
    }
    final String host = OmniboxParser.cleanDomain(rawUrl);
    final String target = OmniboxParser.cleanDomain(matchPattern);
    if (host.isEmpty || target.isEmpty) return false;
    return host == target || host.endsWith('.$target');
  }
}

class ExtensionsController extends ChangeNotifier {
  ExtensionsController(
    this._prefs, {
    bool syncNativeOnInit = true,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client() {
    _loadLocalScripts();
    if (syncNativeOnInit) {
      unawaited(refreshChromeExtensions());
    }
  }

  static const String chromeWebStoreHomeUrl =
      'https://chromewebstore.google.com/?hl=en';
  static const String _keyCustomScripts = 'hb.ext.customScripts.v9';

  static final RegExp _extIdPattern = RegExp(r'([a-p]{32})');
  static final RegExp _rssItemPattern = RegExp(
    r'<item>([\s\S]*?)</item>',
    caseSensitive: false,
  );

  final SharedPreferences _prefs;
  final http.Client _client;

  List<InstalledChromeExtension> _chromeExtensions =
      <InstalledChromeExtension>[];
  List<CustomUserscriptExtension> _customScripts =
      <CustomUserscriptExtension>[];
  bool _isInstalling = false;
  String? _installingId;
  String? _lastError;

  List<InstalledChromeExtension> get chromeExtensions =>
      List<InstalledChromeExtension>.unmodifiable(_chromeExtensions);

  List<InstalledChromeExtension> get enabledChromeExtensions =>
      _chromeExtensions
          .where((InstalledChromeExtension e) => e.enabled)
          .toList(growable: false);

  List<CustomUserscriptExtension> get customScripts =>
      List<CustomUserscriptExtension>.unmodifiable(_customScripts);

  bool get isInstalling => _isInstalling;
  String? get installingId => _installingId;
  String? get lastError => _lastError;

  int get enabledCount =>
      _chromeExtensions
          .where((InstalledChromeExtension e) => e.enabled)
          .length +
      _customScripts.where((CustomUserscriptExtension s) => s.enabled).length;

  bool isInstalled(String extensionId) {
    final String clean = extensionId.trim().toLowerCase();
    return _chromeExtensions.any(
      (InstalledChromeExtension e) => e.id.toLowerCase() == clean,
    );
  }

  /// Returns true if [rawUrl] belongs to Google's Chrome Web Store.
  static bool isChromeWebStoreUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return false;
    final Uri? u = Uri.tryParse(rawUrl.trim());
    if (u == null) return false;
    final String h = u.host.toLowerCase();
    final String p = u.path.toLowerCase();
    return h == 'chromewebstore.google.com' ||
        (h == 'chrome.google.com' && p.startsWith('/webstore'));
  }

  /// Extracts a 32-character Chrome Extension ID if [urlOrId] is a Chrome Web Store
  /// detail page URL or direct extension ID; returns null otherwise.
  static String? extractChromeWebStoreId(String? urlOrId) {
    if (urlOrId == null || urlOrId.trim().isEmpty) {
      return null;
    }
    final String clean = urlOrId.trim().toLowerCase();
    if (RegExp(r'^[a-p]{32}$').hasMatch(clean)) {
      return clean;
    }
    if (clean.contains('chromewebstore.google.com/detail') ||
        clean.contains('chrome.google.com/webstore/detail')) {
      final Iterable<RegExpMatch> matches = _extIdPattern.allMatches(clean);
      if (matches.isNotEmpty) {
        return matches.last.group(1);
      }
    }
    return null;
  }

  /// Live Chrome Web Store search when the user explicitly types a query.
  Future<List<ChromeWebStoreSearchItem>> searchWebStoreExtensions(
    String rawQuery,
  ) async {
    final String q = rawQuery.trim();
    if (q.isEmpty) return const <ChromeWebStoreSearchItem>[];

    try {
      final Uri uri = Uri.https('www.bing.com', '/search', <String, String>{
        'q': 'site:chromewebstore.google.com/detail $q',
        'format': 'rss',
        'count': '20',
      });
      final http.Response res = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
              'Accept': 'application/rss+xml, application/xml, text/xml',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return const <ChromeWebStoreSearchItem>[];
      }

      final String xml = utf8.decode(res.bodyBytes, allowMalformed: true);
      final Set<String> seenIds = <String>{};
      final List<ChromeWebStoreSearchItem> out = <ChromeWebStoreSearchItem>[];

      for (final RegExpMatch match in _rssItemPattern.allMatches(xml)) {
        final String block = match.group(1) ?? '';
        final String link = _extractXmlTag(block, 'link');
        final String? extId = extractChromeWebStoreId(link);
        if (extId == null || !seenIds.add(extId)) continue;
        String title = _unescapeXml(_extractXmlTag(block, 'title'))
            .replaceAll(
              RegExp(
                r'\s*[-–|]\s*Chrome Web Store.*$',
                caseSensitive: false,
              ),
              '',
            )
            .trim();
        final String desc = _unescapeXml(_extractXmlTag(block, 'description'));
        out.add(
          ChromeWebStoreSearchItem(
            extensionId: extId,
            name: title.isEmpty ? 'Chrome Extension' : title,
            description: desc.isEmpty
                ? 'Official Chrome Web Store (.crx) extension'
                : desc,
            storeUrl: link,
          ),
        );
      }
      return out;
    } catch (_) {
      return const <ChromeWebStoreSearchItem>[];
    }
  }

  static String _extractXmlTag(String xml, String tag) {
    final RegExp re = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    );
    final RegExpMatch? m = re.firstMatch(xml);
    if (m == null) return '';
    return (m.group(1) ?? '')
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .trim();
  }

  static String _unescapeXml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  void _loadLocalScripts() {
    final String? raw = _prefs.getString(_keyCustomScripts);
    if (raw == null || raw.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        _customScripts = decoded
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> m) => CustomUserscriptExtension.fromJson(
                Map<String, Object?>.from(m),
              ),
            )
            .where((CustomUserscriptExtension e) => e.id.isNotEmpty)
            .toList();
      }
    } on FormatException {
      _customScripts = <CustomUserscriptExtension>[];
    }
  }

  Future<void> _persistLocalScripts() async {
    await _prefs.setString(
      _keyCustomScripts,
      jsonEncode(
        _customScripts
            .map((CustomUserscriptExtension s) => s.toJson())
            .toList(),
      ),
    );
  }

  Future<void> refreshChromeExtensions() async {
    final List<Map<String, Object?>> rawList = await NativeShieldBridge.instance
        .listChromeExtensions();
    _chromeExtensions = rawList
        .map(InstalledChromeExtension.fromNativeMap)
        .where((InstalledChromeExtension e) => e.id.isNotEmpty)
        .toList();
    notifyListeners();
  }

  Future<String?> installFromWebStore(String urlOrId) async {
    final String? parsedId = extractChromeWebStoreId(urlOrId);
    if (parsedId == null) {
      return 'Enter a valid Chrome Web Store extension link or 32-character Extension ID.';
    }
    _isInstalling = true;
    _installingId = parsedId;
    _lastError = null;
    notifyListeners();

    try {
      final Map<String, Object?> res = await NativeShieldBridge.instance
          .installWebStoreExtension(urlOrId.trim());
      if (res['ok'] != true) {
        final String err =
            res['error']?.toString() ??
            'Could not download CRX package from Chrome Web Store.';
        _lastError = err;
        return err;
      }
      final Object? extObj = res['extension'];
      if (extObj is Map<Object?, Object?>) {
        final InstalledChromeExtension installed =
            InstalledChromeExtension.fromNativeMap(<String, Object?>{
              for (final MapEntry<Object?, Object?> e in extObj.entries)
                if (e.key != null) e.key.toString(): e.value,
            });
        _chromeExtensions = <InstalledChromeExtension>[
          installed,
          ..._chromeExtensions.where(
            (InstalledChromeExtension e) => e.id != installed.id,
          ),
        ];
      } else {
        await refreshChromeExtensions();
      }
      return null;
    } finally {
      _isInstalling = false;
      _installingId = null;
      notifyListeners();
    }
  }

  Future<String?> pickAndInstallCrxOrZip() async {
    _isInstalling = true;
    _lastError = null;
    notifyListeners();
    try {
      final Map<String, Object?>? res = await NativeShieldBridge.instance
          .pickChromeExtensionFile();
      if (res == null) {
        return null;
      }
      if (res['ok'] != true) {
        final String err =
            res['error']?.toString() ?? 'Invalid Chrome .crx or .zip package.';
        _lastError = err;
        return err;
      }
      await refreshChromeExtensions();
      return null;
    } finally {
      _isInstalling = false;
      notifyListeners();
    }
  }

  Future<void> toggleChromeExtension(String id, bool enabled) async {
    await NativeShieldBridge.instance.toggleChromeExtension(id, enabled);
    _chromeExtensions = _chromeExtensions
        .map(
          (InstalledChromeExtension e) =>
              e.id == id ? e.copyWith(enabled: enabled) : e,
        )
        .toList();
    notifyListeners();
  }

  Future<void> uninstallChromeExtension(String id) async {
    await NativeShieldBridge.instance.uninstallChromeExtension(id);
    _chromeExtensions = _chromeExtensions
        .where((InstalledChromeExtension e) => e.id != id)
        .toList();
    notifyListeners();
  }

  Future<String?> addCustomExtension({
    required String name,
    String description = 'Custom script extension',
    String matchPattern = '*',
    String cssCode = '',
    String jsCode = '',
  }) async {
    final String cleanName = name.trim();
    if (cleanName.isEmpty) {
      return 'Enter an extension name.';
    }
    if (cssCode.trim().isEmpty && jsCode.trim().isEmpty) {
      return 'Provide JavaScript or CSS code.';
    }
    final CustomUserscriptExtension item = CustomUserscriptExtension(
      id: 'script_${DateTime.now().millisecondsSinceEpoch}',
      name: cleanName,
      description: description.trim(),
      matchPattern: matchPattern.trim().isEmpty ? '*' : matchPattern.trim(),
      cssCode: cssCode.trim(),
      jsCode: jsCode.trim(),
    );
    _customScripts = <CustomUserscriptExtension>[item, ..._customScripts];
    await _persistLocalScripts();
    notifyListeners();
    return null;
  }

  Future<void> removeCustomScript(String id) async {
    _customScripts = _customScripts
        .where((CustomUserscriptExtension s) => s.id != id)
        .toList();
    await _persistLocalScripts();
    notifyListeners();
  }

  String buildInjectionScriptForUrl(String? rawUrl) {
    if (rawUrl == null ||
        (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://'))) {
      return '';
    }
    final StringBuffer sb = StringBuffer();
    for (final CustomUserscriptExtension ext in _customScripts) {
      if (!ext.enabled || !ext.matchesUrl(rawUrl)) continue;
      sb.writeln('(function(){try{');
      if (ext.cssCode.isNotEmpty) {
        final String styleId = 'hb-ext-css-${ext.id}';
        final String encodedCss = jsonEncode(ext.cssCode);
        sb.writeln(
          'if(!document.getElementById("$styleId")){var st=document.createElement("style");st.id="$styleId";st.textContent=$encodedCss;(document.head||document.documentElement).appendChild(st);}',
        );
      }
      if (ext.jsCode.isNotEmpty) {
        sb.writeln(ext.jsCode);
      }
      sb.writeln('}catch(_){}})();');
    }
    return sb.toString();
  }

  Future<String> buildFullInjectionForUrl(String? rawUrl) async {
    if (rawUrl == null ||
        (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://'))) {
      return '';
    }
    final String crxBundle = await NativeShieldBridge.instance
        .getChromeExtensionScriptsForUrl(rawUrl);
    final String localBundle = buildInjectionScriptForUrl(rawUrl);
    if (crxBundle.isEmpty) return localBundle;
    if (localBundle.isEmpty) return crxBundle;
    return '$crxBundle\n$localBundle';
  }
}
