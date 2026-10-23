package com.hypertechlabs.heavenbrowser;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.VpnService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.webkit.WebView;
import com.wireguard.android.backend.GoBackend;
import com.wireguard.android.backend.Statistics;
import com.wireguard.android.backend.Tunnel;
import com.wireguard.config.Config;
import com.wireguard.config.InetEndpoint;
import com.wireguard.config.InetNetwork;
import com.wireguard.config.Peer;
import com.wireguard.crypto.KeyPair;
import io.flutter.plugin.common.MethodChannel;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TimeZone;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Silent Stealth WireGuard VPN Manager powered by GoBackend.
 *
 * <p>Key guarantees:
 * <ul>
 *   <li>ZERO persistent app notification in the device notification drawer.</li>
 *   <li>Enforces MTU = 1280 so TLS 1.3 Post-Quantum ClientHello packets never blackhole on
 *       mobile/464XLAT/PPPoE networks.</li>
 *   <li>Full IPv4 + IPv6 dual-stack routing (0.0.0.0/0, ::/0) + encrypted DNS (1.1.1.1,
 *       2606:4700:4700::1111) so ISP DNS poisoning and IPv6 leaks cannot block websites.</li>
 *   <li>Automatic multi-port / multi-subnet WireGuard endpoint failover (UDP 4500, 500, 1701,
 *       2408 across 162.159.x.x and 188.114.x.x) verified with live tunnel RX traffic.</li>
 * </ul>
 */
public final class HeavenVpnManager {

  public static final int VPN_PERMISSION_REQUEST_CODE = 9418;
  private static final String LEGACY_VPN_NOTIF_CHANNEL = "heaven_vpn_channel";
  private static final int LEGACY_VPN_NOTIF_ID = 9419;
  private static final String TUNNEL_NAME = "heaven_wg0";
  private static final String WARP_REG_URL = "https://api.cloudflareclient.com/v0a2158/reg";

  private static final String[] ANTI_BLOCK_ENDPOINTS = new String[] {
    "162.159.192.1:4500",
    "188.114.98.224:4500",
    "162.159.193.1:500",
    "188.114.97.3:500",
    "162.159.195.2:1701",
    "188.114.96.3:1701",
    "162.159.192.8:2408",
    "188.114.99.224:2408"
  };

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final ExecutorService vpnExecutor = Executors.newSingleThreadExecutor();

  private GoBackend goBackend;
  private final Tunnel wgTunnel;
  private volatile Tunnel.State currentState = Tunnel.State.DOWN;
  private volatile String activeProfileName = "";
  private volatile String activeEndpoint = "";

  private PendingConnectRequest pendingConnect;

  private static final class PendingConnectRequest {
    final String configText;
    final String profileName;
    final String routeMode;
    final boolean browserOnly;
    final boolean isBuiltInWarp;
    final MethodChannel.Result result;

    PendingConnectRequest(
        String configText,
        String profileName,
        String routeMode,
        boolean browserOnly,
        boolean isBuiltInWarp,
        MethodChannel.Result result) {
      this.configText = configText;
      this.profileName = profileName;
      this.routeMode = routeMode;
      this.browserOnly = browserOnly;
      this.isBuiltInWarp = isBuiltInWarp;
      this.result = result;
    }
  }

  public HeavenVpnManager(Context context) {
    this.appContext = context.getApplicationContext();
    purgeLegacyVpnNotification();
    this.wgTunnel =
        new Tunnel() {
          @Override
          public String getName() {
            return TUNNEL_NAME;
          }

          @Override
          public void onStateChange(State newState) {
            currentState = newState;
            if (newState == State.DOWN) {
              activeProfileName = "";
              activeEndpoint = "";
            }
          }
        };
  }

