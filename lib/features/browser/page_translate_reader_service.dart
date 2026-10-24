import 'dart:convert';

import 'package:http/http.dart' as http;

class TranslateLanguage {
  const TranslateLanguage({
    required this.code,
    required this.name,
    required this.nativeLabel,
  });

  final String code;
  final String name;
  final String nativeLabel;
}

class ReaderArticleData {
  const ReaderArticleData({
    required this.title,
    required this.siteName,
    required this.paragraphs,
  });

  final String title;
  final String siteName;
  final List<String> paragraphs;

  int get estimatedReadMinutes {
    final int words = paragraphs
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .length;
    return (words / 210).ceil().clamp(1, 90);
  }
}

class PageTranslateReaderService {
  const PageTranslateReaderService._();

  static const String _batchDelimiter = '\n⟦HB_SEG⟧\n';

  static const List<TranslateLanguage> supportedLanguages = <TranslateLanguage>[
    TranslateLanguage(code: 'en', name: 'English', nativeLabel: 'English'),
    TranslateLanguage(code: 'hi', name: 'Hindi', nativeLabel: 'हिन्दी'),
    TranslateLanguage(code: 'es', name: 'Spanish', nativeLabel: 'Español'),
    TranslateLanguage(code: 'fr', name: 'French', nativeLabel: 'Français'),
    TranslateLanguage(code: 'de', name: 'German', nativeLabel: 'Deutsch'),
    TranslateLanguage(code: 'ja', name: 'Japanese', nativeLabel: '日本語'),
    TranslateLanguage(code: 'ko', name: 'Korean', nativeLabel: '한국어'),
    TranslateLanguage(code: 'ar', name: 'Arabic', nativeLabel: 'العربية'),
    TranslateLanguage(code: 'pt', name: 'Portuguese', nativeLabel: 'Português'),
    TranslateLanguage(code: 'ru', name: 'Russian', nativeLabel: 'Русский'),
    TranslateLanguage(code: 'zh-CN', name: 'Chinese', nativeLabel: '简体中文'),
    TranslateLanguage(code: 'bn', name: 'Bengali', nativeLabel: 'বাংলা'),
    TranslateLanguage(code: 'ta', name: 'Tamil', nativeLabel: 'தமிழ்'),
    TranslateLanguage(code: 'te', name: 'Telugu', nativeLabel: 'తెలుగు'),
    TranslateLanguage(code: 'mr', name: 'Marathi', nativeLabel: 'मराठी'),
    TranslateLanguage(code: 'ur', name: 'Urdu', nativeLabel: 'اردو'),
    TranslateLanguage(code: 'it', name: 'Italian', nativeLabel: 'Italiano'),
    TranslateLanguage(code: 'tr', name: 'Turkish', nativeLabel: 'Türkçe'),
    TranslateLanguage(code: 'id', name: 'Indonesian', nativeLabel: 'Indonesia'),
    TranslateLanguage(
      code: 'vi',
      name: 'Vietnamese',
      nativeLabel: 'Tiếng Việt',
    ),
  ];

  static TranslateLanguage languageByCode(String code) {
    for (final TranslateLanguage lang in supportedLanguages) {
      if (lang.code.toLowerCase() == code.toLowerCase()) {
        return lang;
      }
    }
    return supportedLanguages.first;
  }

  /// Translates a list of DOM text segments via Google's public GTX endpoint
  /// from Dart so strict website Content-Security-Policy headers never block it.
  static Future<List<String>> translateSegments(
    List<String> segments, {
    required String targetLang,
    http.Client? client,
  }) async {
    if (segments.isEmpty) return const <String>[];
    final http.Client activeClient = client ?? http.Client();
    final bool ownsClient = client == null;
    try {
      final List<String> results = List<String>.from(segments);
      int idx = 0;
      while (idx < segments.length) {
        final List<int> batchIndices = <int>[];
        final List<String> batchTexts = <String>[];
        int charBudget = 0;
        while (idx < segments.length && batchTexts.length < 28) {
          final String seg = segments[idx].trim();
          if (seg.isEmpty) {
            idx++;
            continue;
          }
          if (batchTexts.isNotEmpty && charBudget + seg.length > 1800) {
            break;
          }
          batchIndices.add(idx);
          batchTexts.add(seg);
          charBudget += seg.length + _batchDelimiter.length;
          idx++;
        }
        if (batchTexts.isEmpty) continue;

        final String joined = batchTexts.join(_batchDelimiter);
        final String? translatedJoined = await _fetchSingleTranslation(
          joined,
          targetLang: targetLang,
          client: activeClient,
        );
        if (translatedJoined != null && translatedJoined.isNotEmpty) {
          final List<String> parts = translatedJoined.split(
            RegExp(r'\s*⟦HB_SEG⟧\s*'),
          );
          if (parts.length == batchIndices.length) {
            for (int k = 0; k < batchIndices.length; k++) {
              final String candidate = parts[k].trim();
              if (candidate.isNotEmpty) {
                results[batchIndices[k]] = candidate;
              }
            }
          } else if (batchIndices.length == 1) {
            results[batchIndices.first] = translatedJoined.trim();
          }
        }
      }
      return results;
    } finally {
      if (ownsClient) {
        activeClient.close();
      }
    }
  }

  static Future<String?> _fetchSingleTranslation(
    String text, {
    required String targetLang,
    required http.Client client,
  }) async {
    try {
      final Uri uri = Uri.https(
        'translate.googleapis.com',
        '/translate_a/single',
        <String, String>{
          'client': 'gtx',
          'sl': 'auto',
          'tl': targetLang,
          'dt': 't',
          'q': text,
        },
      );
      final http.Response res = await client
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'User-Agent': 'Mozilla/5.0 HeavenBrowser/0.0.1',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
        return null;
      }
      final StringBuffer out = StringBuffer();
      for (final Object? sentence in decoded.first as List<Object?>) {
        if (sentence is List && sentence.isNotEmpty && sentence.first != null) {
          out.write(sentence.first.toString());
        }
      }
      final String built = out.toString();
      return built.isEmpty ? null : built;
    } catch (_) {
      return null;
    }
  }
}
