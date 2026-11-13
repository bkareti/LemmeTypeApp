// Fakes, the reusable engine contract, and the shared-fixture loader. Test code only.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core-domain"))
    api(libs.serialization.json)
    api(libs.coroutines.test)
    api(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.launcher)
}
