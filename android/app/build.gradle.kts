import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.weview.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    val envStoreFile = System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
    val envStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
    val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")?.takeIf { it.isNotBlank() }
    val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")?.takeIf { it.isNotBlank() }

    val appKeystore = rootProject.file("app/upload-keystore.jks")
    val repoKeystore = rootProject.file("../upload-keystore.jks")
    val fallbackStoreFile = when {
        appKeystore.exists() -> appKeystore
        repoKeystore.exists() -> repoKeystore
        else -> null
    }

    val storeFileValue = envStoreFile
        ?: keystoreProperties["storeFile"]?.toString()?.takeIf { it.isNotBlank() }
    val resolvedStoreFile = storeFileValue?.let { rootProject.file(it) } ?: fallbackStoreFile
    val storePasswordValue = envStorePassword
        ?: keystoreProperties["storePassword"]?.toString()?.takeIf { it.isNotBlank() }
    val keyAliasValue = envKeyAlias
        ?: keystoreProperties["keyAlias"]?.toString()?.takeIf { it.isNotBlank() }
    val keyPasswordValue = envKeyPassword
        ?: keystoreProperties["keyPassword"]?.toString()?.takeIf { it.isNotBlank() }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            val hasReleaseSigning = resolvedStoreFile != null &&
                !storePasswordValue.isNullOrBlank() &&
                !keyAliasValue.isNullOrBlank() &&
                !keyPasswordValue.isNullOrBlank()

            if (hasReleaseSigning) {
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
                storeFile = resolvedStoreFile
                storePassword = storePasswordValue
            } else {
                initWith(getByName("debug"))
            }
        }
    }

    defaultConfig {
        applicationId = "com.weview.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Use release signing if provided; otherwise fall back to debug for local builds.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
