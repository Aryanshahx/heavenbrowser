import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/omnibox_parser.dart';
import '../shield/native_shield_bridge.dart';

enum HeavenShieldMode {
  standard(
    'Standard',
    'Blocks ad networks & trackers while keeping logins and video players smooth',
  ),
  strict(
    'Strict',
    'Aggressive ad, analytics, CNAME tracker & hardware-entropy blocking',
  );

  const HeavenShieldMode(this.label, this.description);
  final String label;
  final String description;

  static HeavenShieldMode fromName(String? raw) {
    for (final HeavenShieldMode m in HeavenShieldMode.values) {
      if (m.name == raw) return m;
    }
    return HeavenShieldMode.standard;
  }
}

enum HeavenTrackersAdsLevel {
  aggressive('Aggressive', 'Block trackers & ads (Aggressive)'),
  standard('Standard', 'Block trackers & ads (Standard)'),
  disabled('Allow all trackers & ads', 'Allow all trackers & ads');

  const HeavenTrackersAdsLevel(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

enum HeavenHttpsUpgradeMode {
  strict('Strict', 'Require HTTPS for all connections'),
  standard('Standard (default)', 'Upgrade to HTTPS whenever possible (default)'),
  disabled('Disabled', 'Do not automatically upgrade HTTP connections');

  const HeavenHttpsUpgradeMode(this.label, this.subtitle);
  final String label;
  final String subtitle;

  static HeavenHttpsUpgradeMode fromName(String? raw) {
    for (final HeavenHttpsUpgradeMode m in HeavenHttpsUpgradeMode.values) {
      if (m.name == raw) return m;
    }
    return HeavenHttpsUpgradeMode.standard;
  }
}

enum HeavenCookiePolicy {
  blockAll('Block all cookies', 'block_all'),
  blockThirdParty('Block third-party cookies', 'block_third_party'),
  allowAll('Allow all cookies', 'allow_all');

  const HeavenCookiePolicy(this.label, this.nativeCode);
  final String label;
  final String nativeCode;

  static HeavenCookiePolicy fromName(String? raw) {
    for (final HeavenCookiePolicy p in HeavenCookiePolicy.values) {
      if (p.name == raw || p.nativeCode == raw) return p;
    }
    return HeavenCookiePolicy.blockThirdParty;
  }
}

enum HeavenAutoShredMode {
  never('Never', 'Manual shred only'),
  siteTabClosed('When site tab closes', 'Auto-shred site data when its tab closes'),
  appExit('On app exit', 'Auto-shred browsing data when leaving Heaven');

  const HeavenAutoShredMode(this.label, this.subtitle);
  final String label;
  final String subtitle;

  static HeavenAutoShredMode fromName(String? raw) {
    for (final HeavenAutoShredMode m in HeavenAutoShredMode.values) {
      if (m.name == raw) return m;
    }
    return HeavenAutoShredMode.never;
  }
}

enum HeavenSafeBrowsingMode {
  enhanced('Enhanced protection', 'Enhanced protection is on', 'enhanced'),
  standard('Standard protection', 'Standard protection is on', 'standard'),
  off('No protection (not recommended)', 'Safe Browsing is off', 'off');

  const HeavenSafeBrowsingMode(this.label, this.subtitle, this.nativeCode);
  final String label;
  final String subtitle;
  final String nativeCode;

  static HeavenSafeBrowsingMode fromName(String? raw) {
    for (final HeavenSafeBrowsingMode m in HeavenSafeBrowsingMode.values) {
      if (m.name == raw || m.nativeCode == raw) return m;
    }
    return HeavenSafeBrowsingMode.standard;
  }
}

enum HeavenWebrtcPolicy {
  defaultPolicy('Default', 'default'),
  publicOnly('Default public interface only', 'public_only'),
  publicAndPrivate('Default public and private interfaces', 'public_and_private'),
  disableNonProxiedUdp('Disable non-proxied UDP', 'disable_non_proxied_udp');

  const HeavenWebrtcPolicy(this.label, this.nativeCode);
  final String label;
  final String nativeCode;

  static HeavenWebrtcPolicy fromName(String? raw) {
    for (final HeavenWebrtcPolicy p in HeavenWebrtcPolicy.values) {
      if (p.name == raw || p.nativeCode == raw) return p;
    }
    return HeavenWebrtcPolicy.defaultPolicy;
  }
}

enum HeavenSecureDnsMode {
  automatic('Automatic', ''),
  cloudflare('Cloudflare (1.1.1.1)', 'https://cloudflare-dns.com/dns-query'),
  quad9('Quad9 (9.9.9.9)', 'https://dns.quad9.net/dns-query'),
  adguard('AdGuard DNS', 'https://dns.adguard-dns.com/dns-query'),
  google('Google (8.8.8.8)', 'https://dns.google/dns-query'),
  off('Off', '');

  const HeavenSecureDnsMode(this.label, this.dohEndpoint);
  final String label;
  final String dohEndpoint;

  static HeavenSecureDnsMode fromName(String? raw) {
    for (final HeavenSecureDnsMode m in HeavenSecureDnsMode.values) {
      if (m.name == raw) return m;
    }
    return HeavenSecureDnsMode.automatic;
  }
}

enum HeavenJsOptimisationMode {
  standard('Standard (V8 JIT)', 'Sites are faster but less secure'),
  strict('Strict security (Disable JIT/Wasm)', 'Hardened runtime for unfamiliar sites');

  const HeavenJsOptimisationMode(this.label, this.subtitle);
  final String label;
  final String subtitle;

  static HeavenJsOptimisationMode fromName(String? raw) {
    for (final HeavenJsOptimisationMode m in HeavenJsOptimisationMode.values) {
      if (m.name == raw) return m;
    }
    return HeavenJsOptimisationMode.standard;
  }
}

enum SitePermissionType {
  location('Location', 'Access your GPS or coarse location'),
  camera('Camera', 'Capture video or photos on this site'),
  microphone('Microphone', 'Record audio or voice calls'),
  notifications('Notifications', 'Show website push alerts'),
  popups('Pop-ups & Redirects', 'Open new windows or external redirects'),
  javascript('JavaScript', 'Run interactive scripts on this site'),
  protectedMedia('Protected Media', 'Play DRM-encrypted video streams');

  const SitePermissionType(this.label, this.description);
  final String label;
  final String description;
}

enum SitePermissionDecision {
  ask('Ask'),
  allow('Allowed'),
  block('Blocked');

  const SitePermissionDecision(this.label);
  final String label;

  static SitePermissionDecision fromName(String? raw) {
    for (final SitePermissionDecision d in SitePermissionDecision.values) {
      if (d.name == raw) return d;
    }
    return SitePermissionDecision.ask;
  }
}

class SiteUsageEntry {
  const SiteUsageEntry({
    required this.domain,
    required this.url,
    required this.title,
    required this.visitCount,
    required this.lastVisitedMs,
    this.isPinned = false,
  });

  final String domain;
  final String url;
  final String title;
  final int visitCount;
  final int lastVisitedMs;
  final bool isPinned;

  SiteUsageEntry copyWith({
    String? url,
    String? title,
    int? visitCount,
    int? lastVisitedMs,
    bool? isPinned,
  }) {
    return SiteUsageEntry(
      domain: domain,
      url: url ?? this.url,
      title: title ?? this.title,
      visitCount: visitCount ?? this.visitCount,
      lastVisitedMs: lastVisitedMs ?? this.lastVisitedMs,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'domain': domain,
    'url': url,
    'title': title,
    'visitCount': visitCount,
    'lastVisitedMs': lastVisitedMs,
    'isPinned': isPinned,
  };

  factory SiteUsageEntry.fromJson(Map<String, Object?> json) {
    final String rawUrl = (json['url']?.toString() ?? '').trim();
    final String domain = (json['domain']?.toString() ?? '').trim().isNotEmpty
        ? json['domain']!.toString().trim()
        : OmniboxParser.cleanDomain(rawUrl);
    return SiteUsageEntry(
      domain: domain,
      url: rawUrl.isEmpty ? 'https://$domain' : rawUrl,
      title: (json['title']?.toString() ?? '').trim().isNotEmpty
          ? json['title']!.toString().trim()
          : OmniboxParser.friendlySiteTitleFromDomain(domain),
      visitCount: (json['visitCount'] is num)
          ? (json['visitCount']! as num).toInt()
          : 0,
      lastVisitedMs: (json['lastVisitedMs'] is num)
          ? (json['lastVisitedMs']! as num).toInt()
          : 0,
      isPinned: json['isPinned'] == true,
    );
  }
}

class BookmarkItem {
  const BookmarkItem({
    required this.title,
    required this.url,
    required this.createdAtMs,
  });

  final String title;
  final String url;
  final int createdAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'createdAtMs': createdAtMs,
  };

  factory BookmarkItem.fromJson(Map<String, Object?> json) {
    return BookmarkItem(
      title: (json['title']?.toString() ?? 'Bookmark').trim(),
      url: (json['url']?.toString() ?? '').trim(),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs']! as num).toInt()
          : 0,
    );
  }
}

class HistoryItem {
  const HistoryItem({
    required this.title,
    required this.url,
    required this.visitedAtMs,
  });

  final String title;
  final String url;
  final int visitedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'visitedAtMs': visitedAtMs,
  };

  factory HistoryItem.fromJson(Map<String, Object?> json) {
    return HistoryItem(
      title: (json['title']?.toString() ?? 'Page').trim(),
      url: (json['url']?.toString() ?? '').trim(),
      visitedAtMs: (json['visitedAtMs'] is num)
          ? (json['visitedAtMs']! as num).toInt()
          : 0,
    );
  }
}

class BrowserSettingsController extends ChangeNotifier {
  BrowserSettingsController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const String _keySearchEngine = 'hb.searchEngine.v13';
  static const String _legacyKeySearchEngine = 'hb.searchEngine.v3';
  static const String _keyThemeMode = 'hb.themeMode.v3';
  static const String _keyHttpsUpgrade = 'hb.httpsUpgrade';
  static const String _keyBlockThirdPartyCookies = 'hb.blockThirdPartyCookies';
  static const String _keySendDntGpc = 'hb.sendDntGpc';
  static const String _keyClearOnExit = 'hb.clearOnExit';
  static const String _keyJavascriptEnabled = 'hb.javascriptEnabled';
  static const String _keyDesktopMode = 'hb.desktopMode';
  static const String _keyTextScalePercent = 'hb.textScalePercent';
  static const String _keyJsDisabledHosts = 'hb.jsDisabledHosts.v8';
  static const String _keyPopupAllowedHosts = 'hb.popupAllowedHosts.v8';
  static const String _keySitePermissions = 'hb.sitePermissions.v13';
  static const String _keyRecentSearches = 'hb.recentSearches.v8';
  static const String _keyLanguage = 'hb.language.v8';
  static const String _keyBgMedia = 'hb.bgMedia.v13';
  static const String _keyBiometricIncognito = 'hb.biometricIncognito.v13';
  static const String _keyBiometricApp = 'hb.biometricApp.v13';
  static const String _keyDownloadNotifs = 'hb.downloadNotifs.v8';
  static const String _keyBgPlayNotifs = 'hb.bgPlayNotifs.v13';
  static const String _keyWebNotifs = 'hb.webNotifs.v8';
  static const String _keyShieldEnabled = 'hb.shield.enabled.v19';
  static const String _keyShieldMode = 'hb.shield.mode.v19';
  static const String _keyShieldBlockAds = 'hb.shield.blockAds.v19';
  static const String _keyShieldCookieBanners = 'hb.shield.cookieBanners.v19';
  static const String _keyShieldCleanUrls = 'hb.shield.cleanUrls.v19';
  static const String _keyShieldAntiFp = 'hb.shield.antiFp.v19';
  static const String _keyShieldBlockPopups = 'hb.shield.blockPopups.v19';
  static const String _keyShieldDisabledHosts = 'hb.shield.disabledHosts.v19';
  static const String _keyShieldHttpsMode = 'hb.shield.httpsMode.v20';
  static const String _keyShieldCookiePolicy = 'hb.shield.cookiePolicy.v20';
  static const String _keyShieldAutoAmp = 'hb.shield.autoAmp.v20';
  static const String _keyShieldLangFp = 'hb.shield.langFp.v20';
  static const String _keyShieldStoreContact = 'hb.shield.storeContact.v20';
  static const String _keyShieldContactEmail = 'hb.shield.contactEmail.v20';
  static const String _keyShieldAutoShred = 'hb.shield.autoShred.v20';
  static const String _keyShieldPrivElemBlock = 'hb.shield.privElemBlock.v20';
  static const String _keyShieldFbEmbeds = 'hb.shield.fbEmbeds.v20';
  static const String _keyShieldTwEmbeds = 'hb.shield.twEmbeds.v20';
  static const String _keyShieldLiEmbeds = 'hb.shield.liEmbeds.v20';
  static const String _keyOpenExtInHeaven = 'hb.shield.openExtInHeaven.v20';
  static const String _keySafeBrowsing = 'hb.shield.safeBrowsing.v20';
  static const String _keyAllowAppLinks = 'hb.shield.allowAppLinks.v20';
  static const String _keyWebrtcPolicy = 'hb.shield.webrtcPolicy.v20';
  static const String _keyPrivScreenshots = 'hb.shield.privScreenshots.v20';
  static const String _keyPaymentQuery = 'hb.shield.paymentQuery.v20';
  static const String _keyUnstoppable = 'hb.shield.unstoppable.v20';
  static const String _keyEns = 'hb.shield.ens.v20';
  static const String _keySns = 'hb.shield.sns.v20';
  static const String _keySecureDns = 'hb.shield.secureDns.v20';
  static const String _keyJsOpt = 'hb.shield.jsOpt.v20';
  static const String _keyBlockSwitchApp = 'hb.shield.blockSwitchApp.v20';
  static const String _keyCloseTabsExit = 'hb.shield.closeTabsExit.v20';
  static const String _keyFilterFanboy = 'hb.shield.filterFanboy.v20';
  static const String _keyFilterMobNotifs = 'hb.shield.filterMobNotifs.v20';
  static const String _keyFilterAntiAb = 'hb.shield.filterAntiAb.v20';
  static const String _keyFilterRegIndia = 'hb.shield.filterRegIndia.v20';
  static const String _keyFilterRegGlobal = 'hb.shield.filterRegGlobal.v20';
  static const String _keyCustomFilterRules = 'hb.shield.customRules.v20';
  static const String _keyTranslateTargetLang = 'hb.translateLang.v18';
  static const String _keyReaderFontSize = 'hb.readerFontSize.v18';
  static const String _keyReaderTheme = 'hb.readerTheme.v18';
  static const String _keySiteUsage = 'hb.siteUsage.v3';
  static const String _keyHiddenDomains = 'hb.hiddenQuickDomains.v3';
  static const String _keyBookmarks = 'hb.bookmarks.v3';
  static const String _keyHistory = 'hb.history.v3';

