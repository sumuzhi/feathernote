plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.smartminutes.smart_minutes_flutter"
    // 部分插件（前台服务 / 音频）要求 compileSdk ≥ 37，故固定为 37
    // （flutter.compileSdkVersion 默认低于此值会导致构建失败）。
    compileSdk = 37
    // 固定使用本机已完整落位的 NDK 29（flutter.ndkVersion 默认指向 28.2，
    // 而本机 28.2 目录残缺——缺 source.properties 与 toolchains，会触发 sdkmanager
    // 重装并因沙箱权限失败导致构建中断）。
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 品牌更名「声羽 FeatherNote」：applicationId 换为新包名
        // （⚠️ 与旧包 com.smartminutes.* 不互通——需重新安装，旧 App 需手动卸载）。
        applicationId = "com.feathernote.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        // 允许 buildType 级 resValue（Debug/Release 的图标背景色区分）。
        resValues = true
    }

    signingConfigs {
        // 共享 debug keystore（提交在仓库内：android/app/debug.keystore）。
        //
        // 为什么提交：release 包沿用 debug 签名（自用侧载，无需正式签名），
        // 而 debug keystore 若依赖 `~/.android/debug.keystore` 自动生成，本机与
        // CI 的签名会互不相同、且可能随环境丢失（2026-10-16 实测丢失过一次），
        // 覆盖安装会因签名不一致被拒。提交后本地与 GitHub Actions 恒同签名。
        //
        // Trade-off（刻意取舍）：公开仓库包含 debug 密钥——debug keystore 无
        // 保密性（密码恒为 android，仅用于侧载签名，不用于任何正式发布）。
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            // Debug 包名加 .debug 后缀：与 Release 版可并存安装、互不覆盖。
            applicationIdSuffix = ".debug"
            // Debug 图标背景：品牌深棕（与 Release 橙底一眼区分）。
            resValue("color", "ic_launcher_background", "#221A14")
        }
        release {
            // Release 图标背景：主题橙。
            resValue("color", "ic_launcher_background", "#F0783C")
            // Debug 签名（共享 keystore，见上方 signingConfigs 注释）：
            // 自用侧载 + CI 与本地同签名，覆盖安装稳定。
            signingConfig = signingConfigs.getByName("debug")
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
