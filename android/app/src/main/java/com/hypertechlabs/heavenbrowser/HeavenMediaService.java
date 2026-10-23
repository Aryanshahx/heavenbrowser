package com.hypertechlabs.heavenbrowser;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Lightweight native foreground service that keeps WebView audio/video streams (YouTube, Twitch,
 * podcasts, live streams) playing cleanly when the screen is locked or Heaven Browser is in the
 * background.
 */
public final class HeavenMediaService extends Service {

  public static final String ACTION_START_OR_UPDATE =
      "com.hypertechlabs.heavenbrowser.MEDIA_START_OR_UPDATE";
  public static final String ACTION_TOGGLE_PLAY =
      "com.hypertechlabs.heavenbrowser.MEDIA_TOGGLE_PLAY";
  public static final String ACTION_STOP_BG =
      "com.hypertechlabs.heavenbrowser.MEDIA_STOP_BG";
  public static final String ACTION_BROADCAST_MEDIA_CMD =
      "com.hypertechlabs.heavenbrowser.MEDIA_COMMAND_EVENT";

  public static final String EXTRA_TITLE = "media_title";
  public static final String EXTRA_HOST = "media_host";
  public static final String EXTRA_PLAYING = "media_playing";
  public static final String EXTRA_SHOW_NOTIF = "show_notif";

  private static final String CHANNEL_ID = "heaven_bg_media_v13";
  private static final int NOTIF_ID = 68130;

  private PowerManager.WakeLock cpuWakeLock;
  private WifiManager.WifiLock wifiLock;
  private String currentTitle = "Background Media Active";
  private String currentHost = "Heaven Browser";
  private boolean isPlaying = true;

  @Override
  public void onCreate() {
    super.onCreate();
    ensureChannel();
    acquireLocks();
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    String action = intent != null ? intent.getAction() : null;
    if (ACTION_STOP_BG.equals(action)) {
      Intent evt = new Intent(ACTION_BROADCAST_MEDIA_CMD);
      evt.setPackage(getPackageName());
      evt.putExtra("cmd", "stop");
      sendBroadcast(evt);
      stopForegroundSafe();
      stopSelf();
      return START_NOT_STICKY;
    }

    if (ACTION_TOGGLE_PLAY.equals(action)) {
      isPlaying = !isPlaying;
      Intent evt = new Intent(ACTION_BROADCAST_MEDIA_CMD);
      evt.setPackage(getPackageName());
      evt.putExtra("cmd", isPlaying ? "play" : "pause");
      sendBroadcast(evt);
    } else if (intent != null) {
      String t = intent.getStringExtra(EXTRA_TITLE);
      String h = intent.getStringExtra(EXTRA_HOST);
      if (t != null && !t.trim().isEmpty()) {
        currentTitle = t.trim();
      }
      if (h != null && !h.trim().isEmpty()) {
        currentHost = h.trim();
      }
      isPlaying = intent.getBooleanExtra(EXTRA_PLAYING, true);
    }

    Notification notification = buildMediaNotification();
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(
            NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
      } else {
        startForeground(NOTIF_ID, notification);
      }
    } catch (Throwable ignored) {
      stopSelf();
      return START_NOT_STICKY;
    }

    if (isPlaying) {
      acquireLocks();
    } else {
      releaseLocks();
    }
    return START_NOT_STICKY;
  }

  @Override
  public void onDestroy() {
    releaseLocks();
    stopForegroundSafe();
    super.onDestroy();
  }

  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }

  private void ensureChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      NotificationManager nm =
          (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null) {
        NotificationChannel ch =
            new NotificationChannel(
                CHANNEL_ID,
                "Background Audio & Video Playback",
                NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Controls for background YouTube, Twitch & web audio playback");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
      }
    }
  }

  @SuppressWarnings("deprecation")
  private Notification buildMediaNotification() {
    Intent openIntent = new Intent(Intent.ACTION_MAIN);
    openIntent.setClassName(
        getPackageName(), "com.hypertechlabs.heavenbrowser.MainActivity");
    openIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    int piFlags =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            ? (PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE)
            : PendingIntent.FLAG_UPDATE_CURRENT;
    PendingIntent contentPi = PendingIntent.getActivity(this, 8810, openIntent, piFlags);

    Intent toggleIntent = new Intent(this, HeavenMediaService.class);
    toggleIntent.setAction(ACTION_TOGGLE_PLAY);
    PendingIntent togglePi = PendingIntent.getService(this, 8811, toggleIntent, piFlags);

    Intent stopIntent = new Intent(this, HeavenMediaService.class);
    stopIntent.setAction(ACTION_STOP_BG);
    PendingIntent stopPi = PendingIntent.getService(this, 8812, stopIntent, piFlags);

    Notification.Builder b =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ? new Notification.Builder(this, CHANNEL_ID)
            : new Notification.Builder(this);

    b.setSmallIcon(android.R.drawable.ic_media_play)
        .setContentTitle(currentTitle)
        .setContentText(
            (isPlaying ? "Playing in background - " : "Paused - ") + currentHost)
        .setContentIntent(contentPi)
        .setOngoing(isPlaying)
        .setOnlyAlertOnce(true)
        .addAction(
            isPlaying ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play,
            isPlaying ? "Pause" : "Resume",
            togglePi)
        .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPi);

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      b.setVisibility(Notification.VISIBILITY_PUBLIC);
      b.setCategory(Notification.CATEGORY_TRANSPORT);
    }
    return b.build();
  }

  @SuppressWarnings("deprecation")
  private void acquireLocks() {
    try {
      if (cpuWakeLock == null) {
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
          cpuWakeLock =
              pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HeavenBrowser::BgMediaWakeLock");
          cpuWakeLock.setReferenceCounted(false);
        }
      }
      if (cpuWakeLock != null && !cpuWakeLock.isHeld()) {
        cpuWakeLock.acquire(4 * 60 * 60 * 1000L);
      }
    } catch (Throwable ignored) {
    }
    try {
      if (wifiLock == null) {
        WifiManager wm =
            (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wm != null) {
          int mode =
              Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                  ? WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                  : WifiManager.WIFI_MODE_FULL_HIGH_PERF;
          wifiLock = wm.createWifiLock(mode, "HeavenBrowser::BgMediaWifiLock");
          wifiLock.setReferenceCounted(false);
        }
      }
      if (wifiLock != null && !wifiLock.isHeld()) {
        wifiLock.acquire();
      }
    } catch (Throwable ignored) {
    }
  }

  private void releaseLocks() {
    try {
      if (cpuWakeLock != null && cpuWakeLock.isHeld()) {
        cpuWakeLock.release();
      }
    } catch (Throwable ignored) {
    }
    try {
      if (wifiLock != null && wifiLock.isHeld()) {
        wifiLock.release();
      }
    } catch (Throwable ignored) {
    }
  }

  @SuppressWarnings("deprecation")
  private void stopForegroundSafe() {
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        stopForeground(STOP_FOREGROUND_REMOVE);
      } else {
        stopForeground(true);
      }
    } catch (Throwable ignored) {
    }
  }
}
