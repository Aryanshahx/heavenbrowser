import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart' as ovpn;
import 'package:shared_preferences/shared_preferences.dart';

import '../shield/native_shield_bridge.dart';

enum VpnProtocol { wireguard, openvpn }

class VpnProfile {
  const VpnProfile({
    required this.id,
    required this.name,
    required this.countryLabel,
    required this.configText,
    this.flagEmoji = '🌐',
    this.countryCode = '',
    this.protocol = VpnProtocol.wireguard,
    this.isBuiltInWarp = false,
    this.isBuiltInForeign = false,
  });

  final String id;
  final String name;
  final String countryLabel;
  final String configText;
  final String flagEmoji;
  final String countryCode;
  final VpnProtocol protocol;
  final bool isBuiltInWarp;
  final bool isBuiltInForeign;

  bool get isBuiltIn => isBuiltInWarp || isBuiltInForeign;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'countryLabel': countryLabel,
    'configText': configText,
    'flagEmoji': flagEmoji,
    'countryCode': countryCode,
    'protocol': protocol.name,
  };

  factory VpnProfile.fromJson(Map<String, Object?> map) {
    final String rawProto = (map['protocol']?.toString() ?? 'wireguard').trim();
    return VpnProfile(
      id: (map['id']?.toString() ?? '').trim(),
      name: (map['name']?.toString() ?? 'Custom VPN').trim(),
      countryLabel: (map['countryLabel']?.toString() ?? 'Custom').trim(),
      configText: (map['configText']?.toString() ?? '').trim(),
      flagEmoji: (map['flagEmoji']?.toString() ?? '🌐').trim(),
      countryCode: (map['countryCode']?.toString() ?? '').trim(),
      protocol: rawProto == 'openvpn'
          ? VpnProtocol.openvpn
          : VpnProtocol.wireguard,
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
      unawaited(_initEngines());
    }
  }

  static const String builtInWarpId = 'builtin_warp';
  static const String defaultForeignUsId = 'foreign_us';

  static const String _keyWarpConfig = 'hb.vpn.warpConfig.v6';
  static const String _keyCustomProfiles = 'hb.vpn.customProfiles.v7';
  static const String _keySelectedProfileId = 'hb.vpn.selectedProfile.v7';
  static const String _keyBrowserOnly = 'hb.vpn.browserOnly.v6';

  static const List<VpnProfile> _coreForeignProfiles = <VpnProfile>[
    VpnProfile(
      id: 'foreign_auto',
      name: 'Fastest Foreign Server',
      countryLabel: 'Auto Lowest-Ping Outside India (OpenVPN)',
      configText: '',
      flagEmoji: '🌍',
      countryCode: 'AUTO_FOREIGN',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: defaultForeignUsId,
      name: 'United States',
      countryLabel: 'Miami / US High-Speed Foreign Tunnel',
      configText: '',
      flagEmoji: '🇺🇸',
      countryCode: 'US',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_nl',
      name: 'Netherlands',
      countryLabel: 'Amsterdam • Europe Dedicated Gateway',
      configText: '',
      flagEmoji: '🇳🇱',
      countryCode: 'NL',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_fr',
      name: 'France',
      countryLabel: 'Paris • Europe High-Capacity Gateway',
      configText: '',
      flagEmoji: '🇫🇷',
      countryCode: 'FR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ca',
      name: 'Canada',
      countryLabel: 'Montreal • North America Gateway',
      configText: '',
      flagEmoji: '🇨🇦',
      countryCode: 'CA',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_jp',
      name: 'Japan',
      countryLabel: 'Tokyo / Tsukuba • High-Speed Asia Relay',
      configText: '',
      flagEmoji: '🇯🇵',
      countryCode: 'JP',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_kr',
      name: 'South Korea',
      countryLabel: 'Seoul • Fast East Asia Relay',
      configText: '',
      flagEmoji: '🇰🇷',
      countryCode: 'KR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_hk',
      name: 'Hong Kong',
      countryLabel: 'Hong Kong • Low-Latency Asia Relay',
      configText: '',
      flagEmoji: '🇭🇰',
      countryCode: 'HK',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_th',
      name: 'Thailand',
      countryLabel: 'Bangkok • Southeast Asia Relay',
      configText: '',
      flagEmoji: '🇹🇭',
      countryCode: 'TH',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
  ];

  final SharedPreferences _prefs;
  final bool enableNativePolling;
  final http.Client _client;

  Timer? _statsTimer;
  ovpn.OpenVPN? _openVpnEngine;
  bool _openVpnReady = false;
  VpnProtocol? _activeEngineProtocol;
  final Set<String> _sessionExcludedHosts = <String>{};
  VoidCallback? onTunnelConnected;

  String _cachedWarpConfig = '';
  List<VpnProfile> _dynamicForeignProfiles = <VpnProfile>[];
  List<VpnProfile> _customProfiles = <VpnProfile>[];
  String _selectedProfileId = defaultForeignUsId;
  bool _browserOnly = true;
  bool _refreshingServers = false;

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
  bool get isRefreshingServers => _refreshingServers;
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
    name: 'Fastest Nearby Edge (WARP)',
    countryLabel: 'Cloudflare 1.1.1.1 WireGuard • Ultra-Low Ping',
    configText: _cachedWarpConfig,
    flagEmoji: '⚡',
    countryCode: 'WARP',
    protocol: VpnProtocol.wireguard,
    isBuiltInWarp: true,
  );

  List<VpnProfile> get foreignProfiles => <VpnProfile>[
    ..._coreForeignProfiles,
    ..._dynamicForeignProfiles,
  ];

  List<VpnProfile> get allProfiles => <VpnProfile>[
    ..._coreForeignProfiles,
    ..._dynamicForeignProfiles,
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
    return _coreForeignProfiles[1]; // United States default
  }

  void _load() {
    _cachedWarpConfig = _prefs.getString(_keyWarpConfig) ?? '';
    _selectedProfileId =
        _prefs.getString(_keySelectedProfileId) ?? defaultForeignUsId;
    _browserOnly = _prefs.getBool(_keyBrowserOnly) ?? true;

    final String? rawProfiles =
        _prefs.getString(_keyCustomProfiles) ??
        _prefs.getString('hb.vpn.customProfiles.v6');
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
      _selectedProfileId = defaultForeignUsId;
    }
  }

  Future<void> _initEngines() async {
    await syncNativeStatus();
    await _ensureOpenVpnEngine();
  }

  Future<ovpn.OpenVPN?> _ensureOpenVpnEngine() async {
    if (!enableNativePolling) {
      return null;
    }
    if (_openVpnEngine != null && _openVpnReady) {
      return _openVpnEngine;
    }
    final ovpn.OpenVPN engine = ovpn.OpenVPN(
      onVpnStatusChanged: (ovpn.VpnStatus? status) {
        if (status == null || _activeEngineProtocol != VpnProtocol.openvpn) {
          return;
        }
        final int rx = int.tryParse(status.byteIn ?? '0') ?? 0;
        final int tx = int.tryParse(status.byteOut ?? '0') ?? 0;
        if (rx != _rxBytes || tx != _txBytes) {
          _rxBytes = rx;
          _txBytes = tx;
          notifyListeners();
        }
      },
      onVpnStageChanged: (ovpn.VPNStage stage, String rawStage) {
        if (_activeEngineProtocol != VpnProtocol.openvpn) {
          return;
        }
        if (stage == ovpn.VPNStage.connected) {
          _isConnected = true;
          _isBusy = false;
          _statusMessage = null;
          _errorMessage = null;
          unawaited(refreshExitIpInfo());
          notifyListeners();
        } else if (stage.isConnecting) {
          _statusMessage = _humanStageLabel(stage);
          notifyListeners();
        } else if (stage == ovpn.VPNStage.disconnected && !_isBusy) {
          _isConnected = false;
          _statusMessage = null;
          notifyListeners();
        }
      },
    );
    try {
      await engine.initialize(
        localizedDescription: 'Heaven VPN',
        showTrafficInNotification: true,
        lastStage: (ovpn.VPNStage stage) {
          if (stage == ovpn.VPNStage.connected) {
            _activeEngineProtocol = VpnProtocol.openvpn;
            _isConnected = true;
            unawaited(refreshExitIpInfo());
            notifyListeners();
          }
        },
      );
      _openVpnEngine = engine;
      _openVpnReady = true;
      return engine;
    } catch (_) {
      return null;
    }
  }

  String _humanStageLabel(ovpn.VPNStage stage) {
    return switch (stage) {
      ovpn.VPNStage.prepare => 'Grant VPN permission...',
      ovpn.VPNStage.resolve => 'Resolving foreign gateway...',
      ovpn.VPNStage.tcp_connect ||
      ovpn.VPNStage.udp_connect ||
      ovpn.VPNStage.wait_connection => 'Handshaking with foreign server...',
      ovpn.VPNStage.authenticating ||
      ovpn.VPNStage.authentication => 'Verifying encrypted certificate...',
      ovpn.VPNStage.get_config ||
      ovpn.VPNStage.assign_ip ||
      ovpn.VPNStage.add_routes => 'Assigning foreign exit IP...',
      _ => 'Connecting foreign VPN...',
    };
  }

  Future<void> refreshLiveForeignServers() async {
    if (_refreshingServers) return;
    _refreshingServers = true;
    notifyListeners();
    try {
      final List<Map<String, Object?>> countries = await NativeShieldBridge
          .instance
          .fetchLiveForeignCountries();
      final Set<String> coreCodes = _coreForeignProfiles
          .map((VpnProfile p) => p.countryCode)
          .toSet();
      final List<VpnProfile> extras = <VpnProfile>[];
      for (final Map<String, Object?> c in countries) {
        final String code = (c['countryCode']?.toString() ?? '')
            .trim()
            .toUpperCase();
        final String name = (c['countryName']?.toString() ?? '').trim();
        final int count = (c['serverCount'] is num)
            ? (c['serverCount']! as num).toInt()
            : 1;
        if (code.length != 2 ||
            code == 'IN' ||
            coreCodes.contains(code) ||
            name.isEmpty) {
          continue;
        }
        extras.add(
          VpnProfile(
            id: 'foreign_${code.toLowerCase()}',
            name: name,
            countryLabel: '$count live foreign relay${count == 1 ? '' : 's'}',
            configText: '',
            flagEmoji: flagEmojiForCountryCode(code),
            countryCode: code,
            protocol: VpnProtocol.openvpn,
            isBuiltInForeign: true,
          ),
        );
      }
      _dynamicForeignProfiles = extras;
    } finally {
      _refreshingServers = false;
      notifyListeners();
    }
  }

  static String flagEmojiForCountryCode(String cc) {
    final String upper = cc.trim().toUpperCase();
    if (upper.length != 2) return '🌐';
    final int first = upper.codeUnitAt(0);
    final int second = upper.codeUnitAt(1);
    if (first < 65 || first > 90 || second < 65 || second > 90) {
      return '🌐';
    }
    return String.fromCharCodes(<int>[0x1F1E6 + first - 65, 0x1F1E6 + second - 65]);
  }

  Future<void> _persistCustomProfiles() async {
    await _prefs.setString(
      _keyCustomProfiles,
      jsonEncode(_customProfiles.map((VpnProfile p) => p.toJson()).toList()),
    );
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
      return 'Paste a WireGuard (.conf) or OpenVPN (.ovpn) config first.';
    }

    final bool looksLikeOpenVpn =
        cleanConfig.contains('<ca>') ||
        RegExp(r'^remote\s+\S+', multiLine: true).hasMatch(cleanConfig);

    VpnProtocol proto = VpnProtocol.wireguard;
    if (looksLikeOpenVpn) {
      proto = VpnProtocol.openvpn;
    } else {
      final Map<String, Object?> check = await NativeShieldBridge.instance
          .validateWireGuardConfig(cleanConfig);
      if (check['valid'] != true) {
        return check['error']?.toString() ??
            'Invalid WireGuard (.conf) or OpenVPN (.ovpn) format.';
      }
    }

    final VpnProfile created = VpnProfile(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Foreign VPN' : name.trim(),
      countryLabel: countryLabel.trim().isEmpty
          ? 'Custom Country (${proto.name.toUpperCase()})'
          : countryLabel.trim(),
      configText: cleanConfig,
      flagEmoji: '🌐',
      protocol: proto,
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
      _selectedProfileId = defaultForeignUsId;
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
    _exitIp = null;
    _exitCountry = null;
    _rxBytes = 0;
    _txBytes = 0;
    _statusMessage = 'Finding fastest live server...';
    notifyListeners();

    final VpnProfile target = selectedProfile;
    if (target.protocol == VpnProtocol.openvpn) {
      return _connectOpenVpnProfile(target);
    }
    return _connectWireGuardProfile(target);
  }

  Future<bool> _connectOpenVpnProfile(VpnProfile target) async {
    try {
      // Ensure any active WireGuard tunnel is stopped before starting OpenVPN
      await NativeShieldBridge.instance.disconnectVpn();
      _statsTimer?.cancel();

      for (int attempt = 0; attempt < 2; attempt++) {
        String configToUse = target.configText.trim();
        String? connectedHost;

        if (target.isBuiltInForeign) {
          _statusMessage = attempt == 0
              ? 'Probing live ${target.name} servers...'
              : 'Switching to backup ${target.name} server...';
          notifyListeners();

          final Map<String, Object?> provisioned = await NativeShieldBridge
              .instance
              .provisionForeignOpenVpnConfig(
                countryCode: target.countryCode,
                excludeHosts: _sessionExcludedHosts.toList(growable: false),
              );
          if (provisioned['ok'] != true ||
              (provisioned['configText']?.toString().trim().isEmpty ?? true)) {
            if (attempt == 0 && _sessionExcludedHosts.isNotEmpty) {
              _sessionExcludedHosts.clear();
              continue;
            }
            _isBusy = false;
            _statusMessage = null;
            _errorMessage =
                provisioned['error']?.toString() ??
                'Foreign servers busy. Please pick another country.';
            notifyListeners();
            return false;
          }
          configToUse = provisioned['configText']!.toString().trim();
          connectedHost = provisioned['serverHost']?.toString().trim();
        }

        // In unit/widget test mode (enableNativePolling == false), mark connected cleanly
        if (!enableNativePolling) {
          _activeEngineProtocol = VpnProtocol.openvpn;
          _isConnected = true;
          _isBusy = false;
          _statusMessage = null;
          await refreshExitIpInfo();
          onTunnelConnected?.call();
          notifyListeners();
          return true;
        }

        final ovpn.OpenVPN? engine = await _ensureOpenVpnEngine();
        if (engine == null) {
          _isBusy = false;
          _statusMessage = null;
          _errorMessage = 'OpenVPN engine unavailable on this device.';
          notifyListeners();
          return false;
        }

        _activeEngineProtocol = VpnProtocol.openvpn;
        _statusMessage = 'Connecting to ${target.name}...';
        notifyListeners();

        final bool hasCert =
            configToUse.contains('<cert>') && configToUse.contains('<key>');
        final bool started = await engine.connect(
          configToUse,
          'Heaven VPN • ${target.name}',
          username: 'vpn',
          password: 'vpn',
          certIsRequired: hasCert,
          allowedPackages: _browserOnly
              ? const <String>['com.hypertechlabs.heavenbrowser']
              : null,
        );

        if (!started) {
          _isBusy = false;
          _statusMessage = null;
          _errorMessage = 'VPN connection permission was declined.';
          notifyListeners();
          return false;
        }

        // Wait up to 16 seconds for tunnel handshake & route setup
        final bool established = await _waitForOpenVpnConnected(engine);
        if (established) {
          _isConnected = true;
          _isBusy = false;
          _statusMessage = null;
          unawaited(refreshExitIpInfo());
          onTunnelConnected?.call();
          notifyListeners();
          return true;
        }

        // Server stalled during TLS/auth -> exclude host and auto-try next live server!
        await engine.disconnect();
        if (connectedHost != null && connectedHost.isNotEmpty) {
          _sessionExcludedHosts.add(connectedHost);
        }
        if (!target.isBuiltInForeign) {
          break;
        }
      }

      _isConnected = false;
      _isBusy = false;
      _statusMessage = null;
      _errorMessage =
          'Could not complete handshake with ${target.name}. Try Netherlands, France, Japan, or USA.';
      notifyListeners();
      return false;
    } catch (e) {
      _isConnected = false;
      _isBusy = false;
      _statusMessage = null;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> _waitForOpenVpnConnected(ovpn.OpenVPN engine) async {
    if (engine.currentStage == ovpn.VPNStage.connected) {
      return true;
    }
    final Completer<bool> completer = Completer<bool>();
    late final StreamSubscription<ovpn.VPNStage> sub;
    final Timer timeout = Timer(const Duration(seconds: 16), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    sub = engine.stageStream.listen((ovpn.VPNStage stage) {
      if (completer.isCompleted) return;
      if (stage == ovpn.VPNStage.connected) {
        completer.complete(true);
      } else if (stage == ovpn.VPNStage.denied ||
          stage == ovpn.VPNStage.error ||
          stage == ovpn.VPNStage.auth_failed) {
        completer.complete(false);
      }
    });

    final bool result = await completer.future;
    timeout.cancel();
    await sub.cancel();
    return result;
  }

  Future<bool> _connectWireGuardProfile(VpnProfile target) async {
    try {
      if (_openVpnEngine != null && _openVpnReady) {
        await _openVpnEngine!.disconnect();
      }
      String configToUse = target.configText;

      if (target.isBuiltInWarp && configToUse.trim().isEmpty) {
        _statusMessage = 'Provisioning free WireGuard key...';
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
              'Could not register WARP key. Pick a Foreign Country server above.';
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
      _activeEngineProtocol = ok ? VpnProtocol.wireguard : null;
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
        _startWireGuardPolling();
      }
      await refreshExitIpInfo();
      onTunnelConnected?.call();
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

    _statsTimer?.cancel();
    if (_openVpnEngine != null && _openVpnReady) {
      await _openVpnEngine!.disconnect();
    }
    await NativeShieldBridge.instance.disconnectVpn();

    _activeEngineProtocol = null;
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
    final bool wgUp = st['connected'] == true;
    if (wgUp) {
      _activeEngineProtocol = VpnProtocol.wireguard;
      _isConnected = true;
      _rxBytes = (st['rxBytes'] is num) ? (st['rxBytes']! as num).toInt() : 0;
      _txBytes = (st['txBytes'] is num) ? (st['txBytes']! as num).toInt() : 0;
      if (enableNativePolling) {
        _startWireGuardPolling();
        if (_exitIp == null) {
          unawaited(refreshExitIpInfo());
        }
      }
      notifyListeners();
    }
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
      // Non-fatal if tunnel routes are still settling.
    }
  }

  void _startWireGuardPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_activeEngineProtocol != VpnProtocol.wireguard) {
        _statsTimer?.cancel();
        return;
      }
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

  static String formatBytes(int bytes) {
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
    _openVpnEngine?.dispose();
    _client.close();
    super.dispose();
  }
}
