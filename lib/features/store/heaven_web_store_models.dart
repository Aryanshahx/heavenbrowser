import 'package:flutter/material.dart';

class HeavenStoreExtension {
  const HeavenStoreExtension({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.category,
    required this.version,
    required this.desktopOrigin,
    required this.icon,
    required this.accentColor,
  });

  final String id;
  final String name;
  final String tagline;
  final String description;
  final String category;
  final String version;
  final String desktopOrigin;
  final IconData icon;
  final Color accentColor;
}

class HeavenWebStoreCatalog {
  const HeavenWebStoreCatalog._();

  static const List<String> categories = <String>[
    'All',
    'Installed',
    'Privacy & Ads',
    'Video & Media',
    'Appearance',
    'Search & Reading',
    'Productivity',
  ];

  /// Default lightweight starter extensions pre-installed on first launch.
  static const List<String> defaultInstalledIds = <String>[
    'ublock_lite',
    'clear_urls',
  ];

  /// Heaven's curated & internally optimized Top 10 Chrome Desktop Extensions.
  /// Zero external CRX bloat; single-pass native execution across all search engines.
  static const List<HeavenStoreExtension> top10Extensions =
      <HeavenStoreExtension>[
        HeavenStoreExtension(
          id: 'ublock_lite',
          name: 'uBlock Origin Lite',
          tagline: 'Zero-CPU MV3 ad & tracker blocker',
          description:
              'Blocks intrusive ad networks and pop-under trackers on the native IO thread with cosmetic slot cleanup and zero scroll lag.',
          category: 'Privacy & Ads',
          version: '2026.10.1',
          desktopOrigin: 'Chrome MV3 Optimized Port',
          icon: Icons.gpp_good_rounded,
          accentColor: Color(0xFF10B981),
        ),
        HeavenStoreExtension(
          id: 'dark_reader',
          name: 'Dark Reader',
          tagline: 'Smart luminance-aware dark mode for every site',
          description:
              'Applies crisp dark theme styling to bright websites and search results while automatically skipping already-dark sites and preserving photos & videos.',
          category: 'Appearance',
          version: '4.9.98',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.dark_mode_rounded,
          accentColor: Color(0xFF3B82F6),
        ),
        HeavenStoreExtension(
          id: 'sponsorblock',
          name: 'SponsorBlock for YouTube',
          tagline: 'Automatically skips YouTube video sponsors',
          description:
              'Connects to the live SponsorBlock community database to jump seamlessly over sponsored segments and self-promotions in YouTube videos.',
          category: 'Video & Media',
          version: '5.10.2',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.fast_forward_rounded,
          accentColor: Color(0xFFEF4444),
        ),
        HeavenStoreExtension(
          id: 'return_yt_dislike',
          name: 'Return YouTube Dislike',
          tagline: 'Restores real dislike counts on YouTube',
          description:
              'Displays live community dislike statistics right inside YouTube video action bars on both mobile and desktop layouts.',
          category: 'Video & Media',
          version: '3.0.1',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.thumb_down_alt_rounded,
          accentColor: Color(0xFFF59E0B),
        ),
        HeavenStoreExtension(
          id: 'video_speed',
          name: 'Video Speed Controller',
          tagline: '0.25x–4.0x HTML5 playback speed & +10s skip pill',
          description:
              'Adds a sleek translucent speed controller overlay to HTML5 video players so you can speed up lectures, podcasts, and streams effortlessly.',
          category: 'Video & Media',
          version: '0.8.4',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.speed_rounded,
          accentColor: Color(0xFF8B5CF6),
        ),
        HeavenStoreExtension(
          id: 'clear_urls',
          name: 'ClearURLs',
          tagline: 'Strips tracking tokens across all search engines',
          description:
              'Automatically removes utm_*, fbclid, gclid, msclkid, and affiliate tracking parameters on Google, Perplexity, DuckDuckGo, Brave, Bing & Startpage.',
          category: 'Privacy & Ads',
          version: '1.27.0',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.link_off_rounded,
          accentColor: Color(0xFF06B6D4),
        ),
        HeavenStoreExtension(
          id: 'consent_o_matic',
          name: "I Don't Care About Cookies",
          tagline: 'Dismisses annoying GDPR & cookie consent walls',
          description:
              'Silently hides OneTrust, Cookiebot, Quantcast, and floating cookie banners while unlocking frozen page scrolling.',
          category: 'Productivity',
          version: '3.5.2',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.cookie_outlined,
          accentColor: Color(0xFFF97316),
        ),
        HeavenStoreExtension(
          id: 'google_dictionary',
          name: 'Quick Dictionary Lookup',
          tagline: 'Double-tap any word for instant definition',
          description:
              'Double-tap any English word on search results, news articles, or docs to view an instant floating definition and phonetic pronunciation.',
          category: 'Search & Reading',
          version: '4.2.5',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.menu_book_rounded,
          accentColor: Color(0xFF2563EB),
        ),
        HeavenStoreExtension(
          id: 'write_check',
          name: 'Grammarly Lite Polish',
          tagline: 'Live word counter & 1-tap typo auto-polish',
          description:
              'Shows a subtle floating word count badge inside text fields and fixes common English spelling slips in one tap without slowing down typing.',
          category: 'Productivity',
          version: '2.4.0',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.spellcheck_rounded,
          accentColor: Color(0xFF14B8A6),
        ),
        HeavenStoreExtension(
          id: 'allow_copy',
          name: 'SuperCopy: Enable Copy & Select',
          tagline: 'Unlocks text selection & copy on restricted sites',
          description:
              'Restores normal text selection, copy, and long-press actions on articles and portals that block copying.',
          category: 'Search & Reading',
          version: '1.9.1',
          desktopOrigin: 'Chrome Desktop Port',
          icon: Icons.content_copy_rounded,
          accentColor: Color(0xFF60A5FA),
        ),
      ];

  static final Set<String> validIds = <String>{
    for (final HeavenStoreExtension e in top10Extensions) e.id,
  };

  static HeavenStoreExtension? byId(String id) {
    for (final HeavenStoreExtension ext in top10Extensions) {
      if (ext.id == id) return ext;
    }
    return null;
  }
}
