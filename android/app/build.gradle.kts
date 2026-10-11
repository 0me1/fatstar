plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fatstar.calorie_diary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.fatstar.calorie_diary"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Calorie Diary signing: release fails without a keystore; no debug fallback.
    signingConfigs {
        create("diaryRelease") {
            val keyPath = System.getenv("DIARY_KEYSTORE_PATH")
            if (keyPath != null) {
                storeFile = file(keyPath)
                storePassword = System.getenv("DIARY_STORE_PASSWORD")
                keyAlias = System.getenv("DIARY_KEY_ALIAS")
                keyPassword = System.getenv("DIARY_KEY_PASSWORD")
            }
        }
    }
    defaultConfig {
        manifestPlaceholders["allowCleartext"] = "false"
    }
    buildTypes {
        debug {
            manifestPlaceholders["allowCleartext"] = "true"
        }
        release {
            // A production keystore must be supplied through CI secrets.
            signingConfig = signingConfigs.getByName("diaryRelease")
        }
    }
}

flutter {
    source = "../.."
}
