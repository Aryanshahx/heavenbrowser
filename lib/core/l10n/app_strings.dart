enum BrowserLanguage {
  en('en-US', 'English', 'English'),
  hi('hi-IN', 'Hindi', 'हिन्दी'),
  bn('bn-IN', 'Bengali', 'বাংলা'),
  ta('ta-IN', 'Tamil', 'தமிழ்'),
  te('te-IN', 'Telugu', 'తెలుగు'),
  mr('mr-IN', 'Marathi', 'मराठी'),
  gu('gu-IN', 'Gujarati', 'ગુજરાતી'),
  es('es-ES', 'Spanish', 'Español'),
  fr('fr-FR', 'French', 'Français'),
  de('de-DE', 'German', 'Deutsch'),
  ja('ja-JP', 'Japanese', '日本語'),
  ar('ar-SA', 'Arabic', 'العربية');

  const BrowserLanguage(this.localeTag, this.englishName, this.nativeName);

  final String localeTag;
  final String englishName;
  final String nativeName;

  String get code => name;
  String get bcp47 => localeTag;
  String get nativeLabel => nativeName;
  String get englishLabel => englishName;

  String get acceptLanguageHeader {
    final String short = localeTag.split('-').first;
    if (short == 'en') {
      return 'en-US,en;q=0.9';
    }
    return '$localeTag,$short;q=0.9,en-US;q=0.7,en;q=0.6';
  }

  static BrowserLanguage fromCode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return BrowserLanguage.en;
    }
    for (final BrowserLanguage lang in BrowserLanguage.values) {
      if (lang.name == raw || lang.localeTag == raw) {
        return lang;
      }
    }
    return BrowserLanguage.en;
  }
}

class AppStrings {
  const AppStrings._();

  static String searchHint(BrowserLanguage lang) => switch (lang) {
    BrowserLanguage.hi => 'खोजें या वेबसाइट पता लिखें',
    BrowserLanguage.bn => 'অনুসন্ধান করুন বা ওয়েব ঠিকানা লিখুন',
    BrowserLanguage.ta => 'தேடுங்கள் அல்லது இணைய முகவரியை உள்ளிடவும்',
    BrowserLanguage.te => 'వెతకండి లేదా వెబ్ చిరునామా టైప్ చేయండి',
    BrowserLanguage.mr => 'शोधा किंवा वेबसाइट पत्ता टाइप करा',
    BrowserLanguage.gu => 'શોધો અથવા વેબ સરનામું લખો',
    BrowserLanguage.es => 'Buscar o escribir dirección web',
    BrowserLanguage.fr => 'Rechercher ou saisir une adresse web',
    BrowserLanguage.de => 'Suchen oder Webadresse eingeben',
    BrowserLanguage.ja => '検索またはURLを入力',
    BrowserLanguage.ar => 'ابحث أو اكتب عنوان الويب',
    BrowserLanguage.en => 'Search or type web address',
  };

  static String discoverTitle(BrowserLanguage lang) => switch (lang) {
    BrowserLanguage.hi => 'डिस्कवर',
    BrowserLanguage.bn => 'ডিসকভার',
    BrowserLanguage.ta => 'டிஸ்கவர்',
    BrowserLanguage.te => 'డిస్కవర్',
    BrowserLanguage.mr => 'डिस्कव्हर',
    BrowserLanguage.gu => 'ડિસ્કવર',
    BrowserLanguage.es => 'Descubrir',
    BrowserLanguage.fr => 'Découvrir',
    BrowserLanguage.de => 'Entdecken',
    BrowserLanguage.ja => 'ディスカバー',
    BrowserLanguage.ar => 'اكتشف',
    BrowserLanguage.en => 'Discover',
  };

  static String recentSearchesTitle(BrowserLanguage lang) => switch (lang) {
    BrowserLanguage.hi => 'हाल की खोजें',
    BrowserLanguage.bn => 'সাম্প্রতিক অনুসন্ধান',
    BrowserLanguage.ta => 'சமீபத்திய தேடல்கள்',
    BrowserLanguage.te => 'ఇటీవలి శోధనలు',
    BrowserLanguage.mr => 'अलीकडील शोध',
    BrowserLanguage.gu => 'તાજેતરની શોધો',
    BrowserLanguage.es => 'Búsquedas recientes',
    BrowserLanguage.fr => 'Recherches récentes',
    BrowserLanguage.de => 'Letzte Suchanfragen',
    BrowserLanguage.ja => '最近の検索',
    BrowserLanguage.ar => 'عمليات البحث الأخيرة',
    BrowserLanguage.en => 'Recent Searches',
  };
}
