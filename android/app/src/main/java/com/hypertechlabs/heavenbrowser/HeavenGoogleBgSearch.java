package com.hypertechlabs.heavenbrowser;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
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
 * Genuine Android Chromium background Google Search engine.
 *
 * <p>Uses an isolated OffscreenActiveWebView with the device's authentic Android Chrome User-Agent
 * (without WebView "; wv" markers and with zero JS prototype tampering or gen_204 blocking) so
 * Google's SearchGuard (SG_SS) VM validates cleanly and returns the exact live Google SERP in
 * Google's exact visual order while stripping all Sponsored / Google Ad slots.
 */
public final class HeavenGoogleBgSearch {

  private static final String FALLBACK_ANDROID_CHROME_UA =
      "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36";

  private static final long COLD_MAX_WAIT_MS = 9000L;
  private static final long WARM_MAX_WAIT_MS = 6500L;
  private static final long POLL_INTERVAL_MS = 95L;
  private static final byte[] EMPTY_BYTES = new byte[0];

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private OffscreenActiveWebView bgWebView;
  private ActiveSearchJob activeJob;
  private int jobCounter = 0;
  private boolean prewarmed = false;
  private boolean warmCookieConfirmed = false;

  /**
   * Standalone offscreen WebView that reports View.VISIBLE to Chromium's scheduler so
   * requestAnimationFrame and SearchGuard (SG_SS) execute at full speed without attaching to the
   * Activity view tree.
   */
  private static final class OffscreenActiveWebView extends WebView {
    OffscreenActiveWebView(Context context) {
      super(context);
    }

    @Override
    protected void onWindowVisibilityChanged(int visibility) {
      super.onWindowVisibilityChanged(View.VISIBLE);
    }

    @Override
    protected void onVisibilityChanged(View changedView, int visibility) {
      super.onVisibilityChanged(changedView, View.VISIBLE);
    }
  }

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

  private static String buildCleanAndroidChromeUa(Context context) {
    try {
      String raw = WebSettings.getDefaultUserAgent(context);
      if (raw != null && !raw.isEmpty()) {
        String cleaned =
            raw.replace("; wv)", ")")
                .replace("; wv;", ";")
                .replace(" Version/4.0 ", " ")
                .replace("Version/4.0 ", "");
        if (cleaned.contains("Chrome/")) {
          return cleaned;
        }
      }
    } catch (Throwable ignored) {
    }
    return FALLBACK_ANDROID_CHROME_UA;
  }

  public void attachToActivityAndPrewarm(final Activity activity) {
    if (activity == null) {
      return;
    }
    mainHandler.postDelayed(
        () -> {
          try {
            ensureWebViewOnMain();
            if (!prewarmed && bgWebView != null && activeJob == null) {
              prewarmed = true;
              Map<String, String> headers = buildAcceptLangHeaders(null);
              bgWebView.loadUrl("https://www.google.com/search?q=weather&hl=en", headers);
            }
          } catch (Throwable ignored) {
          }
        },
        600L);
  }

  public void detachFromActivity() {
    // OffscreenActiveWebView stays completely isolated from Activity view hierarchy.
  }

  private static Map<String, String> buildAcceptLangHeaders(String langHeader) {
    Map<String, String> headers = new HashMap<>(2);
    String fallbackLang = Locale.getDefault().toLanguageTag() + ",en-US;q=0.9,en;q=0.8";
    headers.put(
        "Accept-Language",
        (langHeader != null && !langHeader.isEmpty()) ? langHeader : fallbackLang);
    return headers;
  }

