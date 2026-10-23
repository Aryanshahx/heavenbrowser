package com.hypertechlabs.heavenbrowser;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * High-speed background Google Search engine using an attached offscreen 1280x900 Chromium WebView.
 *
 * <p>Pre-warms Google's SearchGuard (SG_SS) session cookie on startup so subsequent user searches
 * return live Google organic results, Knowledge Graph cards, images, videos, news, and related
 * queries in ~300-650ms without ever opening google.com visibly or serving Google ads.
 */
public final class HeavenGoogleBgSearch {

  private static final String DESKTOP_CHROME_UA =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  private static final long MAX_WAIT_MS = 4500L;
  private static final long POLL_INTERVAL_MS = 90L;
  private static final byte[] EMPTY_BYTES = new byte[0];

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private Activity hostActivity;
  private FrameLayout offscreenHolder;
  private WebView bgWebView;
  private ActiveSearchJob activeJob;
  private int jobCounter = 0;
  private boolean prewarmed = false;

  private static final class ActiveSearchJob {
    final int id;
    final String tab;
    final MethodChannel.Result callback;
    final long startedAtMs;
    boolean completed = false;
    boolean sawChallenge = false;

    ActiveSearchJob(int id, String tab, MethodChannel.Result callback, long startedAtMs) {
      this.id = id;
      this.tab = tab;
      this.callback = callback;
      this.startedAtMs = startedAtMs;
    }
  }

  public HeavenGoogleBgSearch(Context appContext) {
    this.appContext = appContext.getApplicationContext();
  }

  public void attachToActivityAndPrewarm(final Activity activity) {
    this.hostActivity = activity;
    if (activity == null) {
      return;
    }
    mainHandler.postDelayed(
        () -> {
          try {
            ensureWebViewOnMain();
            if (!prewarmed && bgWebView != null && activeJob == null) {
              prewarmed = true;
              Map<String, String> headers = buildDesktopHeaders("en-US,en;q=0.9");
              bgWebView.loadUrl("https://www.google.com/search?q=time&hl=en&num=10", headers);
            }
          } catch (Throwable ignored) {
          }
        },
        350L);
  }

  public void detachFromActivity() {
    this.hostActivity = null;
    mainHandler.post(
        () -> {
          if (offscreenHolder != null) {
            ViewParent parent = offscreenHolder.getParent();
            if (parent instanceof ViewGroup) {
              ((ViewGroup) parent).removeView(offscreenHolder);
            }
          }
        });
  }

  private static Map<String, String> buildDesktopHeaders(String langHeader) {
    Map<String, String> headers = new HashMap<>(6);
    headers.put(
        "Accept-Language",
        (langHeader != null && !langHeader.isEmpty()) ? langHeader : "en-US,en;q=0.9");
    headers.put(
        "Sec-CH-UA",
        "\"Chromium\";v=\"134\", \"Not:A-Brand\";v=\"24\", \"Google Chrome\";v=\"134\"");
    headers.put("Sec-CH-UA-Mobile", "?0");
    headers.put("Sec-CH-UA-Platform", "\"Windows\"");
    return headers;
  }

