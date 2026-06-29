import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val encodedDartDefines: List<String> =
    (project.findProperty("dart-defines") as? String)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?: emptyList()

val dartDefines: Map<String, String> =
    encodedDartDefines
        .mapNotNull { encoded: String ->
            runCatching {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        .mapNotNull { define: String ->
            val separator = define.indexOf('=')
            if (separator <= 0) {
                null
            } else {
                define.substring(0, separator) to define.substring(separator + 1)
            }
        }
        .toMap()

val amapAndroidKey: String =
    dartDefines["AMAP_ANDROID_KEY"]
        ?: (project.findProperty("AMAP_ANDROID_KEY") as? String)
        ?: ""

android {
    namespace = "com.mutualwatch.mutual_watch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mutualwatch.mutual_watch"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["AMAP_ANDROID_KEY"] = amapAndroidKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
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

flutter {
    source = "../.."
}

dependencies {
    implementation("com.amap.api:3dmap:10.0.600")
}
