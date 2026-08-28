plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jathol.orderflow"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jathol.orderflow"
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("sideload") {
            storeFile = rootProject.file("sideload/upload.p12")
            storePassword = "JatholOrderFlowSideload"
            keyAlias = "jathol"
            keyPassword = "JatholOrderFlowSideload"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("sideload")
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