  // Google is the default search engine; Heaven Shield is removed so websites
  // and search engines work natively with their own cookies & settings!
  SearchEngine _searchEngine = SearchEngine.google;
  ThemeMode _themeMode = ThemeMode.dark;
  BrowserLanguage _language = BrowserLanguage.en;
  bool _httpsUpgrade = true;
  bool _blockThirdPartyCookies = false;
  bool _sendDntAndGpc = false;
  bool _clearOnExit = false;
  bool _javascriptEnabled = true;
  bool _desktopMode = false;
  bool _backgroundMediaEnabled = true;
  bool _biometricLockIncognito = false;
  bool _biometricLockApp = false;
  bool _downloadNotificationsEnabled = true;
  bool _backgroundPlayNotificationEnabled = true;
  bool _webNotificationsEnabled = false;
  bool _shieldEnabled = false;
  HeavenShieldMode _shieldMode = HeavenShieldMode.standard;
  bool _shieldBlockAds = false;
  bool _shieldBlockCookieBanners = false;
  bool _shieldCleanUrls = false;
  bool _shieldAntiFingerprinting = false;
  bool _shieldBlockPopups = false;
  HeavenHttpsUpgradeMode _httpsUpgradeMode = HeavenHttpsUpgradeMode.standard;
  HeavenCookiePolicy _cookiePolicy = HeavenCookiePolicy.allowAll;
  bool _shieldAutoRedirectAmp = false;
  bool _shieldPreventLangFp = false;
  bool _storeBrokenSiteContact = true;
  String _brokenSiteContactEmail = '';
  HeavenAutoShredMode _autoShredMode = HeavenAutoShredMode.never;
  bool _allowElementBlockInPrivate = false;
  bool _allowFacebookEmbeds = true;
  bool _allowTwitterEmbeds = true;
  bool _allowLinkedinEmbeds = false;
  bool _openExternalLinksInHeaven = true;
  HeavenSafeBrowsingMode _safeBrowsingMode = HeavenSafeBrowsingMode.standard;
  bool _allowExternalAppLinks = true;
  HeavenWebrtcPolicy _webrtcPolicy = HeavenWebrtcPolicy.defaultPolicy;
  bool _allowPrivateScreenshots = false;
  bool _allowPaymentMethodQuery = true;
  bool _resolveUnstoppableDomains = true;
  bool _resolveEnsDomains = true;
  bool _resolveSnsDomains = true;
  HeavenSecureDnsMode _secureDnsMode = HeavenSecureDnsMode.automatic;
  HeavenJsOptimisationMode _jsOptimisationMode =
      HeavenJsOptimisationMode.standard;
  bool _blockSwitchToAppNotices = true;
  bool _closeTabsOnExit = false;
  bool _filterFanboyAnnoyances = true;
  bool _filterMobileNotifs = true;
  bool _filterAntiAdblock = true;
  bool _filterRegionalIndia = false;
  bool _filterRegionalGlobal = false;
  List<String> _customFilterRules = <String>[];
  int _textScalePercent = 100;
  String _translateTargetLang = 'en';
  double _readerFontSize = 18.0;
  String _readerTheme = 'midnight';