  @SuppressLint("SetJavaScriptEnabled")
  private void ensureWebViewOnMain() {
    if (bgWebView == null) {
      bgWebView = new OffscreenActiveWebView(appContext);

      WebSettings s = bgWebView.getSettings();
      s.setJavaScriptEnabled(true);
      s.setDomStorageEnabled(true);
      s.setUseWideViewPort(true);
      s.setLoadWithOverviewMode(true);
      s.setUserAgentString(buildCleanAndroidChromeUa(appContext));
      s.setCacheMode(WebSettings.LOAD_DEFAULT);
      s.setMediaPlaybackRequiresUserGesture(true);
      s.setJavaScriptCanOpenWindowsAutomatically(false);
      // Keep network images enabled so Google's new Image().src = '/gen_204?...' SearchGuard
      // beacons AND result/video thumbnails load naturally just like Android Chrome!
      s.setLoadsImagesAutomatically(true);
      s.setBlockNetworkImage(false);

      CookieManager cm = CookieManager.getInstance();
      cm.setAcceptCookie(true);
      cm.setAcceptThirdPartyCookies(bgWebView, true);

      bgWebView.setWebViewClient(
          new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(
                WebView view, WebResourceRequest request) {
              try {
                if (request != null && request.getUrl() != null) {
                  Uri u = request.getUrl();
                  String host = u.getHost() != null ? u.getHost().toLowerCase(Locale.US) : "";
                  // Block ONLY third-party ad delivery hosts; NEVER touch google.*, gstatic.*, or
                  // /gen_204 so SearchGuard (SG_SS) validates identically to Chrome!
                  if (host.endsWith("doubleclick.net")
                      || host.endsWith("googlesyndication.com")
                      || host.endsWith("googleadservices.com")
                      || host.endsWith("google-analytics.com")) {
                    return new WebResourceResponse(
                        "text/plain", "UTF-8", new ByteArrayInputStream(EMPTY_BYTES));
                  }
                }
              } catch (Throwable ignored) {
              }
              return super.shouldInterceptRequest(view, request);
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
              if (url != null && url.contains("/sorry/")) {
                finishJobEmpty("captcha");
              }
            }

            @Override
            public void onPageFinished(WebView view, String url) {
              try {
                CookieManager.getInstance().flush();
                if (url != null && url.contains("google.") && !url.contains("/sorry/")) {
                  String ck = CookieManager.getInstance().getCookie("https://www.google.com");
                  if (ck != null && ck.contains("SG_SS")) {
                    warmCookieConfirmed = true;
                  }
                }
                if (activeJob == null || activeJob.completed) {
                  return;
                }
                if (url != null && url.contains("/sorry/")) {
                  finishJobEmpty("captcha");
                  return;
                }
                pollDomExtraction(activeJob.id);
              } catch (Throwable ignored) {
              }
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

    try {
      bgWebView.onResume();
      bgWebView.resumeTimers();
      bgWebView.measure(
          View.MeasureSpec.makeMeasureSpec(412, View.MeasureSpec.EXACTLY),
          View.MeasureSpec.makeMeasureSpec(915, View.MeasureSpec.EXACTLY));
      bgWebView.layout(0, 0, 412, 915);
    } catch (Throwable ignored) {
    }
  }

  public void searchInBackground(
      final String query,
      final String tab,
      final String safeMode,
      final String timeCode,
      final String regionCode,
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
          final int jobId = ++jobCounter;
          prewarmed = true;
          activeJob =
              new ActiveSearchJob(jobId, cleanTab, callback, System.currentTimeMillis());

          String effectiveQuery =
              "cws".equals(cleanTab)
                  ? "site:chromewebstore.google.com/detail " + query.trim()
                  : query.trim();
          String targetUrl =
              buildGoogleUrl(effectiveQuery, cleanTab, safeMode, timeCode, regionCode);
          Map<String, String> headers = buildAcceptLangHeaders(langHeader);

          bgWebView.stopLoading();
          bgWebView.loadUrl(targetUrl, headers);

          mainHandler.postDelayed(() -> pollDomExtraction(jobId), 170L);
        });
  }

  private static String buildGoogleUrl(
      String query, String tab, String safeMode, String timeCode, String regionCode) {
    String encoded = Uri.encode(query);
    StringBuilder sb =
        new StringBuilder("https://www.google.com/search?q=").append(encoded).append("&hl=en");

    if (regionCode != null && !regionCode.trim().isEmpty()) {
      String gl = regionCode.trim().toLowerCase(Locale.US);
      if (gl.length() == 2 && !"wt".equals(gl)) {
        sb.append("&gl=").append(Uri.encode(gl));
      }
    }

    if ("strict".equalsIgnoreCase(safeMode)) {
      sb.append("&safe=active");
    } else if ("off".equalsIgnoreCase(safeMode)) {
      sb.append("&safe=off");
    }

    if ("images".equals(tab)) {
      sb.append("&udm=2");
    } else if ("videos".equals(tab)) {
      sb.append("&udm=7");
    } else if ("news".equals(tab)) {
      sb.append("&tbm=nws");
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
    final long maxBudget =
        (activeJob.sawChallenge || !warmCookieConfirmed) ? COLD_MAX_WAIT_MS : WARM_MAX_WAIT_MS;
    final boolean timedOut = elapsed >= maxBudget;

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
              mainHandler.postDelayed(() -> pollDomExtraction(jobId), 130L);
              return;
            }

            int count = countPrimaryItems(parsed, activeJob.tab);
            String readyState =
                parsed.get("readyState") != null ? parsed.get("readyState").toString() : "";
            boolean domDone = "complete".equals(readyState);
            boolean domInteractive = "interactive".equals(readyState) || domDone;

            // Wait for complete Google SERP instead of truncating at the first 4 streamed cards!
            boolean ready =
                (count >= 8 && domInteractive)
                    || (count >= 1 && domDone && elapsed >= 420L)
                    || (count >= 4 && domInteractive && elapsed >= 1750L);

            if (ready || (timedOut && count >= 1)) {
              warmCookieConfirmed = true;
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
        + "var consentBtn=document.querySelector('button#L2AGLb, button#W0wltc, form[action*=\"consent.google\"] button[type=\"submit\"], div[role=\"dialog\"] button#L2AGLb');"
        + "if(consentBtn){consentBtn.click();return JSON.stringify({status:'consent_clicked'});}"
        + "var retryEl=document.querySelector('a[href*=\"/httpservice/retry/enablejs\"], meta[http-equiv=\"refresh\"]');"
        + "var hasSerpRoot=!!document.querySelector('#rso, #search, #main div.MjjYud, #main div.xpd, #main div.Ww4FFb');"
        + "if(!hasSerpRoot&&(retryEl||(document.title||'').trim()==='Google Search')){"
        + "  return JSON.stringify({status:'solving_challenge'});"
        + "}"
        + "var mode='"
        + escapedTab
        + "';"
        + "function txt(el){return el?((el.innerText||el.textContent||'').replace(/\\s+/g,' ').trim()):'';}"
        + "function isAdNode(el){"
        + "  if(!el)return false;"
        + "  var adAnc=el.closest('#tads, #bottomads, #tvcap, [data-text-ad], [data-rw], [aria-label=\"Ads\"], [aria-label=\"Sponsored\"]');"
        + "  if(adAnc)return true;"
        + "  var blk=el.closest('div.MjjYud, div.xpd, div.g, div.uEierd');"
        + "  if(blk){"
        + "    var firstLine=(blk.innerText||'').trim().slice(0,28).toLowerCase();"
        + "    if(firstLine.indexOf('sponsored')===0||firstLine.indexOf('ad\\n')===0)return true;"
        + "  }"
        + "  return false;"
        + "}"
        + "function unwrap(u){"
        + "  if(!u)return '';"
        + "  try{"
        + "    var parsed=new URL(u,location.origin);"
        + "    var hn=parsed.hostname.toLowerCase();"
        + "    if(hn.indexOf('googleadservices.com')!==-1||parsed.pathname==='/aclk')return '';"
        + "    if(hn.indexOf('google.')!==-1&&hn!=='chromewebstore.google.com'&&hn!=='chrome.google.com'&&hn!=='news.google.com'){"
        + "      if(parsed.pathname==='/url'||parsed.pathname==='/imgres'){"
        + "        return parsed.searchParams.get('q')||parsed.searchParams.get('url')||parsed.searchParams.get('imgurl')||'';"
        + "      }"
        + "      return '';"
        + "    }"
        + "    if(parsed.protocol==='http:'||parsed.protocol==='https:'){"
        + "      parsed.hash=(parsed.hash&&parsed.hash.indexOf(':~:text=')===0)?'':parsed.hash;"
        + "      return parsed.href;"
        + "    }"
        + "  }catch(e){}"
        + "  return '';"
        + "}"
        + "function hostTitle(u){"
        + "  try{var h=new URL(u).hostname.replace(/^www\\./,'').replace(/^m\\./,'');var p=h.split('.')[0]||h;return p.charAt(0).toUpperCase()+p.slice(1);}catch(e){return 'Web';}"
        + "}"
        + "function extractHeadingFromAnchor(a){"
        + "  var hEl=a.querySelector('h3, h2, h4, [role=\"heading\"], .MBeuO, .v7jaNc, .ynAwRc, .vvjwJb, .q8U8x, .oewGkc, .n0jPhd, .CVA68e, .F0FGWb, .cHaqb, .fc9yUc, .JjtOHd');"
        + "  var t=txt(hEl);"
        + "  if(t&&t.length>=2)return t;"
        + "  var parentCard=a.closest('div.MjjYud, div.Ww4FFb, div.xpd, div.g, div.SoaBEf, g-card, article');"
        + "  if(parentCard){"
        + "    var siblingH=parentCard.querySelector('[role=\"heading\"], h3, .MBeuO, .v7jaNc, .vvjwJb');"
        + "    if(siblingH&&(!siblingH.closest('a')||siblingH.closest('a')===a)){"
        + "      var st=txt(siblingH);"
        + "      if(st&&st.length>=3)return st;"
        + "    }"
        + "  }"
        + "  var aria=(a.getAttribute('aria-label')||'').trim();"
        + "  if(aria.length>=6&&aria.length<=180)return aria;"
        + "  var lines=(a.innerText||'').split('\\n').map(function(s){return s.trim();}).filter(function(s){return s.length>=3&&s.indexOf('http')!==0&&s.indexOf('\\u203a')===-1;});"
        + "  if(lines.length===1)return lines[0];"
        + "  if(lines.length>=2)return lines[lines.length-1];"
        + "  return '';"
        + "}"
        + "function extractThumbFromCard(card){"
        + "  if(!card)return '';"
        + "  var imgs=card.querySelectorAll('img');"
        + "  for(var k=0;k<imgs.length;k++){"
        + "    var im=imgs[k];"
        + "    var w=im.naturalWidth||im.width||im.clientWidth||0;"
        + "    var h=im.naturalHeight||im.height||im.clientHeight||0;"
        + "    if(w>0&&w<=36&&h>0&&h<=36)continue;"
        + "    var s=im.currentSrc||im.src||im.getAttribute('data-src')||'';"
        + "    if(!s||s.indexOf('gstatic.com/images/branding')!==-1)continue;"
        + "    if(s.indexOf('http')===0||(s.indexOf('data:image')===0&&s.length>1200))return s;"
        + "  }"
        + "  return '';"
        + "}"
        + "var webResults=[],imageResults=[],videoResults=[],newsResults=[],related=[];"
        + "var seen={};"
        + "if(mode==='images'){"
        + "  var imgs=document.querySelectorAll('#rso img, #search img, #main img, div[data-id] img');"
        + "  for(var i=0;i<imgs.length&&imageResults.length<36;i++){"
        + "    var im=imgs[i];"
        + "    if(isAdNode(im))continue;"
        + "    var src=im.currentSrc||im.src||im.getAttribute('data-src')||im.getAttribute('data-iurl')||'';"
        + "    if(!src||src.indexOf('gstatic.com/images/branding')!==-1||src.indexOf('googlelogo')!==-1)continue;"
        + "    var w=im.naturalWidth||im.width||im.clientWidth||0;var h=im.naturalHeight||im.height||im.clientHeight||0;"
        + "    if(w>0&&w<52&&h>0&&h<52)continue;"
        + "    if(src.indexOf('http')!==0&&src.indexOf('data:image')!==0)continue;"
        + "    if(src.indexOf('data:image')===0&&src.length<900)continue;"
        + "    var a=im.closest('a');"
        + "    var pageUrl=a?unwrap(a.href):'';"
        + "    var alt=(im.alt||'').trim();"
        + "    if(!alt&&a)alt=txt(a);"
        + "    if(!alt)alt='Image result';"
        + "    if(seen[src])continue;seen[src]=1;"
        + "    imageResults.push({title:alt.slice(0,130),thumbUrl:src,fullUrl:src,pageUrl:pageUrl||src});"
        + "  }"
        + "  return JSON.stringify({status:'ok',readyState:document.readyState,imageResults:imageResults});"
        + "}"
        + "var anchors=document.querySelectorAll('#rso a[href], #search a[href], #main a[href]');"
        + "for(var j=0;j<anchors.length;j++){"
        + "  var el=anchors[j];"
        + "  if(isAdNode(el))continue;"
        + "  if(el.closest('#bres, [aria-label=\"Related searches\"]'))continue;"
        + "  var dest=unwrap(el.href);"
        + "  if(!dest||seen[dest])continue;"
        + "  if(dest.indexOf('translate.google.')!==-1||dest.indexOf('webcache.googleusercontent.')!==-1||dest.indexOf('accounts.google.')!==-1||dest.indexOf('support.google.com/websearch')!==-1)continue;"
        + "  var title=extractHeadingFromAnchor(el);"
        + "  if(!title||title.length<3)continue;"
        + "  var tl=title.toLowerCase();"
        + "  if(tl==='read more'||tl==='more results'||tl==='cached'||tl==='similar'||tl==='view all')continue;"
        + "  seen[dest]=1;"
        + "  var card=el.closest('div.MjjYud, div.Ww4FFb, div.xpd, div.g, div.SoaBEf, g-card, article, div[data-hveid]')||el.parentElement;"
        + "  var snippet='';"
        + "  if(card){"
        + "    var snNodes=card.querySelectorAll('div.VwiC3b, div[data-sncf=\"1\"], div[data-sncf=\"2\"], div[data-sncf=\"1,2\"], div.w1C3Le, span.fYyStc, span.yDYNvb, div.GI74Re, div.ITZIwc, div.BNeawe.s3v9rd, span.aCOpRe, div.ukyZMd, div.LGOjhe, span.hgKElc');"
        + "    for(var sIdx=0;sIdx<snNodes.length;sIdx++){"
        + "      var cand=txt(snNodes[sIdx]);"
        + "      if(cand.length>snippet.length&&cand!==title){snippet=cand;}"
        + "    }"
        + "    if(!snippet){"
        + "      var rawLines=(card.innerText||'').split('\\n').map(function(s){return s.trim();}).filter(function(s){return s.length>22&&s!==title&&s.indexOf('http')!==0;});"
        + "      if(rawLines.length>0){snippet=rawLines.join(' ');}"
        + "    }"
        + "  }"
        + "  var citeEl=card?card.querySelector('span.VuuXrf, div.q0vns span, span.OSrXXb, div.byrV5b, cite'):null;"
        + "  var srcName=txt(citeEl);"
        + "  if(!srcName||srcName.length>38||srcName.indexOf('http')===0)srcName=hostTitle(dest);"
        + "  var thumb=extractThumbFromCard(card);"
        + "  var item={title:title.slice(0,180),url:dest,snippet:snippet.slice(0,340),sourceLabel:srcName,thumbnailUrl:thumb};"
        + "  if(mode==='videos')videoResults.push(item);"
        + "  else if(mode==='news')newsResults.push(item);"
        + "  else webResults.push(item);"
        + "  if(webResults.length>=25||videoResults.length>=22||newsResults.length>=22)break;"
        + "}"
        + "var kc=null;"
        + "var kTitle=document.querySelector('[data-attrid=\"title\"], div.PZPZlf[data-attrid=\"title\"], h2[data-attrid=\"title\"], div.SPZz6b h2');"
        + "var kDesc=document.querySelector('[data-attrid*=\"description\"], div.kno-rdesc, span.hgKElc, div.LGOjhe, div.IZ6rdc');"
        + "if(kDesc){"
        + "  var kt=txt(kTitle)||'Google Overview';"
        + "  var kd=txt(kDesc).replace(/^Description\\s*/i,'').replace(/Wikipedia\\s*$/i,'').trim();"
        + "  var ka=kDesc.querySelector('a[href]');"
        + "  var ku=(ka&&unwrap(ka.href))||(webResults[0]?webResults[0].url:'https://www.google.com');"
        + "  if(kd.length>25){kc={heading:kt,summary:kd.slice(0,460),sourceUrl:ku,sourceName:hostTitle(ku)};}"
        + "}"
        + "var relNodes=document.querySelectorAll('#bres a[href*=\"/search?\"], a.k8XOCe, div.s75CSd, a.ngTNl, div.f3LoEf, span.dg6jd');"
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
