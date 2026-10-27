plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.biomedica_app.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.biomedica_app"
        minSdk = 30
        targetSdk = 35
        versionCode = 5
        versionName = "1.3.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
}
