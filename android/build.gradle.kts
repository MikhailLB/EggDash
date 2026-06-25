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

    // -----------------------------------------------------------------
    // Force every Android library plugin to compile against the same
    // compileSdk our app uses (36+). Some plugins still ship with
    // compileSdk=34 but their transitive deps (e.g.
    // flutter_plugin_android_lifecycle) require 36 — without this
    // override Gradle's CheckAarMetadata aborts the build.
    //
    // The afterEvaluate hook MUST be registered before the
    // evaluationDependsOn(":app") block below, otherwise the target
    // subprojects are already evaluated when we get here and Gradle
    // throws "Cannot run Project.afterEvaluate when the project is
    // already evaluated".
    // -----------------------------------------------------------------
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
