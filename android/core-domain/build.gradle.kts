// Session, recorder state machine, engine contract, and runner, ported from Swift Domain (E14-S8). Pure Kotlin.
plugins {
    alias(libs.plugins.kotlin.jvm)
    // For the fixture data classes in tests only; main code has no serialization dependency.
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(libs.coroutines.core)
    testImplementation(project(":core-testing"))
    testImplementation(libs.coroutines.test)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(kotlin("test"))
    testRuntimeOnly(libs.junit.launcher)
}
