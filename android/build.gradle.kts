allprojects {
    repositories {
        // 阿里云 Google Maven 镜像
        maven {
            url = uri("https://maven.aliyun.com/repository/google")
        }

        // 阿里云 Maven Central 镜像
        maven {
            url = uri("https://maven.aliyun.com/repository/central")
        }

        // 阿里云公共仓库
        maven {
            url = uri("https://maven.aliyun.com/repository/public")
        }

        // 官方仓库作为后备
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