  @SuppressLint("SetJavaScriptEnabled")
  private void ensureWebViewOnMain() {
    if (bgWebView == null) {
      Context ctx = hostActivity != null ? hostActivity : appContext;
      bgWebView = new WebView(ctx);

      WebSettings s = bgWebView.getSettings();
      s.setJavaScriptEnabled(true);
      s.setDomStorageEnabled(true);
      s.setUseWideViewPort(true);
      s.setLoadWithOverviewMode(true);
      s.setUserAgentString(DESKTOP_CHROME_UA);
      s.setCacheMode(WebSettings.LOAD_DEFAULT);
      s.setMediaPlaybackRequiresUserGesture(true);
      s.setJavaScriptCanOpenWindowsAutomatically(false);
      s.setLoadsImagesAutomatically(false);
      s.setBlockNetworkImage(true);

      CookieManager cm = CookieManager.getInstance();
      cm.setAcceptCookie(true);
      cm.setAcceptThirdPartyCookies(bgWebView, true);

      bgWebView.setWebViewClient(
          new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(
                WebView view, WebResourceRequest request) {
              if (request != null && request.getUrl() != null) {
                Uri u = request.getUrl();
                String host = u.getHost() != null ? u.getHost().toLowerCase(Locale.US) : "";
                String path = u.getEncodedPath() != null ? u.getEncodedPath().toLowerCase(Locale.US) : "";
                boolean isImagesTab =
                    activeJob != null && "images".equals(activeJob.tab);
                // Block Google ads, trackers, beacons, and heavy web fonts so SERP loads in ~300ms
                if (host.contains("googlesyndication.com")
                    || host.contains("googleadservices.com")
                    || host.contains("doubleclick.net")
                    || host.contains("google-analytics.com")
                    || host.contains("play.google.com")
                    || host.contains("youtube.com")
                    || path.contains("/gen_204")
                    || path.contains("/client_204")
                    || path.contains("/ads?")
                    || path.contains("/pagead/")
                    || path.endsWith(".woff2")
                    || path.endsWith(".woff")
                    || path.endsWith(".ttf")
                    || (!isImagesTab
                        && (path.endsWith(".png")
                            || path.endsWith(".jpg")
                            || path.endsWith(".jpeg")
                            || path.endsWith(".webp")
                            || path.endsWith(".gif")))) {
                  return new WebResourceResponse(
                      "text/plain",
                      "UTF-8",
                      204,
                      "No Content",
                      null,
                      new ByteArrayInputStream(EMPTY_BYTES));
                }
              }
              return super.shouldInterceptRequest(view, request);
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
              if (url != null && url.contains("/sorry/")) {
                finishJobEmpty("captcha");
                return;
              }
              // Remove headless indicators early on every navigation
              view.evaluateJavascript(
                  "(function(){try{Object.defineProperty(navigator,'webdriver',{get:()=>false,configurable:true});"
                      + "Object.defineProperty(navigator,'platform',{get:()=>'Win32',configurable:true});"
                      + "window.chrome=window.chrome||{runtime:{}};}catch(e){}})();",
                  null);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
              CookieManager.getInstance().flush();
              if (activeJob == null || activeJob.completed) {
                return;
              }
              if (url != null && url.contains("/sorry/")) {
                finishJobEmpty("captcha");
                return;
              }
              pollDomExtraction(activeJob.id);
            }

            @Override
            public void onReceivedError(
                WebView view, WebResourceRequest request, WebResourceError error) {
              if (request != null && request.isForMainFrame()) {
                finishJobEmpty("network_error");
              }
            }
          });
    }

    // Attach inside a 1x1 off-screen holder on Activity so Chromium gives full foreground priority
    // and window.innerWidth / innerHeight equal 1280x900 (preventing 0x0 headless detection).
    if (hostActivity != null) {
      View root = hostActivity.findViewById(android.R.id.content);
      if (root instanceof ViewGroup) {
        ViewGroup rootGroup = (ViewGroup) root;
        if (offscreenHolder == null) {
          offscreenHolder = new FrameLayout(hostActivity);
          offscreenHolder.setAlpha(0.0f);
          offscreenHolder.setTranslationX(-12000f);
          offscreenHolder.setClickable(false);
          offscreenHolder.setFocusable(false);
          offscreenHolder.setImportantForAccessibility(
              View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        }
        if (bgWebView.getParent() != offscreenHolder) {
          if (bgWebView.getParent() instanceof ViewGroup) {
            ((ViewGroup) bgWebView.getParent()).removeView(bgWebView);
          }
          offscreenHolder.addView(bgWebView, new FrameLayout.LayoutParams(1280, 900));
        }
        if (offscreenHolder.getParent() != rootGroup) {
          if (offscreenHolder.getParent() instanceof ViewGroup) {
            ((ViewGroup) offscreenHolder.getParent()).removeView(offscreenHolder);
          }
          rootGroup.addView(offscreenHolder, new FrameLayout.LayoutParams(1, 1));
        }
        bgWebView.layout(0, 0, 1280, 900);
      }
    }
  }

