import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A chave da TVIntel (android/key.properties, fora do git): a mesma com que todas as versões foram
// assinadas. Sem o ficheiro, a de depuração deste computador (que é a mesma, aqui).
val chaveTvintel = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "pt.playeriptv.player_iptv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pt.playeriptv.player_iptv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("tvintel") {
            if (!chaveTvintel.isEmpty) {
                storeFile = file(chaveTvintel.getProperty("storeFile"))
                storePassword = chaveTvintel.getProperty("storePassword")
                keyAlias = chaveTvintel.getProperty("keyAlias")
                keyPassword = chaveTvintel.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // a assinatura não pode mudar entre versões: com outra chave, quem tem a app não atualiza
            signingConfig = signingConfigs.getByName(if (chaveTvintel.isEmpty) "debug" else "tvintel")
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

dependencies {
    // Motor ExoPlayer (ReprodutorExo.kt): progressivo (MPEG-TS/MP4) e HLS
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    // FileProvider: entregar o APK da versão nova ao instalador do Android (já vinha por arrasto)
    implementation("androidx.core:core:1.13.1")
}

// libmpv completo (com filtros do ffmpeg) do mpv-android, no lugar do do media_kit
apply(from = "../libmpv_completo.gradle")
