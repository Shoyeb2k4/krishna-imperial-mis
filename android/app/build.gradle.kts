import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release signing (Phase 9 Slice 2, D-346) ──────────────────────────────────────────
//
// A release build is signed with the upload key named by android/key.properties, a file
// held only by the project lead and ignored by git, as is every keystore. There is **no
// fallback to the debug key**: without that file, or with an incomplete one, every
// release build stops with the message below before anything is packaged. Debug and
// profile builds never read it. No value from the file is ever printed.
//
//   storeFile=<path to the upload keystore, absolute or relative to android/>
//   storePassword=…
//   keyAlias=…
//   keyPassword=…
val releaseSigningFile = rootProject.file("key.properties")
val releaseSigning: Properties? =
    if (releaseSigningFile.isFile) {
        Properties().apply { releaseSigningFile.inputStream().use { load(it) } }
    } else {
        null
    }
val releaseSigningFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigningProblem: String? =
    when {
        releaseSigning == null ->
            "android/key.properties is missing"
        releaseSigningFields.any { releaseSigning.getProperty(it).isNullOrBlank() } ->
            "android/key.properties does not name all of " + releaseSigningFields.joinToString()
        !rootProject.file(releaseSigning.getProperty("storeFile")).isFile ->
            "the keystore android/key.properties names does not exist"
        else -> null
    }

android {
    // Approved application identity — see docs/DECISIONS.md D-029.
    // Changing this after installation or publication forces uninstall/reinstall and
    // destroys local data. It is not to be altered without the owner's decision.
    namespace = "in.krishnaimperial.mis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "in.krishnaimperial.mis"
        // SQLCipher and flutter_secure_storage's EncryptedSharedPreferences both require
        // API 21+; 24 keeps us clear of legacy TLS and keystore quirks.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        // Required for the per-flavour app_name resValue below; off by default in
        // current AGP versions.
        resValues = true
    }

    // Environment separation (ARCHITECTURE.md §3). Distinct application ids let all three
    // flavours coexist on one device without overwriting each other's local database.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Krishna Imperial MIS (Dev)")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Krishna Imperial MIS (Staging)")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Krishna Imperial MIS")
        }
    }

    signingConfigs {
        if (releaseSigningProblem == null) {
            create("release") {
                val properties = releaseSigning!!
                storeFile = rootProject.file(properties.getProperty("storeFile"))
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // The upload key, or nothing: never the debug key (D-346). With no signing
            // configuration the build is stopped by verifyReleaseSigning below.
            signingConfig = signingConfigs.findByName("release")
        }
        debug {
            isMinifyEnabled = false
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

// Stops every release build that has no complete upload-key configuration, before anything
// is compiled or packaged. Wired to each variant's `pre…ReleaseBuild`, which every release
// assemble, bundle and install task runs first; debug and profile never reach it.
val verifyReleaseSigning by tasks.registering {
    val problem = releaseSigningProblem
    doLast {
        if (problem != null) {
            throw GradleException(
                "Release signing is not configured: " + problem + ". A release build is " +
                    "never signed with the debug key. See docs/RELEASE_CHECKLIST.md §H " +
                    "and docs/PRODUCTION_RUNBOOK.md (D-346).",
            )
        }
    }
}
tasks.configureEach {
    if (name.startsWith("pre") && name.endsWith("ReleaseBuild")) {
        dependsOn(verifyReleaseSigning)
    }
}