  final Set<String> _jsDisabledHosts = <String>{};
  final Set<String> _popupAllowedHosts = <String>{};
  final Set<String> _shieldDisabledHosts = <String>{};
  final Map<String, Map<SitePermissionType, SitePermissionDecision>>
  _sitePermissions =
      <String, Map<SitePermissionType, SitePermissionDecision>>{};
  List<String> _recentSearches = <String>[];
  final Map<String, SiteUsageEntry> _siteUsageByDomain =
      <String, SiteUsageEntry>{};
  final Set<String> _hiddenQuickDomains = <String>{};
  List<BookmarkItem> _bookmarks = <BookmarkItem>[];
  List<HistoryItem> _history = <HistoryItem>[];

  int _webViewConfigRevision = 0;
  int get webViewConfigRevision => _webViewConfigRevision;
  SharedPreferences get prefs => _prefs;
  SearchEngine get searchEngine => _searchEngine;
  ThemeMode get themeMode => _themeMode;
  BrowserLanguage get language => _language;
  bool get httpsUpgrade => _httpsUpgrade;
  bool get blockThirdPartyCookies => _blockThirdPartyCookies;
  bool get sendDntAndGpc => _sendDntAndGpc;
  bool get clearOnExit => _clearOnExit;
  bool get javascriptEnabled => _javascriptEnabled;
  bool get desktopMode => _desktopMode;
  bool get backgroundMediaEnabled => _backgroundMediaEnabled;
  bool get biometricLockIncognito => _biometricLockIncognito;
  bool get biometricLockApp => _biometricLockApp;
  bool get downloadNotificationsEnabled => _downloadNotificationsEnabled;
  bool get backgroundPlayNotificationEnabled =>
      _backgroundPlayNotificationEnabled;
  bool get webNotificationsEnabled => _webNotificationsEnabled;
  bool get shieldEnabled => _shieldEnabled;
  HeavenShieldMode get shieldMode => _shieldMode;
  bool get shieldBlockAds => _shieldBlockAds;
  bool get shieldBlockCookieBanners => _shieldBlockCookieBanners;
  bool get shieldCleanUrls => _shieldCleanUrls;
  bool get shieldAntiFingerprinting => _shieldAntiFingerprinting;
  bool get shieldBlockPopups => _shieldBlockPopups;
  HeavenTrackersAdsLevel get trackersAdsLevel {
    if (!_shieldBlockAds) return HeavenTrackersAdsLevel.disabled;
    return _shieldMode == HeavenShieldMode.strict
        ? HeavenTrackersAdsLevel.aggressive
        : HeavenTrackersAdsLevel.standard;
  }

  HeavenHttpsUpgradeMode get httpsUpgradeMode => _httpsUpgradeMode;
  HeavenCookiePolicy get cookiePolicy => _cookiePolicy;
  bool get shieldAutoRedirectAmp => _shieldAutoRedirectAmp;
  bool get shieldPreventLangFp => _shieldPreventLangFp;
  bool get storeBrokenSiteContact => _storeBrokenSiteContact;
  String get brokenSiteContactEmail => _brokenSiteContactEmail;
  HeavenAutoShredMode get autoShredMode => _autoShredMode;
  bool get allowElementBlockInPrivate => _allowElementBlockInPrivate;
  bool get allowFacebookEmbeds => _allowFacebookEmbeds;
  bool get allowTwitterEmbeds => _allowTwitterEmbeds;
  bool get allowLinkedinEmbeds => _allowLinkedinEmbeds;
  bool get openExternalLinksInHeaven => _openExternalLinksInHeaven;
  HeavenSafeBrowsingMode get safeBrowsingMode => _safeBrowsingMode;
  bool get allowExternalAppLinks => _allowExternalAppLinks;
  HeavenWebrtcPolicy get webrtcPolicy => _webrtcPolicy;
  bool get allowPrivateScreenshots => _allowPrivateScreenshots;
  bool get allowPaymentMethodQuery => _allowPaymentMethodQuery;
  bool get resolveUnstoppableDomains => _resolveUnstoppableDomains;
  bool get resolveEnsDomains => _resolveEnsDomains;
  bool get resolveSnsDomains => _resolveSnsDomains;
  HeavenSecureDnsMode get secureDnsMode => _secureDnsMode;
  HeavenJsOptimisationMode get jsOptimisationMode => _jsOptimisationMode;
  bool get blockSwitchToAppNotices => _blockSwitchToAppNotices;
  bool get closeTabsOnExit => _closeTabsOnExit;
  bool get filterFanboyAnnoyances => _filterFanboyAnnoyances;
  bool get filterMobileNotifs => _filterMobileNotifs;
  bool get filterAntiAdblock => _filterAntiAdblock;
  bool get filterRegionalIndia => _filterRegionalIndia;
  bool get filterRegionalGlobal => _filterRegionalGlobal;
  List<String> get customFilterRules =>
      List<String>.unmodifiable(_customFilterRules);

  int get activeContentFilterListCount {
    int c = 0;
    if (_shieldBlockCookieBanners) c++;
    if (_filterFanboyAnnoyances) c++;
    if (_filterMobileNotifs) c++;
    if (_filterAntiAdblock) c++;
    if (_filterRegionalIndia) c++;
    if (_filterRegionalGlobal) c++;
    return c;
  }
  List<String> get shieldDisabledHosts {
    final List<String> list = _shieldDisabledHosts.toList()..sort();
    return List<String>.unmodifiable(list);
  }

  int get activeShieldProtectionCount {
    if (!_shieldEnabled) return 0;
    int count = 0;
    if (_shieldBlockAds) count++;
    if (_shieldBlockCookieBanners) count++;
    if (_shieldCleanUrls) count++;
    if (_shieldAntiFingerprinting) count++;
    if (_shieldBlockPopups) count++;
    if (_httpsUpgrade) count++;
    if (_blockThirdPartyCookies) count++;
    return count;
  }
  String get translateTargetLang => _translateTargetLang;
  double get readerFontSize => _readerFontSize;
  String get readerTheme => _readerTheme;
  int get textScalePercent => _textScalePercent;
  List<String> get recentSearches => List<String>.unmodifiable(_recentSearches);
  List<BookmarkItem> get bookmarks =>
      List<BookmarkItem>.unmodifiable(_bookmarks);
  List<HistoryItem> get history => List<HistoryItem>.unmodifiable(_history);

  List<SiteUsageEntry> get quickLaunchSites {
    final List<SiteUsageEntry> pinned = <SiteUsageEntry>[];
    final List<SiteUsageEntry> frequent = <SiteUsageEntry>[];

    for (final SiteUsageEntry entry in _siteUsageByDomain.values) {
      if (_hiddenQuickDomains.contains(entry.domain)) {
        continue;
      }
      if (entry.isPinned) {
        pinned.add(entry);
      } else if (entry.visitCount > 0) {
        frequent.add(entry);
      }
    }

    pinned.sort((SiteUsageEntry a, SiteUsageEntry b) {
      final int byCount = b.visitCount.compareTo(a.visitCount);
      return byCount != 0
          ? byCount
          : b.lastVisitedMs.compareTo(a.lastVisitedMs);
    });

    frequent.sort((SiteUsageEntry a, SiteUsageEntry b) {
      final int byCount = b.visitCount.compareTo(a.visitCount);
      return byCount != 0
          ? byCount
          : b.lastVisitedMs.compareTo(a.lastVisitedMs);
    });

    return <SiteUsageEntry>[...pinned, ...frequent].take(8).toList();
  }

