plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // O plugin Gradle do Flutter tem de ser aplicado depois dos plugins Gradle do Android e do Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.equisim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Defina um Application ID proprio e unico (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.equisim"
        // Os valores abaixo podem ser ajustados as necessidades do aplicativo.
        // Para mais informacoes, ver: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Acrescente uma configuracao de assinatura propria para o build de release.
            // Por enquanto assina com as chaves de debug, para que `flutter run --release` funcione.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}


