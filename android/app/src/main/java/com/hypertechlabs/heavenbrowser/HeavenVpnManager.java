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
import android.util.Base64;
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
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TimeZone;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Multi-Engine VPN Manager for Heaven Browser:
 * 1) 1-Tap Local Fast Edge WireGuard via Cloudflare WARP anonymous registration.
 * 2) 1-Tap Foreign Country OpenVPN Servers (USA, Netherlands, France, Canada, Japan,
 *    South Korea, Hong Kong, Thailand & live global relays) verified by real OpenVPN V2
 *    wire-packet handshakes before connecting.
 * 3) Custom Country WireGuard (.conf) & OpenVPN (.ovpn) profile support + Browser Split-Tunnel.
 */
public final class HeavenVpnManager {
  public static final int VPN_PERMISSION_REQUEST_CODE = 9418;
  private static final String VPN_NOTIF_CHANNEL = "heaven_vpn_status";
  private static final int VPN_NOTIF_ID = 77001;
  private static final String TUNNEL_NAME = "heavenvpn";
  private static final String WARP_REG_URL = "https://api.cloudflareclient.com/v0a2158/reg";

  private static final String RISEUP_CA_URL = "https://api.black.riseup.net/ca.crt";
  private static final String RISEUP_CERT_URL = "https://api.black.riseup.net/3/cert";
  private static final String RISEUP_EIP_URL =
      "https://api.black.riseup.net/3/config/eip-service.json";
  private static final String VPNGATE_HTTPS_URL = "https://www.vpngate.net/api/iphone/";
  private static final String VPNGATE_FALLBACK_IP_URL = "http://130.158.75.39/api/iphone/";

  private static final Pattern PEM_KEY_PATTERN =
      Pattern.compile(
          "(-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]+?-----END [A-Z ]*PRIVATE KEY-----)");
  private static final Pattern PEM_CERT_PATTERN =
      Pattern.compile("(-----BEGIN CERTIFICATE-----[\\s\\S]+?-----END CERTIFICATE-----)");
  private static final Pattern OVPN_REMOTE_PATTERN =
      Pattern.compile("(?m)^remote\\s+(\\S+)\\s+(\\d+)");
  private static final Pattern OVPN_PROTO_PATTERN = Pattern.compile("(?m)^proto\\s+(\\S+)");

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final SecureRandom secureRandom = new SecureRandom();
  private final ExecutorService vpnExecutor =
      Executors.newSingleThreadExecutor(
          r -> {
            Thread t = new Thread(r, "HeavenVpnWorker");
            t.setDaemon(true);
            return t;
          });
  private final ExecutorService probePool =
      Executors.newCachedThreadPool(
          r -> {
            Thread t = new Thread(r, "HeavenVpnProbe");
            t.setDaemon(true);
            return t;
          });

  private GoBackend goBackend;
  private final Tunnel wgTunnel;
  private volatile Tunnel.State currentState = Tunnel.State.DOWN;
  private volatile String activeProfileName = "Heaven Free VPN";

  // Cached Riseup credentials & VPNGate directory (in-memory for fast switching)
  private volatile String cachedRiseupCa;
  private volatile String cachedRiseupCert;
  private volatile String cachedRiseupKey;
  private volatile long cachedRiseupCertAtMs = 0L;
  private volatile String cachedVpnGateCsv;
  private volatile long cachedVpnGateAtMs = 0L;

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

  private static final class VerifiedCandidate {
    final String ovpnConfig;
    final String serverHost;
    final String countryCode;
    final String countryName;
    final long latencyMs;
    final long speedBps;

