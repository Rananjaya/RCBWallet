import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing for RCBWallet.
//
// Credentials are read from android/key.properties, which is git-ignored and
// must never be committed. See android/key.properties.example for the format.
// The original upstream signing credentials are NOT used by this fork.
//
// Debug builds never need key.properties. Release builds REQUIRE a complete,
// valid configuration and never fall back to the debug key: the
// validateReleaseSigning task below fails the build with a clear message.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val requiredSigningProperties = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigningErrors = mutableListOf<String>()

if (!keystorePropertiesFile.exists()) {
    releaseSigningErrors += "android/key.properties was not found."
} else {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    val missing = requiredSigningProperties.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
    val placeholders = requiredSigningProperties.filter {
        keystoreProperties.getProperty(it)?.trim() == "CHANGE_ME"
    }
    if (missing.isNotEmpty()) {
        releaseSigningErrors += "android/key.properties is missing or has empty values for: " +
            missing.joinToString(", ") + "."
    }
    if (placeholders.isNotEmpty()) {
        releaseSigningErrors += "android/key.properties still contains placeholder values for: " +
            placeholders.joinToString(", ") + "."
    }
    if (missing.isEmpty()) {
        // storeFile is resolved relative to android/app/ (absolute paths also work).
        val storeFile = file(keystoreProperties.getProperty("storeFile").trim())
        if (!storeFile.isFile) {
            releaseSigningErrors += "Release keystore not found at: ${storeFile.path}"
        }
    }
}
val releaseSigningReady = releaseSigningErrors.isEmpty()

android {
    namespace = "com.rananjaya.rcbwallet"
    // Android 17 (API 37). Set explicitly: Flutter 3.47.9 still defaults to 36.
    // Requires AGP 9.3+ (see android/settings.gradle.kts).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (card reminders).
        isCoreLibraryDesugaringEnabled = true
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs.
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles.
        includeInBundle = false
    }

    defaultConfig {
        applicationId = "com.rananjaya.rcbwallet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Android 17 (API 37). minSdk stays at Flutter's default (24).
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias").trim()
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile").trim())
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Only ever the dedicated release key. Never the debug key.
            signingConfig = if (releaseSigningReady) signingConfigs.getByName("release") else null
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.ApkVariantOutputImpl
            val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
            val abiName = output.getFilter(com.android.build.OutputFile.ABI)
            val abiCode = abiCodes[abiName]
            if (abiCode != null) {
                output.versionCodeOverride = (variant.versionCode) * 100 + abiCode
            }
        }
    }

    packagingOptions {
        dex.useLegacyPackaging = true
        jniLibs.useLegacyPackaging = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Fails any release build (APK or App Bundle) early if release signing is
// not fully configured. Debug builds do not run this task.
val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    group = "verification"
    description = "Checks that android/key.properties and the release keystore are valid."
    val errors = releaseSigningErrors.toList()
    doLast {
        if (errors.isNotEmpty()) {
            throw GradleException(
                buildString {
                    appendLine("RCBWallet release signing is not configured. Release builds are")
                    appendLine("never signed with the debug key.")
                    appendLine()
                    errors.forEach { appendLine("  - $it") }
                    appendLine()
                    appendLine("To fix:")
                    appendLine("  1. Create your own release/upload keystore (do not commit it).")
                    appendLine("  2. Copy android/key.properties.example to android/key.properties.")
                    appendLine("  3. Set storeFile, storePassword, keyAlias and keyPassword.")
                    appendLine("     storeFile is relative to android/app/ or an absolute path.")
                    appendLine()
                    append("Debug builds (flutter build apk --debug) do not need key.properties.")
                }
            )
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild" || name == "compileFlutterBuildRelease") {
        dependsOn(validateReleaseSigning)
    }
}

dependencies {
    // Required by flutter_local_notifications (card reminders).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
