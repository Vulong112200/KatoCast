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

// Ép mọi plugin Android (vd: geocoding_android) biên dịch với compileSdk = 36.
// Cần thiết vì flutter.compileSdkVersion của SDK hiện tại = 33, trong khi
// androidx mới (fragment 1.7.1, core 1.13.1...) yêu cầu compileSdk >= 34.
subprojects {
    val forceCompileSdk = {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                if (compileSdk == null || compileSdk!! < 36) {
                    compileSdk = 36
                }
            }
        }
    }
    // Một số subproject (vd :app) đã được evaluate sớm vì evaluationDependsOn(":app")
    // ở trên — gọi afterEvaluate lúc đó sẽ ném lỗi, nên xử lý trực tiếp.
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
