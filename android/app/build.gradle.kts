plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
        // Release signing material is supplied by a git-ignored android/key.properties
        // held only by the owner. Absent that file, release builds fall back to the debug
        // key so the build path stays verifiable — a real release must fail this check.
        // Wired up in Phase 9; see docs/RELEASE_CHECKLIST.md §H.
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // TODO(Phase 9): replace with the owner's release keystore.
            signingConfig = signingConfigs.getByName("debug")
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