  void _load() {
    final String? savedEngine =
        _prefs.getString(_keySearchEngine) ??
        _prefs.getString(_legacyKeySearchEngine);
    _searchEngine = SearchEngine.fromName(savedEngine);
    _themeMode = switch (_prefs.getString(_keyThemeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _httpsUpgradeMode = HeavenHttpsUpgradeMode.disabled;
    _httpsUpgrade = false;
    _cookiePolicy = HeavenCookiePolicy.allowAll;
    _blockThirdPartyCookies = false;

    _sendDntAndGpc = false;
    _clearOnExit = _prefs.getBool(_keyClearOnExit) ?? false;
    _javascriptEnabled = _prefs.getBool(_keyJavascriptEnabled) ?? true;
    _desktopMode = _prefs.getBool(_keyDesktopMode) ?? false;
    _textScalePercent = (_prefs.getInt(_keyTextScalePercent) ?? 100).clamp(
      75,
      175,
    );
    _language = BrowserLanguage.fromCode(_prefs.getString(_keyLanguage));
    _backgroundMediaEnabled = _prefs.getBool(_keyBgMedia) ?? true;
    _biometricLockIncognito =
        _prefs.getBool(_keyBiometricIncognito) ?? false;
    _biometricLockApp = _prefs.getBool(_keyBiometricApp) ?? false;
    _downloadNotificationsEnabled =
        _prefs.getBool(_keyDownloadNotifs) ?? true;
    _backgroundPlayNotificationEnabled =
        _prefs.getBool(_keyBgPlayNotifs) ?? true;
    _webNotificationsEnabled = _prefs.getBool(_keyWebNotifs) ?? false;
    // Heaven Shield is completely removed — never activate legacy stored Shield flags!
    _shieldEnabled = false;
    _shieldMode = HeavenShieldMode.standard;
    _shieldBlockAds = false;
    _shieldBlockCookieBanners = false;
    _shieldCleanUrls = false;
    _shieldAntiFingerprinting = false;
    _shieldBlockPopups = false;
    _shieldAutoRedirectAmp = false;
    _shieldPreventLangFp = false;
    _storeBrokenSiteContact = false;
    _brokenSiteContactEmail = '';
    _autoShredMode = HeavenAutoShredMode.never;
    _allowElementBlockInPrivate = false;
    _allowFacebookEmbeds = true;
    _allowTwitterEmbeds = true;
    _allowLinkedinEmbeds = true;
    _openExternalLinksInHeaven = _prefs.getBool(_keyOpenExtInHeaven) ?? true;
    _safeBrowsingMode = HeavenSafeBrowsingMode.standard;
    _allowExternalAppLinks = _prefs.getBool(_keyAllowAppLinks) ?? true;
    _webrtcPolicy = HeavenWebrtcPolicy.defaultPolicy;
    _allowPrivateScreenshots = _prefs.getBool(_keyPrivScreenshots) ?? false;
    _allowPaymentMethodQuery = true;
    _resolveUnstoppableDomains = true;
    _resolveEnsDomains = true;
    _resolveSnsDomains = true;
    _secureDnsMode = HeavenSecureDnsMode.automatic;
    _jsOptimisationMode = HeavenJsOptimisationMode.standard;
    _blockSwitchToAppNotices = false;
    _closeTabsOnExit = _prefs.getBool(_keyCloseTabsExit) ?? false;
    _filterFanboyAnnoyances = false;
    _filterMobileNotifs = false;
    _filterAntiAdblock = false;
    _filterRegionalIndia = false;
    _filterRegionalGlobal = false;
    _customFilterRules = <String>[];
    _translateTargetLang =
        _prefs.getString(_keyTranslateTargetLang) ?? 'en';
    _readerFontSize =
        (_prefs.getDouble(_keyReaderFontSize) ?? 18.0).clamp(14.0, 26.0);
    _readerTheme = _prefs.getString(_keyReaderTheme) ?? 'midnight';

    final List<String>? savedShieldAllow = _prefs.getStringList(
      _keyShieldDisabledHosts,
    );
    if (savedShieldAllow != null) {
      _shieldDisabledHosts
        ..clear()
        ..addAll(
          savedShieldAllow
              .map(OmniboxParser.cleanDomain)
              .where((String h) => h.isNotEmpty),
        );
    }

    final List<String>? savedJsDisabled = _prefs.getStringList(
      _keyJsDisabledHosts,
    );
    if (savedJsDisabled != null) {
      _jsDisabledHosts
        ..clear()
        ..addAll(savedJsDisabled);
    }

    final List<String>? savedPopupAllowed = _prefs.getStringList(
      _keyPopupAllowedHosts,
    );
    if (savedPopupAllowed != null) {
      _popupAllowedHosts
        ..clear()
        ..addAll(savedPopupAllowed);
    }

    final String? rawPerms = _prefs.getString(_keySitePermissions);
    if (rawPerms != null && rawPerms.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawPerms);
        if (decoded is Map<String, Object?>) {
          for (final MapEntry<String, Object?> hostEntry in decoded.entries) {
            final Object? permMap = hostEntry.value;
            if (permMap is Map<String, Object?>) {
              final Map<SitePermissionType, SitePermissionDecision> parsed =
                  <SitePermissionType, SitePermissionDecision>{};
              for (final SitePermissionType t in SitePermissionType.values) {
                final String? v = permMap[t.name]?.toString();
                if (v != null) {
                  parsed[t] = SitePermissionDecision.fromName(v);
                }
              }
              if (parsed.isNotEmpty) {
                _sitePermissions[hostEntry.key] = parsed;
              }
            }
          }
        }
      } on FormatException {
        _sitePermissions.clear();
      }
    }

    final List<String>? savedRecent = _prefs.getStringList(_keyRecentSearches);
    if (savedRecent != null) {
      _recentSearches = savedRecent
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .take(15)
          .toList();
    }

    final List<String>? hidden = _prefs.getStringList(_keyHiddenDomains);
    if (hidden != null) {
      _hiddenQuickDomains
        ..clear()
        ..addAll(hidden);
    }

    final String? rawUsage = _prefs.getString(_keySiteUsage);
    if (rawUsage != null && rawUsage.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawUsage);
        if (decoded is List<Object?>) {
          for (final Object? item in decoded) {
            if (item is Map<String, Object?>) {
              final SiteUsageEntry entry = SiteUsageEntry.fromJson(item);
              if (entry.domain.isNotEmpty) {
                _siteUsageByDomain[entry.domain] = entry;
              }
            }
          }
        }
      } on FormatException {
        _siteUsageByDomain.clear();
      }
    }

