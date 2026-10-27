import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
val coachSigning = Properties()
val coachSigningFile = rootProject.file("key.properties")
if (coachSigningFile.exists()) {
    coachSigningFile.inputStream().use { coachSigning.load(it) }
}
android {
    namespace = "hk.badminton.coach"
    compileSdk = 36
    ndkVersion = "27.0.12077973"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "hk.badminton.coach.autoanalysis"
        minSdk = 28
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (coachSigningFile.exists()) {
            create("coachStable") {
                storeFile = file(coachSigning.getProperty("storeFile"))
                storeType = "PKCS12"
                storePassword = coachSigning.getProperty("storePassword")
                keyAlias = coachSigning.getProperty("keyAlias")
                keyPassword = coachSigning.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        debug { applicationIdSuffix = ".dev" }
        release {
            // Never silently substitute a per-run debug key for distributed updates.
            signingConfig = signingConfigs.findByName("coachStable")
        }
    }
}
flutter { source = "../.." }
dependencies {
    // Bundled model: no Play Services model download, account, API key or network required.
    implementation("com.google.mlkit:pose-detection:18.0.0-beta5")
}