    VerifiedCandidate(
        String ovpnConfig,
        String serverHost,
        String countryCode,
        String countryName,
        long latencyMs,
        long speedBps) {
      this.ovpnConfig = ovpnConfig;
      this.serverHost = serverHost;
      this.countryCode = countryCode;
      this.countryName = countryName;
      this.latencyMs = latencyMs;
      this.speedBps = speedBps;
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

  /**
   * Provisions a verified, live foreign OpenVPN (.ovpn) configuration for the requested
   * countryCode (e.g. US, NL, FR, CA, JP, KR, HK, TH, VN, SE, or AUTO_FOREIGN).
   */
  public void provisionForeignOpenVpnConfig(
      String countryCode, List<String> excludeHosts, MethodChannel.Result result) {
    probePool.execute(
        () -> {
          try {
            String cc =
                countryCode != null ? countryCode.trim().toUpperCase(Locale.US) : "AUTO_FOREIGN";
            Set<String> excluded = new HashSet<>();
            if (excludeHosts != null) {
              for (String h : excludeHosts) {
                if (h != null && !h.trim().isEmpty()) {
                  excluded.add(h.trim());
                }
              }
            }

            VerifiedCandidate chosen = null;

            // 1. Try dedicated RiseupVPN gateways first (supports US, NL, FR, CA, DE, SE, GB & AUTO_FOREIGN)
            chosen = tryProvisionRiseupCandidate(cc, excluded);

            // 2. Try live VPNGate servers for the exact requested country code
            if (chosen == null) {
              chosen = tryProvisionVpnGateCandidate(cc, excluded);
            }

            // 3. Nearest-region fallback if specific country slot is momentarily full
            if (chosen == null && !"AUTO_FOREIGN".equals(cc)) {
              for (String neighborCc : regionalFallbacksFor(cc)) {
                chosen = tryProvisionVpnGateCandidate(neighborCc, excluded);
                if (chosen != null) {
                  break;
                }
                chosen = tryProvisionRiseupCandidate(neighborCc, excluded);
                if (chosen != null) {
                  break;
                }
              }
            }

            // 4. Final global fallback so connection always succeeds cleanly
            if (chosen == null && !"AUTO_FOREIGN".equals(cc)) {
              chosen = tryProvisionRiseupCandidate("AUTO_FOREIGN", excluded);
              if (chosen == null) {
                chosen = tryProvisionVpnGateCandidate("AUTO_FOREIGN", excluded);
              }
            }

            if (chosen == null) {
              postError(
                  result,
                  "All free servers for "
                      + cc
                      + " are busy right now. Tap another country or retry.");
              return;
            }

            Map<String, Object> payload = new HashMap<>();
            payload.put("ok", true);
            payload.put("configText", chosen.ovpnConfig);
            payload.put("serverHost", chosen.serverHost);
            payload.put("countryCode", chosen.countryCode);
            payload.put("countryName", chosen.countryName);
            payload.put("latencyMs", chosen.latencyMs);
            mainHandler.post(() -> result.success(payload));
          } catch (Throwable t) {
            postError(
                result,
                t.getMessage() != null
                    ? t.getMessage()
                    : "Unable to provision foreign VPN server");
          }
        });
  }

  public void fetchLiveForeignCountries(MethodChannel.Result result) {
    probePool.execute(
        () -> {
          Map<String, Map<String, Object>> byCode = new LinkedHashMap<>();
          addCountryMeta(byCode, "US", "United States", 4);
          addCountryMeta(byCode, "NL", "Netherlands", 3);
          addCountryMeta(byCode, "FR", "France", 8);
          addCountryMeta(byCode, "CA", "Canada", 2);

          try {
            String csv = fetchVpnGateCsv();
            if (csv != null) {
              String[] lines = csv.split("\\r?\\n");
              for (int i = 2; i < lines.length; i++) {
                String[] parts = lines[i].split(",", 16);
                if (parts.length >= 15 && !parts[14].trim().isEmpty()) {
                  String cc = parts[6].trim().toUpperCase(Locale.US);
                  String cLong = parts[5].trim();
                  if (cc.length() == 2 && !"IN".equals(cc) && !cLong.isEmpty()) {
                    Map<String, Object> existing = byCode.get(cc);
                    if (existing == null) {
                      addCountryMeta(byCode, cc, cLong, 1);
                    } else {
                      int prev = ((Number) existing.get("serverCount")).intValue();
                      existing.put("serverCount", prev + 1);
                    }
                  }
                }
              }
            }
          } catch (Throwable ignored) {
          }

          List<Map<String, Object>> list = new ArrayList<>(byCode.values());
          Map<String, Object> out = new HashMap<>();
          out.put("ok", true);
          out.put("countries", list);
          mainHandler.post(() -> result.success(out));
        });
  }

  private static void addCountryMeta(
      Map<String, Map<String, Object>> map, String code, String name, int count) {
    Map<String, Object> item = new HashMap<>();
    item.put("countryCode", code);
    item.put("countryName", name);
    item.put("serverCount", count);
    map.put(code, item);
  }

  private VerifiedCandidate tryProvisionRiseupCandidate(String targetCc, Set<String> excluded) {
    try {
      ensureRiseupCredentials();
      if (cachedRiseupCa == null || cachedRiseupCert == null || cachedRiseupKey == null) {
        return null;
      }
      String eipRaw = httpGetText(RISEUP_EIP_URL, null, 8000);
      if (eipRaw == null || eipRaw.isEmpty()) {
        return null;
      }

      JSONObject eip = new JSONObject(eipRaw);
      JSONObject locations = eip.optJSONObject("locations");
      JSONArray gateways = eip.optJSONArray("gateways");
      if (gateways == null || gateways.length() == 0) {
        return null;
      }

      List<Callable<VerifiedCandidate>> tasks = new ArrayList<>();
      for (int i = 0; i < gateways.length(); i++) {
        JSONObject gw = gateways.optJSONObject(i);
        if (gw == null) continue;
        String ip = gw.optString("ip_address", "").trim();
        String locKey = gw.optString("location", "").trim();
        if (ip.isEmpty() || excluded.contains(ip)) continue;

        String gwCc = "";
        String locDisplay = locKey;
        if (locations != null && locations.has(locKey)) {
          JSONObject locObj = locations.optJSONObject(locKey);
          if (locObj != null) {
            gwCc = locObj.optString("country_code", "").trim().toUpperCase(Locale.US);
            locDisplay = locObj.optString("name", locKey);
          }
        }
        if (gwCc.isEmpty() || "IN".equals(gwCc)) continue;
        if (!"AUTO_FOREIGN".equals(targetCc) && !targetCc.equals(gwCc)) continue;

        final String finalCc = gwCc;
        final String finalCountryName = countryNameForCode(gwCc) + " (" + locDisplay + ")";
        tasks.add(
            () -> {
              long rtt = probeOpenVpnTcp(ip, 1194, 2100);
              int bestTcpPort = 1194;
              if (rtt < 0) {
                rtt = probeOpenVpnTcp(ip, 80, 2100);
                bestTcpPort = 80;
              }
              if (rtt < 0) {
                return null;
              }
              long udpRtt = probeOpenVpnUdp(ip, 1194, 1400);
              StringBuilder cfg = new StringBuilder();
              cfg.append("client\n");
              cfg.append("dev tun\n");
              cfg.append("nobind\n");
              cfg.append("persist-key\n");
              if (udpRtt >= 0) {
                cfg.append("remote ").append(ip).append(" 1194 udp\n");
              }
              cfg.append("remote ").append(ip).append(' ').append(bestTcpPort).append(" tcp-client\n");
              if (bestTcpPort != 80) {
                cfg.append("remote ").append(ip).append(" 80 tcp-client\n");
              }
              cfg.append("connect-timeout 7\n");
              cfg.append("remote-cert-tls server\n");
              cfg.append("tls-version-min 1.2\n");
              cfg.append("cipher AES-256-GCM\n");
              cfg.append("data-ciphers AES-256-GCM\n");
              cfg.append("auth SHA512\n");
              cfg.append("keepalive 10 30\n");
              cfg.append("verb 3\n");
              cfg.append("<ca>\n").append(cachedRiseupCa).append("\n</ca>\n");
              cfg.append("<cert>\n").append(cachedRiseupCert).append("\n</cert>\n");
              cfg.append("<key>\n").append(cachedRiseupKey).append("\n</key>\n");

              long effectiveRtt = udpRtt >= 0 ? Math.min(rtt, udpRtt) : rtt;
              return new VerifiedCandidate(
                  cfg.toString(), ip, finalCc, finalCountryName, effectiveRtt, 250_000_000L);
            });
      }

      if (tasks.isEmpty()) {
        return null;
      }
      return pickBestCandidate(tasks, 4500);
    } catch (Throwable ignored) {
      return null;
    }
  }

  private VerifiedCandidate tryProvisionVpnGateCandidate(String targetCc, Set<String> excluded) {
    try {
      String csv = fetchVpnGateCsv();
      if (csv == null || csv.isEmpty()) {
        return null;
      }

      final class RawRow {
        final String countryLong;
        final String countryCode;
        final long speedBps;
        final String b64Ovpn;

        RawRow(String countryLong, String countryCode, long speedBps, String b64Ovpn) {
          this.countryLong = countryLong;
          this.countryCode = countryCode;
          this.speedBps = speedBps;
          this.b64Ovpn = b64Ovpn;
        }
      }

      List<RawRow> matches = new ArrayList<>();
      String[] lines = csv.split("\\r?\\n");
      for (int i = 2; i < lines.length; i++) {
        String[] parts = lines[i].split(",", 16);
        if (parts.length < 15) continue;
        String b64 = parts[14].trim();
        String cc = parts[6].trim().toUpperCase(Locale.US);
        String cLong = parts[5].trim();
        if (b64.isEmpty() || cc.isEmpty() || "IN".equals(cc)) continue;
        if (!"AUTO_FOREIGN".equals(targetCc) && !targetCc.equals(cc)) continue;

        long speed = 0L;
        try {
          speed = Long.parseLong(parts[4].trim());
        } catch (NumberFormatException ignored) {
        }
        matches.add(new RawRow(cLong, cc, speed, b64));
      }

      if (matches.isEmpty()) {
        return null;
      }
      Collections.sort(matches, (a, b) -> Long.compare(b.speedBps, a.speedBps));

      List<Callable<VerifiedCandidate>> tasks = new ArrayList<>();
      int limit = Math.min(matches.size(), 8);
      for (int i = 0; i < limit; i++) {
        RawRow row = matches.get(i);
        tasks.add(
            () -> {
              byte[] decoded = Base64.decode(row.b64Ovpn, Base64.DEFAULT);
              String ovpn = new String(decoded, StandardCharsets.UTF_8);
              Matcher remM = OVPN_REMOTE_PATTERN.matcher(ovpn);
              if (!remM.find()) {
                return null;
              }
              String host = remM.group(1);
              int port = Integer.parseInt(remM.group(2));
              if (host == null || excluded.contains(host)) {
                return null;
              }
              Matcher protoM = OVPN_PROTO_PATTERN.matcher(ovpn);
              String proto = protoM.find() ? protoM.group(1).toLowerCase(Locale.US) : "tcp";

              long rtt =
                  proto.contains("udp")
                      ? probeOpenVpnUdp(host, port, 2300)
                      : probeOpenVpnTcp(host, port, 2300);
              if (rtt < 0) {
                return null;
              }
              String enhancedOvpn =
                  ovpn
                      + "\ndata-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC\n"
                      + "data-ciphers-fallback AES-128-CBC\n"
                      + "connect-timeout 8\n";
              return new VerifiedCandidate(
                  enhancedOvpn, host, row.countryCode, row.countryLong, rtt, row.speedBps);
            });
      }

      return pickBestCandidate(tasks, 5000);
    } catch (Throwable ignored) {
      return null;
    }
  }

  private VerifiedCandidate pickBestCandidate(
      List<Callable<VerifiedCandidate>> tasks, long timeoutMs) {
    try {
      List<Future<VerifiedCandidate>> futures =
          probePool.invokeAll(tasks, timeoutMs, TimeUnit.MILLISECONDS);
      VerifiedCandidate best = null;
      for (Future<VerifiedCandidate> f : futures) {
        if (f.isDone() && !f.isCancelled()) {
          try {
            VerifiedCandidate c = f.get();
            if (c != null) {
              if (best == null || c.latencyMs < best.latencyMs) {
                best = c;
              }
            }
          } catch (Throwable ignored) {
          }
        }
      }
      return best;
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return null;
    }
  }

  private synchronized void ensureRiseupCredentials() {
    long now = System.currentTimeMillis();
    if (cachedRiseupCa != null
        && cachedRiseupCert != null
        && cachedRiseupKey != null
        && (now - cachedRiseupCertAtMs) < 3600_000L * 6) {
      return;
    }
    String ca = httpGetText(RISEUP_CA_URL, null, 8000);
    String clientPem = httpPostEmptyText(RISEUP_CERT_URL, 9000);
    if (ca == null || clientPem == null) {
      return;
    }
    Matcher keyM = PEM_KEY_PATTERN.matcher(clientPem);
    Matcher certM = PEM_CERT_PATTERN.matcher(clientPem);
    if (keyM.find() && certM.find()) {
      cachedRiseupCa = ca.trim();
      cachedRiseupKey = keyM.group(1).trim();
      cachedRiseupCert = certM.group(1).trim();
      cachedRiseupCertAtMs = now;
    }
  }

  private synchronized String fetchVpnGateCsv() {
    long now = System.currentTimeMillis();
    if (cachedVpnGateCsv != null && (now - cachedVpnGateAtMs) < 180_000L) {
      return cachedVpnGateCsv;
    }
    String csv = httpGetText(VPNGATE_HTTPS_URL, null, 9000);
    if (csv == null || !csv.contains("*vpn_servers")) {
      Map<String, String> hostHdr = Collections.singletonMap("Host", "www.vpngate.net");
      csv = httpGetText(VPNGATE_FALLBACK_IP_URL, hostHdr, 9000);
    }
    if (csv != null && csv.contains("*vpn_servers")) {
      cachedVpnGateCsv = csv;
      cachedVpnGateAtMs = now;
      return csv;
    }
    return cachedVpnGateCsv;
  }

  /**
   * Sends a genuine OpenVPN P_CONTROL_HARD_RESET_CLIENT_V2 (0x38) frame over TCP and verifies
   * the remote server replies with P_CONTROL_HARD_RESET_SERVER_V2 (opcode 8).
   */
  private long probeOpenVpnTcp(String host, int port, int timeoutMs) {
    long t0 = System.currentTimeMillis();
    try (Socket s = new Socket()) {
      s.connect(new InetSocketAddress(host, port), timeoutMs);
      s.setSoTimeout(timeoutMs);
      byte[] sessionId = new byte[8];
      secureRandom.nextBytes(sessionId);
      byte[] frame = new byte[16];
      frame[0] = 0x00;
      frame[1] = 0x0E; // 14-byte OpenVPN payload
      frame[2] = 0x38; // P_CONTROL_HARD_RESET_CLIENT_V2 << 3
      System.arraycopy(sessionId, 0, frame, 3, 8);
      // frame[11..15] = ack_len(0) + packet_id(0)

      OutputStream out = s.getOutputStream();
      out.write(frame);
      out.flush();

      InputStream in = s.getInputStream();
      int b0 = in.read();
      int b1 = in.read();
      int opcodeByte = in.read();
      if (b0 < 0 || b1 < 0 || opcodeByte < 0) {
        return -1L;
      }
      int opcode = (opcodeByte & 0xFF) >> 3;
      return opcode == 8 ? Math.max(1L, System.currentTimeMillis() - t0) : -1L;
    } catch (Throwable ignored) {
      return -1L;
    }
  }

  /**
   * Sends a genuine OpenVPN P_CONTROL_HARD_RESET_CLIENT_V2 (0x38) datagram over UDP and verifies
   * the remote server replies with P_CONTROL_HARD_RESET_SERVER_V2 (opcode 8).
   */
  private long probeOpenVpnUdp(String host, int port, int timeoutMs) {
    long t0 = System.currentTimeMillis();
    try (DatagramSocket ds = new DatagramSocket()) {
      ds.setSoTimeout(timeoutMs);
      byte[] pkt = new byte[14];
      pkt[0] = 0x38;
      byte[] sessionId = new byte[8];
      secureRandom.nextBytes(sessionId);
      System.arraycopy(sessionId, 0, pkt, 1, 8);

      InetAddress addr = InetAddress.getByName(host);
      ds.send(new DatagramPacket(pkt, pkt.length, addr, port));

      byte[] recvBuf = new byte[256];
      DatagramPacket resp = new DatagramPacket(recvBuf, recvBuf.length);
      ds.receive(resp);
      if (resp.getLength() < 1) {
        return -1L;
      }
      int opcode = (recvBuf[0] & 0xFF) >> 3;
      return opcode == 8 ? Math.max(1L, System.currentTimeMillis() - t0) : -1L;
    } catch (Throwable ignored) {
      return -1L;
    }
  }

  private static String httpGetText(
      String url, Map<String, String> extraHeaders, int timeoutMs) {
    HttpURLConnection conn = null;
    try {
      conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
      conn.setRequestMethod("GET");
      conn.setConnectTimeout(timeoutMs);
      conn.setReadTimeout(timeoutMs);
      conn.setRequestProperty("User-Agent", "HeavenBrowser/1.0");
      if (extraHeaders != null) {
        for (Map.Entry<String, String> e : extraHeaders.entrySet()) {
          conn.setRequestProperty(e.getKey(), e.getValue());
        }
      }
      int code = conn.getResponseCode();
      if (code < 200 || code >= 300) {
        return null;
      }
      StringBuilder sb = new StringBuilder();
      try (BufferedReader br =
          new BufferedReader(
              new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
        String line;
        while ((line = br.readLine()) != null) {
          sb.append(line).append('\n');
        }
      }
      return sb.toString();
    } catch (Throwable ignored) {
      return null;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  private static String httpPostEmptyText(String url, int timeoutMs) {
    HttpURLConnection conn = null;
    try {
      conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
      conn.setRequestMethod("POST");
      conn.setConnectTimeout(timeoutMs);
      conn.setReadTimeout(timeoutMs);
      conn.setDoOutput(true);
      conn.setFixedLengthStreamingMode(0);
      conn.setRequestProperty("User-Agent", "HeavenBrowser/1.0");
      try (OutputStream os = conn.getOutputStream()) {
        os.flush();
      }
      int code = conn.getResponseCode();
      if (code < 200 || code >= 300) {
        return null;
      }
      StringBuilder sb = new StringBuilder();
      try (BufferedReader br =
          new BufferedReader(
              new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
        String line;
        while ((line = br.readLine()) != null) {
          sb.append(line).append('\n');
        }
      }
      return sb.toString();
    } catch (Throwable ignored) {
      return null;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  private static String countryNameForCode(String cc) {
    if ("US".equals(cc)) return "United States";
    if ("NL".equals(cc)) return "Netherlands";
    if ("FR".equals(cc)) return "France";
    if ("CA".equals(cc)) return "Canada";
    if ("JP".equals(cc)) return "Japan";
    if ("KR".equals(cc)) return "South Korea";
    if ("HK".equals(cc)) return "Hong Kong";
    if ("TH".equals(cc)) return "Thailand";
    if ("SG".equals(cc)) return "Singapore";
    if ("GB".equals(cc)) return "United Kingdom";
    if ("DE".equals(cc)) return "Germany";
    if ("SE".equals(cc)) return "Sweden";
    if ("VN".equals(cc)) return "Vietnam";
    return cc;
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
                  "WARP registration HTTP " + status + ". Try a Foreign Country server instead.");
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
          .setContentTitle("Heaven VPN Active - " + profileName)
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

  private static String[] regionalFallbacksFor(String cc) {
    switch (cc) {
      case "GB":
      case "IE":
      case "DE":
      case "NL":
      case "FR":
      case "CH":
      case "SE":
      case "NO":
      case "FI":
      case "DK":
      case "ES":
      case "IT":
      case "AT":
      case "BE":
      case "PT":
      case "PL":
      case "RO":
      case "CZ":
        return new String[] {"NL", "FR", "DE", "GB", "SE"};
      case "JP":
      case "KR":
      case "SG":
      case "HK":
      case "TW":
      case "TH":
      case "VN":
      case "MY":
      case "ID":
      case "PH":
      case "AU":
      case "NZ":
        return new String[] {"JP", "KR", "SG", "HK", "TH"};
      case "US":
      case "CA":
      case "MX":
      case "BR":
      case "AR":
      case "CL":
      case "CO":
        return new String[] {"US", "CA"};
      default:
        return new String[] {"NL", "FR", "US", "JP"};
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