  public void searchInBackground(
      final String query,
      final String tab,
      final String safeMode,
      final String timeCode,
      final String langHeader,
      final MethodChannel.Result callback) {
    mainHandler.post(
        () -> {
          if (query == null || query.trim().isEmpty()) {
            Map<String, Object> empty = new HashMap<>();
            empty.put("ok", false);
            callback.success(empty);
            return;
          }

          if (activeJob != null && !activeJob.completed) {
            activeJob.completed = true;
            Map<String, Object> cancelled = new HashMap<>();
            cancelled.put("ok", false);
            cancelled.put("reason", "superseded");
            activeJob.callback.success(cancelled);
          }

          try {
            ensureWebViewOnMain();
          } catch (Throwable t) {
            Map<String, Object> err = new HashMap<>();
            err.put("ok", false);
            err.put("reason", "webview_unavailable");
            callback.success(err);
            return;
          }

          final String cleanTab = tab != null ? tab.trim().toLowerCase(Locale.US) : "all";
          final boolean wantImages = "images".equals(cleanTab);
          bgWebView.getSettings().setBlockNetworkImage(!wantImages);
          bgWebView.getSettings().setLoadsImagesAutomatically(wantImages);

          final int jobId = ++jobCounter;
          prewarmed = true;
          activeJob =
              new ActiveSearchJob(jobId, cleanTab, callback, System.currentTimeMillis());

          String effectiveQuery =
              "cws".equals(cleanTab)
                  ? "site:chromewebstore.google.com/detail " + query.trim()
                  : query.trim();
          String targetUrl = buildGoogleUrl(effectiveQuery, cleanTab, safeMode, timeCode);
          Map<String, String> headers = buildDesktopHeaders(langHeader);

          bgWebView.stopLoading();
          bgWebView.loadUrl(targetUrl, headers);

          mainHandler.postDelayed(() -> pollDomExtraction(jobId), 160L);
        });
  }

  private static String buildGoogleUrl(
      String query, String tab, String safeMode, String timeCode) {
    String encoded = Uri.encode(query);
    String safe = "strict".equalsIgnoreCase(safeMode) ? "active" : "off";
    StringBuilder sb =
        new StringBuilder("https://www.google.com/search?q=")
            .append(encoded)
            .append("&hl=en&pws=0&nfpr=0&safe=")
            .append(safe);

    if ("images".equals(tab)) {
      sb.append("&udm=2");
    } else if ("videos".equals(tab)) {
      sb.append("&udm=7");
    } else if ("news".equals(tab)) {
      sb.append("&tbm=nws");
    } else {
      sb.append("&num=18");
    }

    if (timeCode != null && !timeCode.isEmpty() && !"any".equals(timeCode)) {
      sb.append("&tbs=qdr:").append(Uri.encode(timeCode));
    }
    return sb.toString();
  }

  private void pollDomExtraction(final int jobId) {
    if (activeJob == null || activeJob.completed || activeJob.id != jobId || bgWebView == null) {
      return;
    }

    final long elapsed = System.currentTimeMillis() - activeJob.startedAtMs;
    final boolean timedOut = elapsed >= MAX_WAIT_MS;

    bgWebView.evaluateJavascript(
        buildExtractorScript(activeJob.tab),
        rawJson -> {
          if (activeJob == null || activeJob.completed || activeJob.id != jobId) {
            return;
          }
          Map<String, Object> parsed = parseEvaluatedJson(rawJson);
          if (parsed != null) {
            Object statusObj = parsed.get("status");
            String status = statusObj != null ? statusObj.toString() : "";

            if ("captcha".equals(status)) {
              finishJobEmpty("captcha");
              return;
            }
            if (("consent_clicked".equals(status) || "solving_challenge".equals(status))
                && !timedOut) {
              activeJob.sawChallenge = true;
              mainHandler.postDelayed(() -> pollDomExtraction(jobId), 140L);
              return;
            }

            int count = countPrimaryItems(parsed, activeJob.tab);
            boolean ready =
                count >= 4
                    || (count >= 1 && elapsed >= 650L)
                    || (count >= 1 && "complete".equals(parsed.get("readyState")));

            if (ready || (timedOut && count >= 1)) {
              parsed.put("ok", true);
              parsed.put("sourceEngine", "google");
              activeJob.completed = true;
              CookieManager.getInstance().flush();
              activeJob.callback.success(parsed);
              return;
            }
          }

          if (timedOut) {
            finishJobEmpty("timeout");
          } else {
            mainHandler.postDelayed(() -> pollDomExtraction(jobId), POLL_INTERVAL_MS);
          }
        });
  }

