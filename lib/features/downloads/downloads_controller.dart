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
    this.speedBytesPerSec = 0,
    this.localUri = '',
  });

  final int downloadId;
  final String fileName;
  final String url;
  final String mimeType;
  final String state; // running, paused, completed, failed
  final int bytesDownloaded;
  final int totalBytes;
  final int speedBytesPerSec;
  final int createdAtMs;
  final String localUri;

  bool get isCompleted => state == 'completed';
  bool get isFailed => state == 'failed';
  bool get isPaused => state == 'paused';
  bool get isRunning => state == 'running' || state == 'pending';
  bool get isActive => isRunning;

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
    int? speedBytesPerSec,
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
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      createdAtMs: createdAtMs,
      localUri: localUri ?? this.localUri,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
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

  factory DownloadEntry.fromJson(Map<String, Object?> map) {
    final String rawState = (map['state']?.toString() ?? 'paused').trim();
    return DownloadEntry(
      downloadId: (map['downloadId'] is num)
          ? (map['downloadId']! as num).toInt()
          : 0,
      fileName: (map['fileName']?.toString() ?? 'download').trim(),
      url: (map['url']?.toString() ?? '').trim(),
      mimeType: (map['mimeType']?.toString() ?? '').trim(),
      state: rawState == 'running' ? 'paused' : rawState,
      bytesDownloaded: (map['bytesDownloaded'] is num)
          ? (map['bytesDownloaded']! as num).toInt()
          : 0,
      totalBytes: (map['totalBytes'] is num)
          ? (map['totalBytes']! as num).toInt()
          : -1,
      createdAtMs: (map['createdAtMs'] is num)
          ? (map['createdAtMs']! as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
      localUri: (map['localUri']?.toString() ?? '').trim(),
    );
  }
}

class DownloadsController extends ChangeNotifier {
  DownloadsController(this._prefs, {this.enableNativePolling = true}) {
    _load();
    NativeShieldBridge.instance.onDownloadStarted = _onNativeDownloadStarted;
    if (enableNativePolling && _items.isNotEmpty) {
      unawaited(_restoreSavedJobsInNative());
      if (hasActiveDownloads) {
        _ensurePolling();
      }
    }
  }

  static const String _storageKey = 'hb.downloads.v4';

  final SharedPreferences _prefs;
  final bool enableNativePolling;
  Timer? _pollTimer;
  List<DownloadEntry> _items = <DownloadEntry>[];

  void Function(String message)? onDownloadToast;

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

  Future<void> _restoreSavedJobsInNative() async {
    for (final DownloadEntry entry in _items) {
      await NativeShieldBridge.instance.restoreDownload(
        downloadId: entry.downloadId,
        url: entry.url,
        fileName: entry.fileName,
        mimeType: entry.mimeType,
        localUri: entry.localUri,
        state: entry.state,
        totalBytes: entry.totalBytes,
      );
    }
    await refreshStatuses();
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
    onDownloadToast?.call('Download started: ${entry.fileName}');
  }

  DownloadEntry _entryFromNativeMap(Map<String, Object?> info) {
    final int id = (info['downloadId'] is num)
        ? (info['downloadId']! as num).toInt()
        : DateTime.now().millisecondsSinceEpoch;
    final String url = (info['url']?.toString() ?? '').trim();
    final String fileName = (info['fileName']?.toString() ?? 'download').trim();
    final String mime = (info['mimeType']?.toString() ?? '').trim();
    final String localUri = (info['localUri']?.toString() ?? '').trim();
    final int total = (info['totalBytes'] is num)
        ? (info['totalBytes']! as num).toInt()
        : -1;
    final int bytes = (info['bytesDownloaded'] is num)
        ? (info['bytesDownloaded']! as num).toInt()
        : 0;

    final String explicitState = (info['state']?.toString() ?? '').trim();

    return DownloadEntry(
      downloadId: id,
      fileName: fileName.isEmpty ? 'download' : fileName,
      url: url,
      mimeType: mime,
      state: explicitState.isNotEmpty
          ? explicitState
          : (enableNativePolling ? 'running' : 'completed'),
      bytesDownloaded: bytes,
      totalBytes: total,
      localUri: localUri,
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
    onDownloadToast?.call('Download started: ${entry.fileName}');
    return true;
  }

  Future<void> pauseDownload(int downloadId) async {
    final int idx = _items.indexWhere(
      (DownloadEntry e) => e.downloadId == downloadId,
    );
    if (idx < 0) return;

    final DownloadEntry current = _items[idx];
    if (!current.isRunning) return;

    _items[idx] = current.copyWith(state: 'paused', speedBytesPerSec: 0);
    notifyListeners();
    await _persist();

    await NativeShieldBridge.instance.pauseDownload(downloadId);
    if (!hasActiveDownloads) {
      _pollTimer?.cancel();
    }
  }

  Future<void> resumeDownload(int downloadId) async {
    final int idx = _items.indexWhere(
      (DownloadEntry e) => e.downloadId == downloadId,
    );
    if (idx < 0) return;

    final DownloadEntry current = _items[idx];
    if (current.isCompleted || current.isRunning) return;

    _items[idx] = current.copyWith(state: 'running', speedBytesPerSec: 0);
    notifyListeners();
    unawaited(_persist());

    // Ensure native engine knows about the job if app was restarted
    await NativeShieldBridge.instance.restoreDownload(
      downloadId: current.downloadId,
      url: current.url,
      fileName: current.fileName,
      mimeType: current.mimeType,
      localUri: current.localUri,
      state: current.state,
      totalBytes: current.totalBytes,
    );

    await NativeShieldBridge.instance.resumeDownload(downloadId);
    if (enableNativePolling) {
      _ensurePolling();
    }
  }

  void _ensurePolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
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
      final int newSpeed = (row['speedBytesPerSec'] is num)
          ? (row['speedBytesPerSec']! as num).toInt()
          : 0;
      final String newUri = (row['localUri']?.toString() ?? item.localUri)
          .trim();
      final String newMime = (row['mimeType']?.toString() ?? item.mimeType)
          .trim();

      if (newState != item.state ||
          newBytes != item.bytesDownloaded ||
          newTotal != item.totalBytes ||
          newSpeed != item.speedBytesPerSec ||
          newUri != item.localUri) {
        changed = true;
        next.add(
          item.copyWith(
            state: newState,
            bytesDownloaded: newBytes,
            totalBytes: newTotal,
            speedBytesPerSec: newSpeed,
            localUri: newUri.isNotEmpty ? newUri : item.localUri,
            mimeType: newMime.isNotEmpty ? newMime : item.mimeType,
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

  Future<bool> openDownload(DownloadEntry entry) {
    return NativeShieldBridge.instance.openDownloadedFile(
      downloadId: entry.downloadId,
      localUri: entry.localUri,
      mimeType: entry.mimeType,
    );
  }

  Future<void> cancelAndRemove(DownloadEntry entry) async {
    await NativeShieldBridge.instance.cancelDownload(entry.downloadId);
    _items = _items
        .where((DownloadEntry e) => e.downloadId != entry.downloadId)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> clearFinished() async {
    _items = _items
        .where((DownloadEntry e) => e.isRunning || e.isPaused)
        .toList();
    await _persist();
    notifyListeners();
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    int idx = 0;
    while (v >= 1024 && idx < units.length - 1) {
      v /= 1024;
      idx++;
    }
    return '${v.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
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