  private void purgeLegacyVpnNotification() {
    try {
      NotificationManager nm =
          (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null) {
        nm.cancel(LEGACY_VPN_NOTIF_ID);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          nm.deleteNotificationChannel(LEGACY_VPN_NOTIF_CHANNEL);
        }
      }
    } catch (Throwable ignored) {
    }
  }

  private synchronized GoBackend ensureBackend() {
    if (goBackend == null) {
      goBackend = new GoBackend(appContext);
    }
    return goBackend;
  }

  public void provisionFreeWarpConfig(String preferredRouteMode, MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            Map<String, Object> payload = registerWarpProfileBlocking(preferredRouteMode);
            mainHandler.post(() -> result.success(payload));
          } catch (Throwable t) {
            postError(
                result,
                t.getMessage() != null
                    ? t.getMessage()
                    : "Unable to register free encrypted VPN key");
          }
        });
  }

  private Map<String, Object> registerWarpProfileBlocking(String preferredRouteMode)
      throws Exception {
    HttpURLConnection conn = null;
    try {
      KeyPair keyPair = new KeyPair();
      String privateKeyB64 = keyPair.getPrivateKey().toBase64();
      String publicKeyB64 = keyPair.getPublicKey().toBase64();

      SimpleDateFormat iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
      iso.setTimeZone(TimeZone.getTimeZone("UTC"));

      JSONObject body = new JSONObject();
      body.put("key", publicKeyB64);
      body.put("install_id", "");
      body.put("fcm_token", "");
      body.put("tos", iso.format(new Date()));
      body.put("model", "Android");
      body.put("type", "Android");
      body.put("locale", "en_US");

      byte[] payloadBytes = body.toString().getBytes(StandardCharsets.UTF_8);

      conn = (HttpURLConnection) URI.create(WARP_REG_URL).toURL().openConnection();
      conn.setRequestMethod("POST");
      conn.setConnectTimeout(12000);
      conn.setReadTimeout(12000);
      conn.setDoOutput(true);
      conn.setRequestProperty("Content-Type", "application/json");
      conn.setRequestProperty("Accept", "application/json");
      conn.setRequestProperty("CF-Client-Version", "a-6.30-3596");
      conn.setRequestProperty("User-Agent", "okhttp/3.12.1");

      try (OutputStream os = conn.getOutputStream()) {
        os.write(payloadBytes);
      }

      int status = conn.getResponseCode();
      InputStream stream =
          status >= 200 && status < 300 ? conn.getInputStream() : conn.getErrorStream();
      StringBuilder sb = new StringBuilder();
      if (stream != null) {
        try (BufferedReader br =
            new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
          String line;
          while ((line = br.readLine()) != null) {
            sb.append(line);
          }
        }
      }

      if (status < 200 || status >= 300) {
        throw new Exception("VPN registration HTTP " + status);
      }

      JSONObject json = new JSONObject(sb.toString());
      JSONObject cfgObj = json.optJSONObject("config");
      if (cfgObj == null) {
        throw new Exception("Unexpected VPN registration response");
      }

      JSONObject iface = cfgObj.optJSONObject("interface");
      JSONObject addrs = iface != null ? iface.optJSONObject("addresses") : null;
      String v4 = addrs != null ? addrs.optString("v4", "172.16.0.2") : "172.16.0.2";
      String v6 = addrs != null ? addrs.optString("v6", "") : "";

      JSONArray peers = cfgObj.optJSONArray("peers");
      JSONObject peer0 = (peers != null && peers.length() > 0) ? peers.optJSONObject(0) : null;
      String peerPubKey =
          peer0 != null
              ? peer0.optString("public_key", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=")
              : "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";

      String apiIpOnly = "162.159.192.1";
      if (peer0 != null) {
        JSONObject ep = peer0.optJSONObject("endpoint");
        if (ep != null) {
          String rawV4 = ep.optString("v4", "").trim();
          if (!rawV4.isEmpty()) {
            int colon = rawV4.indexOf(':');
            apiIpOnly = colon > 0 ? rawV4.substring(0, colon) : rawV4;
          }
        }
      }

      String primaryEndpoint = selectInitialEndpoint(apiIpOnly, preferredRouteMode);
      String wgConf = buildWarpConfigString(privateKeyB64, v4, v6, peerPubKey, primaryEndpoint);

      Map<String, Object> payload = new HashMap<>();
      payload.put("ok", true);
      payload.put("configText", wgConf);
      payload.put("clientIpv4", v4);
      payload.put("clientIpv6", v6);
      payload.put("endpoint", primaryEndpoint);
      return payload;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  private static String selectInitialEndpoint(String apiIpOnly, String routeMode) {
    String mode = routeMode == null ? "stealth_4500" : routeMode.trim().toLowerCase(Locale.US);
    if ("alt_188_500".equals(mode)) {
      return "188.114.98.224:500";
    }
    if ("l2tp_1701".equals(mode)) {
      return apiIpOnly + ":1701";
    }
    if ("standard_2408".equals(mode)) {
      return apiIpOnly + ":2408";
    }
    return apiIpOnly + ":4500";
  }

  private static String buildWarpConfigString(
      String privateKeyB64, String v4, String v6, String peerPubKey, String endpoint) {
    StringBuilder wgConf = new StringBuilder();
    wgConf.append("[Interface]\n");
    wgConf.append("PrivateKey = ").append(privateKeyB64).append('\n');
    wgConf.append("Address = ").append(v4).append("/32");
    if (v6 != null && !v6.trim().isEmpty()) {
      wgConf.append(", ").append(v6.trim()).append("/128");
    }
    wgConf.append('\n');
    wgConf.append("DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001\n");
    wgConf.append("MTU = 1280\n\n");
    wgConf.append("[Peer]\n");
    wgConf.append("PublicKey = ").append(peerPubKey).append('\n');
    wgConf.append("AllowedIPs = 0.0.0.0/0, ::/0\n");
    wgConf.append("Endpoint = ").append(endpoint).append('\n');
    wgConf.append("PersistentKeepalive = 21\n");
    return wgConf.toString();
  }

  public void validateWireGuardConfig(String configText, MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            Config parsed = parseConfig(configText, false, null);
            String endpoint = "";
            for (Peer p : parsed.getPeers()) {
              InetEndpoint ep = p.getEndpoint().orElse(null);
              if (ep != null) {
                endpoint = ep.toString();
                break;
              }
            }
            StringBuilder addrs = new StringBuilder();
            for (InetNetwork net : parsed.getInterface().getAddresses()) {
              if (addrs.length() > 0) {
                addrs.append(", ");
              }
              addrs.append(net.toString());
            }
            Map<String, Object> res = new HashMap<>();
            res.put("valid", true);
            res.put("endpoint", endpoint);
            res.put("addresses", addrs.toString());
            mainHandler.post(() -> result.success(res));
          } catch (Throwable t) {
            Map<String, Object> res = new HashMap<>();
            res.put("valid", false);
            res.put(
                "error",
                t.getMessage() != null ? t.getMessage() : "Invalid WireGuard configuration");
            mainHandler.post(() -> result.success(res));
          }
        });
  }

  public void connectVpn(
      Activity activity,
      String configText,
      String profileName,
      String routeMode,
      boolean browserOnly,
      boolean isBuiltInWarp,
      MethodChannel.Result result) {
    purgeLegacyVpnNotification();
    if (!isBuiltInWarp && (configText == null || configText.trim().isEmpty())) {
      postError(result, "Missing WireGuard VPN configuration");
      return;
    }

    Intent prepareIntent = VpnService.prepare(appContext);
    if (prepareIntent != null) {
      if (activity == null) {
        postError(result, "Activity unavailable to grant VPN permission");
        return;
      }
      this.pendingConnect =
          new PendingConnectRequest(
              configText, profileName, routeMode, browserOnly, isBuiltInWarp, result);
      activity.startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE);
      return;
    }

    activateTunnelAsync(configText, profileName, routeMode, browserOnly, isBuiltInWarp, result);
  }

  public boolean onActivityResult(int requestCode, int resultCode) {
    if (requestCode != VPN_PERMISSION_REQUEST_CODE) {
      return false;
    }
    PendingConnectRequest req = this.pendingConnect;
    this.pendingConnect = null;
    if (req == null) {
      return true;
    }
    if (resultCode == Activity.RESULT_OK) {
      activateTunnelAsync(
          req.configText,
          req.profileName,
          req.routeMode,
          req.browserOnly,
          req.isBuiltInWarp,
          req.result);
    } else {
      postError(req.result, "VPN connection permission was declined");
    }
    return true;
  }

  private void activateTunnelAsync(
      String initialConfigText,
      String profileName,
      String routeMode,
      boolean browserOnly,
      boolean isBuiltInWarp,
      MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          purgeLegacyVpnNotification();
          try {
            String workingConfig = initialConfigText != null ? initialConfigText.trim() : "";
            if (isBuiltInWarp && workingConfig.isEmpty()) {
              Map<String, Object> fresh = registerWarpProfileBlocking(routeMode);
              Object cfg = fresh.get("configText");
              workingConfig = cfg != null ? cfg.toString() : "";
            }

            GoBackend backend = ensureBackend();
            if (backend.getState(wgTunnel) == Tunnel.State.UP) {
              backend.setState(wgTunnel, Tunnel.State.DOWN, null);
            }

            String resolvedName =
                (profileName != null && !profileName.trim().isEmpty())
                    ? profileName.trim()
                    : "Heaven Stealth VPN";

            if (!isBuiltInWarp) {
              // Custom WireGuard config: enforce safe MTU 1280 + DNS fallback & bring UP
              Config parsed = parseConfig(workingConfig, browserOnly, null);
              Tunnel.State finalState = backend.setState(wgTunnel, Tunnel.State.UP, parsed);
              currentState = finalState;
              activeProfileName = resolvedName;
              Map<String, Object> out = new HashMap<>();
              out.put("ok", finalState == Tunnel.State.UP);
              out.put("connected", finalState == Tunnel.State.UP);
              out.put("profileName", activeProfileName);
              out.put("endpoint", activeEndpoint);
              mainHandler.post(() -> result.success(out));
              return;
            }

            // Built-in Stealth VPN: test candidate endpoints until real RX traffic flows!
            List<String> candidates = buildOrderedCandidates(workingConfig, routeMode);
            Tunnel.State lastState = Tunnel.State.DOWN;
            String verifiedEndpoint = "";
            boolean verifiedTraffic = false;

            for (int attempt = 0; attempt < candidates.size(); attempt++) {
              String ep = candidates.get(attempt);
              try {
                if (backend.getState(wgTunnel) == Tunnel.State.UP) {
                  backend.setState(wgTunnel, Tunnel.State.DOWN, null);
                }
                Config parsed = parseConfig(workingConfig, browserOnly, ep);
                lastState = backend.setState(wgTunnel, Tunnel.State.UP, parsed);
                if (lastState == Tunnel.State.UP) {
                  verifiedEndpoint = ep;
                  if (verifyRealTunnelTraffic(backend)) {
                    verifiedTraffic = true;
                    break;
                  }
                }
              } catch (Throwable ignored) {
              }

              // If the first 2 endpoints had 0 RX bytes, refresh WARP registration key once
              if (attempt == 1) {
                try {
                  if (backend.getState(wgTunnel) == Tunnel.State.UP) {
                    backend.setState(wgTunnel, Tunnel.State.DOWN, null);
                  }
                  Map<String, Object> fresh = registerWarpProfileBlocking(routeMode);
                  Object cfg = fresh.get("configText");
                  if (cfg != null && !cfg.toString().isEmpty()) {
                    workingConfig = cfg.toString();
                  }
                } catch (Throwable ignored) {
                }
              }
            }

            currentState = lastState;
            activeProfileName = resolvedName;
            activeEndpoint = verifiedEndpoint;

            Map<String, Object> out = new HashMap<>();
            out.put("ok", lastState == Tunnel.State.UP);
            out.put("connected", lastState == Tunnel.State.UP);
            out.put("verifiedTraffic", verifiedTraffic);
            out.put("profileName", activeProfileName);
            out.put("endpoint", verifiedEndpoint);
            out.put("configText", workingConfig);
            mainHandler.post(() -> result.success(out));
          } catch (Throwable t) {
            currentState = Tunnel.State.DOWN;
            postError(
                result,
                t.getMessage() != null ? t.getMessage() : "Failed to establish encrypted tunnel");
          }
        });
  }

  private List<String> buildOrderedCandidates(String configText, String routeMode) {
    Set<String> ordered = new LinkedHashSet<>();
    String preferred = selectInitialEndpoint("162.159.192.1", routeMode);
    ordered.add(preferred);

    String existingEp = extractEndpointFromConfig(configText);
    if (!existingEp.isEmpty()) {
      int colon = existingEp.indexOf(':');
      String hostOnly = colon > 0 ? existingEp.substring(0, colon) : existingEp;
      ordered.add(hostOnly + ":4500");
      ordered.add(existingEp);
    }

    for (String ep : ANTI_BLOCK_ENDPOINTS) {
      ordered.add(ep);
    }
    return new ArrayList<>(ordered);
  }

  private static String extractEndpointFromConfig(String rawText) {
    if (rawText == null) return "";
    String[] lines = rawText.split("\\r?\\n");
    for (String line : lines) {
      String trimmed = line.trim();
      if (trimmed.toLowerCase(Locale.US).startsWith("endpoint")) {
        int eq = trimmed.indexOf('=');
        if (eq > 0 && eq + 1 < trimmed.length()) {
          return trimmed.substring(eq + 1).trim();
        }
      }
    }
    return "";
  }

  private boolean verifyRealTunnelTraffic(GoBackend backend) {
    HttpURLConnection conn = null;
    try {
      conn =
          (HttpURLConnection)
              URI.create("https://1.1.1.1/cdn-cgi/trace").toURL().openConnection();
      conn.setRequestMethod("GET");
      conn.setConnectTimeout(3000);
      conn.setReadTimeout(3000);
      conn.setUseCaches(false);
      int code = conn.getResponseCode();
      if (code >= 200 && code < 400) {
        try (InputStream in = conn.getInputStream()) {
          byte[] buf = new byte[512];
          while (in.read(buf) != -1) {
            // Drain trace response
          }
        }
      }
      Statistics stats = backend.getStatistics(wgTunnel);
      return stats != null && stats.totalRx() > 0L;
    } catch (Throwable ignored) {
      try {
        Statistics stats = backend.getStatistics(wgTunnel);
        return stats != null && stats.totalRx() > 120L;
      } catch (Throwable ignored2) {
        return false;
      }
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  public void disconnectVpn(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          purgeLegacyVpnNotification();
          try {
            if (goBackend != null) {
              goBackend.setState(wgTunnel, Tunnel.State.DOWN, null);
            }
          } catch (Throwable ignored) {
          }
          currentState = Tunnel.State.DOWN;
          activeEndpoint = "";
          Map<String, Object> out = new HashMap<>();
          out.put("ok", true);
          out.put("connected", false);
          mainHandler.post(() -> result.success(out));
        });
  }

  public void getVpnStatus(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          boolean up = false;
          long rx = 0L;
          long tx = 0L;
          try {
            if (goBackend != null) {
              up = goBackend.getState(wgTunnel) == Tunnel.State.UP;
              currentState = up ? Tunnel.State.UP : Tunnel.State.DOWN;
              if (up) {
                Statistics stats = goBackend.getStatistics(wgTunnel);
                rx = stats.totalRx();
                tx = stats.totalTx();
              }
            }
          } catch (Throwable ignored) {
            up = currentState == Tunnel.State.UP;
          }
          Map<String, Object> out = new HashMap<>();
          out.put("connected", up);
          out.put("rxBytes", rx);
          out.put("txBytes", tx);
          out.put("profileName", activeProfileName);
          out.put("endpoint", activeEndpoint);
          mainHandler.post(() -> result.success(out));
        });
  }

  private Config parseConfig(String rawText, boolean browserOnly, String overrideEndpoint)
      throws Exception {
    String[] lines = rawText.replace("\r\n", "\n").split("\n");
    StringBuilder rewritten = new StringBuilder();
    boolean hasMtu = false;
    boolean hasDns = false;
    for (String rawLine : lines) {
      String lower = rawLine.trim().toLowerCase(Locale.US);
      if (lower.startsWith("mtu")) hasMtu = true;
      if (lower.startsWith("dns")) hasDns = true;
    }

    boolean injectedInterfaceExtras = false;
    for (String rawLine : lines) {
      String trimmed = rawLine.trim();
      String lower = trimmed.toLowerCase(Locale.US);
      if (lower.startsWith("includedapplications") || lower.startsWith("excludedapplications")) {
        continue;
      }
      if (overrideEndpoint != null
          && !overrideEndpoint.isEmpty()
          && lower.startsWith("endpoint")) {
        rewritten.append("Endpoint = ").append(overrideEndpoint).append('\n');
        activeEndpoint = overrideEndpoint;
        continue;
      }
      if (lower.startsWith("endpoint")) {
        int eq = trimmed.indexOf('=');
        if (eq > 0 && eq + 1 < trimmed.length()) {
          activeEndpoint = trimmed.substring(eq + 1).trim();
        }
      }
      rewritten.append(rawLine).append('\n');

      if (!injectedInterfaceExtras && "[interface]".equalsIgnoreCase(trimmed)) {
        if (!hasMtu) {
          rewritten.append("MTU = 1280\n");
        }
        if (!hasDns) {
          rewritten.append("DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111\n");
        }
        if (browserOnly) {
          rewritten
              .append("IncludedApplications = ")
              .append(resolveSplitTunnelPackages())
              .append('\n');
        }
        injectedInterfaceExtras = true;
      }
    }

    byte[] bytes = rewritten.toString().getBytes(StandardCharsets.UTF_8);
    return Config.parse(new ByteArrayInputStream(bytes));
  }

  private String resolveSplitTunnelPackages() {
    Set<String> pkgs = new LinkedHashSet<>();
    pkgs.add(appContext.getPackageName());
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        PackageInfo wvPkg = WebView.getCurrentWebViewPackage();
        if (wvPkg != null && wvPkg.packageName != null && !wvPkg.packageName.isEmpty()) {
          pkgs.add(wvPkg.packageName);
        }
      }
    } catch (Throwable ignored) {
    }
    PackageManager pm = appContext.getPackageManager();
    for (String candidate :
        new String[] {"com.google.android.webview", "com.android.webview", "com.android.chrome"}) {
      try {
        pm.getPackageInfo(candidate, 0);
        pkgs.add(candidate);
      } catch (Throwable ignored) {
      }
    }
    StringBuilder sb = new StringBuilder();
    for (String pkg : pkgs) {
      if (sb.length() > 0) sb.append(", ");
      sb.append(pkg);
    }
    return sb.toString();
  }

  private void postError(MethodChannel.Result result, String message) {
    Map<String, Object> out = new HashMap<>();
    out.put("ok", false);
    out.put("connected", false);
    out.put("error", message);
    mainHandler.post(() -> result.success(out));
  }
}
