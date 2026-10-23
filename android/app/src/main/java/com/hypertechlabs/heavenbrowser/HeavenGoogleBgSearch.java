package com.hypertechlabs.heavenbrowser;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Runs real Google Search queries silently in an offscreen background Android WebView and copies
 * the live organic results, knowledge panel, images, videos, news, and related queries back into
 * Heaven Browser's native UI.
 */
public final class HeavenGoogleBgSearch {

  private static final String MOBILE_CHROME_UA =
      "Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36";

  private static final long MAX_WAIT_MS = 4200L;
  private static final long POLL_INTERVAL_MS = 180L;

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private WebView bgWebView;
  private ActiveSearchJob activeJob;
  private int jobCounter = 0;

  private static final class ActiveSearchJob {
    final int id;
    final String tab;
    final MethodChannel.Result callback;
    final long startedAtMs;
    boolean completed = false;
    boolean pageFinished = false;

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

  @SuppressLint("SetJavaScriptEnabled")
  private void ensureWebViewOnMain() {
    if (bgWebView != null) {
      return;
    }
    bgWebView = new WebView(appContext);
    bgWebView.setWillNotDraw(true);

    WebSettings s = bgWebView.getSettings();
    s.setJavaScriptEnabled(true);
    s.setDomStorageEnabled(true);
    s.setLoadsImagesAutomatically(false);
    s.setBlockNetworkImage(true);
    s.setUserAgentString(MOBILE_CHROME_UA);
    s.setCacheMode(WebSettings.LOAD_DEFAULT);
    s.setMediaPlaybackRequiresUserGesture(true);

    CookieManager cm = CookieManager.getInstance();
    cm.setAcceptCookie(true);

    bgWebView.setWebViewClient(
        new WebViewClient() {
          @Override
          public void onPageStarted(WebView view, String url, Bitmap favicon) {
            if (url != null && url.contains("/sorry/")) {
              finishJobEmpty("captcha");
            }
          }

          @Override
          public void onPageFinished(WebView view, String url) {
            if (activeJob == null || activeJob.completed) {
              return;
            }
            if (url != null && url.contains("/sorry/")) {
              finishJobEmpty("captcha");
              return;
            }
            activeJob.pageFinished = true;
            pollDomExtraction(activeJob.id, true);
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

          // Cancel any older pending job cleanly so the UI never hangs
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

          final String cleanTab = tab != null ? tab.trim().toLowerCase() : "all";
          final int jobId = ++jobCounter;
          activeJob =
              new ActiveSearchJob(jobId, cleanTab, callback, System.currentTimeMillis());

          String targetUrl = buildGoogleUrl(query.trim(), cleanTab, safeMode, timeCode);
          Map<String, String> headers = new HashMap<>();
          headers.put(
              "Accept-Language",
              (langHeader != null && !langHeader.isEmpty()) ? langHeader : "en-US,en;q=0.9");

          bgWebView.stopLoading();
          bgWebView.loadUrl(targetUrl, headers);

          mainHandler.postDelayed(() -> pollDomExtraction(jobId, false), 260L);
        });
  }

  private static String buildGoogleUrl(
      String query, String tab, String safeMode, String timeCode) {
    String encoded = Uri.encode(query);
    String safe = "strict".equalsIgnoreCase(safeMode) ? "active" : "off";
    StringBuilder sb =
        new StringBuilder("https://www.google.com/search?q=")
            .append(encoded)
            .append("&hl=en&pws=0&safe=")
            .append(safe);

    if ("images".equals(tab)) {
      sb.append("&udm=2");
    } else if ("videos".equals(tab)) {
      sb.append("&udm=7");
    } else if ("news".equals(tab)) {
      sb.append("&tbm=nws");
    } else {
      sb.append("&num=20");
    }

    if (timeCode != null && !timeCode.isEmpty() && !"any".equals(timeCode)) {
      sb.append("&tbs=qdr:").append(Uri.encode(timeCode));
    }
    return sb.toString();
  }

  private void pollDomExtraction(final int jobId, final boolean fromPageFinished) {
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
            if ("consent_clicked".equals(status) && !timedOut) {
              mainHandler.postDelayed(() -> pollDomExtraction(jobId, false), 280L);
              return;
            }
            if ("captcha".equals(status)) {
              finishJobEmpty("captcha");
              return;
            }
            int count = countPrimaryItems(parsed, activeJob.tab);
            if (count >= 2 || (activeJob.pageFinished && count >= 1) || timedOut) {
              if (count > 0) {
                parsed.put("ok", true);
                activeJob.completed = true;
                activeJob.callback.success(parsed);
              } else if (timedOut || fromPageFinished) {
                finishJobEmpty("empty_dom");
              } else {
                mainHandler.postDelayed(
                    () -> pollDomExtraction(jobId, false), POLL_INTERVAL_MS);
              }
              return;
            }
          }
          if (timedOut) {
            finishJobEmpty("timeout");
          } else {
            mainHandler.postDelayed(() -> pollDomExtraction(jobId, false), POLL_INTERVAL_MS);
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
        + "var consentBtn=document.querySelector('button#L2AGLb, form[action*=\"consent.google\"] button');"
        + "if(consentBtn){consentBtn.click();return JSON.stringify({status:'consent_clicked'});}"
        + "var mode='"
        + escapedTab
        + "';"
        + "function unwrap(u){"
        + "  if(!u)return '';"
        + "  try{"
        + "    var parsed=new URL(u,location.origin);"
        + "    if(parsed.hostname.indexOf('google.')!==-1){"
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
        + "  var imgs=document.querySelectorAll('img');"
        + "  for(var i=0;i<imgs.length&&imageResults.length<28;i++){"
        + "    var im=imgs[i];"
        + "    var src=im.currentSrc||im.src||im.getAttribute('data-src')||im.getAttribute('data-iurl')||'';"
        + "    if(!src||src.indexOf('gstatic.com/images/branding')!==-1)continue;"
        + "    var w=im.naturalWidth||im.width||0;var h=im.naturalHeight||im.height||0;"
        + "    if(w>0&&w<64&&h>0&&h<64)continue;"
        + "    if(src.indexOf('http')!==0&&src.indexOf('data:image')!==0)continue;"
        + "    var a=im.closest('a');"
        + "    var pageUrl=a?unwrap(a.href):'';"
        + "    var alt=(im.alt||'').trim();"
        + "    if(!alt&&a)alt=(a.innerText||'').trim();"
        + "    if(!alt)alt='Image result';"
        + "    if(seen[src])continue;seen[src]=1;"
        + "    imageResults.push({title:alt.slice(0,120),thumbUrl:src,fullUrl:src,pageUrl:pageUrl||src});"
        + "  }"
        + "  return JSON.stringify({status:'ok',imageResults:imageResults});"
        + "}"
        + "var anchors=document.querySelectorAll('#rso a[href], #search a[href], #main a[href]');"
        + "for(var j=0;j<anchors.length;j++){"
        + "  var el=anchors[j];"
        + "  if(el.closest('#tads, #bottomads, [data-text-ad]'))continue;"
        + "  var dest=unwrap(el.href);"
        + "  if(!dest||seen[dest])continue;"
        + "  var hEl=el.querySelector('h3, [role=\"heading\"], div.BNeawe.vvjwJb, div.n0jPhd');"
        + "  var title=hEl?(hEl.innerText||'').trim():'';"
        + "  if(!title||title.length<3)continue;"
        + "  seen[dest]=1;"
        + "  var card=el.closest('div.MjjYud, div.g, div.xpd, div.Ww4FFb, g-card, article, div[data-hveid]')||el.parentElement;"
        + "  var snippet='';"
        + "  if(card){"
        + "    var snNode=card.querySelector('div.VwiC3b, div.GI74Re, div.BNeawe.s3v9rd, span.aCOpRe');"
        + "    if(snNode){snippet=(snNode.innerText||'').trim();}"
        + "    else{"
        + "      var lines=(card.innerText||'').split('\\n');"
        + "      for(var k=0;k<lines.length;k++){"
        + "        var ln=lines[k].trim();"
        + "        if(ln.length>38&&ln!==title&&ln.indexOf('http')!==0){if(ln.length>snippet.length)snippet=ln;}"
        + "      }"
        + "    }"
        + "  }"
        + "  var thumb='';"
        + "  if(card){var th=card.querySelector('img');if(th&&(th.src||'').indexOf('http')===0&&th.width>=60)thumb=th.src;}"
        + "  var item={title:title,url:dest,snippet:snippet.slice(0,320),sourceLabel:hostTitle(dest),thumbnailUrl:thumb};"
        + "  if(mode==='videos')videoResults.push(item);"
        + "  else if(mode==='news')newsResults.push(item);"
        + "  else webResults.push(item);"
        + "  if(webResults.length>=24||videoResults.length>=20||newsResults.length>=20)break;"
        + "}"
        + "var kc=null;"
        + "var kTitle=document.querySelector('[data-attrid=\"title\"], div.PZPZlf.ssJ7i');"
        + "var kDesc=document.querySelector('[data-attrid*=\"description\"], div.kno-rdesc, span.hgKElc');"
        + "if(kDesc){"
        + "  var kt=kTitle?(kTitle.innerText||'').trim():'Overview';"
        + "  var kd=(kDesc.innerText||'').replace(/^Description\\s*/i,'').trim();"
        + "  var ka=kDesc.querySelector('a[href]');"
        + "  var ku=(ka&&unwrap(ka.href))||(webResults[0]?webResults[0].url:'https://www.google.com');"
        + "  if(kd.length>25){kc={heading:kt,summary:kd.slice(0,420),sourceUrl:ku,sourceName:hostTitle(ku)};}"
        + "}"
        + "var relLinks=document.querySelectorAll('a[href*=\"/search?\"]');"
        + "var relSeen={};"
        + "for(var r=0;r<relLinks.length&&related.length<6;r++){"
        + "  var rl=relLinks[r];"
        + "  if(rl.closest('header, nav, #hdtb'))continue;"
        + "  try{"
        + "    var ru=new URL(rl.href,location.origin);"
        + "    if(ru.searchParams.get('udm')||ru.searchParams.get('tbm')||ru.searchParams.get('tbs'))continue;"
        + "    var rq=(ru.searchParams.get('q')||'').trim();"
        + "    var txt=(rl.innerText||'').trim();"
        + "    if(rq&&txt&&rq.length>=3&&txt.length<70&&!relSeen[rq.toLowerCase()]){"
        + "      relSeen[rq.toLowerCase()]=1;related.push(rq);"
        + "    }"
        + "  }catch(e){}"
        + "}"
        + "return JSON.stringify({status:'ok',webResults:webResults,videoResults:videoResults,newsResults:newsResults,knowledgeCard:kc,relatedSearches:related});"
        + "}catch(err){return JSON.stringify({status:'err',msg:String(err)});}"
        + "})();";
  }

  private static Map<String, Object> parseEvaluatedJson(String rawJsResult) {
    if (rawJsResult == null || rawJsResult.isEmpty() || "null".equals(rawJsResult)) {
      return null;
    }
    try {
      String decoded = rawJsResult;
      if (decoded.startsWith("\"") && decoded.endsWith("\"")) {
        JSONArray wrapper = new JSONArray("[" + decoded + "]");
        decoded = wrapper.getString(0);
      }
      JSONObject obj = new JSONObject(decoded);
      return jsonObjectToMap(obj);
    } catch (Throwable ignored) {
      return null;
    }
  }

  private static Map<String, Object> jsonObjectToMap(JSONObject obj) {
    Map<String, Object> map = new HashMap<>();
    JSONArray names = obj.names();
    if (names == null) {
      return map;
    }
    for (int i = 0; i < names.length(); i++) {
      String key = names.optString(i);
      Object val = obj.opt(key);
      if (val == null || val == JSONObject.NULL) {
        continue;
      }
      if (val instanceof JSONObject) {
        map.put(key, jsonObjectToMap((JSONObject) val));
      } else if (val instanceof JSONArray) {
        map.put(key, jsonArrayToList((JSONArray) val));
      } else {
        map.put(key, val);
      }
    }
    return map;
  }

  private static List<Object> jsonArrayToList(JSONArray arr) {
    List<Object> list = new ArrayList<>(arr.length());
    for (int i = 0; i < arr.length(); i++) {
      Object val = arr.opt(i);
      if (val == null || val == JSONObject.NULL) {
        continue;
      }
      if (val instanceof JSONObject) {
        list.add(jsonObjectToMap((JSONObject) val));
      } else if (val instanceof JSONArray) {
        list.add(jsonArrayToList((JSONArray) val));
      } else {
        list.add(val);
      }
    }
    return list;
  }

  public void destroy() {
    mainHandler.post(
        () -> {
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
