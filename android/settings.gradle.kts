pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 阿里云 Google Maven 镜像
        maven {
            url = uri("https://maven.aliyun.com/repository/google")
        }

        // 阿里云 Maven Central 镜像
        maven {
            url = uri("https://maven.aliyun.com/repository/central")
        }

        // 阿里云 Gradle 插件镜像
        maven {
            url = uri("https://maven.aliyun.com/repository/gradle-plugin")
        }

        // 官方仓库作为后备
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
