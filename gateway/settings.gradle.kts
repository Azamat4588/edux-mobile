pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven {
            name = "linphone"
            url = uri("https://download.linphone.org/maven_repository")
            content { includeGroupByRegex("org\\.linphone.*") }
        }
    }
}
rootProject.name = "edux-gateway"
include(":app")
