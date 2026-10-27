package com.hypertechlabs.heavenbrowser;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.Locale;

public class HeavenFileProvider extends ContentProvider {

  public static final String AUTHORITY = "com.hypertechlabs.heavenbrowser.fileprovider";

  public static Uri getUriForFile(File file) {
    return new Uri.Builder()
        .scheme("content")
        .authority(AUTHORITY)
        .appendPath("download")
        .appendQueryParameter("path", file.getAbsolutePath())
        .appendPath(file.getName())
        .build();
  }

  @Override
  public boolean onCreate() {
    return true;
  }

  private boolean isCaptureCacheFile(File target) {
    Context ctx = getContext();
    if (ctx == null) {
      return false;
    }
    try {
      File captureDir = new File(ctx.getCacheDir(), "lens_capture").getCanonicalFile();
      return target.getPath().startsWith(captureDir.getPath() + File.separator);
    } catch (IOException e) {
      return false;
    }
  }

  private File resolveSafeFile(Uri uri, boolean allowCaptureWrite) throws FileNotFoundException {
    String rawPath = uri.getQueryParameter("path");
    if (rawPath == null || rawPath.isEmpty()) {
      throw new FileNotFoundException("Missing file path");
    }
    try {
      File target = new File(rawPath).getCanonicalFile();
      if (isCaptureCacheFile(target)) {
        if (allowCaptureWrite || (target.exists() && target.isFile())) {
          return target;
        }
      }
      boolean allowed = false;

      File extRoot = Environment.getExternalStorageDirectory();
      if (extRoot != null) {
        String extCanon = extRoot.getCanonicalFile().getPath() + File.separator;
        allowed = target.getPath().startsWith(extCanon);
      }
      if (!allowed) {
        File pubDownloads =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        if (pubDownloads != null) {
          String dlCanon = pubDownloads.getCanonicalFile().getPath() + File.separator;
          allowed = target.getPath().startsWith(dlCanon);
        }
      }

      Context ctx = getContext();
      if (!allowed && ctx != null) {
        File appExt = ctx.getExternalFilesDir(null);
        if (appExt != null) {
          String appRoot = appExt.getCanonicalFile().getPath() + File.separator;
          allowed = target.getPath().startsWith(appRoot);
        }
        if (!allowed) {
          String filesRoot = ctx.getFilesDir().getCanonicalFile().getPath() + File.separator;
          allowed = target.getPath().startsWith(filesRoot);
        }
      }

      if (!allowed || !target.exists() || !target.isFile()) {
        throw new FileNotFoundException("Access denied or file missing");
      }
      return target;
    } catch (IOException e) {
      throw new FileNotFoundException("Invalid canonical path");
    }
  }

  @Override
  public Cursor query(
      Uri uri,
      String[] projection,
      String selection,
      String[] selectionArgs,
      String sortOrder) {
    try {
      File file = resolveSafeFile(uri, false);
      String[] cols =
          projection != null
              ? projection
              : new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
      String[] finalCols = new String[cols.length];
      Object[] values = new Object[cols.length];
      int i = 0;
      for (String col : cols) {
        if (OpenableColumns.DISPLAY_NAME.equals(col)) {
          finalCols[i] = OpenableColumns.DISPLAY_NAME;
          values[i] = file.getName();
          i++;
        } else if (OpenableColumns.SIZE.equals(col)) {
          finalCols[i] = OpenableColumns.SIZE;
          values[i] = file.length();
          i++;
        }
      }
      String[] trimmedCols = new String[i];
      Object[] trimmedVals = new Object[i];
      System.arraycopy(finalCols, 0, trimmedCols, 0, i);
      System.arraycopy(values, 0, trimmedVals, 0, i);
      MatrixCursor cursor = new MatrixCursor(trimmedCols, 1);
      cursor.addRow(trimmedVals);
      return cursor;
    } catch (FileNotFoundException e) {
      return null;
    }
  }

  @Override
  public String getType(Uri uri) {
    String name = uri.getLastPathSegment();
    if (name != null) {
      int dot = name.lastIndexOf('.');
      if (dot >= 0 && dot + 1 < name.length()) {
        String ext = name.substring(dot + 1).toLowerCase(Locale.US);
        String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        if (mime != null && !mime.isEmpty()) {
          return mime;
        }
      }
    }
    return "application/octet-stream";
  }

  @Override
  public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
    boolean wantsWrite = mode != null && (mode.contains("w") || mode.contains("t"));
    File file = resolveSafeFile(uri, wantsWrite);
    if (wantsWrite && isCaptureCacheFile(file)) {
      int pfdMode =
          ParcelFileDescriptor.MODE_READ_WRITE
              | ParcelFileDescriptor.MODE_CREATE
              | ParcelFileDescriptor.MODE_TRUNCATE;
      return ParcelFileDescriptor.open(file, pfdMode);
    }
    return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
  }

  @Override
  public Uri insert(Uri uri, ContentValues values) {
    throw new UnsupportedOperationException("Read-only provider");
  }

  @Override
  public int delete(Uri uri, String selection, String[] selectionArgs) {
    throw new UnsupportedOperationException("Read-only provider");
  }

  @Override
  public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
    throw new UnsupportedOperationException("Read-only provider");
  }
}
