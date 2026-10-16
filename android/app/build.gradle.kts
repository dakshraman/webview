import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val repoKeyPropertiesFile = rootProject.file("../key.properties")
if (keyPropertiesFile.exists()) {
    FileInputStream(keyPropertiesFile).use { keystoreProperties.load(it) }
} else if (repoKeyPropertiesFile.exists()) {
    FileInputStream(repoKeyPropertiesFile).use { keystoreProperties.load(it) }
}

val envStoreFile = System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val envStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")?.takeIf { it.isNotBlank() }
val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")?.takeIf { it.isNotBlank() }

val configuredStoreFile = envStoreFile
    ?: keystoreProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }

val resolvedStoreFile: File? = when {
    configuredStoreFile != null -> {
        val file = File(configuredStoreFile)
        when {
            file.isAbsolute && file.exists() -> file
            project.file(configuredStoreFile).exists() -> project.file(configuredStoreFile)
            rootProject.file(configuredStoreFile).exists() -> rootProject.file(configuredStoreFile)
            rootProject.file("../$configuredStoreFile").exists() -> rootProject.file("../$configuredStoreFile")
            else -> file
        }
    }
    project.file("upload-keystore.jks").exists() -> project.file("upload-keystore.jks")
    rootProject.file("app/upload-keystore.jks").exists() -> rootProject.file("app/upload-keystore.jks")
    rootProject.file("../upload-keystore.jks").exists() -> rootProject.file("../upload-keystore.jks")
    else -> null
}

val resolvedStorePassword = envStorePassword
    ?: keystoreProperties.getProperty("storePassword")?.takeIf { it.isNotBlank() }
val resolvedKeyAlias = envKeyAlias
    ?: keystoreProperties.getProperty("keyAlias")?.takeIf { it.isNotBlank() }
val resolvedKeyPassword = envKeyPassword
    ?: keystoreProperties.getProperty("keyPassword")?.takeIf { it.isNotBlank() }

val hasReleaseSigning = resolvedStoreFile != null &&
    resolvedStoreFile.exists() &&
    !resolvedStorePassword.isNullOrBlank() &&
    !resolvedKeyAlias.isNullOrBlank() &&
    !resolvedKeyPassword.isNullOrBlank()

android {
    namespace = "com.raj.amkalyan"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = resolvedStoreFile
                storePassword = resolvedStorePassword
                keyAlias = resolvedKeyAlias
                keyPassword = resolvedKeyPassword
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.raj.amkalyan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                if (System.getenv("CI") == "true" || System.getenv("GITHUB_ACTIONS") == "true") {
                    throw GradleException(
                        "Release build in CI failed because release signing is not configured. " +
                        "Keystore file exists: ${resolvedStoreFile?.exists() == true} (${resolvedStoreFile?.path}), " +
                        "storePassword set: ${!resolvedStorePassword.isNullOrBlank()}, " +
                        "keyAlias set: ${!resolvedKeyAlias.isNullOrBlank()}, " +
                        "keyPassword set: ${!resolvedKeyPassword.isNullOrBlank()}"
                    )
                }
                // Fall back to debug signing for local test builds if release keys are not provided
                signingConfig = signingConfigs.getByName("debug")
            }
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
