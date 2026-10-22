package com.hypertechlabs.heavenbrowser;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.provider.Settings;
import android.view.KeyEvent;
import android.webkit.ClientCertRequest;
import android.webkit.HttpAuthHandler;
import android.webkit.ServiceWorkerClient;
import android.webkit.ServiceWorkerController;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class HeavenShieldPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "com.hypertechlabs.heavenbrowser/native_shield";

  private static final byte[] TRANSPARENT_GIF = new byte[] {
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, (byte) 0x80, 0x00,
    0x00, (byte) 0xff, (byte) 0xff, (byte) 0xff, 0x00, 0x00, 0x00, 0x21, (byte) 0xf9,
    0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b
  };

  private static final byte[] EMPTY_JS =
      "/* Blocked by Heaven Shield */".getBytes(StandardCharsets.UTF_8);

  private static final byte[] EMPTY_HTML =
      "<!doctype html><html><head><style>html,body{display:none!important;margin:0;padding:0;}</style></head><body></body></html>"
          .getBytes(StandardCharsets.UTF_8);

  private static final byte[] EMPTY_TEXT = new byte[0];

  private final Activity activity;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private FlutterPluginBinding pluginBinding;
  private MethodChannel channel;

  private volatile boolean shieldEnabled = true;
  private volatile Set<String> blockedDomains = Collections.emptySet();
  private volatile Set<String> trustedHosts = Collections.emptySet();
  private volatile String cosmeticScript = "";
  private final Map<Long, String> currentPageHosts = new ConcurrentHashMap<>();
  private boolean serviceWorkerHooked = false;

  public HeavenShieldPlugin(Activity activity) {
    this.activity = activity;
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    this.pluginBinding = binding;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    setupServiceWorkerShield();
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.pluginBinding = null;
  }

  private void setupServiceWorkerShield() {
    if (serviceWorkerHooked || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      return;
    }
    try {
      ServiceWorkerController swController = ServiceWorkerController.getInstance();
      swController.setServiceWorkerClient(
          new ServiceWorkerClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
              String matched = evaluateRequestBlock(request, null);
              if (matched != null) {
                notifyBlocked(-1L, matched);
                return buildSurrogateResponse(request);
              }
              return null;
            }
          });
      serviceWorkerHooked = true;
    } catch (Throwable ignored) {
    }
  }

  @Override
  @SuppressWarnings("unchecked")
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    switch (call.method) {
      case "updateConfig": {
        Boolean enabled = call.argument("shieldEnabled");
        List<String> domains = call.argument("blockedDomains");
        List<String> trusted = call.argument("trustedHosts");
        String script = call.argument("cosmeticScript");

        if (enabled != null) {
          this.shieldEnabled = enabled;
        }
        if (domains != null) {
          Set<String> next = new HashSet<>(domains.size() * 2);
          for (String d : domains) {
            if (d != null && !d.isEmpty()) {
              next.add(d.trim().toLowerCase(Locale.US));
            }
          }
          this.blockedDomains = next;
        }
        if (trusted != null) {
          Set<String> nextTrusted = new HashSet<>(trusted.size() * 2);
          for (String t : trusted) {
            if (t != null && !t.isEmpty()) {
              nextTrusted.add(normalizeHost(t));
            }
          }
          this.trustedHosts = nextTrusted;
        }
        if (script != null) {
          this.cosmeticScript = script;
        }
        result.success(true);
        break;
      }
      case "attachToWebView": {
        Number idNum = call.argument("webViewId");
        String pageHost = call.argument("pageHost");
        if (idNum == null || pluginBinding == null) {
          result.success(false);
          return;
        }
        long webViewId = idNum.longValue();
        if (pageHost != null && !pageHost.isEmpty()) {
          currentPageHosts.put(webViewId, normalizeHost(pageHost));
        }
        boolean attached = attachShieldClient(webViewId);
        result.success(attached);
        break;
      }
      case "updatePageHost": {
        Number idNum = call.argument("webViewId");
        String pageHost = call.argument("pageHost");
        if (idNum != null) {
          long webViewId = idNum.longValue();
          if (pageHost == null || pageHost.isEmpty()) {
            currentPageHosts.remove(webViewId);
          } else {
            currentPageHosts.put(webViewId, normalizeHost(pageHost));
          }
        }
        result.success(true);
        break;
      }
      case "openDefaultBrowserSettings": {
        try {
          Intent intent = new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS);
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
          activity.startActivity(intent);
          result.success(true);
        } catch (Throwable t) {
          result.success(false);
        }
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  private boolean attachShieldClient(long webViewId) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || pluginBinding == null) {
      return false;
    }
    WebView webView = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, webViewId);
    if (webView == null) {
      return false;
    }
    WebViewClient existing = webView.getWebViewClient();
    if (existing instanceof ShieldWebViewClient) {
      return true;
    }
    webView.getSettings().setSupportMultipleWindows(false);
    webView.getSettings().setJavaScriptCanOpenWindowsAutomatically(false);
    webView.setWebViewClient(new ShieldWebViewClient(webViewId, existing));
    return true;
  }

  private static String normalizeHost(String host) {
    if (host == null) return "";
    String clean = host.trim().toLowerCase(Locale.US);
    if (clean.startsWith("www.") && clean.length() > 4) {
      clean = clean.substring(4);
    }
    return clean;
  }

  private static String extractRegistrableRoot(String host) {
    String clean = normalizeHost(host);
    String[] parts = clean.split("\\.");
    if (parts.length <= 2) {
      return clean;
    }
    return parts[parts.length - 2] + "." + parts[parts.length - 1];
  }

  private boolean isHostTrusted(String host) {
    if (host == null || host.isEmpty()) return false;
    Set<String> trusted = this.trustedHosts;
    if (trusted.isEmpty()) return false;
    String clean = normalizeHost(host);
    while (true) {
      if (trusted.contains(clean)) {
        return true;
      }
      int dot = clean.indexOf('.');
      if (dot < 0 || dot == clean.length() - 1) {
        break;
      }
      clean = clean.substring(dot + 1);
    }
    return false;
  }

  private String matchBlockedDomain(String host) {
    if (host == null || host.isEmpty()) return null;
    Set<String> blocked = this.blockedDomains;
    if (blocked.isEmpty()) return null;
    String clean = host.trim().toLowerCase(Locale.US);
    while (true) {
      if (blocked.contains(clean)) {
        return clean;
      }
      int dot = clean.indexOf('.');
      if (dot < 0 || dot == clean.length() - 1) {
        break;
      }
      clean = clean.substring(dot + 1);
    }
    return null;
  }

  private String evaluateRequestBlock(WebResourceRequest request, String pageHost) {
    if (!shieldEnabled || request == null) {
      return null;
    }
    Uri uri = request.getUrl();
    if (uri == null) {
      return null;
    }
    String scheme = uri.getScheme();
    if (scheme == null || (!scheme.equalsIgnoreCase("http") && !scheme.equalsIgnoreCase("https"))) {
      return null;
    }
    String reqHost = uri.getHost();
    if (reqHost == null || reqHost.isEmpty()) {
      return null;
    }
    if (isHostTrusted(pageHost) || isHostTrusted(reqHost)) {
      return null;
    }

    String matchedDomain = matchBlockedDomain(reqHost);
    if (matchedDomain != null) {
      return matchedDomain;
    }

    // Third-party ad script/banner URL path heuristics (like Brave/EasyList)
    if (!request.isForMainFrame()) {
      String pathAndQuery =
          ((uri.getPath() != null ? uri.getPath() : "")
                  + (uri.getQuery() != null ? "?" + uri.getQuery() : ""))
              .toLowerCase(Locale.US);
      boolean thirdParty =
          pageHost != null
              && !pageHost.isEmpty()
              && !extractRegistrableRoot(reqHost).equals(extractRegistrableRoot(pageHost));

      if (pathAndQuery.contains("/adsbygoogle")
          || pathAndQuery.contains("/pagead/")
          || pathAndQuery.contains("/gpt.js")
          || pathAndQuery.contains("/pubads_impl")
          || pathAndQuery.contains("/prebid")
          || pathAndQuery.contains("/popunder")
          || (thirdParty
              && (pathAndQuery.contains("/adserver")
                  || pathAndQuery.contains("/adframe")
                  || pathAndQuery.contains("/ads/banner")
                  || pathAndQuery.contains("ad_type=video")))) {
        return normalizeHost(reqHost);
      }
    }
    return null;
  }

  private WebResourceResponse buildSurrogateResponse(WebResourceRequest request) {
    Map<String, String> headers = new HashMap<>();
    headers.put("Access-Control-Allow-Origin", "*");
    headers.put("Cache-Control", "no-store");

    String path =
        request.getUrl() != null && request.getUrl().getPath() != null
            ? request.getUrl().getPath().toLowerCase(Locale.US)
            : "";
    Map<String, String> reqHeaders = request.getRequestHeaders();
    String accept = reqHeaders != null && reqHeaders.get("Accept") != null
        ? reqHeaders.get("Accept").toLowerCase(Locale.US)
        : "";

    if (path.endsWith(".js") || accept.contains("script")) {
      return new WebResourceResponse(
          "application/javascript",
          "UTF-8",
          200,
          "OK",
          headers,
          new ByteArrayInputStream(EMPTY_JS));
    }
    if (path.endsWith(".png")
        || path.endsWith(".gif")
        || path.endsWith(".jpg")
        || path.endsWith(".jpeg")
        || path.endsWith(".webp")
        || accept.startsWith("image/")) {
      return new WebResourceResponse(
          "image/gif",
          null,
          200,
          "OK",
          headers,
          new ByteArrayInputStream(TRANSPARENT_GIF));
    }
    if (accept.contains("text/html") && !request.isForMainFrame()) {
      return new WebResourceResponse(
          "text/html",
          "UTF-8",
          200,
          "OK",
          headers,
          new ByteArrayInputStream(EMPTY_HTML));
    }
    return new WebResourceResponse(
        "text/plain",
        "UTF-8",
        204,
        "Blocked",
        headers,
        new ByteArrayInputStream(EMPTY_TEXT));
  }

  private void notifyBlocked(long webViewId, String domain) {
    mainHandler.post(
        () -> {
          if (channel != null) {
            Map<String, Object> payload = new HashMap<>();
            payload.put("webViewId", webViewId);
            payload.put("domain", domain);
            channel.invokeMethod("onResourceBlocked", payload);
          }
        });
  }

  private class ShieldWebViewClient extends WebViewClient {
    private final long webViewId;
    private final WebViewClient delegate;

    ShieldWebViewClient(long webViewId, WebViewClient delegate) {
      this.webViewId = webViewId;
      this.delegate = delegate;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      if (request != null && request.isForMainFrame() && request.getUrl() != null) {
        String h = request.getUrl().getHost();
        if (h != null && !h.isEmpty()) {
          currentPageHosts.put(webViewId, normalizeHost(h));
        }
      }
      String pageHost = currentPageHosts.get(webViewId);
      String matched = evaluateRequestBlock(request, pageHost);
      if (matched != null && !request.isForMainFrame()) {
        notifyBlocked(webViewId, matched);
        return buildSurrogateResponse(request);
      }
      return delegate != null ? delegate.shouldInterceptRequest(view, request) : null;
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
      if (request != null && !request.isForMainFrame()) {
        String pageHost = currentPageHosts.get(webViewId);
        String matched = evaluateRequestBlock(request, pageHost);
        if (matched != null) {
          notifyBlocked(webViewId, matched);
          return true;
        }
      }
      return delegate != null && delegate.shouldOverrideUrlLoading(view, request);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
      if (url != null) {
        Uri parsed = Uri.parse(url);
        if (parsed.getHost() != null) {
          currentPageHosts.put(webViewId, normalizeHost(parsed.getHost()));
        }
      }
      if (delegate != null) {
        delegate.onPageStarted(view, url, favicon);
      }
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
      injectCosmeticFilter(view, url);
      if (delegate != null) {
        delegate.onPageCommitVisible(view, url);
      }
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      injectCosmeticFilter(view, url);
      if (delegate != null) {
        delegate.onPageFinished(view, url);
      }
    }

    private void injectCosmeticFilter(WebView view, String url) {
      if (!shieldEnabled || view == null || url == null) {
        return;
      }
      String host = Uri.parse(url).getHost();
      if (isHostTrusted(host)) {
        return;
      }
      String script = cosmeticScript;
      if (script != null && !script.isEmpty()) {
        view.evaluateJavascript(script, null);
      }
    }

    @Override
    public void onReceivedHttpError(
        WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
      if (delegate != null) {
        delegate.onReceivedHttpError(view, request, errorResponse);
      }
    }

    @Override
    public void onReceivedError(
        WebView view, WebResourceRequest request, WebResourceError error) {
      if (delegate != null) {
        delegate.onReceivedError(view, request, error);
      }
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
      if (delegate != null) {
        delegate.doUpdateVisitedHistory(view, url, isReload);
      }
    }

    @Override
    public void onReceivedHttpAuthRequest(
        WebView view, HttpAuthHandler handler, String host, String realm) {
      if (delegate != null) {
        delegate.onReceivedHttpAuthRequest(view, handler, host, realm);
      } else {
        super.onReceivedHttpAuthRequest(view, handler, host, realm);
      }
    }

    @Override
    public void onFormResubmission(WebView view, Message dontResend, Message resend) {
      if (delegate != null) {
        delegate.onFormResubmission(view, dontResend, resend);
      } else {
        super.onFormResubmission(view, dontResend, resend);
      }
    }

    @Override
    public void onLoadResource(WebView view, String url) {
      if (delegate != null) {
        delegate.onLoadResource(view, url);
      }
    }

    @Override
    public void onReceivedClientCertRequest(WebView view, ClientCertRequest request) {
      if (delegate != null) {
        delegate.onReceivedClientCertRequest(view, request);
      } else {
        super.onReceivedClientCertRequest(view, request);
      }
    }

    @Override
    public void onReceivedLoginRequest(
        WebView view, String realm, String account, String args) {
      if (delegate != null) {
        delegate.onReceivedLoginRequest(view, realm, account, args);
      }
    }

    @Override
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
      if (delegate != null) {
        delegate.onReceivedSslError(view, handler, error);
      } else {
        super.onReceivedSslError(view, handler, error);
      }
    }

    @Override
    public void onScaleChanged(WebView view, float oldScale, float newScale) {
      if (delegate != null) {
        delegate.onScaleChanged(view, oldScale, newScale);
      }
    }

    @Override
    public void onUnhandledKeyEvent(WebView view, KeyEvent event) {
      if (delegate != null) {
        delegate.onUnhandledKeyEvent(view, event);
      }
    }
  }
}
