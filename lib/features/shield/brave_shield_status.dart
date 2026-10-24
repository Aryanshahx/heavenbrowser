/// Snapshot of Heaven's native Brave-style Shields engine counters & rule state.
///
/// Queried on demand when opening Site Controls or Settings (zero background
/// MethodChannel chatter or frame rebuilds during scrolling/browsing).
class BraveShieldStats {
  const BraveShieldStats({
    this.enabled = true,
    this.farblingEnabled = true,
    this.tabBlocked = 0,
    this.tabSurrogates = 0,
    this.tabCnameUncloaked = 0,
    this.totalBlocked = 0,
    this.totalSurrogates = 0,
    this.totalCnameUncloaked = 0,
    this.activeRuleCount = 0,
    this.lastFilterSyncMs = 0,
  });

  factory BraveShieldStats.fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) {
      return const BraveShieldStats();
    }
    int readInt(String key) {
      final Object? v = raw[key];
      return v is num ? v.toInt() : 0;
    }

    return BraveShieldStats(
      enabled: raw['enabled'] != false,
      farblingEnabled: raw['farblingEnabled'] != false,
      tabBlocked: readInt('tabBlocked'),
      tabSurrogates: readInt('tabSurrogates'),
      tabCnameUncloaked: readInt('tabCnameUncloaked'),
      totalBlocked: readInt('totalBlocked'),
      totalSurrogates: readInt('totalSurrogates'),
      totalCnameUncloaked: readInt('totalCnameUncloaked'),
      activeRuleCount: readInt('activeRuleCount'),
      lastFilterSyncMs: readInt('lastFilterSyncMs'),
    );
  }

  final bool enabled;
  final bool farblingEnabled;
  final int tabBlocked;
  final int tabSurrogates;
  final int tabCnameUncloaked;
  final int totalBlocked;
  final int totalSurrogates;
  final int totalCnameUncloaked;
  final int activeRuleCount;
  final int lastFilterSyncMs;
}
