package com.hypertechlabs.heavenbrowser;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import javax.net.SocketFactory;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SNIHostName;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Dual-stack Happy Eyeballs (IPv6-first + IPv4 fallback + DoH DNS recovery + physical non-VPN
 * network bypass) networking engine for Android.
 *
 * <p>Android's built-in HttpURLConnectionImpl connects its plain TCP socket BEFORE invoking
 * SSLSocketFactory, causing 12000ms timeouts to IPv4 (e.g. 142.250.67.14:443) over synthetic
 * /192.0.0.2 RFC 6877 464XLAT CLAT interfaces on IPv6-only 5G carriers (Jio / Airtel) or half-open
 * VPN routes. Connecting the raw Socket directly to Inet6Address first completely bypasses CLAT.
 */
public final class HeavenNetHelper {

  private static final int PER_ADDRESS_CONNECT_MS = 3400;
  private static final int SOCKET_READ_TIMEOUT_MS = 22000;

  private HeavenNetHelper() {}

  /**
   * Downloads binary payload (such as a Chrome .crx package or site icon) following HTTP redirects
   * using direct Happy-Eyeballs IPv6-first TLS sockets, bypassing Android HttpURLConnection's
   * IPv4-first /192.0.0.2 CLAT hang.
   */
  public static byte[] downloadBytesFollowingRedirects(
      Context context,
      String initialUrl,
      String userAgent,
      boolean preferPhysicalNonVpn,
      int maxRedirects,
      int maxBytes)
      throws IOException {
    Network boundNet = preferPhysicalNonVpn ? findBestPhysicalNonVpnNetwork(context) : null;
    String current = initialUrl;

    for (int hop = 0; hop <= maxRedirects; hop++) {
      URI uri = URI.create(current);
      String scheme = uri.getScheme() != null ? uri.getScheme().toLowerCase(Locale.US) : "https";
      boolean isHttps = "https".equals(scheme);
      if (!isHttps && !"http".equals(scheme)) {
        throw new IOException("Unsupported URL scheme: " + scheme);
      }
      String host = uri.getHost();
      if (host == null || host.isEmpty()) {
        throw new IOException("Missing host in URL: " + current);
      }
      int port = uri.getPort() > 0 ? uri.getPort() : (isHttps ? 443 : 80);
      String rawPath = uri.getRawPath();
      if (rawPath == null || rawPath.isEmpty()) {
        rawPath = "/";
      }
      String rawQuery = uri.getRawQuery();
      String requestTarget =
          (rawQuery != null && !rawQuery.isEmpty()) ? (rawPath + "?" + rawQuery) : rawPath;
      String hostHeader =
          (uri.getPort() > 0 && uri.getPort() != (isHttps ? 443 : 80))
              ? (host + ":" + port)
              : host;

      try (Socket sock = openDualStackSocket(host, port, isHttps, boundNet)) {
        sock.setSoTimeout(SOCKET_READ_TIMEOUT_MS);
        OutputStream out = sock.getOutputStream();
        String req =
            "GET "
                + requestTarget
                + " HTTP/1.1\r\n"
                + "Host: "
                + hostHeader
                + "\r\n"
                + "User-Agent: "
                + (userAgent != null && !userAgent.isEmpty()
                    ? userAgent
                    : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                        + "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36")
                + "\r\n"
                + "Accept: */*\r\n"
                + "Accept-Encoding: identity\r\n"
                + "Connection: close\r\n\r\n";
        out.write(req.getBytes(StandardCharsets.ISO_8859_1));
        out.flush();

        BufferedInputStream in = new BufferedInputStream(sock.getInputStream(), 32768);
        String statusLine = readHeaderLine(in);
        if (statusLine == null || !statusLine.startsWith("HTTP/")) {
          throw new IOException("Invalid HTTP response from " + host);
        }
        int status = parseHttpStatusCode(statusLine);
        Map<String, String> headers = new HashMap<>(16);
        while (true) {
          String line = readHeaderLine(in);
          if (line == null || line.isEmpty()) {
            break;
          }
          int colon = line.indexOf(':');
          if (colon > 0) {
            String k = line.substring(0, colon).trim().toLowerCase(Locale.US);
            String v = line.substring(colon + 1).trim();
            headers.put(k, v);
          }
        }

        if (status >= 300 && status < 400) {
          String loc = headers.get("location");
          if (loc == null || loc.isEmpty()) {
            throw new IOException("Redirect HTTP " + status + " missing Location header");
          }
          current = uri.resolve(loc).toString();
          continue;
        }
        if (status != 200) {
          throw new IOException("HTTP " + status + " from " + host);
        }

        String te = headers.get("transfer-encoding");
        boolean chunked = te != null && te.toLowerCase(Locale.US).contains("chunked");
        long contentLen = -1L;
        String clStr = headers.get("content-length");
        if (clStr != null && !clStr.isEmpty()) {
          try {
            contentLen = Long.parseLong(clStr.trim());
          } catch (NumberFormatException ignored) {
          }
        }
        if (contentLen > maxBytes) {
          throw new IOException("Package exceeds safety limit (" + contentLen + " bytes)");
        }

        if (chunked) {
          return readChunkedBody(in, maxBytes);
        }
        return readFixedOrEofBody(in, contentLen, maxBytes);
      }
    }
    throw new IOException("Too many redirects while downloading package");
  }

