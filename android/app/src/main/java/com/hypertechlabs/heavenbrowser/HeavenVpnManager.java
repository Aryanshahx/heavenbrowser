package com.hypertechlabs.heavenbrowser;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
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
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Option 3 Hybrid VPN Manager for Heaven Browser:
 * 1) 1-Tap Free Instant WireGuard Tunnel via Cloudflare WARP anonymous registration.
 * 2) Custom Country WireGuard .conf Profile support (ProtonVPN Free, Windscribe, custom).
 * 3) Optional Browser-Only Split Tunneling (IncludedApplications = com.hypertechlabs.heavenbrowser).
 */
public final class HeavenVpnManager {
  public static final int VPN_PERMISSION_REQUEST_CODE = 9418;
  private static final String VPN_NOTIF_CHANNEL = "heaven_vpn_status";
  private static final int VPN_NOTIF_ID = 77001;
  private static final String TUNNEL_NAME = "heavenvpn";
  private static final String WARP_REG_URL = "https://api.cloudflareclient.com/v0a2158/reg";

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final ExecutorService vpnExecutor =
      Executors.newSingleThreadExecutor(
          r -> {
            Thread t = new Thread(r, "HeavenVpnWorker");
            t.setDaemon(true);
            return t;
          });

  private GoBackend goBackend;
  private final Tunnel wgTunnel;
  private volatile Tunnel.State currentState = Tunnel.State.DOWN;
  private volatile String activeProfileName = "Heaven Free VPN";

  private PendingConnectRequest pendingConnect;

  private static final class PendingConnectRequest {
    final String configText;
    final String profileName;
    final boolean browserOnly;
    final MethodChannel.Result result;

    PendingConnectRequest(
        String configText,
        String profileName,
        boolean browserOnly,
        MethodChannel.Result result) {
      this.configText = configText;
      this.profileName = profileName;
      this.browserOnly = browserOnly;
      this.result = result;
    }
  }

