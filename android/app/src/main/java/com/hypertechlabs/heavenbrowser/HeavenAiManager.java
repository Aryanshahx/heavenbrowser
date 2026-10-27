package com.hypertechlabs.heavenbrowser;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import com.google.mlkit.genai.common.DownloadCallback;
import com.google.mlkit.genai.common.FeatureStatus;
import com.google.mlkit.genai.common.GenAiException;
import com.google.mlkit.genai.prompt.Candidate;
import com.google.mlkit.genai.prompt.GenerateContentRequest;
import com.google.mlkit.genai.prompt.GenerateContentResponse;
import com.google.mlkit.genai.prompt.Generation;
import com.google.mlkit.genai.prompt.GenerativeModel;
import com.google.mlkit.genai.prompt.TextPart;
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures;
import com.google.mlkit.genai.summarization.Summarization;
import com.google.mlkit.genai.summarization.SummarizationRequest;
import com.google.mlkit.genai.summarization.SummarizationResult;
import com.google.mlkit.genai.summarization.Summarizer;
import com.google.mlkit.genai.summarization.SummarizerOptions;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Lazy, zero-startup-overhead bridge to Android's 100% free On-Device ML Kit GenAI
 * APIs (powered by Gemini Nano via Android AICore).
 *
 * <p>No model weights are bundled inside the APK. When AICore reports {@link
 * FeatureStatus#DOWNLOADABLE}, Heaven asks the user before downloading the model on demand.
 */
final class HeavenAiManager {

  interface DownloadProgressReporter {
    void onProgress(String state, long bytesDownloaded, long totalBytes, String error);
  }

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final ExecutorService executor =
      Executors.newSingleThreadExecutor(
          r -> {
            Thread t = new Thread(r, "heaven-ondevice-ai");
            t.setDaemon(true);
            return t;
          });

  private volatile GenerativeModel rawPromptModel;
  private volatile GenerativeModelFutures promptFutures;
  private volatile Summarizer summarizer;
  private final AtomicBoolean downloadInFlight = new AtomicBoolean(false);

  HeavenAiManager(Context context) {
    this.appContext = context.getApplicationContext();
  }

  private synchronized GenerativeModelFutures ensurePromptFutures() {
    if (promptFutures == null) {
      rawPromptModel = Generation.INSTANCE.getClient();
      promptFutures = GenerativeModelFutures.from(rawPromptModel);
    }
    return promptFutures;
  }

  private synchronized Summarizer ensureSummarizer() {
    if (summarizer == null) {
      SummarizerOptions options =
          SummarizerOptions.builder(appContext)
              .setInputType(SummarizerOptions.InputType.ARTICLE)
              .setOutputType(SummarizerOptions.OutputType.THREE_BULLETS)
              .setLanguage(SummarizerOptions.Language.ENGLISH)
              .setLongInputAutoTruncationEnabled(true)
              .build();
      summarizer = Summarization.getClient(options);
    }
    return summarizer;
  }

  private static String statusToString(int code) {
    if (code == FeatureStatus.AVAILABLE) {
      return "available";
    }
    if (code == FeatureStatus.DOWNLOADING) {
      return "downloading";
    }
    if (code == FeatureStatus.DOWNLOADABLE) {
      return "downloadable";
    }
    return "unavailable";
  }

  void checkStatusAsync(final MethodChannel.Result result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      Map<String, Object> out = new HashMap<>(4);
      out.put("status", "unavailable");
      out.put("promptStatus", "unavailable");
      out.put("summarizerStatus", "unavailable");
      out.put("modelName", "");
      postSuccess(result, out);
      return;
    }

    executor.execute(
        () -> {
          String promptState = "unavailable";
          String sumState = "unavailable";
          String modelName = "Gemini Nano";

          try {
            GenerativeModelFutures pf = ensurePromptFutures();
            Integer ps = pf.checkStatus().get(6, TimeUnit.SECONDS);
            if (ps != null) {
              promptState = statusToString(ps);
            }
            if (FeatureStatus.AVAILABLE == (ps != null ? ps : FeatureStatus.UNAVAILABLE)) {
              try {
                String base = pf.getBaseModelName().get(3, TimeUnit.SECONDS);
                if (base != null && !base.trim().isEmpty()) {
                  modelName = base.trim();
                }
              } catch (Throwable ignored) {
              }
            }
          } catch (Throwable ignored) {
          }

          try {
            Summarizer sum = ensureSummarizer();
            Integer ss = sum.checkFeatureStatus().get(6, TimeUnit.SECONDS);
            if (ss != null) {
              sumState = statusToString(ss);
            }
          } catch (Throwable ignored) {
          }

          String effective;
          if ("available".equals(promptState) || "available".equals(sumState)) {
            effective = "available";
          } else if (downloadInFlight.get()
              || "downloading".equals(promptState)
              || "downloading".equals(sumState)) {
            effective = "downloading";
          } else if ("downloadable".equals(promptState) || "downloadable".equals(sumState)) {
            effective = "downloadable";
          } else {
            effective = "unavailable";
          }

          Map<String, Object> out = new HashMap<>(6);
          out.put("status", effective);
          out.put("promptStatus", promptState);
          out.put("summarizerStatus", sumState);
          out.put("modelName", modelName);
          postSuccess(result, out);
        });
  }

  void downloadModelAsync(
      final DownloadProgressReporter reporter, final MethodChannel.Result result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      Map<String, Object> out = new HashMap<>(4);
      out.put("ok", false);
      out.put("status", "unavailable");
      out.put("error", "Android 8.0+ is required for ML Kit GenAI.");
      postSuccess(result, out);
      return;
    }

    if (!downloadInFlight.compareAndSet(false, true)) {
      Map<String, Object> out = new HashMap<>(4);
      out.put("ok", true);
      out.put("status", "downloading");
      postSuccess(result, out);
      return;
    }

    executor.execute(
        () -> {
          final AtomicLong totalBytesRef = new AtomicLong(0L);
          final StringBuilder lastErr = new StringBuilder();
          boolean anyReady = false;

          try {
            GenerativeModelFutures pf = ensurePromptFutures();
            Integer ps = pf.checkStatus().get(6, TimeUnit.SECONDS);
            if (ps != null && ps == FeatureStatus.AVAILABLE) {
              anyReady = true;
            } else if (ps != null
                && (ps == FeatureStatus.DOWNLOADABLE || ps == FeatureStatus.DOWNLOADING)) {
              DownloadCallback cb =
                  new DownloadCallback() {
                    @Override
                    public void onDownloadStarted(long bytesToDownload) {
                      totalBytesRef.set(Math.max(0L, bytesToDownload));
                      emitProgress(reporter, "downloading", 0L, totalBytesRef.get(), null);
                    }

                    @Override
                    public void onDownloadProgress(long totalBytesDownloaded) {
                      emitProgress(
                          reporter,
                          "downloading",
                          Math.max(0L, totalBytesDownloaded),
                          totalBytesRef.get(),
                          null);
                    }

                    @Override
                    public void onDownloadCompleted() {
                      long tot = totalBytesRef.get();
                      emitProgress(reporter, "completed", tot, tot, null);
                    }

                    @Override
                    public void onDownloadFailed(GenAiException e) {
                      String msg = e != null && e.getMessage() != null ? e.getMessage() : "Failed";
                      if (lastErr.length() == 0) {
                        lastErr.append(msg);
                      }
                    }
                  };
              try {
                pf.download(cb).get(10, TimeUnit.MINUTES);
                Integer after = pf.checkStatus().get(5, TimeUnit.SECONDS);
                if (after != null && after == FeatureStatus.AVAILABLE) {
                  anyReady = true;
                  try {
                    pf.warmup().get(10, TimeUnit.SECONDS);
                  } catch (Throwable ignored) {
                  }
                }
              } catch (Throwable e) {
                if (lastErr.length() == 0 && e.getMessage() != null) {
                  lastErr.append(e.getMessage());
                }
              }
            }
          } catch (Throwable e) {
            if (lastErr.length() == 0 && e.getMessage() != null) {
              lastErr.append(e.getMessage());
            }
          }

          try {
            Summarizer sum = ensureSummarizer();
            Integer ss = sum.checkFeatureStatus().get(6, TimeUnit.SECONDS);
            if (ss != null && ss == FeatureStatus.AVAILABLE) {
              anyReady = true;
            } else if (ss != null
                && (ss == FeatureStatus.DOWNLOADABLE || ss == FeatureStatus.DOWNLOADING)) {
              DownloadCallback sumCb =
                  new DownloadCallback() {
                    @Override
                    public void onDownloadStarted(long bytesToDownload) {
                      if (bytesToDownload > 0) {
                        totalBytesRef.set(bytesToDownload);
                      }
                      emitProgress(reporter, "downloading", 0L, totalBytesRef.get(), null);
                    }

                    @Override
                    public void onDownloadProgress(long totalBytesDownloaded) {
                      emitProgress(
                          reporter,
                          "downloading",
                          Math.max(0L, totalBytesDownloaded),
                          totalBytesRef.get(),
                          null);
                    }

                    @Override
                    public void onDownloadCompleted() {
                      long tot = totalBytesRef.get();
                      emitProgress(reporter, "completed", tot, tot, null);
                    }

                    @Override
                    public void onDownloadFailed(GenAiException e) {
                      String msg = e != null && e.getMessage() != null ? e.getMessage() : "Failed";
                      if (lastErr.length() == 0) {
                        lastErr.append(msg);
                      }
                    }
                  };
              try {
                sum.downloadFeature(sumCb).get(10, TimeUnit.MINUTES);
                Integer afterSum = sum.checkFeatureStatus().get(5, TimeUnit.SECONDS);
                if (afterSum != null && afterSum == FeatureStatus.AVAILABLE) {
                  anyReady = true;
                  try {
                    sum.prepareInferenceEngine().get(10, TimeUnit.SECONDS);
                  } catch (Throwable ignored) {
                  }
                }
              } catch (Throwable e) {
                if (lastErr.length() == 0 && e.getMessage() != null) {
                  lastErr.append(e.getMessage());
                }
              }
            }
          } catch (Throwable ignored) {
          } finally {
            downloadInFlight.set(false);
          }

          Map<String, Object> out = new HashMap<>(4);
          out.put("ok", anyReady);
          out.put("status", anyReady ? "available" : "unavailable");
          if (!anyReady && lastErr.length() > 0) {
            out.put("error", lastErr.toString());
            emitProgress(reporter, "failed", 0L, totalBytesRef.get(), lastErr.toString());
          }
          postSuccess(result, out);
        });
  }

  void summarizeArticleAsync(final String articleText, final MethodChannel.Result result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O
        || articleText == null
        || articleText.trim().isEmpty()) {
      Map<String, Object> out = new HashMap<>(4);
      out.put("ok", false);
      out.put("error", "No readable text available.");
      postSuccess(result, out);
      return;
    }

    final String trimmed =
        articleText.length() > 14000 ? articleText.substring(0, 14000) : articleText;

    executor.execute(
        () -> {
          try {
            Summarizer sum = ensureSummarizer();
            Integer ss = sum.checkFeatureStatus().get(5, TimeUnit.SECONDS);
            if (ss != null && ss == FeatureStatus.AVAILABLE) {
              SummarizationRequest req = SummarizationRequest.builder(trimmed).build();
              SummarizationResult res = sum.runInference(req).get(45, TimeUnit.SECONDS);
              String summary = res != null ? res.getSummary() : null;
              if (summary != null && !summary.trim().isEmpty()) {
                Map<String, Object> out = new HashMap<>(4);
                out.put("ok", true);
                out.put("text", summary.trim());
                out.put("engine", "gemini-nano");
                postSuccess(result, out);
                return;
              }
            }
          } catch (Throwable ignored) {
          }

          // Fallback to Gemini Nano Prompt API if available
          String prompt =
              "Summarize the following webpage clearly in 3 concise bullet points:\n\n"
                  + (trimmed.length() > 9000 ? trimmed.substring(0, 9000) : trimmed);
          runPromptInternal(prompt, result);
        });
  }

  void generatePromptAsync(final String promptText, final MethodChannel.Result result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O
        || promptText == null
        || promptText.trim().isEmpty()) {
      Map<String, Object> out = new HashMap<>(4);
      out.put("ok", false);
      out.put("error", "Empty prompt.");
      postSuccess(result, out);
      return;
    }

    final String bounded =
        promptText.length() > 11000 ? promptText.substring(0, 11000) : promptText.trim();
    executor.execute(() -> runPromptInternal(bounded, result));
  }

  private void runPromptInternal(String promptText, MethodChannel.Result result) {
    try {
      GenerativeModelFutures pf = ensurePromptFutures();
      Integer ps = pf.checkStatus().get(5, TimeUnit.SECONDS);
      if (ps == null || ps != FeatureStatus.AVAILABLE) {
        Map<String, Object> out = new HashMap<>(4);
        out.put("ok", false);
        out.put("status", ps != null ? statusToString(ps) : "unavailable");
        out.put("error", "On-device Gemini Nano model is not ready yet.");
        postSuccess(result, out);
        return;
      }

      GenerateContentRequest.Builder builder =
          new GenerateContentRequest.Builder(new TextPart(promptText));
      builder.setMaxOutputTokens(512);
      builder.setTemperature(0.3f);
      GenerateContentResponse response =
          pf.generateContent(builder.build()).get(45, TimeUnit.SECONDS);
      if (response != null) {
        List<Candidate> candidates = response.getCandidates();
        if (candidates != null && !candidates.isEmpty()) {
          String text = candidates.get(0).getText();
          if (text != null && !text.trim().isEmpty()) {
            Map<String, Object> out = new HashMap<>(4);
            out.put("ok", true);
            out.put("text", text.trim());
            out.put("engine", "gemini-nano");
            postSuccess(result, out);
            return;
          }
        }
      }
      Map<String, Object> emptyOut = new HashMap<>(4);
      emptyOut.put("ok", false);
      emptyOut.put("error", "Empty response from on-device model.");
      postSuccess(result, emptyOut);
    } catch (Throwable e) {
      Map<String, Object> errOut = new HashMap<>(4);
      errOut.put("ok", false);
      errOut.put("error", e.getMessage() != null ? e.getMessage() : "Inference error");
      postSuccess(result, errOut);
    }
  }

  private void emitProgress(
      DownloadProgressReporter reporter,
      String state,
      long downloaded,
      long total,
      String error) {
    if (reporter == null) {
      return;
    }
    mainHandler.post(() -> reporter.onProgress(state, downloaded, total, error));
  }

  private void postSuccess(final MethodChannel.Result result, final Map<String, Object> data) {
    mainHandler.post(
        () -> {
          try {
            result.success(data);
          } catch (Throwable ignored) {
          }
        });
  }

  synchronized void dispose() {
    try {
      if (summarizer != null) {
        summarizer.close();
        summarizer = null;
      }
    } catch (Throwable ignored) {
    }
    try {
      if (rawPromptModel != null) {
        rawPromptModel.close();
        rawPromptModel = null;
      }
      promptFutures = null;
    } catch (Throwable ignored) {
    }
  }
}
