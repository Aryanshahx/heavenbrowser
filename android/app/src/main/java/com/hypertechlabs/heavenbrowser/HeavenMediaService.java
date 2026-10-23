package com.hypertechlabs.heavenbrowser;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Native foreground media playback service with active Android MediaSession, AudioFocus,
 * PARTIAL_WAKE_LOCK, and WifiLock so YouTube, Twitch, podcasts, and web audio continue playing
 * without interruption when the screen is off or Heaven is in the background.
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

  private static final String CHANNEL_ID = "heaven_bg_media_v14";
  private static final int NOTIF_ID = 68130;

  private PowerManager.WakeLock cpuWakeLock;
  private WifiManager.WifiLock wifiLock;
  private MediaSession mediaSession;
  private AudioFocusRequest audioFocusRequest;
  private final AudioManager.OnAudioFocusChangeListener focusListener =
      focusChange -> {
        // Keep WebView playback active across transient ducking; pause only if user stops.
      };

  private String currentTitle = "Background Audio";
  private String currentHost = "Heaven";
  private boolean isPlaying = true;

  @Override
  public void onCreate() {
    super.onCreate();
    ensureChannel();
    initMediaSession();
    acquireLocksAndAudioFocus();
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    String action = intent != null ? intent.getAction() : null;
    if (ACTION_STOP_BG.equals(action)) {
      broadcastCommand("stop");
      releaseLocksAndAudioFocus();
      releaseMediaSession();
      stopForegroundSafe();
      stopSelf();
      return START_NOT_STICKY;
    }

    if (ACTION_TOGGLE_PLAY.equals(action)) {
      isPlaying = !isPlaying;
      broadcastCommand(isPlaying ? "play" : "pause");
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

    updateMediaSessionState();
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
      acquireLocksAndAudioFocus();
    } else {
      releaseLocksAndAudioFocus();
    }
    return START_STICKY;
  }

  @Override
  public void onDestroy() {
    releaseLocksAndAudioFocus();
    releaseMediaSession();
    stopForegroundSafe();
    super.onDestroy();
  }

  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }

  private void broadcastCommand(String cmd) {
    Intent evt = new Intent(ACTION_BROADCAST_MEDIA_CMD);
    evt.setPackage(getPackageName());
    evt.putExtra("cmd", cmd);
    sendBroadcast(evt);
  }

  private void initMediaSession() {
    try {
      mediaSession = new MediaSession(this, "HeavenBgMediaSession");
      mediaSession.setCallback(
          new MediaSession.Callback() {
            @Override
            public void onPlay() {
              isPlaying = true;
              acquireLocksAndAudioFocus();
              updateMediaSessionState();
              refreshNotification();
              broadcastCommand("play");
            }

            @Override
            public void onPause() {
              isPlaying = false;
              releaseLocksAndAudioFocus();
              updateMediaSessionState();
              refreshNotification();
              broadcastCommand("pause");
            }

            @Override
            public void onStop() {
              isPlaying = false;
              broadcastCommand("stop");
              releaseLocksAndAudioFocus();
              releaseMediaSession();
              stopForegroundSafe();
              stopSelf();
            }
          });
      mediaSession.setActive(true);
      updateMediaSessionState();
    } catch (Throwable ignored) {
    }
  }

  private void updateMediaSessionState() {
    if (mediaSession == null) {
      return;
    }
    try {
      long actions =
          PlaybackState.ACTION_PLAY
              | PlaybackState.ACTION_PAUSE
              | PlaybackState.ACTION_PLAY_PAUSE
              | PlaybackState.ACTION_STOP;
      PlaybackState state =
          new PlaybackState.Builder()
              .setActions(actions)
              .setState(
                  isPlaying ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED,
                  PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                  isPlaying ? 1.0f : 0.0f)
              .build();
      mediaSession.setPlaybackState(state);

      MediaMetadata metadata =
          new MediaMetadata.Builder()
              .putString(MediaMetadata.METADATA_KEY_TITLE, currentTitle)
              .putString(MediaMetadata.METADATA_KEY_ARTIST, currentHost)
              .putString(MediaMetadata.METADATA_KEY_ALBUM, "Heaven")
              .build();
      mediaSession.setMetadata(metadata);
      mediaSession.setActive(true);
    } catch (Throwable ignored) {
    }
  }

  private void refreshNotification() {
    try {
      NotificationManager nm =
          (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null) {
        nm.notify(NOTIF_ID, buildMediaNotification());
      }
    } catch (Throwable ignored) {
    }
  }

  private void releaseMediaSession() {
    if (mediaSession != null) {
      try {
        mediaSession.setActive(false);
        mediaSession.release();
      } catch (Throwable ignored) {
      }
      mediaSession = null;
    }
  }

  private void ensureChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      NotificationManager nm =
          (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null) {
        NotificationChannel ch =
            new NotificationChannel(
                CHANNEL_ID,
                "Background Audio Playback",
                NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Lock-screen controls for background audio & video in Heaven");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
      }
    }
  }

  @SuppressWarnings("deprecation")
  private Notification buildMediaNotification() {
    Intent openIntent = new Intent(Intent.ACTION_MAIN);
    openIntent.setClassName(getPackageName(), "com.hypertechlabs.heavenbrowser.MainActivity");
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

    b.setSmallIcon(isPlaying ? android.R.drawable.ic_media_play : android.R.drawable.ic_media_pause)
        .setContentTitle(currentTitle)
        .setContentText((isPlaying ? "Playing - " : "Paused - ") + currentHost)
        .setContentIntent(contentPi)
        .setOngoing(isPlaying)
        .setOnlyAlertOnce(true)
        .setVisibility(Notification.VISIBILITY_PUBLIC)
        .setCategory(Notification.CATEGORY_TRANSPORT)
        .addAction(
            new Notification.Action.Builder(
                    isPlaying
                        ? android.R.drawable.ic_media_pause
                        : android.R.drawable.ic_media_play,
                    isPlaying ? "Pause" : "Play",
                    togglePi)
                .build())
        .addAction(
            new Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPi)
                .build());

    if (mediaSession != null) {
      Notification.MediaStyle style =
          new Notification.MediaStyle()
              .setMediaSession(mediaSession.getSessionToken())
              .setShowActionsInCompactView(0, 1);
      b.setStyle(style);
    }
    return b.build();
  }

  @SuppressWarnings("deprecation")
  private void acquireLocksAndAudioFocus() {
    try {
      AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      if (am != null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          if (audioFocusRequest == null) {
            AudioAttributes attrs =
                new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
            audioFocusRequest =
                new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(true)
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener(focusListener)
                    .build();
          }
          am.requestAudioFocus(audioFocusRequest);
        } else {
          am.requestAudioFocus(
              focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
        }
      }
    } catch (Throwable ignored) {
    }

    try {
      if (cpuWakeLock == null) {
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
          cpuWakeLock =
              pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Heaven::BgAudioWakeLock");
          cpuWakeLock.setReferenceCounted(false);
        }
      }
      if (cpuWakeLock != null && !cpuWakeLock.isHeld()) {
        cpuWakeLock.acquire(6 * 60 * 60 * 1000L);
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
          wifiLock = wm.createWifiLock(mode, "Heaven::BgAudioWifiLock");
          wifiLock.setReferenceCounted(false);
        }
      }
      if (wifiLock != null && !wifiLock.isHeld()) {
        wifiLock.acquire();
      }
    } catch (Throwable ignored) {
    }
  }

  @SuppressWarnings("deprecation")
  private void releaseLocksAndAudioFocus() {
    try {
      AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      if (am != null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
          am.abandonAudioFocusRequest(audioFocusRequest);
        } else {
          am.abandonAudioFocus(focusListener);
        }
      }
    } catch (Throwable ignored) {
    }
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