  public HeavenVpnManager(Context context) {
    this.appContext = context.getApplicationContext();
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
              cancelStatusNotification();
            }
          }
        };
  }

  private synchronized GoBackend ensureBackend() {
    if (goBackend == null) {
      goBackend = new GoBackend(appContext);
    }
    return goBackend;
  }

  public void provisionFreeWarpConfig(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          HttpURLConnection conn = null;
          try {
            KeyPair keyPair = new KeyPair();
            String privateKeyB64 = keyPair.getPrivateKey().toBase64();
            String publicKeyB64 = keyPair.getPublicKey().toBase64();

            SimpleDateFormat iso =
                new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
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
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(15000);
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
              postError(
                  result,
                  "WARP registration HTTP " + status + ". Try a Custom Country .conf profile.");
              return;
            }

            JSONObject json = new JSONObject(sb.toString());
            JSONObject cfgObj = json.optJSONObject("config");
            if (cfgObj == null) {
              postError(result, "Unexpected WARP config response");
              return;
            }

            JSONObject iface = cfgObj.optJSONObject("interface");
            JSONObject addrs = iface != null ? iface.optJSONObject("addresses") : null;
            String v4 = addrs != null ? addrs.optString("v4", "172.16.0.2") : "172.16.0.2";
            String v6 = addrs != null ? addrs.optString("v6", "") : "";

            JSONArray peers = cfgObj.optJSONArray("peers");
            JSONObject peer0 = (peers != null && peers.length() > 0) ? peers.optJSONObject(0) : null;
            String peerPubKey =
                peer0 != null
                    ? peer0.optString(
                        "public_key", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=")
                    : "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";

            String endpointHost = "162.159.192.6:2408";
            if (peer0 != null) {
              JSONObject ep = peer0.optJSONObject("endpoint");
              if (ep != null) {
                String rawV4 = ep.optString("v4", "").trim();
                if (!rawV4.isEmpty()) {
                  int colon = rawV4.indexOf(':');
                  String ipOnly = colon > 0 ? rawV4.substring(0, colon) : rawV4;
                  endpointHost = ipOnly + ":2408";
                }
              }
            }

            StringBuilder wgConf = new StringBuilder();
            wgConf.append("[Interface]\n");
            wgConf.append("PrivateKey = ").append(privateKeyB64).append('\n');
            wgConf.append("Address = ").append(v4).append("/32");
            if (!v6.isEmpty()) {
              wgConf.append(", ").append(v6).append("/128");
            }
            wgConf.append('\n');
            wgConf.append("DNS = 1.1.1.1, 1.0.0.1\n");
            wgConf.append("MTU = 1280\n\n");
            wgConf.append("[Peer]\n");
            wgConf.append("PublicKey = ").append(peerPubKey).append('\n');
            wgConf.append("AllowedIPs = 0.0.0.0/0, ::/0\n");
            wgConf.append("Endpoint = ").append(endpointHost).append('\n');
            wgConf.append("PersistentKeepalive = 25\n");

            Map<String, Object> payload = new HashMap<>();
            payload.put("ok", true);
            payload.put("configText", wgConf.toString());
            payload.put("clientIpv4", v4);
            payload.put("endpoint", endpointHost);
            mainHandler.post(() -> result.success(payload));
          } catch (Throwable t) {
            postError(
                result,
                t.getMessage() != null ? t.getMessage() : "Unable to provision free VPN profile");
          } finally {
            if (conn != null) {
              conn.disconnect();
            }
          }
        });
  }

  public void validateWireGuardConfig(String configText, MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            Config parsed = parseConfig(configText, false);
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
      boolean browserOnly,
      MethodChannel.Result result) {
    if (configText == null || configText.trim().isEmpty()) {
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
          new PendingConnectRequest(configText, profileName, browserOnly, result);
      activity.startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE);
      return;
    }

    activateTunnelAsync(configText, profileName, browserOnly, result);
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
      activateTunnelAsync(req.configText, req.profileName, req.browserOnly, req.result);
    } else {
      postError(req.result, "VPN connection permission was declined");
    }
    return true;
  }

  private void activateTunnelAsync(
      String rawConfigText,
      String profileName,
      boolean browserOnly,
      MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            Config parsed = parseConfig(rawConfigText, browserOnly);
            GoBackend backend = ensureBackend();
            if (backend.getState(wgTunnel) == Tunnel.State.UP) {
              backend.setState(wgTunnel, Tunnel.State.DOWN, null);
            }
            Tunnel.State finalState = backend.setState(wgTunnel, Tunnel.State.UP, parsed);
            currentState = finalState;
            activeProfileName =
                (profileName != null && !profileName.trim().isEmpty())
                    ? profileName.trim()
                    : "Heaven Free VPN";

            if (finalState == Tunnel.State.UP) {
              showConnectedNotification(activeProfileName, browserOnly);
            }

            Map<String, Object> out = new HashMap<>();
            out.put("ok", finalState == Tunnel.State.UP);
            out.put("connected", finalState == Tunnel.State.UP);
            out.put("profileName", activeProfileName);
            mainHandler.post(() -> result.success(out));
          } catch (Throwable t) {
            currentState = Tunnel.State.DOWN;
            cancelStatusNotification();
            postError(
                result,
                t.getMessage() != null ? t.getMessage() : "Failed to establish WireGuard tunnel");
          }
        });
  }

  public void disconnectVpn(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            if (goBackend != null) {
              goBackend.setState(wgTunnel, Tunnel.State.DOWN, null);
            }
          } catch (Throwable ignored) {
            // Ensure clean state even if tunnel already stopped.
          }
          currentState = Tunnel.State.DOWN;
          cancelStatusNotification();
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
          mainHandler.post(() -> result.success(out));
        });
  }

  private Config parseConfig(String rawText, boolean browserOnly) throws Exception {
    String[] lines = rawText.replace("\r\n", "\n").split("\n");
    StringBuilder rewritten = new StringBuilder();
    boolean injectedSplitTunnel = false;

    for (String rawLine : lines) {
      String trimmed = rawLine.trim();
      String lower = trimmed.toLowerCase(Locale.US);
      if (lower.startsWith("includedapplications")
          || lower.startsWith("excludedapplications")) {
        continue;
      }
      rewritten.append(rawLine).append('\n');
      if (!injectedSplitTunnel && "[interface]".equalsIgnoreCase(trimmed) && browserOnly) {
        rewritten
            .append("IncludedApplications = ")
            .append(appContext.getPackageName())
            .append('\n');
        injectedSplitTunnel = true;
      }
    }

    byte[] bytes = rewritten.toString().getBytes(StandardCharsets.UTF_8);
    return Config.parse(new ByteArrayInputStream(bytes));
  }

  @SuppressWarnings("deprecation")
  private void showConnectedNotification(String profileName, boolean browserOnly) {
    try {
      NotificationManager nm =
          (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm == null) {
        return;
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        NotificationChannel ch =
            new NotificationChannel(
                VPN_NOTIF_CHANNEL,
                "Heaven VPN Status",
                NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Shows encrypted WireGuard VPN status");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
      }

      Intent launchIntent =
          appContext.getPackageManager().getLaunchIntentForPackage(appContext.getPackageName());
      PendingIntent pi = null;
      if (launchIntent != null) {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        pi = PendingIntent.getActivity(appContext, 7701, launchIntent, flags);
      }

      Notification.Builder builder =
          Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
              ? new Notification.Builder(appContext, VPN_NOTIF_CHANNEL)
              : new Notification.Builder(appContext);

      String scope = browserOnly ? "Browser Split-Tunnel" : "Device-Wide Tunnel";
      builder
          .setSmallIcon(android.R.drawable.ic_lock_lock)
          .setContentTitle("Heaven VPN Active \u2022 " + profileName)
          .setContentText("Encrypted WireGuard (" + scope + ")")
          .setOngoing(true);
      if (pi != null) {
        builder.setContentIntent(pi);
      }
      nm.notify(VPN_NOTIF_ID, builder.build());
    } catch (Throwable ignored) {
      // Non-fatal if notifications are suppressed by system settings.
    }
  }

  private void cancelStatusNotification() {
    try {
      NotificationManager nm =
          (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null) {
        nm.cancel(VPN_NOTIF_ID);
      }
    } catch (Throwable ignored) {
    }
  }

  private void postError(MethodChannel.Result result, String message) {
    Map<String, Object> out = new HashMap<>();
    out.put("ok", false);
    out.put("connected", false);
    out.put("error", message);
    mainHandler.post(() -> result.success(out));
  }
}
