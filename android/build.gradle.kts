allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// media_store_plus 0.1.3 自身按 android-33 编译，但其依赖 exifinterface 1.4.1
// 要求 compileSdk ≥ 34。统一提升到 37（与 app 一致），否则 AGP 校验失败：
// "Dependency 'androidx.exifinterface:...' requires ... version 34 or later".
subprojects {
    if (project.name == "media_store_plus") {
        afterEvaluate {
            val androidExtension = project.extensions.findByName("android")
            (androidExtension as? com.android.build.gradle.LibraryExtension)?.compileSdk = 37
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