  private int countPrimaryItems(Map<String, Object> map, String tab) {
    String key = "webResults";
    if ("images".equals(tab)) {
      key = "imageResults";
    } else if ("videos".equals(tab)) {
      key = "videoResults";
    } else if ("news".equals(tab)) {
      key = "newsResults";
    }
    Object list = map.get(key);
    if (list instanceof List<?>) {
      return ((List<?>) list).size();
    }
    return 0;
  }

  private void finishJobEmpty(String reason) {
    if (activeJob == null || activeJob.completed) {
      return;
    }
    activeJob.completed = true;
    Map<String, Object> out = new HashMap<>();
    out.put("ok", false);
    out.put("reason", reason);
    activeJob.callback.success(out);
  }

  private static String buildExtractorScript(String tab) {
    String escapedTab = tab.replace("'", "");
    return "(function(){"
        + "try{"
        + "var hrefNow=location.href||'';"
        + "if(hrefNow.indexOf('/sorry/')!==-1){return JSON.stringify({status:'captcha'});}"
        + "var consentBtn=document.querySelector('button#L2AGLb, button#W0wltc, form[action*=\"consent.google\"] button');"
        + "if(consentBtn){consentBtn.click();return JSON.stringify({status:'consent_clicked'});}"
        + "var docTitle=(document.title||'').trim();"
        + "var retryLink=document.querySelector('a[href*=\"/httpservice/retry/enablejs\"], meta[http-equiv=\"refresh\"]');"
        + "if(docTitle==='Google Search'&&retryLink&&!document.querySelector('#rso, #search, #main h3')){"
        + "  return JSON.stringify({status:'solving_challenge'});"
        + "}"
        + "var mode='"
        + escapedTab
        + "';"
        + "function txt(el){return el?((el.textContent||'').replace(/\\s+/g,' ').trim()):'';}"
        + "function unwrap(u){"
        + "  if(!u)return '';"
        + "  try{"
        + "    var parsed=new URL(u,location.origin);"
        + "    var hn=parsed.hostname.toLowerCase();"
        + "    if(hn.indexOf('google.')!==-1&&hn!=='chromewebstore.google.com'&&hn!=='chrome.google.com'){"
        + "      if(parsed.pathname==='/url'||parsed.pathname==='/imgres'){"
        + "        return parsed.searchParams.get('q')||parsed.searchParams.get('url')||parsed.searchParams.get('imgurl')||'';"
        + "      }"
        + "      return '';"
        + "    }"
        + "    if(parsed.protocol==='http:'||parsed.protocol==='https:')return parsed.href;"
        + "  }catch(e){}"
        + "  return '';"
        + "}"
        + "function hostTitle(u){"
        + "  try{var h=new URL(u).hostname.replace(/^www\\./,'');var p=h.split('.')[0]||h;return p.charAt(0).toUpperCase()+p.slice(1);}catch(e){return 'Web';}"
        + "}"
        + "var webResults=[],imageResults=[],videoResults=[],newsResults=[],related=[];"
        + "var seen={};"
        + "if(mode==='images'){"
        + "  var imgs=document.querySelectorAll('#search img, #rso img, div[data-id] img, img');"
        + "  for(var i=0;i<imgs.length&&imageResults.length<30;i++){"
        + "    var im=imgs[i];"
        + "    var src=im.currentSrc||im.src||im.getAttribute('data-src')||im.getAttribute('data-iurl')||'';"
        + "    if(!src||src.indexOf('gstatic.com/images/branding')!==-1||src.indexOf('googlelogo')!==-1)continue;"
        + "    var w=im.naturalWidth||im.width||0;var h=im.naturalHeight||im.height||0;"
        + "    if(w>0&&w<60&&h>0&&h<60)continue;"
        + "    if(src.indexOf('http')!==0&&src.indexOf('data:image')!==0)continue;"
        + "    if(src.indexOf('data:image')===0&&src.length<900)continue;"
        + "    var a=im.closest('a');"
        + "    var pageUrl=a?unwrap(a.href):'';"
        + "    var alt=(im.alt||'').trim();"
        + "    if(!alt&&a)alt=txt(a);"
        + "    if(!alt)alt='Image result';"
        + "    if(seen[src])continue;seen[src]=1;"
        + "    imageResults.push({title:alt.slice(0,120),thumbUrl:src,fullUrl:src,pageUrl:pageUrl||src});"
        + "  }"
        + "  return JSON.stringify({status:'ok',readyState:document.readyState,imageResults:imageResults});"
        + "}"
        + "var anchors=document.querySelectorAll('#rso a[href], #search a[href], #main a[href]');"
        + "for(var j=0;j<anchors.length;j++){"
        + "  var el=anchors[j];"
        + "  if(el.closest('#tads, #bottomads, #tvcap, [data-text-ad], [aria-label=\"Ads\"]'))continue;"
        + "  var dest=unwrap(el.href);"
        + "  if(!dest||seen[dest])continue;"
        + "  if(dest.indexOf('translate.google.')!==-1||dest.indexOf('webcache.googleusercontent.')!==-1)continue;"
        + "  var hEl=el.querySelector('h3, [role=\"heading\"], div.BNeawe.vvjwJb, div.n0jPhd, div.MBeuO, span.CVA68e');"
        + "  var title=txt(hEl);"
        + "  if(!title||title.length<3)continue;"
        + "  seen[dest]=1;"
        + "  var card=el.closest('div.MjjYud, div.g, div.SoaBEf, div.Ww4FFb, div.xpd, g-card, article, div[data-hveid]')||el.parentElement;"
        + "  var snippet='';"
        + "  if(card){"
        + "    var snNodes=card.querySelectorAll('div.VwiC3b, div[data-sncf=\"1\"], div[data-sncf=\"2\"], div.GI74Re, div.ITZIwc, div.BNeawe.s3v9rd, span.aCOpRe');"
        + "    for(var sIdx=0;sIdx<snNodes.length;sIdx++){"
        + "      var cand=txt(snNodes[sIdx]);"
        + "      if(cand.length>snippet.length&&cand!==title){snippet=cand;}"
        + "    }"
        + "    if(!snippet){"
        + "      var rawCard=txt(card);"
        + "      var pos=rawCard.indexOf(title);"
        + "      if(pos!==-1){rawCard=rawCard.slice(pos+title.length).trim();}"
        + "      if(rawCard.length>24){snippet=rawCard;}"
        + "    }"
        + "  }"
        + "  var citeEl=card?card.querySelector('span.VuuXrf, div.byrV5b, cite'):null;"
        + "  var srcName=txt(citeEl);"
        + "  if(!srcName||srcName.length>36)srcName=hostTitle(dest);"
        + "  var item={title:title,url:dest,snippet:snippet.slice(0,320),sourceLabel:srcName,thumbnailUrl:''};"
        + "  if(mode==='videos')videoResults.push(item);"
        + "  else if(mode==='news')newsResults.push(item);"
        + "  else webResults.push(item);"
        + "  if(webResults.length>=22||videoResults.length>=20||newsResults.length>=20)break;"
        + "}"
        + "var kc=null;"
        + "var kTitle=document.querySelector('[data-attrid=\"title\"], div.PZPZlf[data-attrid=\"title\"], h2[data-attrid=\"title\"]');"
        + "var kDesc=document.querySelector('[data-attrid*=\"description\"], div.kno-rdesc, span.hgKElc');"
        + "if(kDesc){"
        + "  var kt=txt(kTitle)||'Google Overview';"
        + "  var kd=txt(kDesc).replace(/^Description\\s*/i,'').replace(/Wikipedia\\s*$/i,'').trim();"
        + "  var ka=kDesc.querySelector('a[href]');"
        + "  var ku=(ka&&unwrap(ka.href))||(webResults[0]?webResults[0].url:'https://www.google.com');"
        + "  if(kd.length>25){kc={heading:kt,summary:kd.slice(0,440),sourceUrl:ku,sourceName:hostTitle(ku)};}"
        + "}"
        + "var relNodes=document.querySelectorAll('#bres a[href*=\"/search?\"], a.k8XOCe, div.s75CSd');"
        + "var relSeen={};"
        + "for(var r=0;r<relNodes.length&&related.length<8;r++){"
        + "  var rt=txt(relNodes[r]);"
        + "  if(rt&&rt.length>=3&&rt.length<=68&&!relSeen[rt.toLowerCase()]){"
        + "    relSeen[rt.toLowerCase()]=1;related.push(rt);"
        + "  }"
        + "}"
        + "return JSON.stringify({status:'ok',readyState:document.readyState,webResults:webResults,videoResults:videoResults,newsResults:newsResults,knowledgeCard:kc,relatedSearches:related});"
        + "}catch(err){return JSON.stringify({status:'error',msg:String(err)});}"
        + "})();";
  }

