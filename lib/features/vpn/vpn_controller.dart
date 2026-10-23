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
    this.flagEmoji = '⚡',
    this.routeMode = 'stealth_4500',
    this.isBuiltInWarp = false,
  });

  final String id;
  final String name;
  final String countryLabel;
  final String configText;
  final String flagEmoji;
  final String routeMode;
  final bool isBuiltInWarp;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'countryLabel': countryLabel,
    'configText': configText,
    'flagEmoji': flagEmoji,
    'routeMode': routeMode,
  };

  factory VpnProfile.fromJson(Map<String, Object?> map) {
    return VpnProfile(
      id: (map['id']?.toString() ?? '').trim(),
      name: (map['name']?.toString() ?? 'Custom VPN').trim(),
      countryLabel: (map['countryLabel']?.toString() ?? 'Custom Country')
          .trim(),
      configText: (map['configText']?.toString() ?? '').trim(),
      flagEmoji: (map['flagEmoji']?.toString() ?? '🌐').trim(),
      routeMode: (map['routeMode']?.toString() ?? 'custom').trim(),
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

  static const String defaultStealthId = 'route_stealth_4500';
  static const String _keyWarpConfig = 'hb.vpn.warpConfig.v8';
  static const String _keyCustomProfiles = 'hb.vpn.customProfiles.v8';
  static const String _keySelectedProfileId = 'hb.vpn.selectedId.v8';
  static const String _keyBrowserOnly = 'hb.vpn.browserOnly.v8';

  final SharedPreferences _prefs;
  final bool enableNativePolling;
  final http.Client _client;

  VoidCallback? onTunnelConnected;

  Timer? _statsTimer;
  String _cachedWarpConfig = '';
  List<VpnProfile> _customProfiles = <VpnProfile>[];
  String _selectedProfileId = defaultStealthId;
  // Default false = Full Encrypted DNS + IPv6 Tunnel so ISP blocks never leak!
  bool _browserOnly = false;

  bool _isConnected = false;
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;
  int _rxBytes = 0;
  int _txBytes = 0;
  String? _exitIp;
  String? _exitCountry;
  String _activeEndpoint = '';

  bool get isConnected => _isConnected;
  bool get isBusy => _isBusy;
  bool get browserOnly => _browserOnly;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  int get rxBytes => _rxBytes;
  int get txBytes => _txBytes;
  String? get exitIp => _exitIp;
  String? get exitCountry => _exitCountry;
  String get activeEndpoint => _activeEndpoint;
  String get selectedProfileId => _selectedProfileId;

  List<VpnProfile> get builtInRoutes => <VpnProfile>[
    VpnProfile(
      id: defaultStealthId,
      name: 'Stealth Anti-Block (Port 4500)',
      countryLabel: 'Bypasses ISP blocks • MTU 1280 + Dual-Stack DNS',
      configText: _cachedWarpConfig,
      flagEmoji: '⚡',
      routeMode: 'stealth_4500',
      isBuiltInWarp: true,
    ),
    VpnProfile(
      id: 'route_alt_500',
      name: 'Alternate Edge Route (Port 500)',
      countryLabel: '188.114 Multi-Subnet • Anti-Throttle Tunnel',
      configText: _cachedWarpConfig,
      flagEmoji: '🛡️',
      routeMode: 'alt_188_500',
      isBuiltInWarp: true,
    ),
    VpnProfile(
      id: 'route_l2tp_1701',
      name: 'Direct High-Speed (Port 1701)',
      countryLabel: 'Low-Latency Encrypted UDP 1701 Route',
      configText: _cachedWarpConfig,
      flagEmoji: '🌐',
      routeMode: 'l2tp_1701',
      isBuiltInWarp: true,
    ),
    VpnProfile(
      id: 'route_standard_2408',
      name: 'Standard Warp Edge (Port 2408)',
      countryLabel: 'Cloudflare 1.1.1.1 Standard WireGuard Port',
      configText: _cachedWarpConfig,
      flagEmoji: '🚀',
      routeMode: 'standard_2408',
      isBuiltInWarp: true,
    ),
  ];

  List<VpnProfile> get customProfiles =>
      List<VpnProfile>.unmodifiable(_customProfiles);

  List<VpnProfile> get allProfiles => <VpnProfile>[
    ...builtInRoutes,
    ..._customProfiles,
  ];

  VpnProfile get selectedProfile {
    for (final VpnProfile p in allProfiles) {
      if (p.id == _selectedProfileId) {
        return p;
      }
    }
    return builtInRoutes.first;
  }

  void _load() {
    _cachedWarpConfig = _prefs.getString(_keyWarpConfig) ?? '';
    _selectedProfileId =
        _prefs.getString(_keySelectedProfileId) ?? defaultStealthId;
    _browserOnly = _prefs.getBool(_keyBrowserOnly) ?? false;

    final String? rawProfiles =
        _prefs.getString(_keyCustomProfiles) ??
        _prefs.getString('hb.vpn.customProfiles.v7') ??
        _prefs.getString('hb.vpn.customProfiles.v6');
    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawProfiles);
        if (decoded is List<Object?>) {
          _customProfiles = decoded
              .whereType<Map<String, Object?>>()
              .map(VpnProfile.fromJson)
              .where(
                (VpnProfile p) =>
                    p.id.isNotEmpty && p.configText.contains('[Interface]'),
              )
              .toList();
        }
      } on FormatException {
        _customProfiles = <VpnProfile>[];
      }
    }
    if (!allProfiles.any((VpnProfile p) => p.id == _selectedProfileId)) {
      _selectedProfileId = defaultStealthId;
    }
  }

  Future<void> _persistCustomProfiles() async {
    await _prefs.setString(
      _keyCustomProfiles,
      jsonEncode(_customProfiles.map((VpnProfile p) => p.toJson()).toList()),
    );
  }

  Future<void> selectProfile(String id) async {
    if (_selectedProfileId == id) return;
    _selectedProfileId = id;
    _errorMessage = null;
    notifyListeners();
    unawaited(_prefs.setString(_keySelectedProfileId, id));
    if (_isConnected) {
      await reconnect();
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

  Future<String?> addCustomProfile({
    required String name,
    required String countryLabel,
    required String configText,
  }) async {
    final String clean = configText.trim();
    if (clean.isEmpty) {
      return 'Paste or import a WireGuard (.conf) configuration first.';
    }
    final Map<String, Object?> check = await NativeShieldBridge.instance
        .validateWireGuardConfig(clean);
    if (check['valid'] != true) {
      return check['error']?.toString() ?? 'Invalid WireGuard (.conf) format.';
    }
    final VpnProfile created = VpnProfile(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Country Server' : name.trim(),
      countryLabel: countryLabel.trim().isEmpty
          ? 'Custom WireGuard Country'
          : countryLabel.trim(),
      configText: clean,
      flagEmoji: '🌍',
      routeMode: 'custom',
    );
    _customProfiles = <VpnProfile>[created, ..._customProfiles];
    _selectedProfileId = created.id;
    notifyListeners();
    await _persistCustomProfiles();
    await _prefs.setString(_keySelectedProfileId, created.id);
    return null;
  }

  Future<void> removeCustomProfile(String id) async {
    _customProfiles = _customProfiles
        .where((VpnProfile p) => p.id != id)
        .toList();
    if (_selectedProfileId == id) {
      _selectedProfileId = defaultStealthId;
      await _prefs.setString(_keySelectedProfileId, defaultStealthId);
    }
    notifyListeners();
    await _persistCustomProfiles();
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

  Future<void> refreshWarpKeyAndReconnect() async {
    _cachedWarpConfig = '';
    await _prefs.remove(_keyWarpConfig);
    await reconnect();
  }

  Future<void> connect() async {
    if (_isBusy) return;
    _isBusy = true;
    _errorMessage = null;
    _statusMessage = 'Securing stealth WireGuard tunnel...';
    notifyListeners();

    try {
      final VpnProfile profile = selectedProfile;
      String cfgToUse = profile.configText;

      if (profile.isBuiltInWarp && cfgToUse.trim().isEmpty) {
        _statusMessage = 'Provisioning fresh encrypted key...';
        notifyListeners();
        final Map<String, Object?> reg = await NativeShieldBridge.instance
            .provisionFreeWarpConfig(routeMode: profile.routeMode);
        if (reg['ok'] != true) {
          _errorMessage =
              reg['error']?.toString() ?? 'Unable to provision VPN key.';
          _isBusy = false;
          _statusMessage = null;
          notifyListeners();
          return;
        }
        cfgToUse = (reg['configText']?.toString() ?? '').trim();
        if (cfgToUse.isNotEmpty) {
          _cachedWarpConfig = cfgToUse;
          unawaited(_prefs.setString(_keyWarpConfig, cfgToUse));
        }
      }

      _statusMessage = 'Verifying anti-block route...';
      notifyListeners();

      final Map<String, Object?> res = await NativeShieldBridge.instance
          .connectVpn(
            configText: cfgToUse,
            profileName: profile.name,
            routeMode: profile.routeMode,
            browserOnly: _browserOnly,
            isBuiltInWarp: profile.isBuiltInWarp,
          );

      if (res['ok'] == true && res['connected'] == true) {
        final String updatedCfg = (res['configText']?.toString() ?? '').trim();
        if (profile.isBuiltInWarp && updatedCfg.isNotEmpty) {
          _cachedWarpConfig = updatedCfg;
          unawaited(_prefs.setString(_keyWarpConfig, updatedCfg));
        }
        _isConnected = true;
        _activeEndpoint = (res['endpoint']?.toString() ?? '').trim();
        _statusMessage = null;
        _errorMessage = null;
        if (enableNativePolling) {
          _startPolling();
        }
        onTunnelConnected?.call();
        unawaited(refreshExitIpInfo());
      } else {
        _isConnected = false;
        _statusMessage = null;
        _errorMessage =
            res['error']?.toString() ?? 'Could not establish VPN connection.';
      }
    } catch (e) {
      _isConnected = false;
      _statusMessage = null;
      _errorMessage = 'VPN connection error: $e';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _isBusy = true;
    _statusMessage = 'Disconnecting...';
    notifyListeners();
    await NativeShieldBridge.instance.disconnectVpn();
    _isConnected = false;
    _isBusy = false;
    _statusMessage = null;
    _rxBytes = 0;
    _txBytes = 0;
    _exitIp = null;
    _exitCountry = null;
    _activeEndpoint = '';
    notifyListeners();
  }

  Future<void> syncNativeStatus() async {
    final Map<String, Object?> status = await NativeShieldBridge.instance
        .getVpnStatus();
    final bool up = status['connected'] == true;
    _isConnected = up;
    _rxBytes = (status['rxBytes'] is num)
        ? (status['rxBytes']! as num).toInt()
        : 0;
    _txBytes = (status['txBytes'] is num)
        ? (status['txBytes']! as num).toInt()
        : 0;
    _activeEndpoint = (status['endpoint']?.toString() ?? '').trim();
    if (up) {
      if (enableNativePolling) {
        _startPolling();
      }
      if (_exitIp == null) {
        unawaited(refreshExitIpInfo());
      }
    }
    notifyListeners();
  }

  void _startPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final Map<String, Object?> status = await NativeShieldBridge.instance
          .getVpnStatus();
      final bool up = status['connected'] == true;
      _isConnected = up;
      if (up) {
        _rxBytes = (status['rxBytes'] is num)
            ? (status['rxBytes']! as num).toInt()
            : _rxBytes;
        _txBytes = (status['txBytes'] is num)
            ? (status['txBytes']! as num).toInt()
            : _txBytes;
      } else {
        _statsTimer?.cancel();
      }
      notifyListeners();
    });
  }

  Future<void> refreshExitIpInfo() async {
    try {
      final http.Response res = await _client
          .get(Uri.parse('https://1.1.1.1/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        for (final String line in res.body.split('\n')) {
          if (line.startsWith('ip=')) {
            _exitIp = line.substring(3).trim();
          } else if (line.startsWith('loc=')) {
            _exitCountry = line.substring(4).trim();
          }
        }
        notifyListeners();
      }
    } catch (_) {
      // Non-fatal if trace endpoint times out.
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final double kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final double mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final double gb = mb / 1024.0;
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _client.close();
    super.dispose();
  }
}