    final String? rawBookmarks = _prefs.getString(_keyBookmarks);
    if (rawBookmarks != null && rawBookmarks.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawBookmarks);
        if (decoded is List<Object?>) {
          _bookmarks = decoded
              .whereType<Map<String, Object?>>()
              .map(BookmarkItem.fromJson)
              .where((BookmarkItem b) => b.url.isNotEmpty)
              .toList();
        }
      } on FormatException {
        _bookmarks = <BookmarkItem>[];
      }
    }

    final String? rawHistory = _prefs.getString(_keyHistory);
    if (rawHistory != null && rawHistory.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawHistory);
        if (decoded is List<Object?>) {
          _history = decoded
              .whereType<Map<String, Object?>>()
              .map(HistoryItem.fromJson)
              .where((HistoryItem h) => h.url.isNotEmpty)
              .toList();
        }
      } on FormatException {
        _history = <HistoryItem>[];
      }
    }

    _pushNativeBrowserConfig();
  }

  void _pushNativeBrowserConfig() {
    NativeShieldBridge.instance.syncBrowserConfig(
      desktopMode: _desktopMode,
      backgroundMediaEnabled: _backgroundMediaEnabled,
      webNotificationsEnabled: _webNotificationsEnabled,
      backgroundPlayNotificationEnabled: _backgroundPlayNotificationEnabled,
      shieldEnabled: _shieldEnabled,
      shieldStrictMode: _shieldMode == HeavenShieldMode.strict,
      shieldBlockAds: _shieldBlockAds,
      shieldBlockCookieBanners: _shieldBlockCookieBanners,
      shieldCleanUrls: _shieldCleanUrls,
      shieldAntiFingerprinting: _shieldAntiFingerprinting,
      shieldBlockPopups: _shieldBlockPopups,
      shieldDisabledHosts: _shieldDisabledHosts.toList(growable: false),
      shieldCookiePolicy: _cookiePolicy.nativeCode,
      shieldSafeBrowsing: _safeBrowsingMode.nativeCode,
      shieldAutoRedirectAmp: _shieldAutoRedirectAmp,
      shieldPreventLangFp: _shieldPreventLangFp,
      shieldAllowFacebookEmbeds: _allowFacebookEmbeds,
      shieldAllowTwitterEmbeds: _allowTwitterEmbeds,
      shieldAllowLinkedinEmbeds: _allowLinkedinEmbeds,
      shieldWebrtcPolicy: _webrtcPolicy.nativeCode,
      shieldAllowPaymentQuery: _allowPaymentMethodQuery,
      shieldStrictJsSecurity:
          _jsOptimisationMode == HeavenJsOptimisationMode.strict,
      shieldBlockSwitchToApp: _blockSwitchToAppNotices,
      shieldSendDoNotTrack: _sendDntAndGpc,
      shieldFilterFanboyAnnoyances: _filterFanboyAnnoyances,
      shieldFilterMobileNotifs: _filterMobileNotifs,
      shieldFilterAntiAdblock: _filterAntiAdblock,
      shieldFilterRegionalIndia: _filterRegionalIndia,
      shieldFilterRegionalGlobal: _filterRegionalGlobal,
      shieldCustomRules: _customFilterRules,
    );
  }

  static final RegExp _trackingParamRegex = RegExp(
    r'^(utm_[a-z0-9_]+|fbclid|gclid|dclid|msclkid|yclid|mc_eid|igshid|_hsenc|_hsmi|vero_id|mkt_tok)$',
    caseSensitive: false,
  );

  static Uri stripTrackingParameters(Uri uri) {
    if (!uri.hasQuery || uri.queryParametersAll.isEmpty) {
      return uri;
    }
    bool modified = false;
    final Map<String, List<String>> kept = <String, List<String>>{};
    uri.queryParametersAll.forEach((String key, List<String> values) {
      if (_trackingParamRegex.hasMatch(key)) {
        modified = true;
      } else {
        kept[key] = values;
      }
    });
    if (!modified) {
      return uri;
    }
    if (kept.isEmpty) {
      return uri.replace(queryParameters: const <String, dynamic>{}).removeFragment().replace(
        fragment: uri.hasFragment ? uri.fragment : null,
      );
    }
    return uri.replace(queryParameters: kept);
  }

  bool isHostShieldAllowlisted(String? rawHost) {
    String cur = OmniboxParser.cleanDomain(rawHost);
    if (cur.isEmpty || _shieldDisabledHosts.isEmpty) {
      return false;
    }
    while (true) {
      if (_shieldDisabledHosts.contains(cur)) {
        return true;
      }
      final int dot = cur.indexOf('.');
      if (dot < 0 || dot + 1 >= cur.length) {
        break;
      }
      cur = cur.substring(dot + 1);
    }
    return false;
  }

  bool isShieldActiveForHost(String? rawHost) {
    return _shieldEnabled && !isHostShieldAllowlisted(rawHost);
  }

  Future<void> setShieldEnabled(bool enabled) async {
    if (_shieldEnabled == enabled) return;
    _shieldEnabled = enabled;
    await _prefs.setBool(_keyShieldEnabled, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldMode(HeavenShieldMode mode) async {
    if (_shieldMode == mode) return;
    _shieldMode = mode;
    await _prefs.setString(_keyShieldMode, mode.name);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldBlockAds(bool enabled) async {
    if (_shieldBlockAds == enabled) return;
    _shieldBlockAds = enabled;
    await _prefs.setBool(_keyShieldBlockAds, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldBlockCookieBanners(bool enabled) async {
    if (_shieldBlockCookieBanners == enabled) return;
    _shieldBlockCookieBanners = enabled;
    await _prefs.setBool(_keyShieldCookieBanners, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldCleanUrls(bool enabled) async {
    if (_shieldCleanUrls == enabled) return;
    _shieldCleanUrls = enabled;
    await _prefs.setBool(_keyShieldCleanUrls, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldAntiFingerprinting(bool enabled) async {
    if (_shieldAntiFingerprinting == enabled) return;
    _shieldAntiFingerprinting = enabled;
    await _prefs.setBool(_keyShieldAntiFp, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldBlockPopups(bool enabled) async {
    if (_shieldBlockPopups == enabled) return;
    _shieldBlockPopups = enabled;
    await _prefs.setBool(_keyShieldBlockPopups, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<bool> addShieldExceptionHost(String rawHost) async {
    final String clean = OmniboxParser.cleanDomain(rawHost);
    if (clean.isEmpty || !clean.contains('.')) {
      return false;
    }
    if (!_shieldDisabledHosts.add(clean)) {
      return true;
    }
    await _prefs.setStringList(
      _keyShieldDisabledHosts,
      _shieldDisabledHosts.toList(growable: false),
    );
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
    return true;
  }

  Future<void> removeShieldExceptionHost(String rawHost) async {
    final String clean = OmniboxParser.cleanDomain(rawHost);
    if (!_shieldDisabledHosts.remove(clean)) {
      return;
    }
    await _prefs.setStringList(
      _keyShieldDisabledHosts,
      _shieldDisabledHosts.toList(growable: false),
    );
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldProtectionForHost(String rawHost, bool protectSite) async {
    if (protectSite) {
      // Remove exact host or any parent domain matching rawHost
      String cur = OmniboxParser.cleanDomain(rawHost);
      bool changed = false;
      while (cur.isNotEmpty) {
        if (_shieldDisabledHosts.remove(cur)) {
          changed = true;
        }
        final int dot = cur.indexOf('.');
        if (dot < 0 || dot + 1 >= cur.length) {
          break;
        }
        cur = cur.substring(dot + 1);
      }
      if (!changed) return;
      await _prefs.setStringList(
        _keyShieldDisabledHosts,
        _shieldDisabledHosts.toList(growable: false),
      );
      _webViewConfigRevision += 1;
      _pushNativeBrowserConfig();
      notifyListeners();
    } else {
      await addShieldExceptionHost(rawHost);
    }
  }

  Future<void> setTrackersAdsLevel(HeavenTrackersAdsLevel level) async {
    switch (level) {
      case HeavenTrackersAdsLevel.aggressive:
        _shieldEnabled = true;
        _shieldBlockAds = true;
        _shieldMode = HeavenShieldMode.strict;
      case HeavenTrackersAdsLevel.standard:
        _shieldEnabled = true;
        _shieldBlockAds = true;
        _shieldMode = HeavenShieldMode.standard;
      case HeavenTrackersAdsLevel.disabled:
        _shieldBlockAds = false;
    }
    await _prefs.setBool(_keyShieldEnabled, _shieldEnabled);
    await _prefs.setBool(_keyShieldBlockAds, _shieldBlockAds);
    await _prefs.setString(_keyShieldMode, _shieldMode.name);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setHttpsUpgradeMode(HeavenHttpsUpgradeMode mode) async {
    _httpsUpgradeMode = mode;
    _httpsUpgrade = mode != HeavenHttpsUpgradeMode.disabled;
    await _prefs.setString(_keyShieldHttpsMode, mode.name);
    await _prefs.setBool(_keyHttpsUpgrade, _httpsUpgrade);
    _webViewConfigRevision += 1;
    notifyListeners();
  }

  Future<void> setCookiePolicy(HeavenCookiePolicy policy) async {
    _cookiePolicy = policy;
    _blockThirdPartyCookies = policy != HeavenCookiePolicy.allowAll;
    await _prefs.setString(_keyShieldCookiePolicy, policy.name);
    await _prefs.setBool(_keyBlockThirdPartyCookies, _blockThirdPartyCookies);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldAutoRedirectAmp(bool v) async {
    if (_shieldAutoRedirectAmp == v) return;
    _shieldAutoRedirectAmp = v;
    await _prefs.setBool(_keyShieldAutoAmp, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldPreventLangFp(bool v) async {
    if (_shieldPreventLangFp == v) return;
    _shieldPreventLangFp = v;
    await _prefs.setBool(_keyShieldLangFp, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setStoreBrokenSiteContact(bool v) async {
    _storeBrokenSiteContact = v;
    await _prefs.setBool(_keyShieldStoreContact, v);
    if (!v) {
      _brokenSiteContactEmail = '';
      await _prefs.remove(_keyShieldContactEmail);
    }
    notifyListeners();
  }

  Future<void> setBrokenSiteContactEmail(String email) async {
    final String clean = email.trim();
    _brokenSiteContactEmail = clean;
    if (_storeBrokenSiteContact && clean.isNotEmpty) {
      await _prefs.setString(_keyShieldContactEmail, clean);
    } else {
      await _prefs.remove(_keyShieldContactEmail);
    }
    notifyListeners();
  }

  Future<void> setAutoShredMode(HeavenAutoShredMode mode) async {
    if (_autoShredMode == mode) return;
    _autoShredMode = mode;
    await _prefs.setString(_keyShieldAutoShred, mode.name);
    if (mode == HeavenAutoShredMode.appExit) {
      _clearOnExit = true;
      await _prefs.setBool(_keyClearOnExit, true);
    }
    notifyListeners();
  }

  Future<void> setAllowElementBlockInPrivate(bool v) async {
    if (_allowElementBlockInPrivate == v) return;
    _allowElementBlockInPrivate = v;
    await _prefs.setBool(_keyShieldPrivElemBlock, v);
    notifyListeners();
  }

  Future<void> setAllowFacebookEmbeds(bool v) async {
    if (_allowFacebookEmbeds == v) return;
    _allowFacebookEmbeds = v;
    await _prefs.setBool(_keyShieldFbEmbeds, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setAllowTwitterEmbeds(bool v) async {
    if (_allowTwitterEmbeds == v) return;
    _allowTwitterEmbeds = v;
    await _prefs.setBool(_keyShieldTwEmbeds, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setAllowLinkedinEmbeds(bool v) async {
    if (_allowLinkedinEmbeds == v) return;
    _allowLinkedinEmbeds = v;
    await _prefs.setBool(_keyShieldLiEmbeds, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setOpenExternalLinksInHeaven(bool v) async {
    if (_openExternalLinksInHeaven == v) return;
    _openExternalLinksInHeaven = v;
    await _prefs.setBool(_keyOpenExtInHeaven, v);
    notifyListeners();
  }

  Future<void> setSafeBrowsingMode(HeavenSafeBrowsingMode mode) async {
    if (_safeBrowsingMode == mode) return;
    _safeBrowsingMode = mode;
    await _prefs.setString(_keySafeBrowsing, mode.name);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setAllowExternalAppLinks(bool v) async {
    if (_allowExternalAppLinks == v) return;
    _allowExternalAppLinks = v;
    await _prefs.setBool(_keyAllowAppLinks, v);
    notifyListeners();
  }

  Future<void> setWebrtcPolicy(HeavenWebrtcPolicy policy) async {
    if (_webrtcPolicy == policy) return;
    _webrtcPolicy = policy;
    await _prefs.setString(_keyWebrtcPolicy, policy.name);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setAllowPrivateScreenshots(bool v) async {
    if (_allowPrivateScreenshots == v) return;
    _allowPrivateScreenshots = v;
    await _prefs.setBool(_keyPrivScreenshots, v);
    notifyListeners();
  }

  Future<void> setAllowPaymentMethodQuery(bool v) async {
    if (_allowPaymentMethodQuery == v) return;
    _allowPaymentMethodQuery = v;
    await _prefs.setBool(_keyPaymentQuery, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setResolveUnstoppableDomains(bool v) async {
    if (_resolveUnstoppableDomains == v) return;
    _resolveUnstoppableDomains = v;
    await _prefs.setBool(_keyUnstoppable, v);
    notifyListeners();
  }

  Future<void> setResolveEnsDomains(bool v) async {
    if (_resolveEnsDomains == v) return;
    _resolveEnsDomains = v;
    await _prefs.setBool(_keyEns, v);
    notifyListeners();
  }

  Future<void> setResolveSnsDomains(bool v) async {
    if (_resolveSnsDomains == v) return;
    _resolveSnsDomains = v;
    await _prefs.setBool(_keySns, v);
    notifyListeners();
  }

  Future<void> setSecureDnsMode(HeavenSecureDnsMode mode) async {
    if (_secureDnsMode == mode) return;
    _secureDnsMode = mode;
    await _prefs.setString(_keySecureDns, mode.name);
    notifyListeners();
  }

  Future<void> setJsOptimisationMode(HeavenJsOptimisationMode mode) async {
    if (_jsOptimisationMode == mode) return;
    _jsOptimisationMode = mode;
    await _prefs.setString(_keyJsOpt, mode.name);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setBlockSwitchToAppNotices(bool v) async {
    if (_blockSwitchToAppNotices == v) return;
    _blockSwitchToAppNotices = v;
    await _prefs.setBool(_keyBlockSwitchApp, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setCloseTabsOnExit(bool v) async {
    if (_closeTabsOnExit == v) return;
    _closeTabsOnExit = v;
    await _prefs.setBool(_keyCloseTabsExit, v);
    notifyListeners();
  }

  Future<void> setFilterFanboyAnnoyances(bool v) async {
    if (_filterFanboyAnnoyances == v) return;
    _filterFanboyAnnoyances = v;
    await _prefs.setBool(_keyFilterFanboy, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setFilterMobileNotifs(bool v) async {
    if (_filterMobileNotifs == v) return;
    _filterMobileNotifs = v;
    await _prefs.setBool(_keyFilterMobNotifs, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setFilterAntiAdblock(bool v) async {
    if (_filterAntiAdblock == v) return;
    _filterAntiAdblock = v;
    await _prefs.setBool(_keyFilterAntiAb, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setFilterRegionalIndia(bool v) async {
    if (_filterRegionalIndia == v) return;
    _filterRegionalIndia = v;
    await _prefs.setBool(_keyFilterRegIndia, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setFilterRegionalGlobal(bool v) async {
    if (_filterRegionalGlobal == v) return;
    _filterRegionalGlobal = v;
    await _prefs.setBool(_keyFilterRegGlobal, v);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setCustomFilterRulesFromText(String rawText) async {
    final List<String> lines = rawText
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toSet()
        .toList();
    _customFilterRules = lines;
    await _prefs.setStringList(_keyCustomFilterRules, _customFilterRules);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> addCustomElementBlockRule(String host, String selector) async {
    final String cleanHost = OmniboxParser.cleanDomain(host);
    final String cleanSel = selector.trim();
    if (cleanSel.isEmpty) return;
    final String rule = cleanHost.isEmpty
        ? '##$cleanSel'
        : '$cleanHost##$cleanSel';
    if (!_customFilterRules.contains(rule)) {
      _customFilterRules = <String>[..._customFilterRules, rule];
      await _prefs.setStringList(_keyCustomFilterRules, _customFilterRules);
      _webViewConfigRevision += 1;
      _pushNativeBrowserConfig();
      notifyListeners();
    }
  }

  Future<void> clearHistoryOnly() async {
    _history = <HistoryItem>[];
    _siteUsageByDomain.clear();
    await _prefs.remove(_keyHistory);
    await _prefs.remove(_keySiteUsage);
    notifyListeners();
  }

  Future<void> resetHeavenShieldDefaults() async {
    _shieldEnabled = true;
    _shieldMode = HeavenShieldMode.standard;
    _shieldBlockAds = true;
    _shieldBlockCookieBanners = true;
    _shieldCleanUrls = true;
    _shieldAntiFingerprinting = true;
    _shieldBlockPopups = true;
    _httpsUpgradeMode = HeavenHttpsUpgradeMode.standard;
    _httpsUpgrade = true;
    _cookiePolicy = HeavenCookiePolicy.blockThirdParty;
    _blockThirdPartyCookies = true;
    _sendDntAndGpc = false;
    _javascriptEnabled = true;
    _shieldAutoRedirectAmp = true;
    _shieldPreventLangFp = true;
    _storeBrokenSiteContact = true;
    _autoShredMode = HeavenAutoShredMode.never;
    _allowElementBlockInPrivate = false;
    _allowFacebookEmbeds = true;
    _allowTwitterEmbeds = true;
    _allowLinkedinEmbeds = false;
    _openExternalLinksInHeaven = true;
    _safeBrowsingMode = HeavenSafeBrowsingMode.standard;
    _allowExternalAppLinks = true;
    _webrtcPolicy = HeavenWebrtcPolicy.defaultPolicy;
    _allowPrivateScreenshots = false;
    _allowPaymentMethodQuery = true;
    _resolveUnstoppableDomains = true;
    _resolveEnsDomains = true;
    _resolveSnsDomains = true;
    _secureDnsMode = HeavenSecureDnsMode.automatic;
    _jsOptimisationMode = HeavenJsOptimisationMode.standard;
    _blockSwitchToAppNotices = true;
    _closeTabsOnExit = false;
    _filterFanboyAnnoyances = true;
    _filterMobileNotifs = true;
    _filterAntiAdblock = true;
    _filterRegionalIndia = false;
    _filterRegionalGlobal = false;
    _customFilterRules = <String>[];
    _shieldDisabledHosts.clear();

    await _prefs.setBool(_keyShieldEnabled, true);
    await _prefs.setString(_keyShieldMode, HeavenShieldMode.standard.name);
    await _prefs.setBool(_keyShieldBlockAds, true);
    await _prefs.setBool(_keyShieldCookieBanners, true);
    await _prefs.setBool(_keyShieldCleanUrls, true);
    await _prefs.setBool(_keyShieldAntiFp, true);
    await _prefs.setBool(_keyShieldBlockPopups, true);
    await _prefs.setString(
      _keyShieldHttpsMode,
      HeavenHttpsUpgradeMode.standard.name,
    );
    await _prefs.setBool(_keyHttpsUpgrade, true);
    await _prefs.setString(
      _keyShieldCookiePolicy,
      HeavenCookiePolicy.blockThirdParty.name,
    );
    await _prefs.setBool(_keyBlockThirdPartyCookies, true);
    await _prefs.setBool(_keySendDntGpc, false);
    await _prefs.setBool(_keyJavascriptEnabled, true);
    await _prefs.setBool(_keyShieldAutoAmp, true);
    await _prefs.setBool(_keyShieldLangFp, true);
    await _prefs.setBool(_keyShieldStoreContact, true);
    await _prefs.setString(_keyShieldAutoShred, HeavenAutoShredMode.never.name);
    await _prefs.setBool(_keyShieldPrivElemBlock, false);
    await _prefs.setBool(_keyShieldFbEmbeds, true);
    await _prefs.setBool(_keyShieldTwEmbeds, true);
    await _prefs.setBool(_keyShieldLiEmbeds, false);
    await _prefs.setBool(_keyOpenExtInHeaven, true);
    await _prefs.setString(
      _keySafeBrowsing,
      HeavenSafeBrowsingMode.standard.name,
    );
    await _prefs.setBool(_keyAllowAppLinks, true);
    await _prefs.setString(
      _keyWebrtcPolicy,
      HeavenWebrtcPolicy.defaultPolicy.name,
    );
    await _prefs.setBool(_keyPrivScreenshots, false);
    await _prefs.setBool(_keyPaymentQuery, true);
    await _prefs.setBool(_keyUnstoppable, true);
    await _prefs.setBool(_keyEns, true);
    await _prefs.setBool(_keySns, true);
    await _prefs.setString(
      _keySecureDns,
      HeavenSecureDnsMode.automatic.name,
    );
    await _prefs.setString(
      _keyJsOpt,
      HeavenJsOptimisationMode.standard.name,
    );
    await _prefs.setBool(_keyBlockSwitchApp, true);
    await _prefs.setBool(_keyCloseTabsExit, false);
    await _prefs.setBool(_keyFilterFanboy, true);
    await _prefs.setBool(_keyFilterMobNotifs, true);
    await _prefs.setBool(_keyFilterAntiAb, true);
    await _prefs.setBool(_keyFilterRegIndia, false);
    await _prefs.setBool(_keyFilterRegGlobal, false);
    await _prefs.setStringList(_keyCustomFilterRules, const <String>[]);
    await _prefs.setStringList(_keyShieldDisabledHosts, const <String>[]);

    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> addShieldDisabledHost(String rawHost) =>
      addShieldExceptionHost(rawHost);

  Future<void> removeShieldDisabledHost(String rawHost) =>
      removeShieldExceptionHost(rawHost);

  Future<void> setTranslateTargetLang(String langCode) async {
    final String clean = langCode.trim();
    if (clean.isEmpty || _translateTargetLang == clean) return;
    _translateTargetLang = clean;
    await _prefs.setString(_keyTranslateTargetLang, clean);
    notifyListeners();
  }

  Future<void> setReaderFontSize(double size) async {
    final double clamped = size.clamp(14.0, 26.0);
    if ((_readerFontSize - clamped).abs() < 0.05) return;
    _readerFontSize = clamped;
    await _prefs.setDouble(_keyReaderFontSize, clamped);
    notifyListeners();
  }

  Future<void> setReaderTheme(String theme) async {
    if (_readerTheme == theme) return;
    _readerTheme = theme;
    await _prefs.setString(_keyReaderTheme, theme);
    notifyListeners();
  }

  SitePermissionDecision getSitePermission(
    String? host,
    SitePermissionType type,
  ) {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) {
      return switch (type) {
        SitePermissionType.javascript =>
          _javascriptEnabled
              ? SitePermissionDecision.allow
              : SitePermissionDecision.block,
        SitePermissionType.popups => SitePermissionDecision.block,
        SitePermissionType.protectedMedia => SitePermissionDecision.allow,
        SitePermissionType.notifications =>
          _webNotificationsEnabled
              ? SitePermissionDecision.ask
              : SitePermissionDecision.block,
        _ => SitePermissionDecision.ask,
      };
    }
    if (type == SitePermissionType.javascript) {
      return isJavaScriptAllowedForHost(clean)
          ? SitePermissionDecision.allow
          : SitePermissionDecision.block;
    }
    if (type == SitePermissionType.popups) {
      return arePopupsBlockedForHost(clean)
          ? SitePermissionDecision.block
          : SitePermissionDecision.allow;
    }
    final SitePermissionDecision? explicit = _sitePermissions[clean]?[type];
    if (explicit != null) {
      return explicit;
    }
    if (type == SitePermissionType.protectedMedia) {
      return SitePermissionDecision.allow;
    }
    if (type == SitePermissionType.notifications && !_webNotificationsEnabled) {
      return SitePermissionDecision.block;
    }
    return SitePermissionDecision.ask;
  }

  Future<void> setSitePermission(
    String host,
    SitePermissionType type,
    SitePermissionDecision decision,
  ) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    if (type == SitePermissionType.javascript) {
      if (decision == SitePermissionDecision.block) {
        _jsDisabledHosts.add(clean);
      } else {
        _jsDisabledHosts.remove(clean);
      }
      await _prefs.setStringList(
        _keyJsDisabledHosts,
        _jsDisabledHosts.toList(),
      );
      _webViewConfigRevision += 1;
      notifyListeners();
      return;
    }
    if (type == SitePermissionType.popups) {
      if (decision == SitePermissionDecision.allow) {
        _popupAllowedHosts.add(clean);
      } else {
        _popupAllowedHosts.remove(clean);
      }
      await _prefs.setStringList(
        _keyPopupAllowedHosts,
        _popupAllowedHosts.toList(),
      );
      notifyListeners();
      return;
    }
    final Map<SitePermissionType, SitePermissionDecision> map =
        _sitePermissions.putIfAbsent(
          clean,
          () => <SitePermissionType, SitePermissionDecision>{},
        );
    if (decision == SitePermissionDecision.ask) {
      map.remove(type);
      if (map.isEmpty) {
        _sitePermissions.remove(clean);
      }
    } else {
      map[type] = decision;
    }
    await _persistSitePermissions();
    notifyListeners();
  }

  Future<void> revokeSitePermission(
    String host,
    SitePermissionType type,
  ) async {
    await setSitePermission(host, type, SitePermissionDecision.block);
  }

  Future<void> revokeAllPermissionsForSite(String host) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    _sitePermissions[clean] = <SitePermissionType, SitePermissionDecision>{
      SitePermissionType.location: SitePermissionDecision.block,
      SitePermissionType.camera: SitePermissionDecision.block,
      SitePermissionType.microphone: SitePermissionDecision.block,
      SitePermissionType.notifications: SitePermissionDecision.block,
      SitePermissionType.protectedMedia: SitePermissionDecision.block,
    };
    _popupAllowedHosts.remove(clean);
    await _prefs.setStringList(
      _keyPopupAllowedHosts,
      _popupAllowedHosts.toList(),
    );
    await _persistSitePermissions();
    notifyListeners();
  }

  Future<void> _persistSitePermissions() async {
    final Map<String, Map<String, String>> out =
        <String, Map<String, String>>{};
    for (final MapEntry<String, Map<SitePermissionType, SitePermissionDecision>>
        e
        in _sitePermissions.entries) {
      out[e.key] = <String, String>{
        for (final MapEntry<SitePermissionType, SitePermissionDecision> p
            in e.value.entries)
          p.key.name: p.value.name,
      };
    }
    await _prefs.setString(_keySitePermissions, jsonEncode(out));
  }

  Future<void> recordPageVisit({
    required String url,
    required String title,
  }) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final String cleanDomain = OmniboxParser.cleanDomain(uri.host);
    final String cleanTitle = title.trim().isNotEmpty
        ? title.trim()
        : OmniboxParser.friendlySiteTitleFromDomain(cleanDomain);

    if (cleanDomain.isNotEmpty && !_hiddenQuickDomains.contains(cleanDomain)) {
      final SiteUsageEntry? existing = _siteUsageByDomain[cleanDomain];
      final String canonicalOrigin = '${uri.scheme}://${uri.host}';
      final String shortLabel = existing != null && existing.isPinned
          ? existing.title
          : OmniboxParser.friendlySiteTitleFromDomain(cleanDomain);

      _siteUsageByDomain[cleanDomain] = SiteUsageEntry(
        domain: cleanDomain,
        url: existing != null && existing.isPinned
            ? existing.url
            : canonicalOrigin,
        title: shortLabel,
        visitCount: (existing?.visitCount ?? 0) + 1,
        lastVisitedMs: now,
        isPinned: existing?.isPinned ?? false,
      );
      await _persistSiteUsage();
    }

    if (_history.isEmpty || _history.first.url != url) {
      _history = <HistoryItem>[
        HistoryItem(title: cleanTitle, url: url, visitedAtMs: now),
        ..._history.where((HistoryItem h) => h.url != url).take(249),
      ];
      await _persistHistory();
    }

    notifyListeners();
  }

  Future<void> pinOrAddQuickLaunchSite({
    required String title,
    required String rawUrl,
  }) async {
    final Uri resolved = OmniboxParser.resolveInput(
      rawUrl,
      searchEngine: _searchEngine,
      httpsUpgrade: _httpsUpgrade,
    );
    final String domain = OmniboxParser.cleanDomain(resolved.toString());
    if (domain.isEmpty) {
      return;
    }
    _hiddenQuickDomains.remove(domain);
    await _prefs.setStringList(_keyHiddenDomains, _hiddenQuickDomains.toList());

    final SiteUsageEntry? existing = _siteUsageByDomain[domain];
    _siteUsageByDomain[domain] = SiteUsageEntry(
      domain: domain,
      url: resolved.toString(),
      title: title.trim().isEmpty
          ? OmniboxParser.friendlySiteTitleFromDomain(domain)
          : title.trim(),
      visitCount: (existing?.visitCount ?? 0) + 1,
      lastVisitedMs: DateTime.now().millisecondsSinceEpoch,
      isPinned: true,
    );
    await _persistSiteUsage();
    notifyListeners();
  }

  Future<void> togglePinQuickSite(String domain) async {
    final String clean = OmniboxParser.cleanDomain(domain);
    final SiteUsageEntry? existing = _siteUsageByDomain[clean];
    if (existing != null) {
      _siteUsageByDomain[clean] = existing.copyWith(
        isPinned: !existing.isPinned,
      );
      await _persistSiteUsage();
      notifyListeners();
    }
  }

  Future<void> removeQuickLaunchSite(String domain) async {
    final String clean = OmniboxParser.cleanDomain(domain);
    _siteUsageByDomain.remove(clean);
    _hiddenQuickDomains.add(clean);
    await _prefs.setStringList(_keyHiddenDomains, _hiddenQuickDomains.toList());
    await _persistSiteUsage();
    notifyListeners();
  }

  Future<void> restoreDefaultQuickLaunch() async {
    _hiddenQuickDomains.clear();
    await _prefs.remove(_keyHiddenDomains);
    notifyListeners();
  }

  bool isBookmarked(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    return _bookmarks.any((BookmarkItem b) => b.url == url);
  }

  Future<bool> toggleBookmark({
    required String url,
    required String title,
  }) async {
    if (url.isEmpty) {
      return false;
    }
    final int idx = _bookmarks.indexWhere((BookmarkItem b) => b.url == url);
    bool added;
    if (idx >= 0) {
      _bookmarks = List<BookmarkItem>.of(_bookmarks)..removeAt(idx);
      added = false;
    } else {
      final String cleanTitle = title.trim().isNotEmpty
          ? title.trim()
          : OmniboxParser.formatDisplayUrl(url);
      _bookmarks = <BookmarkItem>[
        BookmarkItem(
          title: cleanTitle,
          url: url,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        ..._bookmarks,
      ];
      added = true;
    }
    await _persistBookmarks();
    notifyListeners();
    return added;
  }

  Future<void> removeBookmark(String url) async {
    _bookmarks = _bookmarks.where((BookmarkItem b) => b.url != url).toList();
    await _persistBookmarks();
    notifyListeners();
  }

  Future<void> deleteHistoryItem(HistoryItem target) async {
    _history = _history
        .where(
          (HistoryItem h) =>
              !(h.url == target.url && h.visitedAtMs == target.visitedAtMs),
        )
        .toList();
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = <HistoryItem>[];
    await _prefs.remove(_keyHistory);
    notifyListeners();
  }

  Future<void> clearUsageAndHistory() async {
    _history = <HistoryItem>[];
    _siteUsageByDomain.removeWhere((_, SiteUsageEntry v) => !v.isPinned);
    await _prefs.remove(_keyHistory);
    await _persistSiteUsage();
    notifyListeners();
  }

  Future<void> _persistSiteUsage() async {
    final String encoded = jsonEncode(
      _siteUsageByDomain.values.map((SiteUsageEntry e) => e.toJson()).toList(),
    );
    await _prefs.setString(_keySiteUsage, encoded);
  }

  Future<void> _persistBookmarks() async {
    final String encoded = jsonEncode(
      _bookmarks.map((BookmarkItem b) => b.toJson()).toList(),
    );
    await _prefs.setString(_keyBookmarks, encoded);
  }

  Future<void> _persistHistory() async {
    final String encoded = jsonEncode(
      _history.map((HistoryItem h) => h.toJson()).toList(),
    );
    await _prefs.setString(_keyHistory, encoded);
  }

  Future<void> setSearchEngine(SearchEngine engine) async {
    _searchEngine = engine;
    await _prefs.setString(_keySearchEngine, engine.name);
    unawaited(NativeShieldBridge.instance.refreshSearchWidgets());
    notifyListeners();
  }

  static const String _keyPromptedDefaultBrowser =
      'heaven_prompted_default_browser_v1';

  bool get hasPromptedDefaultBrowser =>
      _prefs.getBool(_keyPromptedDefaultBrowser) ?? false;

  Future<void> markPromptedDefaultBrowser() async {
    await _prefs.setBool(_keyPromptedDefaultBrowser, true);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final String raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await _prefs.setString(_keyThemeMode, raw);
    notifyListeners();
  }

  Future<void> setBackgroundMediaEnabled(bool value) async {
    _backgroundMediaEnabled = value;
    await _prefs.setBool(_keyBgMedia, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setBiometricLockIncognito(bool value) async {
    _biometricLockIncognito = value;
    await _prefs.setBool(_keyBiometricIncognito, value);
    notifyListeners();
  }

  Future<void> setBiometricLockApp(bool value) async {
    _biometricLockApp = value;
    await _prefs.setBool(_keyBiometricApp, value);
    notifyListeners();
  }

  Future<void> setHttpsUpgrade(bool value) async {
    _httpsUpgrade = value;
    await _prefs.setBool(_keyHttpsUpgrade, value);
    notifyListeners();
  }

  Future<void> setBlockThirdPartyCookies(bool value) async {
    _blockThirdPartyCookies = value;
    _webViewConfigRevision += 1;
    await _prefs.setBool(_keyBlockThirdPartyCookies, value);
    notifyListeners();
  }

  Future<void> setSendDntAndGpc(bool value) async {
    _sendDntAndGpc = value;
    await _prefs.setBool(_keySendDntGpc, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setClearOnExit(bool value) async {
    _clearOnExit = value;
    await _prefs.setBool(_keyClearOnExit, value);
    notifyListeners();
  }

  Future<void> setJavascriptEnabled(bool value) async {
    _javascriptEnabled = value;
    _webViewConfigRevision += 1;
    await _prefs.setBool(_keyJavascriptEnabled, value);
    notifyListeners();
  }

  Future<void> setDesktopMode(bool value) async {
    _desktopMode = value;
    _webViewConfigRevision += 1;
    await _prefs.setBool(_keyDesktopMode, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setTextScalePercent(int value) async {
    _textScalePercent = value.clamp(75, 175);
    _webViewConfigRevision += 1;
    await _prefs.setInt(_keyTextScalePercent, _textScalePercent);
    notifyListeners();
  }

  Future<void> setLanguage(BrowserLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    await _prefs.setString(_keyLanguage, lang.name);
    notifyListeners();
  }

  Future<void> setDownloadNotificationsEnabled(bool value) async {
    _downloadNotificationsEnabled = value;
    await _prefs.setBool(_keyDownloadNotifs, value);
    unawaited(NativeShieldBridge.instance.setDownloadNotificationsEnabled(value));
    notifyListeners();
  }

  Future<void> setBackgroundPlayNotificationEnabled(bool value) async {
    _backgroundPlayNotificationEnabled = value;
    await _prefs.setBool(_keyBgPlayNotifs, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setWebNotificationsEnabled(bool value) async {
    _webNotificationsEnabled = value;
    await _prefs.setBool(_keyWebNotifs, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  List<String> matchingRecentSearches(String prefix, {int limit = 8}) {
    final String q = prefix.trim().toLowerCase();
    if (q.isEmpty) {
      return List<String>.unmodifiable(_recentSearches.take(limit));
    }
    return _recentSearches
        .where((String s) => s.toLowerCase().contains(q))
        .take(limit)
        .toList(growable: false);
  }

  Future<void> recordRecentSearch(String rawQuery) async {
    final String clean = rawQuery.trim();
    if (clean.isEmpty ||
        clean.startsWith('http://') ||
        clean.startsWith('https://')) {
      return;
    }
    _recentSearches = <String>[
      clean,
      ..._recentSearches.where(
        (String s) => s.toLowerCase() != clean.toLowerCase(),
      ),
    ].take(15).toList();
    await _prefs.setStringList(_keyRecentSearches, _recentSearches);
    notifyListeners();
  }

  Future<void> removeRecentSearch(String query) async {
    _recentSearches = _recentSearches
        .where((String s) => s != query)
        .toList();
    await _prefs.setStringList(_keyRecentSearches, _recentSearches);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = <String>[];
    await _prefs.remove(_keyRecentSearches);
    notifyListeners();
  }

  bool isJavaScriptAllowedForHost(String? host) {
    if (!_javascriptEnabled) return false;
    if (host == null || host.isEmpty) return true;
    return !_jsDisabledHosts.contains(OmniboxParser.cleanDomain(host));
  }

  Future<void> toggleSiteJavaScript(String host) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    if (!_jsDisabledHosts.remove(clean)) {
      _jsDisabledHosts.add(clean);
    }
    _webViewConfigRevision += 1;
    await _prefs.setStringList(_keyJsDisabledHosts, _jsDisabledHosts.toList());
    notifyListeners();
  }

  bool arePopupsBlockedForHost(String? host) {
    if (host == null || host.isEmpty) return true;
    return !_popupAllowedHosts.contains(OmniboxParser.cleanDomain(host));
  }

  Future<void> toggleSitePopups(String host) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    if (!_popupAllowedHosts.remove(clean)) {
      _popupAllowedHosts.add(clean);
    }
    await _prefs.setStringList(
      _keyPopupAllowedHosts,
      _popupAllowedHosts.toList(),
    );
    notifyListeners();
  }
}