  private static Map<String, Object> parseEvaluatedJson(String rawEvalResult) {
    if (rawEvalResult == null || rawEvalResult.isEmpty() || "null".equals(rawEvalResult)) {
      return null;
    }
    try {
      String jsonText = rawEvalResult;
      if (jsonText.startsWith("\"") && jsonText.endsWith("\"")) {
        JSONArray wrapper = new JSONArray("[" + jsonText + "]");
        jsonText = wrapper.getString(0);
      }
      JSONObject obj = new JSONObject(jsonText);
      return jsonObjectToMap(obj);
    } catch (Throwable ignored) {
      return null;
    }
  }

  private static Map<String, Object> jsonObjectToMap(JSONObject obj) {
    Map<String, Object> map = new HashMap<>();
    Iterator<String> keys = obj.keys();
    while (keys.hasNext()) {
      String k = keys.next();
      Object v = obj.opt(k);
      if (v == null || v == JSONObject.NULL) {
        continue;
      }
      if (v instanceof JSONObject) {
        map.put(k, jsonObjectToMap((JSONObject) v));
      } else if (v instanceof JSONArray) {
        map.put(k, jsonArrayToList((JSONArray) v));
      } else {
        map.put(k, v);
      }
    }
    return map;
  }

  private static List<Object> jsonArrayToList(JSONArray arr) {
    List<Object> list = new ArrayList<>(arr.length());
    for (int i = 0; i < arr.length(); i++) {
      Object v = arr.opt(i);
      if (v == null || v == JSONObject.NULL) {
        continue;
      }
      if (v instanceof JSONObject) {
        list.add(jsonObjectToMap((JSONObject) v));
      } else if (v instanceof JSONArray) {
        list.add(jsonArrayToList((JSONArray) v));
      } else {
        list.add(v);
      }
    }
    return list;
  }

  public void destroy() {
    mainHandler.post(
        () -> {
          if (activeJob != null && !activeJob.completed) {
            finishJobEmpty("destroyed");
          }
          if (offscreenHolder != null) {
            ViewParent parent = offscreenHolder.getParent();
            if (parent instanceof ViewGroup) {
              ((ViewGroup) parent).removeView(offscreenHolder);
            }
            offscreenHolder.removeAllViews();
            offscreenHolder = null;
          }
          if (bgWebView != null) {
            try {
              bgWebView.stopLoading();
              bgWebView.destroy();
            } catch (Throwable ignored) {
            }
            bgWebView = null;
          }
        });
  }
}
