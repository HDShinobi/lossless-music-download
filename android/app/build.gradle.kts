plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upstream Rust engine (Layer 1, vendored). Built by upstream's script before preBuild.
val rustBackendDir = rootProject.file("../rust_backend")

android {
    namespace = "xyz.losslessmusic.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    repositories { flatDir { dirs("libs") } }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // CoreBackend.kt (vendored) reads BuildConfig.APPLICATION_ID via our shim.
        buildConfig = true
    }

    sourceSets.getByName("main") {
        java.srcDir(rustBackendDir.resolve("target/bindings/kotlin"))
        jniLibs.srcDir(rustBackendDir.resolve("target/android/jniLibs"))
    }

    testOptions {
        unitTests.all {
            // JVM unit tests load the host build of the engine through JNA.
            it.systemProperty("jna.library.path", rustBackendDir.resolve("target/release").absolutePath)
        }
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "xyz.losslessmusic.app"
        // Kept at Android 8.0. Lowering was investigated (ffmpeg needs only 24)
        // but rejected: Android < 7.1.1 lacks the ISRG Root X1 CA, breaking
        // HTTPS to Let's Encrypt hosts, and 7.x ships a frozen WebView too old
        // to render the signed-session verification challenge.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Read from pubspec (via Flutter) so the installed app reports its real
        // version — required for the in-app update check to compare correctly.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Phase 0: gomobile .aar is arm64-only (see scripts/build_android.sh). Add x86_64/armeabi-v7a here AND to the gomobile -target before any release build.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 strips/renames the ffmpeg-kit Java classes that its native
            // JNI_OnLoad binds to ("Bad JNI version" → all plugins fail to
            // register → blank screen on real devices). Disable shrinking for
            // this sideloaded beta; the APK is dominated by native libs anyway.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Extract native libs to disk on install. ffmpeg-kit's 16KB-aligned .so
    // files can fail to load directly from the APK (uncompressed) on older
    // Android (e.g. the LG V30 / API 28); extraction loads them reliably.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

val buildRustBackend = tasks.register<Exec>("buildRustBackend") {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("bash", "scripts/build_rust_backend.sh", "android")
    environment("SPOTIFLAC_RUST_ANDROID_ABIS", "arm64-v8a")
    // Always NDK 29 (upstream pin). Deliberately NOT ANDROID_NDK_HOME: on dev machines it
    // may point at the older NDK Flutter uses for the rest of the app.
    environment(
        "ANDROID_NDK_HOME",
        providers.environmentVariable("RUST_ANDROID_NDK_HOME").orNull
            ?: android.sdkDirectory.resolve("ndk/29.0.14206865").absolutePath,
    )
    inputs.files(fileTree(rustBackendDir) {
        include("**/*.rs", "**/*.toml", "**/*.lock", "**/*.js", "**/*.tsv", "**/*.pem")
        exclude("target/**", "smoke/**")
    })
    inputs.file(rootProject.file("../scripts/build_rust_backend.sh"))
    outputs.dir(rustBackendDir.resolve("target/bindings/kotlin"))
    outputs.dir(rustBackendDir.resolve("target/android/jniLibs"))
    outputs.file(rustBackendDir.resolve("target/release/libspotiflac_mobile.dylib"))
}
tasks.named("preBuild").configure { dependsOn(buildRustBackend) }

flutter {
    source = "../.."
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    // ffmpeg_kit_flutter_new_full declares this with `implementation` (not `api`),
    // so its classes aren't on app's compile classpath transitively. We declare it
    // directly as `implementation` here to guarantee runtime presence, matching
    // SpotiFLAC-Mobile's proven pattern.
    implementation("com.antonkarpenko:ffmpeg-kit-full:2.1.0")
    // UniFFI Kotlin bindings call the Rust engine through JNA.
    implementation("net.java.dev.jna:jna:5.19.1@aar")

    testImplementation("junit:junit:4.13.2")
    // Android's org.json is a stub on the JVM; unit tests need the real one.
    testImplementation("org.json:json:20250517")
    // Desktop JNA (jnidispatch for macOS) so JVM tests can load the host engine build.
    testImplementation("net.java.dev.jna:jna:5.19.1")
}
