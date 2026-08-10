plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_template"
    // flutter_secure_storage 10.x compiles against API 36. Keep the compile
    // SDK explicit until the supported Flutter baseline exposes that version.
    compileSdk = 36

    // The Android implementations of the selected storage plugins require
    // NDK 27. Pinning their common version prevents Gradle from selecting the
    // older NDK bundled as Flutter 3.29's default.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Replace this placeholder during project initialization. Keep the
        // namespace, Kotlin package, manifests, tests, and iOS identifiers
        // aligned by following docs/project-initialization.md.
        applicationId = "com.example.flutter_template"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_secure_storage 10.x uses cryptography APIs introduced in API 23.
        // Keep this explicit so an SDK default cannot silently lower the floor.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing is intentionally unset. Real projects must inject an
            // external signing configuration without committing keys or passwords.
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Flutter Template Dev")
            resValue("string", "app_environment", "dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Flutter Template Staging")
            resValue("string", "app_environment", "staging")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "Flutter Template")
            resValue("string", "app_environment", "prod")
        }
    }
}

flutter {
    source = "../.."
}

// Flutter invokes aggregate APK or App Bundle tasks when --flavor is omitted.
// A doFirst action on an aggregate task runs after its flavored dependencies,
// so it can contaminate otherwise valid outputs before reporting the error.
// Inspect the explicitly requested tasks during configuration and fail before
// Gradle executes any dependency or writes an environment-specific artifact.
val environmentlessBuildTasks = setOf(
    "assembleDebug",
    "assembleProfile",
    "assembleRelease",
    "bundleDebug",
    "bundleProfile",
    "bundleRelease",
)
val requestedEnvironmentlessBuildTask =
    gradle.startParameter.taskNames
        .asSequence()
        .map { it.substringAfterLast(':') }
        .firstOrNull { it in environmentlessBuildTasks }

if (requestedEnvironmentlessBuildTask != null) {
    throw GradleException(
        "An environment flavor is required. Use a dev, staging, or prod variant.",
    )
}
