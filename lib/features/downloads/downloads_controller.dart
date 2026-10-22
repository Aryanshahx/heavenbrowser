import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../shield/native_shield_bridge.dart';

class DownloadEntry {
  const DownloadEntry({
    required this.downloadId,
    required this.fileName,
    required this.url,
    required this.mimeType,
    required this.state,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.createdAtMs,
    this.localUri = '',
  });

  final int downloadId;
  final String fileName;
  final String url;
  final String mimeType;
  final String state; // running | paused | completed | failed
  final int bytesDownloaded;
  final int totalBytes;
  final int createdAtMs;
  final String localUri;

  bool get isRunning => state == 'running' || state == 'paused';
  bool get isCompleted => state == 'completed';

  double? get progress {
    if (totalBytes <= 0) {
      return null;
    }
    return (bytesDownloaded / totalBytes).clamp(0.0, 1.0);
  }

  DownloadEntry copyWith({
    String? state,
    int? bytesDownloaded,
    int? totalBytes,
    String? localUri,
    String? mimeType,
  }) {
    return DownloadEntry(
      downloadId: downloadId,
      fileName: fileName,
      url: url,
      mimeType: mimeType ?? this.mimeType,
      state: state ?? this.state,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      createdAtMs: createdAtMs,
      localUri: localUri ?? this.localUri,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'downloadId': downloadId,
    'fileName': fileName,
    'url': url,
    'mimeType': mimeType,
    'state': state,
    'bytesDownloaded': bytesDownloaded,
    'totalBytes': totalBytes,
    'createdAtMs': createdAtMs,
    'localUri': localUri,
  };

  factory DownloadEntry.fromJson(Map<String, Object?> json) {
    return DownloadEntry(
      downloadId: (json['downloadId'] is num)
          ? (json['downloadId']! as num).toInt()
          : 0,
      fileName: (json['fileName']?.toString() ?? 'file').trim(),
      url: (json['url']?.toString() ?? '').trim(),
      mimeType: (json['mimeType']?.toString() ?? '').trim(),
      state: (json['state']?.toString() ?? 'running').trim(),
      bytesDownloaded: (json['bytesDownloaded'] is num)
          ? (json['bytesDownloaded']! as num).toInt()
          : 0,
      totalBytes: (json['totalBytes'] is num)
          ? (json['totalBytes']! as num).toInt()
          : -1,
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs']! as num).toInt()
          : 0,
      localUri: (json['localUri']?.toString() ?? '').trim(),
    );
  }
}

class DownloadsController extends ChangeNotifier {
  DownloadsController(this._prefs, {this.enableNativePolling = true}) {
    _load();
    NativeShieldBridge.instance.onDownloadStarted = _onNativeDownloadStarted;
    if (enableNativePolling && hasActiveDownloads) {
      _ensurePolling();
    }
  }

  final SharedPreferences _prefs;
  final bool enableNativePolling;
  static const String _storageKey = 'hb.downloads.v4';

  List<DownloadEntry> _items = <DownloadEntry>[];
  Timer? _pollTimer;
  ValueChanged<String>? onDownloadToast;

  List<DownloadEntry> get items => List<DownloadEntry>.unmodifiable(_items);
  bool get hasActiveDownloads => _items.any((DownloadEntry e) => e.isRunning);
  int get activeCount => _items.where((DownloadEntry e) => e.isRunning).length;

