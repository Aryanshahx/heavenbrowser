package com.hypertechlabs.heavenbrowser;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.MeteringRectangle;
import android.hardware.camera2.params.OutputConfiguration;
import android.hardware.camera2.params.SessionConfiguration;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.ExifInterface;
import android.media.Image;
import android.media.ImageReader;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Base64;
import android.util.Range;
import android.util.Size;
import android.view.Surface;
import android.webkit.CookieManager;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Instant 60fps Camera2 + Flutter SurfaceTexture viewfinder & native Google Lens multipart upload
 * engine for Heaven Visual Search.
 */
final class HeavenLensCameraManager {

  private static final String MOBILE_CHROME_UA =
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36";

  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final ExecutorService ioPool;

  private HandlerThread cameraThread;
  private Handler cameraHandler;
  private TextureRegistry.SurfaceTextureEntry surfaceEntry;
  private Surface previewSurface;
  private ImageReader jpegReader;
  private CameraDevice cameraDevice;
  private CameraCaptureSession captureSession;
  private CaptureRequest.Builder previewBuilder;

  private String activeCameraId;
  private boolean activeFrontFacing = false;
  private boolean hasFlashUnit = false;
  private boolean torchEnabled = false;
  private float currentZoom = 1.0f;
  private float maxZoom = 4.0f;
  private Rect sensorActiveArray;
  private int sensorOrientation = 90;
  private Size previewSize = new Size(1280, 960);

  HeavenLensCameraManager(ExecutorService ioPool) {
    this.ioPool = ioPool;
  }

  boolean hasCameraPermission(Activity act) {
    if (act == null) return false;
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true;
    return act.checkSelfPermission(Manifest.permission.CAMERA)
        == PackageManager.PERMISSION_GRANTED;
  }

