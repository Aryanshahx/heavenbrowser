import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

/// Fast, lightweight search autocomplete service powered by Google Suggest
/// (with DuckDuckGo fallback) for Omnibox and StartPage live suggestions.
class HeavenSearchService {
  HeavenSearchService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<String>> fetchSuggestions(String rawQuery) async {
    final String query = rawQuery.trim();
    if (query.length < 2) {
      return const <String>[];
    }

    try {
      final Uri uri = Uri.https(
        'suggestqueries.google.com',
        '/complete/search',
        <String, String>{'client': 'firefox', 'q': query},
      );
      final http.Response res = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent': AppConstants.mobileUserAgent,
            },
          )
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is List<Object?> && decoded.length >= 2) {
          final Object? items = decoded[1];
          if (items is List<Object?>) {
            return items
                .map((Object? e) => e?.toString().trim() ?? '')
                .where((String s) => s.isNotEmpty)
                .take(7)
                .toList(growable: false);
          }
        }
      }
    } catch (_) {
      // Fallback to DuckDuckGo autocomplete below.
    }

    try {
      final Uri fallback = Uri.https('duckduckgo.com', '/ac/', <String, String>{
        'q': query,
        'type': 'list',
      });
      final http.Response res = await _client
          .get(fallback)
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is List<Object?> && decoded.length >= 2) {
          final Object? items = decoded[1];
          if (items is List<Object?>) {
            return items
                .map((Object? e) => e?.toString().trim() ?? '')
                .where((String s) => s.isNotEmpty)
                .take(7)
                .toList(growable: false);
          }
        }
      }
    } catch (_) {
      // Offline or blocked; return empty suggestions gracefully.
    }
    return const <String>[];
  }
}
