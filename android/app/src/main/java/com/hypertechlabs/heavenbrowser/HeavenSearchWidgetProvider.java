package com.hypertechlabs.heavenbrowser;

import android.app.ActivityOptions;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Resources;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.widget.RemoteViews;

/**
 * Home Screen Search Bar Widget ("Heaven Search") — instant launch with zero transition lag,
 * Android 14+ Background Activity Launch (BAL) opt-in, resize/update resilience, Voice Search,
 * and instant Google-Lens Camera Search.
 */
public final class HeavenSearchWidgetProvider extends AppWidgetProvider {

  public static final String EXTRA_WIDGET_ACTION = "heaven_widget_action";
  public static final String ACTION_OMNIBOX = "omnibox";
  public static final String ACTION_VOICE = "voice";
  public static final String ACTION_CAMERA = "camera";

  private static final String FLUTTER_PREFS = "FlutterSharedPreferences";
  private static final String FLUTTER_SEARCH_ENGINE_KEY = "flutter.pref_search_engine_v2";

  @Override
  public void onReceive(Context context, Intent intent) {
    super.onReceive(context, intent);
    if (context == null || intent == null) {
      return;
    }
    String action = intent.getAction();
    if (Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
        || "android.appwidget.action.APPWIDGET_ENABLED".equals(action)) {
      refreshAllWidgets(context);
    }
  }

  @Override
  public void onEnabled(Context context) {
    super.onEnabled(context);
    refreshAllWidgets(context);
  }

  @Override
  public void onRestored(Context context, int[] oldWidgetIds, int[] newWidgetIds) {
    super.onRestored(context, oldWidgetIds, newWidgetIds);
    refreshAllWidgets(context);
  }

  @Override
  public void onAppWidgetOptionsChanged(
      Context context, AppWidgetManager appWidgetManager, int appWidgetId, Bundle newOptions) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions);
    if (context != null && appWidgetManager != null) {
      updateSingleWidget(context, appWidgetManager, appWidgetId);
    }
  }

  @Override
  public void onUpdate(
      Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
    if (context == null || appWidgetManager == null || appWidgetIds == null) {
      return;
    }
    for (int widgetId : appWidgetIds) {
      updateSingleWidget(context, appWidgetManager, widgetId);
    }
  }

  public static void refreshAllWidgets(Context context) {
    if (context == null) {
      return;
    }
    try {
      AppWidgetManager mgr = AppWidgetManager.getInstance(context);
      if (mgr == null) {
        return;
      }
      ComponentName provider = new ComponentName(context, HeavenSearchWidgetProvider.class);
      int[] ids = mgr.getAppWidgetIds(provider);
      if (ids != null && ids.length > 0) {
        for (int id : ids) {
          updateSingleWidget(context, mgr, id);
        }
      }
    } catch (Throwable ignored) {
    }
  }

  public static boolean isPinWidgetSupported(Context context) {
    if (context == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return false;
    }
    try {
      AppWidgetManager mgr = AppWidgetManager.getInstance(context);
      return mgr != null && mgr.isRequestPinAppWidgetSupported();
    } catch (Throwable ignored) {
      return false;
    }
  }

  public static boolean requestPinToHomeScreen(Context context) {
    if (context == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return false;
    }
    try {
      AppWidgetManager mgr = AppWidgetManager.getInstance(context);
      if (mgr == null || !mgr.isRequestPinAppWidgetSupported()) {
        return false;
      }
      ComponentName provider = new ComponentName(context, HeavenSearchWidgetProvider.class);
      return mgr.requestPinAppWidget(provider, null, null);
    } catch (Throwable ignored) {
      return false;
    }
  }

  private static void updateSingleWidget(
      Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
    try {
      String pkg = context.getPackageName();
      Resources res = context.getResources();
      int layoutId = res.getIdentifier("heaven_search_widget", "layout", pkg);
      if (layoutId == 0) {
        return;
      }

      RemoteViews views = new RemoteViews(pkg, layoutId);
      int rootId = res.getIdentifier("heaven_widget_root", "id", pkg);
      int logoId = res.getIdentifier("heaven_widget_logo", "id", pkg);
      int textId = res.getIdentifier("heaven_widget_search_text", "id", pkg);
      int micId = res.getIdentifier("heaven_widget_mic_btn", "id", pkg);
      int camId = res.getIdentifier("heaven_widget_camera_btn", "id", pkg);

      String engineLabel = readActiveEngineLabel(context);
      if (textId != 0) {
        views.setTextViewText(textId, "Search " + engineLabel + " or type URL");
      }

      int baseReq = Math.abs(appWidgetId) * 10;
      PendingIntent omniboxPi =
          buildLaunchPendingIntent(context, ACTION_OMNIBOX, appWidgetId, baseReq + 1);
      PendingIntent voicePi =
          buildLaunchPendingIntent(context, ACTION_VOICE, appWidgetId, baseReq + 2);
      PendingIntent cameraPi =
          buildLaunchPendingIntent(context, ACTION_CAMERA, appWidgetId, baseReq + 3);

      if (rootId != 0) {
        views.setOnClickPendingIntent(rootId, omniboxPi);
      }
      if (logoId != 0) {
        views.setOnClickPendingIntent(logoId, omniboxPi);
      }
      if (textId != 0) {
        views.setOnClickPendingIntent(textId, omniboxPi);
      }
      if (micId != 0) {
        views.setOnClickPendingIntent(micId, voicePi);
      }
      if (camId != 0) {
        views.setOnClickPendingIntent(camId, cameraPi);
      }

      appWidgetManager.updateAppWidget(appWidgetId, views);
    } catch (Throwable ignored) {
    }
  }

  private static String readActiveEngineLabel(Context context) {
    try {
      SharedPreferences sp = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE);
      String raw = sp.getString(FLUTTER_SEARCH_ENGINE_KEY, "google");
      if (raw == null) {
        return "Google";
      }
      switch (raw) {
        case "perplexity":
          return "Perplexity";
        case "duckDuckGo":
          return "DuckDuckGo";
        case "brave":
          return "Brave";
        case "bing":
          return "Bing";
        case "startpage":
          return "Startpage";
        default:
          return "Google";
      }
    } catch (Throwable ignored) {
      return "Google";
    }
  }

  private static PendingIntent buildLaunchPendingIntent(
      Context context, String widgetAction, int appWidgetId, int reqCode) {
    Intent launch = new Intent(Intent.ACTION_VIEW);
    launch.setComponent(
        new ComponentName(
            context.getPackageName(), "com.hypertechlabs.heavenbrowser.MainActivity"));
    launch.setData(Uri.parse("heaven://widget/" + widgetAction + "?wid=" + appWidgetId));
    launch.putExtra(EXTRA_WIDGET_ACTION, widgetAction);
    launch.addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK
            | Intent.FLAG_ACTIVITY_SINGLE_TOP
            | Intent.FLAG_ACTIVITY_CLEAR_TOP
            | Intent.FLAG_ACTIVITY_NO_ANIMATION);

    int flags = PendingIntent.FLAG_UPDATE_CURRENT;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      flags |= PendingIntent.FLAG_IMMUTABLE;
    }

    if (Build.VERSION.SDK_INT >= 34) {
      try {
        ActivityOptions opts = ActivityOptions.makeBasic();
        opts.setPendingIntentBackgroundActivityStartMode(
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED);
        return PendingIntent.getActivity(context, reqCode, launch, flags, opts.toBundle());
      } catch (Throwable ignored) {
      }
    }
    return PendingIntent.getActivity(context, reqCode, launch, flags);
  }
}