  @SuppressLint("MissingPermission")
  void startCamera(
      final Context ctx,
      final TextureRegistry textureRegistry,
      final boolean wantFront,
      final MethodChannel.Result result) {
    if (ctx == null || textureRegistry == null) {
      Map<String, Object> err = new HashMap<>(4);
      err.put("ok", false);
      err.put("error", "Camera unavailable");
      result.success(err);
      return;
    }

    ensureCameraThread();
    final AtomicBoolean replied = new AtomicBoolean(false);

    cameraHandler.post(
        () -> {
          try {
            closeSessionOnlySync();
            CameraManager cm = (CameraManager) ctx.getSystemService(Context.CAMERA_SERVICE);
            if (cm == null) {
              replyOnce(replied, result, errorMap("Camera service unavailable"));
              return;
            }

            String chosenId = selectCameraId(cm, wantFront);
            if (chosenId == null) {
              replyOnce(replied, result, errorMap("No camera found on this device"));
              return;
            }

            CameraCharacteristics chars = cm.getCameraCharacteristics(chosenId);
            Integer lensFacing = chars.get(CameraCharacteristics.LENS_FACING);
            this.activeFrontFacing =
                lensFacing != null && lensFacing == CameraCharacteristics.LENS_FACING_FRONT;
            Boolean flashAvail = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
            this.hasFlashUnit = flashAvail != null && flashAvail && !this.activeFrontFacing;
            this.torchEnabled = false;
            this.currentZoom = 1.0f;
            Integer orient = chars.get(CameraCharacteristics.SENSOR_ORIENTATION);
            this.sensorOrientation = orient != null ? orient : 90;
            this.sensorActiveArray =
                chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);

            this.maxZoom = resolveMaxZoom(chars);

            StreamConfigurationMap map =
                chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size chosenPreview = chooseOptimalSize(map, SurfaceTexture.class, 1600, 1200);
            Size chosenJpeg = chooseOptimalJpegSize(map, 1920, 1440, chosenPreview);
            this.previewSize = chosenPreview;
            this.activeCameraId = chosenId;

            if (this.surfaceEntry == null) {
              final Object lock = new Object();
              mainHandler.post(
                  () -> {
                    synchronized (lock) {
                      try {
                        this.surfaceEntry = textureRegistry.createSurfaceTexture();
                      } catch (Throwable ignored) {
                      }
                      lock.notifyAll();
                    }
                  });
              synchronized (lock) {
                if (this.surfaceEntry == null) {
                  lock.wait(1500);
                }
              }
            }

            if (this.surfaceEntry == null) {
              replyOnce(replied, result, errorMap("Could not allocate camera surface"));
              return;
            }

            SurfaceTexture st = this.surfaceEntry.surfaceTexture();
            st.setDefaultBufferSize(chosenPreview.getWidth(), chosenPreview.getHeight());
            this.previewSurface = new Surface(st);

            this.jpegReader =
                ImageReader.newInstance(
                    chosenJpeg.getWidth(), chosenJpeg.getHeight(), ImageFormat.JPEG, 2);

            final long texId = this.surfaceEntry.id();
            final boolean swapDims = (this.sensorOrientation == 90 || this.sensorOrientation == 270);
            final int logicalW =
                swapDims ? chosenPreview.getHeight() : chosenPreview.getWidth();
            final int logicalH =
                swapDims ? chosenPreview.getWidth() : chosenPreview.getHeight();

            cm.openCamera(
                chosenId,
                new CameraDevice.StateCallback() {
                  @Override
                  public void onOpened(CameraDevice camera) {
                    cameraDevice = camera;
                    createPreviewSession(
                        camera,
                        texId,
                        logicalW,
                        logicalH,
                        replied,
                        result);
                  }

                  @Override
                  public void onDisconnected(CameraDevice camera) {
                    try {
                      camera.close();
                    } catch (Throwable ignored) {
                    }
                    if (cameraDevice == camera) {
                      cameraDevice = null;
                    }
                    replyOnce(replied, result, errorMap("Camera disconnected"));
                  }

                  @Override
                  public void onError(CameraDevice camera, int error) {
                    try {
                      camera.close();
                    } catch (Throwable ignored) {
                    }
                    if (cameraDevice == camera) {
                      cameraDevice = null;
                    }
                    replyOnce(replied, result, errorMap("Camera open error (" + error + ")"));
                  }
                },
                cameraHandler);
          } catch (Throwable t) {
            replyOnce(replied, result, errorMap("Failed to open camera"));
          }
        });
  }

  private void createPreviewSession(
      final CameraDevice camera,
      final long texId,
      final int logicalW,
      final int logicalH,
      final AtomicBoolean replied,
      final MethodChannel.Result result) {
    try {
      if (previewSurface == null || jpegReader == null) {
        replyOnce(replied, result, errorMap("Preview surface closed"));
        return;
      }
      final CaptureRequest.Builder builder =
          camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
      builder.addTarget(previewSurface);
      builder.set(
          CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
      builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
      previewBuilder = builder;

      final List<Surface> targets = Arrays.asList(previewSurface, jpegReader.getSurface());
      final CameraCaptureSession.StateCallback sessionCb =
          new CameraCaptureSession.StateCallback() {
            @Override
            public void onConfigured(CameraCaptureSession session) {
              if (cameraDevice == null) {
                return;
              }
              captureSession = session;
              try {
                session.setRepeatingRequest(builder.build(), null, cameraHandler);
                Map<String, Object> ok = new HashMap<>(10);
                ok.put("ok", true);
                ok.put("textureId", texId);
                ok.put("previewWidth", logicalW);
                ok.put("previewHeight", logicalH);
                ok.put("isFront", activeFrontFacing);
                ok.put("hasFlash", hasFlashUnit);
                ok.put("maxZoom", (double) maxZoom);
                replyOnce(replied, result, ok);
              } catch (Throwable e) {
                replyOnce(replied, result, errorMap("Preview start failed"));
              }
            }

            @Override
            public void onConfigureFailed(CameraCaptureSession session) {
              replyOnce(replied, result, errorMap("Camera session configuration failed"));
            }
          };

      openCameraSessionCompat(camera, targets, sessionCb);
    } catch (Throwable t) {
      replyOnce(replied, result, errorMap("Camera preview error"));
    }
  }

  @SuppressWarnings("deprecation")
  private void openCameraSessionCompat(
      CameraDevice camera, List<Surface> surfaces, CameraCaptureSession.StateCallback cb)
      throws Exception {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      List<OutputConfiguration> configs = new ArrayList<>(surfaces.size());
      for (Surface s : surfaces) {
        configs.add(new OutputConfiguration(s));
      }
      Executor exec =
          command -> {
            Handler h = cameraHandler;
            if (h != null) {
              h.post(command);
            }
          };
      SessionConfiguration sc =
          new SessionConfiguration(SessionConfiguration.SESSION_REGULAR, configs, exec, cb);
      camera.createCaptureSession(sc);
    } else {
      camera.createCaptureSession(surfaces, cb, cameraHandler);
    }
  }

  boolean setTorch(boolean enabled) {
    Handler h = this.cameraHandler;
    if (h == null || !this.hasFlashUnit) {
      return false;
    }
    this.torchEnabled = enabled;
    h.post(
        () -> {
          try {
            if (captureSession != null && previewBuilder != null) {
              previewBuilder.set(
                  CaptureRequest.FLASH_MODE,
                  enabled ? CaptureRequest.FLASH_MODE_TORCH : CaptureRequest.FLASH_MODE_OFF);
              captureSession.setRepeatingRequest(previewBuilder.build(), null, cameraHandler);
            }
          } catch (Throwable ignored) {
          }
        });
    return this.torchEnabled;
  }

  void setZoom(float zoomRatio) {
    Handler h = this.cameraHandler;
    if (h == null) return;
    final float clamped = Math.max(1.0f, Math.min(this.maxZoom, zoomRatio));
    this.currentZoom = clamped;
    h.post(
        () -> {
          try {
            if (captureSession != null && previewBuilder != null) {
              applyZoomToBuilder(previewBuilder, clamped);
              captureSession.setRepeatingRequest(previewBuilder.build(), null, cameraHandler);
            }
          } catch (Throwable ignored) {
          }
        });
  }

  void focusAtNormalizedPoint(float normX, float normY) {
    Handler h = this.cameraHandler;
    if (h == null) return;
    final float nx = Math.max(0.05f, Math.min(0.95f, normX));
    final float ny = Math.max(0.05f, Math.min(0.95f, normY));
    h.post(
        () -> {
          try {
            if (captureSession == null || previewBuilder == null || sensorActiveArray == null) {
              return;
            }
            int aw = sensorActiveArray.width();
            int ah = sensorActiveArray.height();
            int cx = sensorActiveArray.left + Math.round(nx * aw);
            int cy = sensorActiveArray.top + Math.round(ny * ah);
            int half = Math.max(60, Math.min(aw, ah) / 10);
            Rect focusRect =
                new Rect(
                    Math.max(sensorActiveArray.left, cx - half),
                    Math.max(sensorActiveArray.top, cy - half),
                    Math.min(sensorActiveArray.right, cx + half),
                    Math.min(sensorActiveArray.bottom, cy + half));
            MeteringRectangle mr =
                new MeteringRectangle(focusRect, MeteringRectangle.METERING_WEIGHT_MAX - 1);
            previewBuilder.set(
                CaptureRequest.CONTROL_AF_REGIONS, new MeteringRectangle[] {mr});
            previewBuilder.set(
                CaptureRequest.CONTROL_AE_REGIONS, new MeteringRectangle[] {mr});
            previewBuilder.set(
                CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO);
            previewBuilder.set(
                CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_START);
            captureSession.capture(previewBuilder.build(), null, cameraHandler);

            previewBuilder.set(
                CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_IDLE);
            previewBuilder.set(
                CaptureRequest.CONTROL_AF_MODE,
                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            captureSession.setRepeatingRequest(previewBuilder.build(), null, cameraHandler);
          } catch (Throwable ignored) {
          }
        });
  }

  void captureAndUploadToLens(
      final double cropLeft,
      final double cropTop,
      final double cropRight,
      final double cropBottom,
      final String mode,
      final String query,
      final String language,
      final MethodChannel.Result result) {
    Handler h = this.cameraHandler;
    if (h == null) {
      result.success(errorMap("Camera is not active"));
      return;
    }
    final AtomicBoolean finished = new AtomicBoolean(false);

    h.post(
        () -> {
          try {
            if (cameraDevice == null || captureSession == null || jpegReader == null) {
              replyOnce(finished, result, errorMap("Camera session not ready"));
              return;
            }
            jpegReader.setOnImageAvailableListener(
                reader -> {
                  byte[] rawBytes = null;
                  try (Image img = reader.acquireLatestImage()) {
                    if (img != null && img.getPlanes().length > 0) {
                      ByteBuffer buf = img.getPlanes()[0].getBuffer();
                      rawBytes = new byte[buf.remaining()];
                      buf.get(rawBytes);
                    }
                  } catch (Throwable ignored) {
                  }
                  if (rawBytes == null || rawBytes.length == 0) {
                    return;
                  }
                  reader.setOnImageAvailableListener(null, null);
                  final byte[] capturedJpeg = rawBytes;
                  final int fallbackSensorDeg = sensorOrientation;
                  final boolean mirrorFront = activeFrontFacing;

                  ioPool.execute(
                      () -> {
                        try {
                          byte[] processed =
                              processAndCropJpegBytes(
                                  capturedJpeg,
                                  fallbackSensorDeg,
                                  mirrorFront,
                                  cropLeft,
                                  cropTop,
                                  cropRight,
                                  cropBottom);
                          if (processed == null || processed.length == 0) {
                            replyOnce(finished, result, errorMap("Could not process captured frame"));
                            return;
                          }
                          Map<String, Object> uploaded =
                              uploadToGoogleLens(processed, mode, query, language);
                          uploaded.put(
                              "previewBase64",
                              Base64.encodeToString(processed, Base64.NO_WRAP));
                          replyOnce(finished, result, uploaded);
                        } catch (Throwable e) {
                          replyOnce(finished, result, errorMap("Lens upload failed"));
                        }
                      });
                },
                cameraHandler);

            CaptureRequest.Builder still =
                cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
            still.addTarget(jpegReader.getSurface());
            still.set(
                CaptureRequest.CONTROL_AF_MODE,
                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            still.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
            if (hasFlashUnit && torchEnabled) {
              still.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH);
            }
            applyZoomToBuilder(still, currentZoom);
            still.set(CaptureRequest.JPEG_QUALITY, (byte) 88);

            captureSession.capture(still.build(), null, cameraHandler);
          } catch (Throwable t) {
            replyOnce(finished, result, errorMap("Capture failed"));
          }
        });
  }

  void processGalleryUriAndPrepare(
      final Context ctx, final Uri pickedUri, final MethodChannel.Result result) {
    if (ctx == null || pickedUri == null) {
      result.success(errorMap("No image selected"));
      return;
    }
    ioPool.execute(
        () -> {
          try {
            byte[] rawBytes = readUriBytes(ctx, pickedUri, 18 * 1024 * 1024);
            if (rawBytes == null || rawBytes.length == 0) {
              mainHandler.post(() -> result.success(errorMap("Unable to read selected image")));
              return;
            }
            Bitmap oriented = decodeOrientedBitmapFromBytes(rawBytes, 1440, 0, false);
            if (oriented == null) {
              mainHandler.post(() -> result.success(errorMap("Unsupported image format")));
              return;
            }
            ByteArrayOutputStream bos = new ByteArrayOutputStream(98304);
            oriented.compress(Bitmap.CompressFormat.JPEG, 88, bos);
            byte[] normalizedJpeg = bos.toByteArray();
            final String b64 = Base64.encodeToString(normalizedJpeg, Base64.NO_WRAP);
            final int w = oriented.getWidth();
            final int h = oriented.getHeight();
            mainHandler.post(
                () -> {
                  Map<String, Object> out = new HashMap<>(6);
                  out.put("ok", true);
                  out.put("base64Jpeg", b64);
                  out.put("width", w);
                  out.put("height", h);
                  result.success(out);
                });
          } catch (Throwable t) {
            mainHandler.post(() -> result.success(errorMap("Could not load gallery photo")));
          }
        });
  }

  void searchBase64ImageWithLens(
      final String base64Jpeg,
      final double cropLeft,
      final double cropTop,
      final double cropRight,
      final double cropBottom,
      final String mode,
      final String query,
      final String language,
      final MethodChannel.Result result) {
    if (base64Jpeg == null || base64Jpeg.trim().isEmpty()) {
      result.success(errorMap("Empty image"));
      return;
    }
    ioPool.execute(
        () -> {
          try {
            byte[] raw = Base64.decode(base64Jpeg.trim(), Base64.DEFAULT);
            byte[] cropped =
                processAndCropJpegBytes(
                    raw, 0, false, cropLeft, cropTop, cropRight, cropBottom);
            if (cropped == null || cropped.length == 0) {
              mainHandler.post(() -> result.success(errorMap("Could not crop image")));
              return;
            }
            Map<String, Object> uploaded = uploadToGoogleLens(cropped, mode, query, language);
            mainHandler.post(() -> result.success(uploaded));
          } catch (Throwable e) {
            mainHandler.post(() -> result.success(errorMap("Google Lens connection failed")));
          }
        });
  }

  private Map<String, Object> uploadToGoogleLens(
      byte[] jpegBytes, String mode, String query, String language) throws Exception {
    String hl = (language != null && !language.trim().isEmpty()) ? language.trim() : "en";
    int dash = hl.indexOf('-');
    if (dash > 0) {
      hl = hl.substring(0, dash);
    }
    long st = System.currentTimeMillis();
    String endpoint =
        "https://lens.google.com/v3/upload?hl="
            + URLEncoder.encode(hl, "UTF-8")
            + "&re=df&st="
            + st
            + "&vpw=412&vph=915&ep=ccm";

    String boundary = "----HeavenLensBoundary" + st;
    byte[] headerBytes =
        ("--"
                + boundary
                + "\r\n"
                + "Content-Disposition: form-data; name=\"encoded_image\"; filename=\"lens.jpg\"\r\n"
                + "Content-Type: image/jpeg\r\n\r\n")
            .getBytes(StandardCharsets.UTF_8);
    byte[] footerBytes = ("\r\n--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8);

    HttpURLConnection conn = (HttpURLConnection) URI.create(endpoint).toURL().openConnection();
    try {
      conn.setInstanceFollowRedirects(false);
      conn.setConnectTimeout(12000);
      conn.setReadTimeout(16000);
      conn.setRequestMethod("POST");
      conn.setDoOutput(true);
      conn.setFixedLengthStreamingMode(
          headerBytes.length + jpegBytes.length + footerBytes.length);
      conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);
      conn.setRequestProperty("User-Agent", MOBILE_CHROME_UA);
      conn.setRequestProperty("Origin", "https://www.google.com");
      conn.setRequestProperty("Referer", "https://www.google.com/");
      conn.setRequestProperty(
          "Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");

      try (OutputStream os = conn.getOutputStream()) {
        os.write(headerBytes);
        os.write(jpegBytes);
        os.write(footerBytes);
        os.flush();
      }

      int code = conn.getResponseCode();
      Map<String, List<String>> headers = conn.getHeaderFields();
      if (headers != null) {
        List<String> setCookies = new ArrayList<>();
        for (Map.Entry<String, List<String>> entry : headers.entrySet()) {
          if (entry.getKey() != null
              && "set-cookie".equalsIgnoreCase(entry.getKey())
              && entry.getValue() != null) {
            setCookies.addAll(entry.getValue());
          }
        }
        if (!setCookies.isEmpty()) {
          mainHandler.post(
              () -> {
                try {
                  CookieManager cm = CookieManager.getInstance();
                  cm.setAcceptCookie(true);
                  for (String ck : setCookies) {
                    if (ck != null && !ck.isEmpty()) {
                      cm.setCookie("https://www.google.com", ck);
                      cm.setCookie("https://lens.google.com", ck);
                    }
                  }
                  cm.flush();
                } catch (Throwable ignored) {
                }
              });
        }
      }

      String location = conn.getHeaderField("Location");
      if ((code == 301 || code == 302 || code == 303 || code == 307 || code == 308)
          && location != null
          && !location.trim().isEmpty()) {
        String resolvedUrl = normalizeLensLocationUrl(location.trim(), mode, query);
        Map<String, Object> ok = new HashMap<>(4);
        ok.put("ok", true);
        ok.put("resultUrl", resolvedUrl);
        return ok;
      }

      // Fallback: inspect response body for embedded redirect URL if HTTP 200 returned
      try (InputStream is =
          (code >= 200 && code < 400) ? conn.getInputStream() : conn.getErrorStream()) {
        if (is != null) {
          ByteArrayOutputStream bos = new ByteArrayOutputStream(4096);
          byte[] buf = new byte[2048];
          int r;
          while ((r = is.read(buf)) != -1 && bos.size() < 65536) {
            bos.write(buf, 0, r);
          }
          String body = bos.toString("UTF-8");
          int idx = body.indexOf("https://www.google.com/search?vsrid=");
          if (idx >= 0) {
            int end = body.indexOf('"', idx);
            if (end < 0) end = body.indexOf('\'', idx);
            if (end > idx) {
              String extracted =
                  body.substring(idx, end).replace("&amp;", "&");
              Map<String, Object> ok = new HashMap<>(4);
              ok.put("ok", true);
              ok.put("resultUrl", normalizeLensLocationUrl(extracted, mode, query));
              return ok;
            }
          }
        }
      }
      return errorMap("Google Lens returned HTTP " + code);
    } finally {
      conn.disconnect();
    }
  }

  private static String normalizeLensLocationUrl(
      String rawLocation, String mode, String query) throws Exception {
    String url = rawLocation;
    if (url.startsWith("/")) {
      url = "https://www.google.com" + url;
    }
    String cleanQuery = query != null ? query.trim() : "";
    String cleanMode = mode != null ? mode.trim().toLowerCase(Locale.US) : "search";

    if (!cleanQuery.isEmpty()) {
      url = url.replace("udm=26", "udm=24");
      url = url + "&q=" + URLEncoder.encode(cleanQuery, "UTF-8");
      return url;
    }

    switch (cleanMode) {
      case "translate":
        url = url.replace("udm=26", "udm=24").replace("lns_mode=un", "lns_mode=tr");
        url = url + "&q=" + URLEncoder.encode("translate text in image", "UTF-8");
        break;
      case "text":
        url = url.replace("lns_mode=un", "lns_mode=text");
        break;
      case "shopping":
        url = url.replace("udm=26", "udm=24");
        url = url + "&q=" + URLEncoder.encode("buy shopping price", "UTF-8");
        break;
      default:
        break;
    }
    return url;
  }

  void stopCamera(final boolean releaseSurface) {
    Handler h = this.cameraHandler;
    if (h != null) {
      h.post(
          () -> {
            closeSessionOnlySync();
            if (releaseSurface) {
              final TextureRegistry.SurfaceTextureEntry entry = this.surfaceEntry;
              this.surfaceEntry = null;
              if (entry != null) {
                mainHandler.post(
                    () -> {
                      try {
                        entry.release();
                      } catch (Throwable ignored) {
                      }
                    });
              }
              quitCameraThreadSync();
            }
          });
    } else if (releaseSurface && this.surfaceEntry != null) {
      final TextureRegistry.SurfaceTextureEntry entry = this.surfaceEntry;
      this.surfaceEntry = null;
      mainHandler.post(
          () -> {
            try {
              entry.release();
            } catch (Throwable ignored) {
            }
          });
    }
  }

  private void closeSessionOnlySync() {
    this.torchEnabled = false;
    if (this.captureSession != null) {
      try {
        this.captureSession.close();
      } catch (Throwable ignored) {
      }
      this.captureSession = null;
    }
    this.previewBuilder = null;
    if (this.cameraDevice != null) {
      try {
        this.cameraDevice.close();
      } catch (Throwable ignored) {
      }
      this.cameraDevice = null;
    }
    if (this.jpegReader != null) {
      try {
        this.jpegReader.close();
      } catch (Throwable ignored) {
      }
      this.jpegReader = null;
    }
    if (this.previewSurface != null) {
      try {
        this.previewSurface.release();
      } catch (Throwable ignored) {
      }
      this.previewSurface = null;
    }
  }

  private synchronized void ensureCameraThread() {
    if (this.cameraThread == null || !this.cameraThread.isAlive()) {
      this.cameraThread = new HandlerThread("HeavenLensCamera");
      this.cameraThread.start();
      this.cameraHandler = new Handler(this.cameraThread.getLooper());
    }
  }

  private synchronized void quitCameraThreadSync() {
    if (this.cameraThread != null) {
      try {
        this.cameraThread.quitSafely();
      } catch (Throwable ignored) {
      }
      this.cameraThread = null;
      this.cameraHandler = null;
    }
  }

  private void applyZoomToBuilder(CaptureRequest.Builder builder, float zoom) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      builder.set(CaptureRequest.CONTROL_ZOOM_RATIO, zoom);
      return;
    }
    if (sensorActiveArray != null && zoom > 1.0f) {
      int w = sensorActiveArray.width();
      int h = sensorActiveArray.height();
      int cropW = Math.max(64, Math.round(w / zoom));
      int cropH = Math.max(64, Math.round(h / zoom));
      int dx = (w - cropW) / 2;
      int dy = (h - cropH) / 2;
      Rect zoomRect =
          new Rect(
              sensorActiveArray.left + dx,
              sensorActiveArray.top + dy,
              sensorActiveArray.right - dx,
              sensorActiveArray.bottom - dy);
      builder.set(CaptureRequest.SCALER_CROP_REGION, zoomRect);
    }
  }

  private static float resolveMaxZoom(CameraCharacteristics chars) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      Range<Float> range = chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);
      if (range != null && range.getUpper() != null) {
        return Math.max(1.0f, Math.min(8.0f, range.getUpper()));
      }
    }
    Float legacy = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
    if (legacy != null) {
      return Math.max(1.0f, Math.min(8.0f, legacy));
    }
    return 4.0f;
  }

  private static String selectCameraId(CameraManager cm, boolean wantFront) throws Exception {
    int desired =
        wantFront
            ? CameraCharacteristics.LENS_FACING_FRONT
            : CameraCharacteristics.LENS_FACING_BACK;
    String fallback = null;
    for (String id : cm.getCameraIdList()) {
      CameraCharacteristics c = cm.getCameraCharacteristics(id);
      Integer facing = c.get(CameraCharacteristics.LENS_FACING);
      if (fallback == null) {
        fallback = id;
      }
      if (facing != null && facing == desired) {
        return id;
      }
    }
    return fallback;
  }

  private static Size chooseOptimalSize(
      StreamConfigurationMap map, Class<?> klass, int maxW, int maxH) {
    if (map == null) {
      return new Size(1280, 960);
    }
    Size[] sizes = map.getOutputSizes(klass);
    if (sizes == null || sizes.length == 0) {
      return new Size(1280, 960);
    }
    Size best = null;
    long bestPixels = 0;
    for (Size s : sizes) {
      int w = s.getWidth();
      int h = s.getHeight();
      if (w <= maxW && h <= maxH) {
        long px = (long) w * h;
        if (px > bestPixels) {
          bestPixels = px;
          best = s;
        }
      }
    }
    return best != null ? best : sizes[0];
  }

  private static Size chooseOptimalJpegSize(
      StreamConfigurationMap map, int maxW, int maxH, Size fallback) {
    if (map == null) {
      return fallback;
    }
    Size[] sizes = map.getOutputSizes(ImageFormat.JPEG);
    if (sizes == null || sizes.length == 0) {
      return fallback;
    }
    float targetAspect = (float) fallback.getWidth() / Math.max(1, fallback.getHeight());
    Size bestMatch = null;
    long bestMatchPx = 0;
    Size bestAny = null;
    long bestAnyPx = 0;
    for (Size s : sizes) {
      int w = s.getWidth();
      int h = s.getHeight();
      if (w <= maxW && h <= maxH) {
        long px = (long) w * h;
        float aspect = (float) w / Math.max(1, h);
        if (Math.abs(aspect - targetAspect) < 0.12f && px > bestMatchPx) {
          bestMatchPx = px;
          bestMatch = s;
        }
        if (px > bestAnyPx) {
          bestAnyPx = px;
          bestAny = s;
        }
      }
    }
    if (bestMatch != null) return bestMatch;
    if (bestAny != null) return bestAny;
    return sizes[0];
  }

  private static byte[] processAndCropJpegBytes(
      byte[] rawBytes,
      int fallbackRotationDeg,
      boolean mirrorHorizontal,
      double cropL,
      double cropT,
      double cropR,
      double cropB) {
    Bitmap bmp = decodeOrientedBitmapFromBytes(rawBytes, 1440, fallbackRotationDeg, mirrorHorizontal);
    if (bmp == null) {
      return null;
    }
    double l = Math.max(0.0, Math.min(0.92, cropL));
    double t = Math.max(0.0, Math.min(0.92, cropT));
    double r = Math.max(l + 0.08, Math.min(1.0, cropR));
    double b = Math.max(t + 0.08, Math.min(1.0, cropB));

    if (l > 0.01 || t > 0.01 || r < 0.99 || b < 0.99) {
      int bw = bmp.getWidth();
      int bh = bmp.getHeight();
      int x = Math.max(0, (int) Math.round(l * bw));
      int y = Math.max(0, (int) Math.round(t * bh));
      int cw = Math.max(32, Math.min(bw - x, (int) Math.round((r - l) * bw)));
      int ch = Math.max(32, Math.min(bh - y, (int) Math.round((b - t) * bh)));
      bmp = Bitmap.createBitmap(bmp, x, y, cw, ch);
    }

    int maxDim = 1280;
    if (bmp.getWidth() > maxDim || bmp.getHeight() > maxDim) {
      float ratio = Math.min((float) maxDim / bmp.getWidth(), (float) maxDim / bmp.getHeight());
      bmp =
          Bitmap.createScaledBitmap(
              bmp,
              Math.max(1, Math.round(bmp.getWidth() * ratio)),
              Math.max(1, Math.round(bmp.getHeight() * ratio)),
              true);
    }

    ByteArrayOutputStream bos = new ByteArrayOutputStream(98304);
    bmp.compress(Bitmap.CompressFormat.JPEG, 86, bos);
    return bos.toByteArray();
  }

  private static Bitmap decodeOrientedBitmapFromBytes(
      byte[] rawBytes, int maxDim, int fallbackDeg, boolean mirrorHorizontal) {
    BitmapFactory.Options bounds = new BitmapFactory.Options();
    bounds.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.length, bounds);
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
      return null;
    }
    int sample = 1;
    while ((bounds.outWidth / sample) > maxDim * 2 || (bounds.outHeight / sample) > maxDim * 2) {
      sample *= 2;
    }
    BitmapFactory.Options opts = new BitmapFactory.Options();
    opts.inSampleSize = sample;
    Bitmap decoded = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.length, opts);
    if (decoded == null) {
      return null;
    }

    int exifDeg = -1;
    try {
      ExifInterface exif = new ExifInterface(new ByteArrayInputStream(rawBytes));
      int ori =
          exif.getAttributeInt(
              ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED);
      switch (ori) {
        case ExifInterface.ORIENTATION_ROTATE_90:
          exifDeg = 90;
          break;
        case ExifInterface.ORIENTATION_ROTATE_180:
          exifDeg = 180;
          break;
        case ExifInterface.ORIENTATION_ROTATE_270:
          exifDeg = 270;
          break;
        case ExifInterface.ORIENTATION_NORMAL:
          exifDeg = 0;
          break;
        default:
          break;
      }
    } catch (Throwable ignored) {
    }

    int rotateDeg = exifDeg >= 0 ? exifDeg : fallbackDeg;
    if (rotateDeg != 0 || mirrorHorizontal) {
      Matrix m = new Matrix();
      if (rotateDeg != 0) {
        m.postRotate(rotateDeg);
      }
      if (mirrorHorizontal) {
        m.postScale(-1.0f, 1.0f);
      }
      decoded =
          Bitmap.createBitmap(
              decoded, 0, 0, decoded.getWidth(), decoded.getHeight(), m, true);
    }
    return decoded;
  }

  private static byte[] readUriBytes(Context ctx, Uri uri, int maxBytes) throws IOException {
    try (InputStream is = ctx.getContentResolver().openInputStream(uri)) {
      if (is == null) return null;
      ByteArrayOutputStream bos = new ByteArrayOutputStream(65536);
      byte[] buf = new byte[16384];
      int n;
      while ((n = is.read(buf)) != -1) {
        if (bos.size() + n > maxBytes) {
          throw new IOException("Image exceeds maximum size");
        }
        bos.write(buf, 0, n);
      }
      return bos.toByteArray();
    }
  }

  private void replyOnce(
      AtomicBoolean gate, final MethodChannel.Result result, final Map<String, Object> payload) {
    if (gate.compareAndSet(false, true)) {
      mainHandler.post(() -> result.success(payload));
    }
  }

  private static Map<String, Object> errorMap(String message) {
    Map<String, Object> m = new HashMap<>(4);
    m.put("ok", false);
    m.put("error", message);
    return m;
  }
}
