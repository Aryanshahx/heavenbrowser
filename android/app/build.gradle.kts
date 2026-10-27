import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val configuredStoreFile: String? =
    (keystoreProperties.getProperty("storeFile") ?: System.getenv("HEAVEN_STORE_FILE"))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
val configuredStorePassword: String? =
    (keystoreProperties.getProperty("storePassword") ?: System.getenv("HEAVEN_STORE_PASSWORD"))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
val configuredKeyAlias: String? =
    (keystoreProperties.getProperty("keyAlias") ?: System.getenv("HEAVEN_KEY_ALIAS"))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
val configuredKeyPassword: String? =
    (keystoreProperties.getProperty("keyPassword") ?: System.getenv("HEAVEN_KEY_PASSWORD"))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
val resolvedKeystoreFile = configuredStoreFile?.let { file(it) }
val hasPlayStoreSigning =
    resolvedKeystoreFile != null &&
        resolvedKeystoreFile.exists() &&
        configuredStorePassword != null &&
        configuredKeyAlias != null &&
        configuredKeyPassword != null

android {
    namespace = "com.hypertechlabs.heavenbrowser"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hypertechlabs.heavenbrowser"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasPlayStoreSigning) {
            create("release") {
                keyAlias = configuredKeyAlias
                keyPassword = configuredKeyPassword
                storeFile = resolvedKeystoreFile
                storePassword = configuredStorePassword
            }
        }
    }

    // Required for OpenVPN & WireGuard native binary execution (libovpnexec.so, libopenvpn.so, libwg-go.so)
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasPlayStoreSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.webkit:webkit:1.15.0")
    implementation("com.wireguard.android:tunnel:1.0.20260102")
    implementation("com.google.mlkit:genai-summarization:1.0.0-beta1")
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta2")
}

flutter {
    source = "../.."
}
