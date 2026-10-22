import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../shield/native_shield_bridge.dart';

class VpnProfile {
  const VpnProfile({
    required this.id,
    required this.name,
    required this.countryLabel,
    required this.configText,
    this.isBuiltInWarp = false,
  });

  final String id;
  final String name;
  final String countryLabel;
  final String configText;
  final bool isBuiltInWarp;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'countryLabel': countryLabel,
    'configText': configText,
  };

  factory VpnProfile.fromJson(Map<String, Object?> map) {
    return VpnProfile(
      id: (map['id']?.toString() ?? '').trim(),
      name: (map['name']?.toString() ?? 'Custom VPN').trim(),
      countryLabel: (map['countryLabel']?.toString() ?? 'Custom').trim(),
      configText: (map['configText']?.toString() ?? '').trim(),
    );
  }
}

class VpnController extends ChangeNotifier {
  VpnController(
    this._prefs, {
    this.enableNativePolling = true,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    _load();
    if (enableNativePolling) {
      unawaited(syncNativeStatus());
    }
  }

  static const String builtInWarpId = 'builtin_warp';
  static const String _keyWarpConfig = 'hb.vpn.warpConfig.v6';
  static const String _keyCustomProfiles = 'hb.vpn.customProfiles.v6';
  static const String _keySelectedProfileId = 'hb.vpn.selectedProfile.v6';
  static const String _keyBrowserOnly = 'hb.vpn.browserOnly.v6';

  final SharedPreferences _prefs;
  final bool enableNativePolling;
  final http.Client _client;

  Timer? _statsTimer;

  String _cachedWarpConfig = '';
  List<VpnProfile> _customProfiles = <VpnProfile>[];
  String _selectedProfileId = builtInWarpId;
  bool _browserOnly = true;

  bool _isConnected = false;
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;
  int _rxBytes = 0;
  int _txBytes = 0;
  String? _exitIp;
  String? _exitCountry;

  bool get isConnected => _isConnected;
  bool get isBusy => _isBusy;
  bool get browserOnly => _browserOnly;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  int get rxBytes => _rxBytes;
  int get txBytes => _txBytes;
  String? get exitIp => _exitIp;
  String? get exitCountry => _exitCountry;
  String get selectedProfileId => _selectedProfileId;

  VpnProfile get builtInWarpProfile => VpnProfile(
    id: builtInWarpId,
    name: 'Heaven Instant Free VPN',
    countryLabel: 'Fastest Edge (Cloudflare WARP)',
    configText: _cachedWarpConfig,
    isBuiltInWarp: true,
  );

  List<VpnProfile> get allProfiles => <VpnProfile>[
    builtInWarpProfile,
    ..._customProfiles,
  ];

  List<VpnProfile> get customProfiles =>
      List<VpnProfile>.unmodifiable(_customProfiles);

  VpnProfile get selectedProfile {
    for (final VpnProfile p in allProfiles) {
      if (p.id == _selectedProfileId) {
        return p;
      }
    }
    return builtInWarpProfile;
  }

  void _load() {
    _cachedWarpConfig = _prefs.getString(_keyWarpConfig) ?? '';
    _selectedProfileId =
        _prefs.getString(_keySelectedProfileId) ?? builtInWarpId;
    _browserOnly = _prefs.getBool(_keyBrowserOnly) ?? true;

    final String? rawProfiles = _prefs.getString(_keyCustomProfiles);
    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawProfiles);
        if (decoded is List<Object?>) {
          _customProfiles = decoded
              .whereType<Map<String, Object?>>()
              .map(VpnProfile.fromJson)
              .where(
                (VpnProfile p) => p.id.isNotEmpty && p.configText.isNotEmpty,
              )
              .toList();
        }
      } on FormatException {
        _customProfiles = <VpnProfile>[];
      }
    }
    if (!allProfiles.any((VpnProfile p) => p.id == _selectedProfileId)) {
      _selectedProfileId = builtInWarpId;
    }
  }

  Future<void> setBrowserOnly(bool value) async {
    if (_browserOnly == value) return;
    _browserOnly = value;
    notifyListeners();
    unawaited(_prefs.setBool(_keyBrowserOnly, value));
    if (_isConnected) {
      await reconnect();
    }
  }

  Future<void> selectProfile(String profileId) async {
    if (_selectedProfileId == profileId) return;
    if (!allProfiles.any((VpnProfile p) => p.id == profileId)) return;
    _selectedProfileId = profileId;
    _errorMessage = null;
    notifyListeners();
    unawaited(_prefs.setString(_keySelectedProfileId, profileId));
    if (_isConnected) {
      await reconnect();
    }
  }

  Future<String?> addCustomProfile({
    required String name,
    required String countryLabel,
    required String configText,
  }) async {
    final String cleanConfig = configText.trim();
    if (cleanConfig.isEmpty) {
      return 'Paste a WireGuard .conf configuration first.';
    }

    final Map<String, Object?> check = await NativeShieldBridge.instance
        .validateWireGuardConfig(cleanConfig);
    if (check['valid'] != true) {
      return check['error']?.toString() ?? 'Invalid WireGuard .conf format.';
    }

    final VpnProfile created = VpnProfile(
      id: 'wg_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Country VPN' : name.trim(),
      countryLabel: countryLabel.trim().isEmpty
          ? 'Custom Country'
          : countryLabel.trim(),
      configText: cleanConfig,
    );

    _customProfiles = <VpnProfile>[created, ..._customProfiles];
    _selectedProfileId = created.id;
    notifyListeners();
    unawaited(_persistCustomProfiles());
    unawaited(_prefs.setString(_keySelectedProfileId, _selectedProfileId));
    return null;
  }

  Future<void> removeCustomProfile(String profileId) async {
    final bool wasSelected = _selectedProfileId == profileId;
    _customProfiles = _customProfiles
        .where((VpnProfile p) => p.id != profileId)
        .toList();
    if (wasSelected) {
      _selectedProfileId = builtInWarpId;
      unawaited(_prefs.setString(_keySelectedProfileId, _selectedProfileId));
      if (_isConnected) {
        await disconnect();
      }
    }
    notifyListeners();
    unawaited(_persistCustomProfiles());
  }

  Future<void> rotateFreeWarpIdentity() async {
    _cachedWarpConfig = '';
    notifyListeners();
    unawaited(_prefs.remove(_keyWarpConfig));
    if (_isConnected && _selectedProfileId == builtInWarpId) {
      await reconnect();
    }
  }

  Future<void> toggleConnection() async {
    if (_isBusy) return;
    if (_isConnected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }

  Future<bool> connect() async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    _statusMessage = 'Starting encrypted tunnel...';
    notifyListeners();

    try {
      VpnProfile target = selectedProfile;
      String configToUse = target.configText;

      if (target.isBuiltInWarp && configToUse.trim().isEmpty) {
        _statusMessage = 'Provisioning free anonymous WireGuard key...';
        notifyListeners();

        final Map<String, Object?> provisioned = await NativeShieldBridge
            .instance
            .provisionFreeWarpConfig();
        if (provisioned['ok'] != true ||
            (provisioned['configText']?.toString().trim().isEmpty ?? true)) {
          _isBusy = false;
          _statusMessage = null;
          _errorMessage =
              provisioned['error']?.toString() ??
              'Could not auto-register free WARP key. Import a custom .conf profile instead.';
          notifyListeners();
          return false;
        }
        configToUse = provisioned['configText']!.toString().trim();
        _cachedWarpConfig = configToUse;
        unawaited(_prefs.setString(_keyWarpConfig, _cachedWarpConfig));
      }

      _statusMessage = 'Establishing WireGuard tunnel...';
      notifyListeners();

      final Map<String, Object?> res = await NativeShieldBridge.instance
          .connectVpn(
            configText: configToUse,
            profileName: target.name,
            browserOnly: _browserOnly,
          );

      final bool ok = res['ok'] == true && res['connected'] == true;
      _isConnected = ok;
      _isBusy = false;
      _statusMessage = null;

      if (!ok) {
        _errorMessage =
            res['error']?.toString() ?? 'Unable to connect WireGuard VPN';
        notifyListeners();
        return false;
      }

      if (enableNativePolling) {
        _startPolling();
      }
      unawaited(refreshExitIpInfo());
      notifyListeners();
      return true;
    } catch (e) {
      _isBusy = false;
      _isConnected = false;
      _statusMessage = null;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    await NativeShieldBridge.instance.disconnectVpn();
    _statsTimer?.cancel();
    _isConnected = false;
    _isBusy = false;
    _statusMessage = null;
    _rxBytes = 0;
    _txBytes = 0;
    _exitIp = null;
    _exitCountry = null;
    notifyListeners();
  }

  Future<void> syncNativeStatus() async {
    final Map<String, Object?> st = await NativeShieldBridge.instance
        .getVpnStatus();
    final bool up = st['connected'] == true;
    _isConnected = up;
    _rxBytes = (st['rxBytes'] is num) ? (st['rxBytes']! as num).toInt() : 0;
    _txBytes = (st['txBytes'] is num) ? (st['txBytes']! as num).toInt() : 0;
    if (up && enableNativePolling) {
      _startPolling();
      if (_exitIp == null) {
        unawaited(refreshExitIpInfo());
      }
    }
    notifyListeners();
  }

  Future<void> refreshExitIpInfo() async {
    try {
      final http.Response resp = await _client
          .get(Uri.parse('https://1.1.1.1/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        String? ip;
        String? loc;
        for (final String line in resp.body.split('\n')) {
          if (line.startsWith('ip=')) {
            ip = line.substring(3).trim();
          } else if (line.startsWith('loc=')) {
            loc = line.substring(4).trim();
          }
        }
        if (ip != null && ip.isNotEmpty) {
          _exitIp = ip;
          _exitCountry = loc;
          notifyListeners();
        }
      }
    } catch (_) {
      // Non-fatal in offline/test environments.
    }
  }

  void _startPolling() {
    if (_statsTimer != null && _statsTimer!.isActive) return;
    _statsTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      final Map<String, Object?> st = await NativeShieldBridge.instance
          .getVpnStatus();
      final bool up = st['connected'] == true;
      _isConnected = up;
      _rxBytes = (st['rxBytes'] is num) ? (st['rxBytes']! as num).toInt() : 0;
      _txBytes = (st['txBytes'] is num) ? (st['txBytes']! as num).toInt() : 0;
      if (!up) {
        _statsTimer?.cancel();
      }
      notifyListeners();
    });
  }

  Future<void> _persistCustomProfiles() async {
    final String encoded = jsonEncode(
      _customProfiles.map((VpnProfile p) => p.toJson()).toList(),
    );
    await _prefs.setString(_keyCustomProfiles, encoded);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _client.close();
    super.dispose();
  }
}