  public static HttpURLConnection openRobustConnection(
      Context context,
      URI uri,
      boolean preferPhysicalNonVpn,
      int connectTimeoutMs,
      int readTimeoutMs)
      throws IOException {
    URL url = uri.toURL();
    Network boundNet = preferPhysicalNonVpn ? findBestPhysicalNonVpnNetwork(context) : null;
    HttpURLConnection conn =
        boundNet != null
            ? (HttpURLConnection) boundNet.openConnection(url)
            : (HttpURLConnection) url.openConnection();
    conn.setConnectTimeout(connectTimeoutMs);
    conn.setReadTimeout(readTimeoutMs);
    return conn;
  }

  @SuppressWarnings("deprecation")
  public static Network findBestPhysicalNonVpnNetwork(Context context) {
    if (context == null) {
      return null;
    }
    try {
      ConnectivityManager cm =
          (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
      if (cm == null) {
        return null;
      }
      Network active = cm.getActiveNetwork();
      if (active != null) {
        NetworkCapabilities activeCaps = cm.getNetworkCapabilities(active);
        if (activeCaps != null
            && !activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            && activeCaps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
          return active;
        }
      }
      Network bestWifi = null;
      Network bestCell = null;
      Network bestOther = null;
      Network[] all = cm.getAllNetworks();
      if (all == null) {
        return null;
      }
      for (Network net : all) {
        if (net == null) {
          continue;
        }
        NetworkCapabilities caps = cm.getNetworkCapabilities(net);
        if (caps == null) {
          continue;
        }
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
          continue;
        }
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
          continue;
        }
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
          bestWifi = net;
        } else if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
          bestCell = net;
        } else {
          bestOther = net;
        }
      }
      if (bestWifi != null) {
        return bestWifi;
      }
      if (bestCell != null) {
        return bestCell;
      }
      return bestOther;
    } catch (Throwable ignored) {
      return null;
    }
  }

  private static Socket openDualStackSocket(
      String host, int port, boolean tls, Network boundNet) throws IOException {
    List<InetAddress> candidates = resolveDualStackAddresses(host, boundNet);
    SSLSocketFactory sslFactory = HttpsURLConnection.getDefaultSSLSocketFactory();
    SocketFactory plainFactory =
        boundNet != null ? boundNet.getSocketFactory() : SocketFactory.getDefault();

    IOException lastError = null;
    for (InetAddress addr : candidates) {
      Socket raw = null;
      try {
        raw = plainFactory.createSocket();
        raw.connect(new InetSocketAddress(addr, port), PER_ADDRESS_CONNECT_MS);
        raw.setSoTimeout(SOCKET_READ_TIMEOUT_MS);
        if (!tls) {
          return raw;
        }
        SSLSocket ssl = (SSLSocket) sslFactory.createSocket(raw, host, port, true);
        configureHttpsTlsAndSni(ssl, host);
        ssl.startHandshake();
        return ssl;
      } catch (IOException ioe) {
        lastError = ioe;
        if (raw != null) {
          try {
            raw.close();
          } catch (Throwable ignored) {
          }
        }
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw new IOException("Unable to connect to " + host + ":" + port);
  }

  private static List<InetAddress> resolveDualStackAddresses(String host, Network boundNet)
      throws IOException {
    List<InetAddress> v6 = new ArrayList<>(4);
    List<InetAddress> v4 = new ArrayList<>(4);
    Set<String> seen = new LinkedHashSet<>();

    try {
      InetAddress[] sys =
          boundNet != null ? boundNet.getAllByName(host) : InetAddress.getAllByName(host);
      if (sys != null) {
        for (InetAddress addr : sys) {
          if (addr != null && seen.add(addr.getHostAddress())) {
            if (addr instanceof Inet6Address) {
              v6.add(addr);
            } else if (addr instanceof Inet4Address) {
              v4.add(addr);
            }
          }
        }
      }
    } catch (Throwable ignored) {
    }

    // If system DNS omitted AAAA records or failed, query DoH so native IPv6 carriers bypass CLAT!
    if (v6.isEmpty()) {
      resolveViaDoh(host, 28, v6, v4, seen);
    }
    if (v4.isEmpty()) {
      resolveViaDoh(host, 1, v6, v4, seen);
    }

    List<InetAddress> ordered = new ArrayList<>(v6.size() + v4.size());
    ordered.addAll(v6);
    ordered.addAll(v4);
    if (ordered.isEmpty()) {
      throw new IOException("Unable to resolve DNS for " + host);
    }
    return ordered;
  }

  private static void resolveViaDoh(
      String host,
      int dnsType,
      List<InetAddress> v6,
      List<InetAddress> v4,
      Set<String> seen) {
    String encodedHost = URLEncoder.encode(host, StandardCharsets.UTF_8);
    String[] resolverIps = {"2606:4700:4700::1111", "2001:4860:4860::8888", "1.1.1.1", "8.8.8.8"};
    SSLSocketFactory sslFactory = HttpsURLConnection.getDefaultSSLSocketFactory();

    for (String ipLiteral : resolverIps) {
      Socket raw = null;
      try {
        InetAddress dnsAddr = InetAddress.getByName(ipLiteral);
        raw = new Socket();
        raw.connect(new InetSocketAddress(dnsAddr, 443), 1800);
        raw.setSoTimeout(2200);
        String sniHost =
            ipLiteral.contains("4700") || ipLiteral.startsWith("1.1.")
                ? "cloudflare-dns.com"
                : "dns.google";
        String pathPrefix = sniHost.equals("cloudflare-dns.com") ? "/dns-query" : "/resolve";
        SSLSocket ssl = (SSLSocket) sslFactory.createSocket(raw, sniHost, 443, true);
        configureHttpsTlsAndSni(ssl, sniHost);
        ssl.startHandshake();
        String req =
            "GET "
                + pathPrefix
                + "?name="
                + encodedHost
                + "&type="
                + dnsType
                + " HTTP/1.1\r\n"
                + "Host: "
                + sniHost
                + "\r\n"
                + "Accept: application/dns-json\r\n"
                + "Connection: close\r\n\r\n";
        ssl.getOutputStream().write(req.getBytes(StandardCharsets.ISO_8859_1));
        ssl.getOutputStream().flush();

        BufferedInputStream in = new BufferedInputStream(ssl.getInputStream(), 4096);
        String statusLine = readHeaderLine(in);
        if (statusLine == null || parseHttpStatusCode(statusLine) != 200) {
          ssl.close();
          continue;
        }
        boolean chunked = false;
        long cl = -1L;
        while (true) {
          String h = readHeaderLine(in);
          if (h == null || h.isEmpty()) {
            break;
          }
          String lower = h.toLowerCase(Locale.US);
          if (lower.startsWith("transfer-encoding:") && lower.contains("chunked")) {
            chunked = true;
          } else if (lower.startsWith("content-length:")) {
            try {
              cl = Long.parseLong(h.substring(15).trim());
            } catch (NumberFormatException ignored) {
            }
          }
        }
        byte[] bodyBytes = chunked ? readChunkedBody(in, 65536) : readFixedOrEofBody(in, cl, 65536);
        ssl.close();
        JSONObject json = new JSONObject(new String(bodyBytes, StandardCharsets.UTF_8));
        JSONArray answers = json.optJSONArray("Answer");
        if (answers == null) {
          return;
        }
        for (int i = 0; i < answers.length(); i++) {
          JSONObject rec = answers.optJSONObject(i);
          if (rec == null) {
            continue;
          }
          int rtype = rec.optInt("type", 0);
          String data = rec.optString("data", "").trim();
          if ((rtype == 28 || rtype == 1) && !data.isEmpty()) {
            InetAddress parsed = InetAddress.getByName(data);
            if (seen.add(parsed.getHostAddress())) {
              if (parsed instanceof Inet6Address) {
                v6.add(parsed);
              } else if (parsed instanceof Inet4Address) {
                v4.add(parsed);
              }
            }
          }
        }
        return;
      } catch (Throwable ignored) {
        if (raw != null) {
          try {
            raw.close();
          } catch (Throwable ignoredClose) {
          }
        }
      }
    }
  }

  private static String readHeaderLine(InputStream in) throws IOException {
    ByteArrayOutputStream bos = new ByteArrayOutputStream(128);
    int prev = -1;
    int b;
    while ((b = in.read()) != -1) {
      if (b == '\n') {
        byte[] bytes = bos.toByteArray();
        int len = (prev == '\r' && bytes.length > 0) ? bytes.length - 1 : bytes.length;
        return new String(bytes, 0, len, StandardCharsets.ISO_8859_1);
      }
      prev = b;
      bos.write(b);
      if (bos.size() > 16384) {
        throw new IOException("HTTP header line too long");
      }
    }
    if (bos.size() == 0) {
      return null;
    }
    return new String(bos.toByteArray(), StandardCharsets.ISO_8859_1);
  }

  private static int parseHttpStatusCode(String statusLine) throws IOException {
    int sp1 = statusLine.indexOf(' ');
    if (sp1 < 0 || sp1 + 4 > statusLine.length()) {
      throw new IOException("Malformed HTTP status line: " + statusLine);
    }
    int sp2 = statusLine.indexOf(' ', sp1 + 1);
    String num =
        sp2 > sp1 ? statusLine.substring(sp1 + 1, sp2).trim() : statusLine.substring(sp1 + 1).trim();
    try {
      return Integer.parseInt(num);
    } catch (NumberFormatException e) {
      throw new IOException("Invalid HTTP status code: " + num);
    }
  }

  private static byte[] readFixedOrEofBody(InputStream in, long contentLength, int maxBytes)
      throws IOException {
    ByteArrayOutputStream bos =
        new ByteArrayOutputStream(
            contentLength > 0 && contentLength < 1048576 ? (int) contentLength : 32768);
    byte[] buf = new byte[16384];
    long remaining = contentLength;
    int total = 0;
    while (remaining != 0) {
      int toRead =
          remaining > 0 ? (int) Math.min(buf.length, remaining) : buf.length;
      int n = in.read(buf, 0, toRead);
      if (n < 0) {
        if (remaining > 0) {
          throw new EOFException(
              "Premature EOF reading package (" + total + "/" + contentLength + ")");
        }
        break;
      }
      total += n;
      if (total > maxBytes) {
        throw new IOException("Package exceeds safety limit");
      }
      bos.write(buf, 0, n);
      if (remaining > 0) {
        remaining -= n;
      }
    }
    return bos.toByteArray();
  }

  private static byte[] readChunkedBody(InputStream in, int maxBytes) throws IOException {
    ByteArrayOutputStream bos = new ByteArrayOutputStream(32768);
    byte[] buf = new byte[16384];
    int total = 0;
    while (true) {
      String sizeLine = readHeaderLine(in);
      if (sizeLine == null) {
        throw new EOFException("Unexpected EOF in chunked stream");
      }
      int semi = sizeLine.indexOf(';');
      if (semi >= 0) {
        sizeLine = sizeLine.substring(0, semi);
      }
      int chunkSize;
      try {
        chunkSize = Integer.parseInt(sizeLine.trim(), 16);
      } catch (NumberFormatException e) {
        throw new IOException("Invalid chunk size: " + sizeLine);
      }
      if (chunkSize == 0) {
        readHeaderLine(in);
        break;
      }
      int rem = chunkSize;
      while (rem > 0) {
        int n = in.read(buf, 0, Math.min(buf.length, rem));
        if (n < 0) {
          throw new EOFException("Unexpected EOF inside HTTP chunk");
        }
        total += n;
        if (total > maxBytes) {
          throw new IOException("Package exceeds safety limit");
        }
        bos.write(buf, 0, n);
        rem -= n;
      }
      readHeaderLine(in);
    }
    return bos.toByteArray();
  }

  private static void configureHttpsTlsAndSni(SSLSocket ssl, String host) {
    try {
      String[] supported = ssl.getSupportedProtocols();
      List<String> wanted = new ArrayList<>(2);
      for (String p : supported) {
        if ("TLSv1.3".equals(p) || "TLSv1.2".equals(p)) {
          wanted.add(p);
        }
      }
      if (!wanted.isEmpty()) {
        ssl.setEnabledProtocols(wanted.toArray(new String[0]));
      }
      SSLParameters params = ssl.getSSLParameters();
      params.setEndpointIdentificationAlgorithm("HTTPS");
      if (host != null && !host.isEmpty() && !host.contains(":")) {
        try {
          params.setServerNames(Collections.singletonList(new SNIHostName(host)));
        } catch (IllegalArgumentException ignored) {
        }
      }
      ssl.setSSLParameters(params);
    } catch (Throwable ignored) {
    }
  }
}