  void _load() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        _items = decoded
            .whereType<Map<String, Object?>>()
            .map(DownloadEntry.fromJson)
            .where((DownloadEntry e) => e.url.isNotEmpty)
            .toList();
      }
    } on FormatException {
      _items = <DownloadEntry>[];
    }
  }

  Future<void> _persist() async {
    final String encoded = jsonEncode(
      _items.map((DownloadEntry e) => e.toJson()).toList(),
    );
    await _prefs.setString(_storageKey, encoded);
  }

  void _onNativeDownloadStarted(Map<String, Object?> info) {
    final DownloadEntry entry = _entryFromNativeMap(info);
    _insertEntry(entry);
    onDownloadToast?.call('Downloading ${entry.fileName}...');
  }

  DownloadEntry _entryFromNativeMap(Map<String, Object?> info) {
    final int id = (info['downloadId'] is num)
        ? (info['downloadId']! as num).toInt()
        : DateTime.now().millisecondsSinceEpoch;
    final String url = (info['url']?.toString() ?? '').trim();
    final String fileName = (info['fileName']?.toString() ?? 'download').trim();
    final String mime = (info['mimeType']?.toString() ?? '').trim();
    final int total = (info['totalBytes'] is num)
        ? (info['totalBytes']! as num).toInt()
        : -1;

    return DownloadEntry(
      downloadId: id,
      fileName: fileName.isEmpty ? 'download' : fileName,
      url: url,
      mimeType: mime,
      state: enableNativePolling ? 'running' : 'completed',
      bytesDownloaded: 0,
      totalBytes: total,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _insertEntry(DownloadEntry entry) {
    _items = <DownloadEntry>[
      entry,
      ..._items.where((DownloadEntry e) => e.downloadId != entry.downloadId),
    ];
    unawaited(_persist());
    if (enableNativePolling) {
      _ensurePolling();
    }
    notifyListeners();
  }

  Future<bool> startUrlDownload({
    required String url,
    String? suggestedFileName,
    String? mimeType,
  }) async {
    final String clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      return false;
    }
    final Map<String, Object?>? info = await NativeShieldBridge.instance
        .startDownload(
          url: clean,
          fileName: suggestedFileName,
          mimeType: mimeType,
          userAgent: AppConstants.mobileUserAgent,
        );
    if (info == null) {
      return false;
    }
    final DownloadEntry entry = _entryFromNativeMap(info);
    _insertEntry(entry);
    onDownloadToast?.call('Downloading ${entry.fileName}...');
    return true;
  }

  void _ensurePolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      unawaited(refreshStatuses());
    });
  }

  Future<void> refreshStatuses() async {
    if (_items.isEmpty) {
      _pollTimer?.cancel();
      return;
    }
    final List<int> ids = _items
        .map((DownloadEntry e) => e.downloadId)
        .toList(growable: false);
    final List<Map<String, Object?>> statuses = await NativeShieldBridge
        .instance
        .queryDownloads(ids);
    if (statuses.isEmpty) {
      if (!hasActiveDownloads) {
        _pollTimer?.cancel();
      }
      return;
    }

    final Map<int, Map<String, Object?>> byId = <int, Map<String, Object?>>{};
    for (final Map<String, Object?> row in statuses) {
      final Object? idVal = row['downloadId'];
      if (idVal is num) {
        byId[idVal.toInt()] = row;
      }
    }

    bool changed = false;
    final List<DownloadEntry> next = <DownloadEntry>[];
    for (final DownloadEntry item in _items) {
      final Map<String, Object?>? row = byId[item.downloadId];
      if (row == null) {
        next.add(item);
        continue;
      }
      final String newState = (row['state']?.toString() ?? item.state).trim();
      final int newBytes = (row['bytesDownloaded'] is num)
          ? (row['bytesDownloaded']! as num).toInt()
          : item.bytesDownloaded;
      final int newTotal = (row['totalBytes'] is num)
          ? (row['totalBytes']! as num).toInt()
          : item.totalBytes;
      final String newUri = (row['localUri']?.toString() ?? item.localUri)
          .trim();
      final String newMime = (row['mimeType']?.toString() ?? item.mimeType)
          .trim();

      if (newState != item.state ||
          newBytes != item.bytesDownloaded ||
          newTotal != item.totalBytes ||
          newUri != item.localUri) {
        changed = true;
        next.add(
          item.copyWith(
            state: newState,
            bytesDownloaded: newBytes,
            totalBytes: newTotal,
            localUri: newUri,
            mimeType: newMime.isEmpty ? item.mimeType : newMime,
          ),
        );
      } else {
        next.add(item);
      }
    }

    if (changed) {
      _items = next;
      await _persist();
      notifyListeners();
    }
    if (!hasActiveDownloads) {
      _pollTimer?.cancel();
    }
  }

  Future<bool> openDownload(DownloadEntry entry) async {
    return NativeShieldBridge.instance.openDownloadedFile(entry.downloadId);
  }

  Future<void> removeOrCancelDownload(DownloadEntry entry) async {
    await NativeShieldBridge.instance.cancelDownload(entry.downloadId);
    _items = _items
        .where((DownloadEntry e) => e.downloadId != entry.downloadId)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> clearFinishedDownloads() async {
    _items = _items.where((DownloadEntry e) => e.isRunning).toList();
    await _persist();
    notifyListeners();
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (NativeShieldBridge.instance.onDownloadStarted ==
        _onNativeDownloadStarted) {
      NativeShieldBridge.instance.onDownloadStarted = null;
    }
    super.dispose();
  }
}
