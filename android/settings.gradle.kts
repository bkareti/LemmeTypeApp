// LemmeType for Android (ADR 0035). Pure-Kotlin core modules first (E14-S7 … E14-S9);
// the Android app and platform modules are added by E14-S6 once the SDK is set up.
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenCentral()
    }
}

rootProject.name = "LemmeTypeAndroid"

include(":core-domain", ":core-writing", ":core-testing")
