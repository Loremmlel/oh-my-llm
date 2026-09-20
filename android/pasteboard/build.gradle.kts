plugins {
    id("com.android.library")
}

// 只适配锁定的 pasteboard 0.5.0，不修改全局 Kotlin 模式或用户的 Pub 缓存。
// 升级到上游支持 built-in Kotlin 的版本后删除此文件，由 Android Release 构建验证。
val pasteboardSources = gradle.extra["pasteboardSources"] as File

android {
    namespace = "one.mixin.pasteboard"
    compileSdk = 37
    defaultConfig { minSdk = 21 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets.getByName("main") {
        kotlin.setSrcDirs(listOf(pasteboardSources.resolve("kotlin")))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
