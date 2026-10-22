# Heaven Browser

[![Build Heaven Browser Android](https://github.com/Aryanshahx/heavenbrowser/actions/workflows/build.yml/badge.svg)](https://github.com/Aryanshahx/heavenbrowser/actions/workflows/build.yml)

**Heaven Browser** is a fast, private web browser for Android built with Flutter.

- **Package Name:** `com.hypertechlabs.heavenbrowser`
- **Version:** `0.0.1`
- **Android Builds:** Automated APK & AAB builds via GitHub Actions

## Local Verification (Raspberry Pi / Ubuntu)

```bash
flutter clean && flutter pub get && dart analyze && flutter test
```

## Downloading APK / AAB Builds

Every push to `main` (or manual run in the **Actions** tab) runs static analysis, executes tests, and uploads direct Android build artifacts:

- `HeavenBrowser-v0.0.1-release.apk`
- `HeavenBrowser-v0.0.1-debug.apk`
- `HeavenBrowser-v0.0.1-release.aab`
